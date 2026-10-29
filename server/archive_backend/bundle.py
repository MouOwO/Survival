from __future__ import annotations
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import shutil
import subprocess

MODULES = ("archive_settlement", "archive_challenge_rewards", "archive_social_rewards", "archive_challenge_reward_eligibility", "archive_challenge_gear",
           "archive_daily_rewards", "archive_benefit_rewards", "archive_stackable_items", "archive_daily_limits", "archive_clear_progress", "archive_online_rewards", "archive_endless_config", "archive_endless_rewards", "archive_building_rewards", "lottery_http_settlement", "archive_starjoy_rewards", "archive_vip_rewards", "archive_calendar", "archive_welfare_rewards", "archive_titles", "commerce_settlement", "commerce_effects", "archive_cooperative_reward_policy")
# Presentation tables have a different schema and never participate in settlement.
PRESENTATION_CSV = {"archive_icon_presentation.csv", "archive_item_icons.csv", "archive_navigation_icons.csv"}

def read_csv(path):
    # Parse complete logical records before inspecting metadata. Physical-line
    # filtering flattens quoted tooltip paragraphs and can delete a legitimate
    # body line beginning with '#'. Both are part of a description, not rows.
    records = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8-sig"), newline="")))
    header = records[0]
    type_record = next((row for row in records[1:] if row and row[0].startswith("#types:")), None)
    if type_record is None: raise ValueError(f"csv_types_missing:{path.name}")
    types = [type_record[0][7:], *type_record[1:]]
    if len(header) != len(types):
        raise ValueError(f"csv_types_mismatch:{path.name}")
    rows, seen = [], set()
    for values in records[1:]:
        if not values or values[0].startswith("#"): continue
        raw = dict(zip(header, values))
        row = {}
        for key, kind in zip(header, types):
            value = (raw.get(key) or "").strip()
            if not value:
                continue
            if kind == "number":
                value = float(value)
                if not math.isfinite(value): raise ValueError("csv_nonfinite")
                if value.is_integer(): value = int(value)
            elif kind == "boolean":
                if value.lower() not in {"1","0","true","false","yes","no","on","off"}: raise ValueError("csv_boolean")
                value = value.lower() in {"1","true","yes","on"}
            elif kind == "list": value = [v.strip() for v in value.split("|" if "|" in value else ",") if v.strip()]
            row[key] = value
        identity = row[header[0]]
        if identity in seen: raise ValueError(f"csv_duplicate:{path.name}:{identity}")
        seen.add(identity); rows.append(row)
    return {"key": header[0], "rows": rows}

def challenge_modes(source: str):
    """Export exact mode tiers from the same Lua bytes packaged for settlement."""
    lua = os.environ.get("LUA_EXECUTABLE") or shutil.which("lua5.1") or shutil.which("lua")
    if not lua:
        candidate = Path("C:/Program Files/lua/bin/lua5.1.exe")
        lua = str(candidate) if candidate.is_file() else None
    if not lua:
        raise RuntimeError("set LUA_EXECUTABLE to export immutable challenge mode tiers")
    script = ('local data=assert(loadstring(io.read("*a")))(); '
              'for mode,rows in pairs(data.modes) do '
              'io.write(mode,"\\t"); for number,row in ipairs(rows) do '
              'if number>1 then io.write(",") end; io.write(number) end; '
              'io.write("\\n") end')
    result = subprocess.run([lua, "-e", script], input=source.encode("utf-8"),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=10, check=True,
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    rows = []
    for line in result.stdout.decode("utf-8").splitlines():
        mode, numbers = line.split("\t")
        tiers = [int(value) for value in numbers.split(",")]
        if not tiers or tiers != list(range(1, max(tiers) + 1)):
            raise ValueError("archive_challenge_mode_tiers_invalid")
        rows.append({"mode_id": mode, "difficulties": tiers})
    if not rows:
        raise ValueError("archive_challenge_modes_missing")
    return {"key": "mode_id", "rows": sorted(rows, key=lambda row: row["mode_id"])}

def build(root: Path, destination: Path | None = None, update_game_config: bool = True):
    from .commerce_catalog import build_catalog
    commerce = build_catalog(root)
    files = sorted(p for p in (root / "data/csv/存档系统").glob("*.csv") if p.name not in PRESENTATION_CSV)
    files += sorted((root / "data/csv/抽奖系统").glob("*.csv"))
    files += [root / 'data/csv/商城兑换系统' / (name + '.csv')
              for name in ('commerce_products', 'commerce_rewards', 'commerce_import_status', 'commerce_bundle_members')
              if (root / 'data/csv/商城兑换系统' / (name + '.csv')).is_file()]
    files += [root / "data/csv/玩家档案系统" / (n+".csv") for n in ("player_gameplay_stats","map_level_effect_rules")]
    sources = {"systems/"+n+".lua": (root/"scripts/vscripts/systems"/(n+".lua")).read_text(encoding="utf-8-sig") for n in MODULES}
    for name in ("lottery_config", "content_id_aliases", "difficulty_config", "mode_progression", "recorded_mode_balance",
                 "human_monster_rules", "mode_release_config", "generated/human_monster_spec"):
        source = root/"scripts/vscripts/config"/(name+".lua")
        # Older difficulty_config versions have no separate progression module.
        if name == "mode_progression" and not source.is_file():
            continue
        sources["config/"+name+".lua"] = source.read_text(encoding="utf-8-sig")
    for name in ("json_encoder","json_decoder"):
        sources["core/"+name+".lua"] = (root/"scripts/vscripts/core"/(name+".lua")).read_text(encoding="utf-8-sig")
    sources["worker.lua"] = (root/"server/archive_backend/worker.lua").read_text(encoding="utf-8-sig")
    configs = {p.stem: read_csv(p) for p in files}
    configs["archive_challenge_modes"] = challenge_modes(sources["config/generated/human_monster_spec.lua"])
    configs['commerce_catalog'] = {'key': 'sku', 'rows': commerce['products']}
    csv_hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes().replace(b"\r\n",b"\n")).hexdigest() for p in files}
    data = {"protocol":1,"configs":configs,"sources":sources,"csv_hashes":csv_hashes}
    raw = json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
    digest = hashlib.sha256(raw).hexdigest()
    bundle_root = destination if destination is not None else root / "server/bundles"
    directory = bundle_root / digest
    directory.mkdir(parents=True,exist_ok=True)
    for path,text in sources.items():
        output=directory/path;output.parent.mkdir(parents=True,exist_ok=True);output.write_text(text,encoding="utf-8",newline="\n")
    (directory/"bundle.json").write_bytes(raw)
    (bundle_root/"current.json").write_text(json.dumps({"hash":digest,"protocol":1}),encoding="utf-8")
    if update_game_config:
        (root/"scripts/vscripts/config/generated/archive_http_bundle.lua").write_text(
            '-- AUTO-GENERATED by tools/build_archive_server_bundle.py\nreturn { protocol = 1, hash = "'+digest+'" }\n',encoding="utf-8")
    return digest

class Bundle:
    def __init__(self, directory: Path):
        self.directory = directory.resolve()
        raw = (self.directory/"bundle.json").read_bytes()
        self.hash = hashlib.sha256(raw).hexdigest()
        if self.hash != self.directory.name: raise ValueError("bundle_hash_mismatch")
        data=json.loads(raw);self.configs=data["configs"]
        from .config_compatibility import parse
        self.compatible_config_hashes = parse(data)
        for path,source in data["sources"].items():
            if (self.directory/path).read_text(encoding="utf-8")!=source: raise ValueError("bundle_source_mismatch")
        self.tables={name:{row[cfg["key"]]:row for row in cfg["rows"]} for name,cfg in self.configs.items()}
