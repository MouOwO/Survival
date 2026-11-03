"""Build an account-free three-domain UI catalogue from immutable Git blobs.

Prototype outputs stay under output/: no running Lua/JS, CSV, reward rule,
database, installed package or Workshop state is changed. Numeric identities
are append-only; the preserved registry history proves IDs were not recycled.
"""
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EXECUTED_GENERATOR_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
CONTENT = Path("D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival")
OUTPUT = ROOT / "output/ui_static_catalog_20261103"
REGISTRY_PATH = "data/ui/ui_static_catalog_registry.json"
CATALOG_PATH = "panorama/src/scripts/custom_game/common/ui_static_catalog.js"
LOOKUP_PATH = "scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"
MANIFEST_PATH = "data/ui/ui_static_catalog_manifest.json"
FORMAT = 1
MAX_RECORD = 65535
MAX_FIELD = 255
MAX_UINT = 4294967295
MAX_SINT = 2147483647
TABLES = (
    "archive_categories", "archive_achievements", "archive_shadow_items", "archive_cage_items",
    "archive_fragment_definitions", "archive_fragment_levels", "archive_endless_achievements",
    "archive_challenge_gear_items", "archive_boss_achievements", "archive_work_items",
    "archive_map_levels", "archive_social_items", "archive_social_rules", "archive_fishing_items",
    "archive_building_items", "archive_building_rules", "archive_welfare_rewards",
    "archive_starjoy_levels", "archive_titles", "archive_daily_items", "archive_daily_schedule",
    "archive_daily_rules", "archive_benefit_rewards", "archive_stackable_items",
    "archive_daily_limits",
)
LOTTERY_TABLES = (
    "lottery_item_definitions", "lottery_pool_definitions", "lottery_currency_definitions",
    "lottery_pool_items", "lottery_pity_rules", "lottery_quality_weights", "lottery_pool_updates",
)
ROW_TABLES = {
    "archive_achievements": ("clear", "achievement_id"),
    "archive_shadow_items": ("shadow", "item_id"),
    "archive_cage_items": ("pet", "item_id"),
    "archive_fragment_definitions": ("fragment", "fragment_id"),
    "archive_endless_achievements": ("endless", "achievement_id"),
    "archive_challenge_gear_items": ("endless", "item_id"),
    "archive_boss_achievements": ("boss", "achievement_id"),
    "archive_work_items": ("work", "item_id"),
    "archive_map_levels": ("map_level", "level_id"),
    "archive_fishing_items": ("fishing", "reward_id"),
    "archive_building_items": ("building", "item_id"),
    "archive_welfare_rewards": ("gift", "achievement_id"),
    "archive_starjoy_levels": ("starjoy_points", "tier_id"),
    "archive_titles": ("titles", "title_id"),
    "archive_commerce_goods": ("commerce_goods", "id"),
}
# Public display metadata only. Weights, grant effects, ownership selectors,
# account values and eligibility results are never copied into the catalogue.
PUBLIC_FIELDS = frozenset({
    "description", "quality", "icon", "icon_type", "icon_style", "max_owned", "max_level",
    "cost", "required_count", "required_score", "required_wave", "required_seconds",
    "required_points", "required_kills", "pass_required_kills", "level", "mode_id",
    "difficulty_id", "reward_mode", "reward_start", "reward_limit", "unlock_condition",
    "rune", "progress_kind", "pending_effect", "duration_type", "duration_text",
    "item_type", "effect_status", "duplicate_points", "exchange_points", "exchange_enabled",
    "converted_currency", "category_id", "renderer", "sort_order", "display_width",
    "display_height", "fragments_per_level", "promotion_required_total", "promotion_cost",
    "currency_id", "currency_name", "draw_cost", "unlock_count", "ticket_content_id",
    "single_cost", "ten_cost", "pool_group", "ui_order", "unlock_pool_id", "unlock_draws",
    "unlock_required", "unlock_pool_name", "ticket_name", "pity", "update_notice",
    "revision", "updated_at", "kind", "source_id", "sku", "catalog_paused", "resource_id",
    "day_id", "item_ids", "item_counts", "pass_milestones", "pass_item_ids",
    "pass_entitlement_id", "duration_days", "price_text", "purchase_enabled", "makeup_days",
    "timezone_hours", "pass_sku", "track", "period", "metric", "required", "base_item_ids",
    "base_counts", "pass_counts", "monthly_only", "auto_claim", "starts_at", "ends_at",
    "daily_limit", "pass_daily_limit", "implemented", "limit_id", "default_unlocked",
})


def need(ok, reason):
    if not ok:
        raise ValueError(reason)


def canonical(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf8")


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def fields():
    # Do not reorder. New meanings are appended, never assigned an old ID.
    definitions = [
        ("known", "bool", "flag"), ("count", "uint", "count"), ("unlocked", "bool", "flag"),
        ("completed", "bool", "flag"), ("owned_count", "uint", "count"), ("level", "uint", "level"),
        ("can_upgrade", "bool", "flag"), ("equipped", "bool", "flag"), ("status", "uint", "status_enum"),
        ("is_today", "bool", "flag"), ("can_claim", "bool", "flag"), ("progress", "uint", "count"),
        ("rank", "uint", "rank"), ("tickets", "uint", "count"), ("draws", "uint", "count"),
        ("update_unread", "bool", "flag"), ("notice_unread", "bool", "flag"), ("pending", "bool", "flag"),
        ("has_pass", "bool", "flag"), ("day", "uint", "day_index"), ("period", "uint", "period_index"),
        ("expires_at", "uint", "unix_utc_seconds"), ("count_hi", "uint", "count_high32"),
        ("owned_count_hi", "uint", "count_high32"), ("progress_hi", "uint", "count_high32"),
        ("rank_delta", "sint", "rank"), ("balance", "uint", "count"), ("balance_hi", "uint", "count_high32"),
        ("earned_today", "uint", "count"), ("daily_cap", "uint", "count"), ("total", "uint", "count"),
        ("remaining", "uint", "count"), ("enabled", "bool", "flag"), ("active", "bool", "flag"),
        ("calendar_current_day", "uint", "calendar_day_1_28"), ("calendar_start_count", "uint", "count"),
        ("current_day", "uint", "cycle_day_1_7"), ("refresh_at", "uint", "unix_utc_seconds"),
        ("weekly_refresh_at", "uint", "unix_utc_seconds"), ("error_code", "uint", "error_enum"),
        ("visible", "bool", "flag"), ("at_max_owned", "bool", "flag"), ("unlock_progress", "uint", "count"),
        ("claim_count", "uint", "count"), ("absolute_count", "uint", "count"), ("target", "uint", "count"),
        ("missed_mask", "uint", "relative_day_bitmask_bit0_day_minus_1_bit28_day_minus_29"),
        ("unique_owned_mask", "uint", "daily_item_bits_by_record_id_ascending"),
        ("request_token", "uint", "session_request_token"), ("success", "bool", "flag"),
        ("terminal", "bool", "flag"), ("target_record", "uint", "record_id_or_zero"),
        ("probability_hi", "uint", "ieee754_binary64_high32"),
        ("probability_lo", "uint", "ieee754_binary64_low32"),
    ]
    definitions.extend((name, "uint", "hud_integer") for name in (
        "wood", "wood_hi", "gold", "gold_hi", "population", "max_population", "city_level", "worker_count",
        "wave_index", "wave_total", "wave_planned", "wave_pending", "wave_spawned", "wave_alive", "wave_killed",
        "wave_failed_spawn", "wave_difficulty", "wave_phase", "alive_limit", "overflow_grace_seconds",
        "countdown_deadline_ms", "overflow_deadline_ms", "challenge_deadline_ms", "defeat_reason"))
    definitions.extend((name, "bool", "flag") for name in (
        "shop_unlocked", "research_unlocked", "advanced_researcher_unlocked", "wave_boss_alive", "wave_selected",
        "wave_early_final_used", "wave_victory_settled", "wave_defeat_settled", "wave_post_clear_frozen",
        "overflow_active", "player_defeated", "challenge_saving", "challenge_player_finished", "challenge_ended"))
    definitions.extend((name, "uint", "action_enum" if name == "action_code" else "integer")
                       for name in ("action_code", "arg_a", "arg_b", "arg_c"))
    definitions.extend((name, "bool" if name in ("owned", "quantity_unknown", "can_promote", "upgrade_pending", "title_preview", "ready") else "uint", "flag" if name in ("owned", "quantity_unknown", "can_promote", "upgrade_pending", "title_preview", "ready") else "integer")
                       for name in ("owned", "quantity_unknown", "reward_count", "can_promote", "fragment_total", "source_revision",
                                    "upgrade_pending", "title_preview", "ready", "types", "earned", "faith", "per_clear", "actual_seconds", "map_seconds", "coins", "zero_mask"))
    definitions.extend((name, "bool", "flag") for name in ("automatic", "preview_only"))
    definitions.append(("wave_game_mode", "uint", "hud_game_mode_enum"))
    definitions.extend((name, "bool" if name in ("duplicate", "guarantee_satisfied", "free_available") else "uint", "lottery_quality_enum" if name == "quality_code" else "flag" if name in ("duplicate", "guarantee_satisfied", "free_available") else "count_high32" if name.endswith("_hi") else "count")
                       for name in ("duplicate", "converted_points", "converted_points_hi", "granted_count", "overflow_count", "quality_code", "guarantee_satisfied", "tickets_hi", "draws_hi", "free_available", "pity_remaining"))
    definitions.extend(("grid_" + name, kind, unit) for name, kind, unit in (
        ("action", "uint", "grid_action_enum"), ("session", "uint", "grid_session_token"),
        ("request", "uint", "grid_request_token"), ("profile", "uint", "grid_profile_record_id"),
        ("actor", "uint", "entity_index"), ("ability", "uint", "entity_index"),
        ("x_hi", "uint", "ieee754_binary64_high32"), ("x_lo", "uint", "ieee754_binary64_low32"),
        ("y_hi", "uint", "ieee754_binary64_high32"), ("y_lo", "uint", "ieee754_binary64_low32"),
        ("z_hi", "uint", "ieee754_binary64_high32"), ("z_lo", "uint", "ieee754_binary64_low32"),
        ("anchor_x", "sint", "grid_coordinate"), ("anchor_y", "sint", "grid_coordinate"),
        ("request_anchor_x", "sint", "grid_coordinate"), ("request_anchor_y", "sint", "grid_coordinate"),
        ("cell_count", "uint", "cell_count"), ("cell_mask", "uint", "cell_valid_bits"),
        ("word", "uint", "sixteen_cells_two_bits_each"), ("width", "uint", "cells"),
        ("height", "uint", "cells"), ("size", "uint", "world_units"),
        ("origin_x", "sint", "grid_coordinate"), ("origin_y", "sint", "grid_coordinate"),
        ("complete", "bool", "flag"), ("layout_ready", "bool", "flag"),
        ("scope", "uint", "grid_scope_token"), ("error", "uint", "grid_error_code")))
    definitions.extend(("selected_" + name, "uint", unit) for name, unit in (
        ("action", "selected_action_enum"), ("entity", "entity_index"),
        ("token", "selected_request_token"), ("value_hi", "ieee754_binary64_high32"),
        ("value_lo", "ieee754_binary64_low32")))
    definitions.append(("grid_map", "uint", "grid_map_enum"))
    definitions.append(("grid_atlas_base", "uint", "grid_candidate_atlas_id_or_zero"))
    definitions.append(("selected_value_int", "sint", "exact_selected_integer"))
    need(len(definitions) <= MAX_FIELD, "field_id_space_exhausted")
    result = []
    for index, (name, kind, unit) in enumerate(definitions, 1):
        row = dict(id=index, name=name, kind=kind, min=-MAX_SINT if kind == "sint" else 0,
                   max=1 if kind == "bool" else MAX_SINT if kind == "sint" else MAX_UINT,
                   default=0 if name == "known" else None, unit=unit)
        if name == "status":
            row.update(max=7, enum=list(range(8)), labels={
                "unknown": 0, "locked": 1, "claimable": 2, "claimed": 3,
                "not_open": 4, "pending": 5, "unconfigured": 6, "failed": 7})
        if name == "calendar_current_day": row["max"] = 28
        if name == "current_day": row["max"] = 7
        if name == "missed_mask": row["max"] = 1073741823
        if name == "unique_owned_mask": row["max"] = 4095
        if name == "request_token": row.update(min=1, max=16383)
        if name == "target_record": row["max"] = MAX_RECORD
        if name == "action_code": row.update(min=1, max=31)
        if name == "wave_game_mode": row.update(min=1, max=8, enum=list(range(1, 9)), labels={name: index for index, name in enumerate(("standard", "pure", "rich", "cold", "scourge", "ruins", "celestial", "fishing"), 1)})
        if name == "quality_code": row.update(max=5, enum=list(range(6)), labels=dict(none=0,n=1,r=2,sr=3,ssr=4,ur=5))
        if name == "grid_action": row.update(min=1, max=5, enum=list(range(1, 6)), labels={"validate":1, "pose":2, "end":3, "commit":4, "pause":5})
        if name in ("grid_profile", "grid_error"): row["max"] = 65535
        if name == "grid_cell_count": row["max"] = 16
        if name == "grid_cell_mask": row["max"] = 65535
        if name in ("grid_width", "grid_height", "grid_size"): row.update(min=1, max=65536)
        if name == "selected_action": row.update(min=1, max=2, enum=[1,2])
        if name == "selected_token": row["min"] = 1
        if name == "grid_map": row.update(min=1, max=3, enum=[1,2,3], labels={"default":1,"template_map":2,"survival_c6":3})
        if name == "grid_atlas_base": row["max"] = 65535
        result.append(row)
    return result


class GitSource:
    def __init__(self, repository, revision):
        self.repository = Path(repository).resolve()
        need(re.fullmatch(r"[a-f0-9]{40}", revision or "") is not None, "immutable_git_revision_required")
        self.revision = revision
        self.cache = {}
        self.binary_hashes = {}
        self.git("cat-file", "-e", revision + "^{commit}")

    def git(self, *args):
        return subprocess.check_output(["git", "--no-replace-objects", "-c", "safe.directory=" + self.repository.as_posix(),
                                        "-C", str(self.repository), *args], timeout=120)

    def read(self, relative):
        need(not relative.startswith("/") and ".." not in relative.split("/"), "source_path_outside_repository")
        if relative not in self.cache:
            raw = self.git("show", self.revision + ":" + relative)
            need(len(raw) <= 8 * 1024 * 1024, "bounded_public_source_required:" + relative)
            self.cache[relative] = raw
        return self.cache[relative]

    def exists(self, relative):
        need(not relative.startswith("/") and ".." not in relative.split("/"), "source_path_outside_repository")
        return bool(self.git("ls-tree", "--name-only", self.revision, "--", relative).strip())

    def map_sha256(self, relative):
        # One explicitly reviewed binary resource, outside the 8MiB text API.
        # Bound size before git-show; do not retain map bytes in public cache.
        need(relative == "maps/template_map.vpk", "unreviewed_binary_public_source")
        if relative not in self.binary_hashes:
            identity = self.revision + ":" + relative
            size = int(self.git("cat-file", "-s", identity))
            need(0 < size <= 128 * 1024 * 1024, "bounded_immutable_map_required")
            raw = self.git("show", identity)
            need(len(raw) == size, "immutable_map_size_changed")
            lfs = re.fullmatch(rb"version https://git-lfs.github.com/spec/v1\r?\noid sha256:([a-f0-9]{64})\r?\nsize \d+\r?\n?", raw)
            self.binary_hashes[relative] = lfs[1].decode("ascii") if lfs else digest(raw)
        return self.binary_hashes[relative]


def csv_table(raw):
    rows = list(csv.reader(io.StringIO(raw.decode("utf-8-sig"))))
    need(len(rows) >= 2, "typed_csv_required")
    header = rows[0]
    at = next((i for i, row in enumerate(rows) if row and row[0].startswith("#types:")), None)
    need(at is not None, "csv_types_missing")
    kinds = rows[at][:]
    if len(kinds) == 1: kinds = kinds[0][7:].split(",")
    else: kinds[0] = kinds[0][7:]
    need(len(header) == len(kinds), "csv_type_width_mismatch")
    result = []
    for cells in rows[at + 1:]:
        if not cells or not cells[0].strip() or cells[0].strip().startswith("#"): continue
        need(len(cells) <= len(header), "csv_row_width_mismatch")
        cells = [*cells, *([""] * (len(header) - len(cells)))]
        row = {}
        for key, raw_value, kind in zip(header, cells, kinds):
            value = raw_value.strip()
            if not value: continue
            if kind == "number":
                need(re.fullmatch(r"[-+]?\d+(?:\.\d+)?", value) is not None, "csv_number_invalid")
                row[key] = float(value) if "." in value else int(value)
            elif kind == "boolean": row[key] = value.lower() in {"1", "true", "yes", "y", "on"}
            elif kind == "list": row[key] = [part.strip() for part in value.split("," if "," in value and "|" not in value else "|") if part.strip()]
            elif kind == "json": row[key] = json.loads(value)
            else: row[key] = value
        result.append(row)
    return result


def lua_literal(value):
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False).replace("\\u2028", "\u2028").replace("\\u2029", "\u2029")
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, list): return "{" + ",".join(lua_literal(child) for child in value) + "}"
    if isinstance(value, dict): return "{" + ",".join("[" + lua_literal(key) + "]=" + lua_literal(child) for key, child in value.items()) + "}"
    raise TypeError(type(value).__name__)


def generated_rows(source, names, lua):
    """Read existing generated config tables in one isolated Lua process.

    Only immutable generated source and the immutable JSON encoder execute.
    Config chunks cannot require modules, access files, mutate game state or
    start a network operation. The main export writes one bounded stdout JSON.
    """
    raw = {name: source.read("scripts/vscripts/config/generated/" + name + ".lua").decode("utf-8-sig") for name in names}
    encoder = source.read("scripts/vscripts/core/json_encoder.lua").decode("utf-8-sig")
    script = ("local sources=" + lua_literal(raw) + "\nlocal json=assert(loadstring(" + lua_literal(encoder) + "))()\n"
              "local result={}\nfor name,text in pairs(sources) do\n"
              "local fn=assert(loadstring(text,'@immutable_config/'..name))\n"
              "setfenv(fn,{ipairs=ipairs,pairs=pairs,tonumber=tonumber,tostring=tostring,type=type,assert=assert,math=math,string=string,table=table})\n"
              "local value=fn();assert(type(value)=='table' and type(value.rows)=='table');result[name]=value.rows\nend\n"
              "io.write(json.encode(result))\n")
    run = subprocess.run([lua, "-"], input=script.encode("utf8"), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         timeout=20, check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    need(len(run.stdout) <= 16 * 1024 * 1024, "generated_public_tables_too_large")
    return json.loads(run.stdout)


def public_definition(row):
    result = {key: value for key, value in row.items() if key in PUBLIC_FIELDS}
    name = row.get("display_name", row.get("name"))
    if name is not None: result["name"] = name
    return result


def selected_projection_seed(source, lua, operator=None):
    """Bind reviewed new protocol code and immutable public configuration.

    New generator/schema code is an operator input, not falsely attributed to
    an older game commit. Its exact LF hashes enter the generated schema.
    """
    operator = operator or source
    operator_paths = ("tools/selected_stats_static_seed.lua", "scripts/vscripts/ui/selected_stats_schema.lua")
    seed = operator.read(operator_paths[0]).decode("utf-8-sig").replace("\r\n", "\n")
    schema_source = source.read(operator_paths[1]).decode("utf-8-sig").replace("\r\n", "\n")
    match = re.search(r"local modules=\{(.*?)\}", seed, re.S)
    need(match is not None, "selected_seed_module_list_changed")
    names = source.git("ls-tree", "-r", "--name-only", source.revision, "scripts/vscripts").decode().splitlines()
    paths = {name[len("scripts/vscripts/"):-4]: name for name in names if name.endswith(".lua")}
    pending = ["config/generated/" + name for name in re.findall(r'"([A-Za-z0-9_]+)"', match[1])]
    pending += ["config/tower_route_config", "core/json_encoder"]
    pending += [name for name in re.findall(r"\brequire\s*\(?\s*[\"']([^\"']+)[\"']", seed) if name in paths]
    sources = {"ui/selected_stats_schema": schema_source}
    while pending:
        name = pending.pop()
        if name in sources: continue
        need(name in paths, "immutable_selected_dependency_missing:" + name)
        text = source.read(paths[name]).decode("utf-8-sig");sources[name] = text
        for dependency in re.findall(r"\brequire\s*\(?\s*[\"']([^\"']+)[\"']", text):
            if dependency in paths and dependency not in sources: pending.append(dependency)
    need(len(sources) <= 512, "selected_metadata_dependency_budget_exceeded")
    npc_paths = source.git("ls-tree", "-r", "--name-only", source.revision, "scripts/npc").decode().splitlines()
    npc_paths = [name for name in npc_paths if name.startswith("scripts/npc/") and name.endswith(".txt")]
    need(0 < len(npc_paths) <= 512, "selected_public_npc_file_budget_exceeded")
    files = {};total = 0
    for name in npc_paths:
        raw = source.read(name);total += len(raw)
        need(total <= 64 * 1024 * 1024, "selected_public_npc_bytes_budget_exceeded")
        files[name] = raw.decode("utf-8-sig")
    program = "local sources=" + lua_literal(sources) + "\nlocal files=" + lua_literal(files) + "\nlocal program=" + lua_literal(seed) + "\n" + r'''
local loaded,requiring={},{}
local function forbidden() error("selected_catalogue_side_effect") end
local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,pcall=pcall,select=select,
 tonumber=tonumber,tostring=tostring,type=type,unpack=unpack,rawget=rawget,rawset=rawset,
 setmetatable=setmetatable,getmetatable=getmetatable,math=math,string=string,table=table,
 os={clock=os.clock},package={path="",loaded=loaded},print=function(value) io.write(value) end,
 GetMapName=function() return "template_map" end,IsServer=function() return true end,
 IsClient=function() return false end,IsInToolsMode=function() return false end}
env._G=env
env.io={open=function(path,mode)
 assert(mode=="rb" and files[path],"selected_non_public_file_refused")
 local closed=false
 return {read=function(_,what) assert(not closed and what=="*a");return files[path] end,
  close=function() closed=true end}
end}
local function load_public(name)
 if loaded[name]~=nil then return loaded[name] end
 assert(sources[name],"missing_readonly_selected_module:"..tostring(name));assert(not requiring[name],"selected_catalogue_dependency_cycle")
 requiring[name]=true;local fn=assert(loadstring(sources[name],"@immutable/"..name));setfenv(fn,env)
 local value=fn();requiring[name]=nil;loaded[name]=value==nil and true or value;return loaded[name]
end
env.require=load_public
local fn=assert(loadstring(program,"@reviewed_operator/selected_static_seed"));setfenv(fn,env);fn()
'''
    result = subprocess.run([lua, "-"], input=program.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20, check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    need(len(result.stdout) <= 4 * 1024 * 1024, "selected_metadata_output_budget_exceeded")
    value = json.loads(result.stdout)
    value["generator_inputs"] = {
        operator_paths[0]: dict(sha256=digest(seed.encode()), normalization="CRLF_TO_LF", role="operator",
                               revision=operator.revision, origin=getattr(operator,"input_origin","IMMUTABLE_GIT_OPERATOR_BLOB")),
        operator_paths[1]: dict(sha256=digest(schema_source.encode()), normalization="CRLF_TO_LF", role="game",
                               revision=source.revision, origin=getattr(source,"input_origin","IMMUTABLE_GIT_RUNTIME_BLOB"))}
    return value


def grid_budget_only_compatible(original, current):
    path = "scripts/vscripts/systems/grid_placement_system.lua"
    old = b"count>=8 and clock()-started>=number(payload.time_budget,0.002)"
    new = b"count>=1 and clock()-started>=number(payload.time_budget,0.002)"
    return (set(original) == set(current) and path in original and original[path].count(old) == 1
            and current[path] == original[path].replace(old, new)
            and all(current[name] == raw for name, raw in original.items() if name != path))


def grid_projection_seed(source, lua, atlas_reference=None, operator=None):
    """Execute the immutable router's actual static-profile functions only.

    Configuration requires are isolated; engine/scheduler/IO entry points are
    absent. No terrain or occupancy sample is invented by this static export.
    """
    router = source.read("scripts/vscripts/ui/grid_placement_router.lua").decode("utf-8-sig")
    start = router.index("local function build_profiles()")
    stop = router.index("local function request_anchor(", start)
    actual_profile_functions = router[start:stop]
    need("local function profile_list()" in actual_profile_functions, "grid_static_profile_source_shape_changed")
    names = source.git("ls-tree", "-r", "--name-only", source.revision, "scripts/vscripts").decode().splitlines()
    paths = {name[len("scripts/vscripts/"):-4]: name for name in names if name.endswith(".lua")}
    pending = ["config/buildings_config", "config/generated/building_definitions", "config/grid_placement_config",
               "config/map_layouts/template_map", "config/map_layouts/survival_c6", "core/json_encoder"]
    sources = {}
    while pending:
        name = pending.pop()
        if name in sources: continue
        need(name in paths, "immutable_grid_dependency_missing:" + name)
        text = source.read(paths[name]).decode("utf-8-sig");sources[name] = text
        for dependency in re.findall(r"\brequire\s*\(?\s*[\"']([^\"']+)[\"']", text):
            if dependency in paths and dependency not in sources: pending.append(dependency)
    need(len(sources) <= 512, "grid_metadata_dependency_budget_exceeded")
    script = "local sources=" + lua_literal(sources) + "\nlocal functions=" + lua_literal(actual_profile_functions) + "\n" + r'''
local function run(map)
 local loaded,requiring={},{}
 local function forbidden() error("grid_catalogue_side_effect") end
 local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,pcall=pcall,select=select,
 tonumber=tonumber,tostring=tostring,type=type,unpack=unpack,rawget=rawget,rawset=rawset,
 setmetatable=setmetatable,getmetatable=getmetatable,math=math,string=string,table=table,
 os={clock=os.clock},print=forbidden,GetMapName=function() return map end,
 IsServer=function() return true end,IsClient=function() return false end,IsInToolsMode=function() return false end}
 env._G=env;env.package={loaded=loaded}
 local function load_public(name)
  if loaded[name]~=nil then return loaded[name] end
  assert(sources[name],"missing_readonly_grid_module:"..tostring(name));assert(not requiring[name],"grid_catalogue_dependency_cycle")
  requiring[name]=true;local fn=assert(loadstring(sources[name],"@immutable/"..name));setfenv(fn,env)
  local value=fn();requiring[name]=nil;loaded[name]=value==nil and true or value;return loaded[name]
 end
 env.require=load_public
 local config=load_public("config/grid_placement_config")
 local program="local buildings=require('config/buildings_config');local building_definitions=require('config/generated/building_definitions');local grid_config=require('config/grid_placement_config');local profiles_by_ability={}\n"..functions.."\nbuild_profiles();return profile_list(),buildings"
 local fn=assert(loadstring(program,"@immutable/grid_profile_functions"));setfenv(fn,env)
 local profiles,buildings=fn();local definitions={}
 for key,row in pairs(buildings) do if type(row)=="table" then
  definitions[key]={unlock_city_level=row.unlock_city_level,max_count=row.max_count}
 end end
 return {profiles=profiles,config={cell_size=config.cell_size,footprint_subdivision=config.footprint_subdivision,
  minimum_footprint=config.minimum_footprint,preview_visual=config.preview_visual,
  build_bounds=config.build_bounds,grid_display_bounds=config.grid_display_bounds,
  build_ground_height=config.build_ground_height,build_ground_height_tolerance=config.build_ground_height_tolerance},
  building_error_parameters=definitions},load_public("core/json_encoder")
end
local result={maps={}};local encoder
for _,map in ipairs({"default","template_map","survival_c6"}) do
 local value,json=run(map);result.maps[map]=value.config
 if not result.profiles then result.profiles=value.profiles;result.building_error_parameters=value.building_error_parameters end
 encoder=json
end
io.write(encoder.encode(result))
'''
    result = subprocess.run([lua, "-"], input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20, check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    need(len(result.stdout) <= 2 * 1024 * 1024, "grid_metadata_output_budget_exceeded")
    value = json.loads(result.stdout)
    maximum = max(row["grid_footprint_x"] * row["grid_footprint_y"] for row in value["profiles"])
    need(maximum <= 16, "grid_footprint_exceeds_registered_cell_capacity")
    value.update(max_footprint_cells=16, dynamic_area_words=256, static_area_words=4096,
                 terrain_atlas_local=False, coordinate_encoding="ieee754_binary64_high32_low32")
    error_paths = ["ui/grid_placement_router", "systems/grid_placement_system", "systems/tower_relocation_service",
                   "systems/building_system", "systems/resource_system", "systems/forbidden_region_service",
                   "systems/rich_region_service", "systems/builder_service"]
    errors = set()
    for name in error_paths:
        text = source.read("scripts/vscripts/" + name + ".lua").decode("utf-8-sig")
        for pattern in (r'\berror\s*=\s*["\']([^"\'\n]+)["\']',
                        r'\breturn\s+(?:nil|false)(?:\s*,\s*nil)*\s*,\s*["\']([^"\'\n]+)["\']'):
            errors.update(re.findall(pattern, text))
    for row in value.pop("building_error_parameters").values():
        if row.get("unlock_city_level") is not None:
            errors.add("主城达到Lv." + str(row["unlock_city_level"]) + "后解锁")
        if row.get("max_count") is not None:
            errors.add("防御塔数量已达上限（每人最多" + str(row["max_count"]) + "座）")
    errors.discard("");errors.discard("grid_validation_failed")
    need("move_ability_cooldown" in errors, "grid_cooldown_error_missing")
    value["errors"] = ["", "grid_validation_failed", *sorted(errors)]
    candidate_path = "data/ui/grid_static_atlas_candidate_20261103.json"
    candidate_raw = source.read(candidate_path)
    candidate = json.loads(candidate_raw)
    need(candidate.get("format") == 1 and 0 < len(candidate.get("atlases", [])) <= 8,
         "public_grid_atlas_candidate_invalid")
    operator = operator or source
    helper_source = operator.read("tools/extract_grid_static_atlas_20261103.py").decode("utf-8-sig")
    declarations = [node for node in ast.parse(helper_source).body if isinstance(node,ast.Assign)
                    and any(isinstance(target,ast.Name) and target.id=="PUBLIC_SOURCES" for target in node.targets)]
    need(len(declarations)==1,"immutable_atlas_public_source_declaration_required")
    PUBLIC_SOURCES = ast.literal_eval(declarations[0].value)
    need(isinstance(PUBLIC_SOURCES,tuple) and len(PUBLIC_SOURCES)==6
         and all(isinstance(path,str) and path.startswith("scripts/vscripts/") and ".." not in path.split("/") for path in PUBLIC_SOURCES),
         "immutable_atlas_public_source_paths_invalid")
    atlas_reference = atlas_reference or source
    immutable_sources = {path: atlas_reference.read(path).replace(b"\r\n", b"\n") for path in PUBLIC_SOURCES}
    current_sources = {path: source.read(path).replace(b"\r\n", b"\n") for path in PUBLIC_SOURCES}
    signature_sources = {path: digest(raw) for path, raw in immutable_sources.items()}
    value["projection_signature"] = digest(canonical(signature_sources))
    value["runtime_source_sha256"] = {path: digest(raw) for path, raw in current_sources.items()}
    value["runtime_projection_signature"] = digest(canonical(value["runtime_source_sha256"]))
    compatible = grid_budget_only_compatible(immutable_sources, current_sources)
    value["map_sha256"] = {"template_map": source.map_sha256("maps/template_map.vpk")}
    value["atlases"] = candidate["atlases"]
    for atlas in value["atlases"]:
        need(atlas.get("authority") is False and atlas.get("requires_current_live_scan") is True
             and atlas.get("original_scope_session_account_included") is False,
             "grid_atlas_must_remain_non_authoritative")
        metadata_matches = (atlas.get("projection_signature") == value["projection_signature"]
                            and atlas.get("source_map_sha256") == value["map_sha256"].get(atlas.get("map")))
        atlas["binding_matches_source"] = metadata_matches and immutable_sources == current_sources
        atlas["runtime_source_compatible"] = metadata_matches and compatible
        if compatible:
            path = "scripts/vscripts/systems/grid_placement_system.lua"
            atlas["runtime_compatibility_proof"] = dict(
                kind="EXACT_ONE_CPU_BUDGET_EXPRESSION_REPLACEMENT_OTHER_BYTES_IDENTICAL",
                path=path, source_sha256=signature_sources[path], runtime_sha256=value["runtime_source_sha256"][path],
                old_expression="count>=8 and clock()-started>=number(payload.time_budget,0.002)",
                new_expression="count>=1 and clock()-started>=number(payload.time_budget,0.002)",
                normalization="CRLF_TO_LF", other_five_public_files_identical=True,
                authority=False, requires_current_live_scan=True,
                runtime_source_origin=getattr(source,"input_origin","IMMUTABLE_GIT_RUNTIME_BLOB"),
                runtime_source_revision=source.revision, reference_source_revision=atlas_reference.revision)
    value["terrain_atlas_local"] = any(row["binding_matches_source"] or row["runtime_source_compatible"] for row in value["atlases"])
    value["atlas_candidate_source"] = dict(path=candidate_path, sha256=digest(candidate_raw),
                                           revision=source.revision,
                                           origin=getattr(source,"input_origin","IMMUTABLE_GIT_CLOSED_NATIVE_PUBLIC_CANDIDATE"))
    return value


def archive_projection_seed(source, lua):
    """Run immutable read-only projectors; all game/HTTP/write APIs are refused."""
    names = source.git("ls-tree", "-r", "--name-only", source.revision, "scripts/vscripts").decode().splitlines()
    paths = {name[len("scripts/vscripts/"):-4]: name for name in names if name.endswith(".lua")}
    overrides = {"systems/player_profile_service", "core/scheduler", "core/test_access_policy",
                 "systems/archive_http_adapter", "systems/match_setup_service",
                 "debug/mode_unlock_test", "debug/offline_logic_test",
                 "config/generated/ui_static_catalog_lookup", "config/generated/ui_compact_wire_budget"}
    pending = ["systems/archive_service", "config/generated/player_gameplay_stats", "core/json_encoder"]
    sources = {}
    while pending:
        name = pending.pop()
        if name in sources or name in overrides: continue
        need(name in paths, "immutable_archive_dependency_missing:" + name)
        text = source.read(paths[name]).decode("utf-8-sig")
        sources[name] = text
        for dependency in re.findall(r"\brequire\s*\(?\s*[\"']([^\"']+)[\"']", text):
            if dependency in paths and dependency not in sources and dependency not in overrides:
                pending.append(dependency)
    need(len(sources) <= 512, "archive_metadata_dependency_budget_exceeded")
    script = "local sources=" + lua_literal(sources) + "\n" + r'''
local profile={revision=1,save={gameplay_stats={},content_inventory={},archive={}},entitlements={}}
local function copy(v) if type(v)~="table" then return v end local r={} for k,c in pairs(v) do r[k]=copy(c) end return r end
local function forbidden() error("catalogue_projection_has_side_effect") end
local provider={archive_enabled=function() return false end}
local loaded={
 ["systems/player_profile_service"]={get_account_profile=function() return copy(profile) end,get_profile=function() return copy(profile) end,get_provider=function() return provider end,update_save_sections=forbidden},
 ["core/scheduler"]={after=forbidden,every=forbidden,cancel=function() end},
 ["core/test_access_policy"]={enabled=function() return false end,allowed=function() return true end,enforce=function() return true end},
 ["systems/archive_http_adapter"]={enabled=function() return false end},
 ["systems/match_setup_service"]={get_mode=function() return "standard" end,get_profile_mode=function() return "standard" end,get_session_id=function() return "public_catalogue" end,is_mode_selected=function() return true end},
 ["debug/mode_unlock_test"]={is_enabled=function() return true end},
 ["debug/offline_logic_test"]={is_enabled=function() return true end,is_provider=function(v) return v==provider end}
}
local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,pcall=pcall,select=select,
 tonumber=tonumber,tostring=tostring,type=type,unpack=unpack,rawget=rawget,rawset=rawset,
 setmetatable=setmetatable,getmetatable=getmetatable,math=math,string=string,table=table,
 os={time=function() return 1700000000 end,clock=os.clock},print=function() end,
 IsInToolsMode=function() return false end,IsServer=function() return true end,IsClient=function() return false end,
 GetMapName=function() return "template_map" end,RandomInt=forbidden,CreateHTTPRequestScriptVM=forbidden,
 GameRules={GetGameTime=function() return 0 end,IsCheatMode=function() return false end},
 PlayerResource={GetPlayer=function() return nil end,IsValidPlayerID=function(_,id) return id==0 end},
 CustomNetTables={SetTableValue=forbidden},CustomGameEventManager={RegisterListener=forbidden,Send_ServerToPlayer=forbidden}}
env._G=env;env.package={loaded=loaded}
local requiring={}
local function require_public(name)
 if loaded[name]~=nil then return loaded[name] end
 assert(sources[name],"missing_readonly_module:"..tostring(name));assert(not requiring[name],"catalogue_dependency_cycle:"..name)
 requiring[name]=true;local fn=assert(loadstring(sources[name],"@immutable/"..name));setfenv(fn,env)
 local value=fn();requiring[name]=nil;loaded[name]=value==nil and true or value;return loaded[name]
end
env.require=require_public
for _,row in ipairs(require_public("config/generated/player_gameplay_stats").rows) do if row.enabled~=false then profile.save.gameplay_stats[row.field_id]=tonumber(row.default_value) or 0 end end
local archive=require_public("systems/archive_service");archive.set_clock(function() return 1700000000 end)
local categories=require_public("config/generated/archive_categories")
local result={pages={},held_pages={}}
for _,category in ipairs(categories.rows) do if category.enabled then
 local page=archive.snapshot(0,category.category_id);assert(page.ok);page.daily_limits=nil;result.pages[category.category_id]=page
end end
profile.save.archive.shadow_counts={};profile.save.archive.cage_counts={}
for _,row in ipairs(require_public("config/generated/archive_shadow_items").rows) do if row.enabled then profile.save.archive.shadow_counts[row.item_id]=1 end end
for _,row in ipairs(require_public("config/generated/archive_cage_items").rows) do if row.enabled then profile.save.archive.cage_counts[row.item_id]=1 end end
for _,id in ipairs({"shadow","pet"}) do local page=archive.snapshot(0,id);assert(page.ok);page.daily_limits=nil;result.held_pages[id]=page end
io.write(require_public("core/json_encoder").encode(result))
'''
    result = subprocess.run([lua, "-"], input=script.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=20, check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    need(len(result.stdout) <= 8 * 1024 * 1024, "archive_metadata_output_budget_exceeded")
    return json.loads(result.stdout)


def archive_templates(seed, tables):
    """Compile immutable real projector output into display-only templates.

    Dynamic values are never retained as permanent metadata. Declared zero
    defaults apply only after the server's atomic full/known+zero-mask commit.
    """
    header_fields = {
        "revision": "source_revision", "has_pass": "has_pass", "pending": "pending",
        "upgrade_pending": "upgrade_pending", "title_preview": "title_preview",
        "fishing.ready": "ready", "fishing.owned": "owned_count", "fishing.total": "total", "fishing.types": "types",
        "starjoy.balance": "balance", "starjoy.earned": "earned", "starjoy.level": "level",
        "buildings.faith": "faith", "buildings.earned_today": "earned_today", "buildings.daily_cap": "daily_cap", "buildings.per_clear": "per_clear",
        "online.actual_seconds": "actual_seconds", "online.map_seconds": "map_seconds", "online.coins": "coins", "online.level": "level", "online.max_level": "target",
        "social.tickets": "tickets", "social.remaining": "remaining", "social.total": "total", "social.draw_total": "draws", "social.unlocked": "unlocked",
    }
    row_fields = {"count": "count", "completed": "completed", "can_upgrade": "can_upgrade", "equipped": "equipped",
                  "count_known": "known", "owned": "owned", "quantity_unknown": "quantity_unknown", "unlocked": "unlocked",
                  "reward_count": "reward_count", "can_promote": "can_promote", "automatic": "automatic", "preview_only": "preview_only"}
    social = {"friend", "ex", "wife", "concubine", "beast"}
    # A bit is an explicit declaration that the corresponding server-derived
    # zero is present; these defaults do not arise from merely receiving full.
    zero_fields = ["count", "completed", "can_upgrade", "equipped", "owned", "quantity_unknown", "unlocked", "reward_count", "can_promote", "level", "fragment_total", "visible"]
    result = {"categories": next(iter(seed["pages"].values()))["categories"], "pages": {},
              "header_fields": header_fields, "row_fields": row_fields, "zero_fields": zero_fields,
              "zero_mask": (1 << len(zero_fields)) - 1,
              "social_rules": [{k: v for k, v in row.items() if k in {"pool_id", "quality_weight_n", "quality_weight_r", "quality_weight_sr", "quality_weight_ssr", "quality_weight_ur"}}
                               for row in tables["archive_social_rules"] if row.get("enabled") is not False]}
    for category, page in seed["pages"].items():
        header = {k: v for k, v in page.items() if k not in {"rows", "categories", "last_draw"}}
        paths = {}
        def strip(value, prefix=""):
            for key in list(value):
                path = prefix + key
                if path in header_fields:
                    paths[path] = header_fields[path];del value[key]
                elif path in {"social.rarity_probabilities", "social.rarity_base_probabilities"}: del value[key]
                elif isinstance(value[key], dict): strip(value[key], path + ".")
        strip(header)
        rows = seed["held_pages"].get(category, page)["rows"]
        out = {"header": header, "header_paths": paths, "rows": [], "filtered": category in {"shadow", "pet"}}
        for original in rows:
            static = dict(original);dynamic = {};formatter = {}
            for name, field in row_fields.items():
                if name in static: dynamic[name] = field;del static[name]
            if category in {"building", "work", "fragment"}:
                dynamic["level"] = "level";del static["level"]
            if category == "boss":
                dynamic["target"] = "target";del static["target"]
                formatter["name"] = "boss";formatter["name_base"] = re.sub(r"（\d+次）$", "", static.pop("name"))
            if category == "titles":
                dynamic["preview_only"] = "preview_only"
                formatter["preview_condition"] = "测试试穿 · 正式条件待开放"
            if category in social:
                for name in ("draw_probability", "initial_draw_probability", "quality_draw_probability"): static.pop(name)
                if static["draw_enabled"] == 1:
                    formatter["description"] = "social"
                    formatter["description_base"] = static.pop("description").rsplit("（每件）\n已拥有", 1)[0]
            elif category == "building":
                formatter.update(description="building", description_base=static.pop("description").rsplit("\n当前等级：", 1)[0])
            elif category == "work":
                formatter.update(description="work", description_base=static.pop("description").rsplit("\n激活消耗：", 1)[0])
            elif category == "fragment":
                description = static.pop("description");match = re.fullmatch(r"当前Lv\d+，累计获得\d+片。每20片晋升1级。\n(.*)", description, re.S)
                need(match is not None, "archive_fragment_description_template_unknown")
                formatter.update(description="fragment", description_tail=match[1]);dynamic["fragment_total"] = "fragment_total"
            out["rows"].append({"key": "archive:" + category + ":" + original["id"], "static": static, "dynamic": dynamic, "formatter": formatter})
        result["pages"][category] = out
    return result


def make_catalog(source, lua, operator=None, atlas_reference=None):
    tables = {name: csv_table(source.read("data/csv/存档系统/" + name + ".csv")) for name in TABLES}
    lottery = {name: csv_table(source.read("data/csv/抽奖系统/" + name + ".csv")) for name in LOTTERY_TABLES}
    actual = generated_rows(source, [*TABLES, *LOTTERY_TABLES, "archive_commerce_goods"], lua)
    for name, expected in {**tables, **lottery}.items():
        need(expected == actual[name], "csv_runtime_generated_config_drift:" + name)
    tables["archive_commerce_goods"] = actual["archive_commerce_goods"]
    # The artwork inventories use ordinary CSV rather than the gameplay
    # #types schema and are not generated authority/rule configuration.
    for name in ("archive_item_icons", "archive_icon_presentation"):
        raw = source.read("data/csv/存档系统/" + name + ".csv")
        values = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
        for row in values:
            if "enabled" in row: row["enabled"] = row["enabled"] not in ("0", "false")
        tables[name] = values
    resources = json.loads(source.read("data/ui/item_resources.json"))
    need(resources.get("schema_version") == 1, "item_resource_schema_unknown")
    resource_index = {}
    for item in resources["items"]:
        for key in [item["id"], *item.get("aliases", [])]:
            need(key not in resource_index or resource_index[key]["id"] == item["id"], "resource_alias_collision:" + key)
            resource_index[key] = item
    icon_index = {(row["category_id"], row["item_id"]): row for row in tables["archive_item_icons"] if row.get("enabled") is not False}
    records = {}
    def add(key, domain, kind, business_id, definition=None, category=None):
        need(key not in records, "duplicate_public_record:" + key)
        entry = dict(key=key, domain=domain, kind=kind, business_id=str(business_id), definition=definition or {})
        if category is not None: entry["category"] = category
        item = resource_index.get(str(business_id))
        icon = icon_index.get((category, str(business_id)))
        if item:
            entry["resource_id"] = item["id"]
            entry["definition"].setdefault("icon", item.get("uri"))
            entry["definition"].setdefault("icon_type", "image")
        elif icon:
            entry["definition"].setdefault("icon", icon.get("icon_path"))
            entry["definition"].setdefault("icon_type", "image")
        records[key] = entry
    for row in tables["archive_categories"]:
        if row.get("enabled") is not False:
            identity = row["category_id"]
            add("archive:category:" + identity, "archive", "category", identity, public_definition(row), identity)
    for name, (category, identity_field) in ROW_TABLES.items():
        for row in tables[name]:
            if row.get("enabled") is False: continue
            identity = str(row[identity_field])
            add("archive:" + category + ":" + identity, "archive", "row", identity, public_definition(row), category)
    for row in tables["archive_social_items"]:
        if row.get("enabled") is False: continue
        category, identity = row["pool_id"], row["item_id"]
        add("archive:" + category + ":" + identity, "archive", "row", identity, public_definition(row), category)
    for row in tables["archive_daily_items"]:
        if row.get("enabled") is False: continue
        identity = row["item_id"]
        add("daily:item:" + identity, "daily", "item", identity, public_definition(row))
        add("archive:points:" + identity, "archive", "row", identity, public_definition(row), "points")
    for row in lottery["lottery_item_definitions"]:
        if row.get("enabled") is False or row.get("item_type") != "积分道具": continue
        identity = row["item_id"]
        add("archive:points:" + identity, "archive", "row", identity, public_definition(row), "points")
    # Stackable welfare has an independently maintained definition, not a
    # fabricated reward copied from a screenshot or inferred from ownership.
    for row in tables["archive_stackable_items"]:
        if row.get("enabled") is False or not row.get("description"): continue
        key = "archive:points:" + row["item_id"]
        definition = public_definition(row)
        if key in records:
            records[key]["stackable_definition"] = definition
        else: add(key, "archive", "row", row["item_id"], definition, "points")
    source.read("scripts/vscripts/systems/archive_challenge_rewards.lua")
    challenge_text = source.read("scripts/vscripts/systems/archive_challenge_rewards.lua").decode("utf8")
    # These two labels live in the existing projector rather than a CSV.
    for identity, name, description in (
        ("football", "绿茵积分", "绿茵挑战获得的永久积分；每次10点，每日最多100点。"),
        ("watermelon", "西瓜积分", "西瓜挑战获得的永久积分；每次1点，每日最多10点。"),
    ):
        need(name in challenge_text and description in challenge_text, "challenge_public_text_changed:" + identity)
        key = "challenge_points_" + identity
        add("archive:points:" + key, "archive", "row", key, {"name": name, "description": description, "quality": "gold"}, "points")
    for row in tables["archive_daily_schedule"]:
        if row.get("enabled") is False: continue
        identity = row["day_id"]
        add("daily:cycle:" + str(identity), "daily", "cycle", identity, public_definition(row))
    for index in range(1, 29):
        add("daily:calendar:" + str(index), "daily", "calendar", index, {"schedule_day": (index - 1) % 7 + 1})
    for row in tables["archive_benefit_rewards"]:
        if row.get("enabled") is False: continue
        add("daily:benefit:" + row["reward_id"], "daily", "benefit", row["reward_id"], public_definition(row))
    for track in ("daily_time", "daily_wins", "weekly_time"):
        add("daily:track:" + track, "daily", "track", track)
    add("daily:state", "daily", "state", "state", public_definition(tables["archive_daily_rules"][0]))
    add("daily:premium", "daily", "premium", "premium", {"name": "周末高级装备", "configured": False})
    for kind in ("claim", "benefit"):
        add("daily:ack:" + kind, "daily", "ack", kind)
    seed = json.loads(source.read("data/ui/lottery_catalog.json"))
    need(hashlib.md5(seed["catalog_json"].encode("ascii"), usedforsecurity=False).hexdigest() == seed["md5"], "lottery_public_catalog_digest_invalid")
    public = json.loads(seed["catalog_json"])
    need(public.get("schema") == 1, "lottery_public_schema_unknown")
    public_items = {}
    for snapshot in public["snapshots"]:
        pool = snapshot["selected_pool"]
        add("lottery:pool:" + pool["id"], "lottery", "pool", pool["id"], public_definition(pool))
        for item in snapshot["items"]:
            if item["id"] in public_items: need(public_items[item["id"]] == item, "public_lottery_item_conflict:" + item["id"])
            public_items[item["id"]] = item
    for identity, row in public_items.items():
        add("lottery:item:" + identity, "lottery", "item", identity, public_definition(row))
    for row in lottery["lottery_currency_definitions"]:
        if row.get("enabled") is False: continue
        add("lottery:currency:" + row["currency_id"], "lottery", "currency", row["currency_id"], public_definition(row))
    add("lottery:state", "lottery", "state", "state")
    add("lottery:receipt", "lottery", "receipt", "receipt")
    for index in range(1, 11): add("lottery:result:" + str(index), "lottery", "result", index)
    add("hud:state", "hud", "state", "state")
    for index in range(1, 9):
        add("wire:hello:" + str(index), "wire", "schema_word", index, {"word_index": index})
    add("wire:control", "wire", "control", "control")
    grid = grid_projection_seed(source, lua, atlas_reference, operator)
    for profile in grid["profiles"]:
        add("grid:profile:" + profile["ability_name"], "grid", "profile", profile["ability_name"], profile)
    for name in ("input", "state", "validation", "commit"):
        add("grid:" + name, "grid", name, name)
    for name in ("min_display", "max_display", "min_build", "max_build", "plane"):
        add("grid:layout:" + name, "grid", "layout", name)
    for index in range(1, grid["max_footprint_cells"] + 1):
        add("grid:cell:" + str(index), "grid", "cell", index)
    for kind, limit in (("area", grid["dynamic_area_words"]), ("static", grid["static_area_words"])):
        add("grid:" + kind + ":meta", "grid", kind + "_meta", "meta")
        for index in range(1, limit + 1):
            add("grid:" + kind + ":word:" + str(index), "grid", kind + "_word", index)
    selected = selected_projection_seed(source, lua, operator)
    selected["text_by_value"] = {}
    for name in ("input", "state"):
        add("selected:" + name, "selected", name, name)
    for index in range(1, 5):
        add("selected:zero:" + str(index), "selected", "zero", index, {"offset": (index - 1) * 32})
    selected["metric_paths"] = []
    for path in selected["numeric_paths"]:
        key = "selected:metric:" + path
        add(key, "selected", "metric", path, {"path": path, "kind": "number"})
        selected["metric_paths"].append({"path": path, "kind": "number", "key": key})
    for path in selected["text_paths"]:
        key = "selected:metric:" + path
        add(key, "selected", "metric", path, {"path": path, "kind": "text"})
        selected["metric_paths"].append({"path": path, "kind": "text", "key": key})
    for value in selected["text_values"]:
        key = "selected:text:" + digest(value.encode("utf8"))
        add(key, "selected", "text", value, {"value": value})
        selected["text_by_value"][value] = key
    auxiliary = {name: [public_definition(row) for row in tables[name] if row.get("enabled") is not False] for name in
                 ("archive_daily_rules", "archive_daily_schedule", "archive_social_rules", "archive_building_rules", "archive_daily_limits")}
    auxiliary["fragment_levels"] = [{key: row[key] for key in ("fragment_id", "level", "required_total", "description") if key in row}
                                     for row in tables["archive_fragment_levels"] if row.get("enabled") is not False]
    auxiliary["lottery_public"] = public
    auxiliary["lottery_config_hash"] = seed["config_hash"]
    auxiliary["grid"] = grid
    auxiliary["selected"] = selected
    daily_source = source.read("scripts/vscripts/systems/archive_daily_rewards.lua").decode("utf8")
    daily_text = {
        "subtitle": "每日领取 · 七次循环",
        "rule_text": "北京时间每日05:00刷新；断签不重置累计进度。通行证奖励按累计签到次数发放。",
        "premium_description": "周周期与装备候选池尚未配置；现有累计签到通行证奖励仍按原规则发放。",
    }
    need(all(value in daily_source for value in daily_text.values()), "daily_public_template_source_changed")
    auxiliary["daily_text"] = daily_text
    seed = archive_projection_seed(source, lua)
    auxiliary["archive_projection"] = archive_templates(seed, tables)
    title_source = source.read("scripts/vscripts/systems/title_presentation_service.lua").decode("utf8")
    need("测试试穿 · 正式条件待开放" in title_source, "title_preview_public_condition_changed")
    points = {row["id"]: row for row in seed["pages"]["points"]["rows"]}
    for entry in records.values():
        if entry["domain"] == "daily" and entry["kind"] == "item":
            projected = points[entry["business_id"]]
            for name in ("duplicate_points", "duplicate_currency", "converted_currency"):
                entry["definition"][name] = projected[name]
    benefits_source = source.read("scripts/vscripts/systems/archive_benefit_rewards.lua").decode("utf8")
    for identity, description in (("lottery_ticket", "用于地图抽奖。"), ("special_lottery_ticket", "用于修仙、龙骑与暑期宝箱。")):
        need(description in benefits_source, "benefit_currency_description_source_changed")
        if "lottery:currency:" + identity in records:
            records["lottery:currency:" + identity]["definition"]["description"] = description
    return records, auxiliary


def validate_registry(registry, previous=None):
    need(registry.get("format") == FORMAT and isinstance(registry.get("records"), list), "registry_schema_unknown")
    ids, keys = {}, {}
    for row in registry["records"]:
        identity, key = row.get("id"), row.get("key")
        need(type(identity) is int and 1 <= identity <= MAX_RECORD, "record_id_out_of_range")
        need(isinstance(key, str) and re.fullmatch(r"[A-Za-z0-9_.:-]+", key) is not None, "record_key_invalid")
        need(identity not in ids and key not in keys, "registry_id_or_key_reused")
        need(type(row.get("tombstone")) is bool, "explicit_tombstone_required")
        ids[identity], keys[key] = row, row
    supplied_fields = registry.get("fields")
    need(isinstance(supplied_fields, list) and 0 < len(supplied_fields) <= len(fields())
         and supplied_fields == fields()[:len(supplied_fields)], "field_dictionary_changed_without_schema_review")
    enums = registry.get("public_enums", {})
    need(isinstance(enums, dict), "public_enum_registry_invalid")
    for name, values in enums.items():
        need(name == "grid_errors" and isinstance(values, list) and 2 <= len(values) <= 65536
             and values[:2] == ["", "grid_validation_failed"]
             and all(isinstance(value, str) for value in values) and len(values) == len(set(values)),
             "public_enum_registry_invalid")
    if previous is not None:
        validate_registry(previous)
        need(registry["fields"][:len(previous["fields"])] == previous["fields"], "historical_field_meaning_changed")
        maximum = max((row["id"] for row in previous["records"]), default=0)
        for old in previous["records"]:
            new = ids.get(old["id"])
            need(new is not None and new["key"] == old["key"], "historical_id_removed_or_reassigned")
            for key in ("domain", "kind", "business_id", "category"):
                need(new.get(key) == old.get(key), "historical_identity_semantics_changed")
            need(not old["tombstone"] or new["tombstone"], "tombstone_cannot_be_reactivated")
        old_keys = {row["key"] for row in previous["records"]}
        need(all(row["id"] > maximum for row in registry["records"] if row["key"] not in old_keys), "new_ids_must_append_after_historical_maximum")
        for name, values in previous.get("public_enums", {}).items():
            need(name in enums and enums[name][:len(values)] == values, "historical_public_enum_meaning_changed")
    return ids, keys


def update_registry(records, previous=None, public_enums=None):
    if previous is not None: validate_registry(previous)
    rows = json.loads(json.dumps(previous["records"])) if previous else []
    by_key = {row["key"]: row for row in rows}
    for row in rows:
        if row["key"] not in records: row["tombstone"] = True
        elif row["tombstone"]: raise ValueError("tombstoned_business_key_reintroduced:" + row["key"])
    next_id = max((row["id"] for row in rows), default=0) + 1
    for key in sorted(set(records) - set(by_key)):
        need(next_id <= MAX_RECORD, "record_id_space_exhausted")
        identity = {name: value for name, value in records[key].items() if name not in {"definition", "resource_id", "stackable_definition"}}
        rows.append(dict(identity, id=next_id, tombstone=False));next_id += 1
    result = dict(format=FORMAT, generation=(previous.get("generation", 0) + 1) if previous else 1,
                  parent_sha256=digest(canonical(previous)) if previous else None, records=rows, fields=fields())
    enums = public_enums if public_enums is not None else (previous or {}).get("public_enums", {})
    if enums: result["public_enums"] = enums
    if previous and rows == previous["records"] and previous["fields"] == fields() and enums == previous.get("public_enums", {}): result = previous
    validate_registry(result, previous)
    return result


def registry_history(registry, directory):
    seen = set()
    current = registry
    for _ in range(1024):
        current_sha = digest(canonical(current))
        need(current_sha not in seen, "registry_history_cycle")
        seen.add(current_sha);validate_registry(current)
        parent = current.get("parent_sha256")
        if parent is None:
            need(current.get("generation") == 1, "registry_initial_generation_invalid")
            return
        need(re.fullmatch(r"[a-f0-9]{64}", parent or "") is not None, "registry_parent_digest_invalid")
        path = Path(directory) / (parent + ".json")
        need(path.is_file() and path.stat().st_size <= 8 * 1024 * 1024, "registry_history_parent_missing")
        previous = json.loads(path.read_bytes())
        need(digest(canonical(previous)) == parent and previous["generation"] + 1 == current["generation"], "registry_history_parent_digest_or_generation_mismatch")
        validate_registry(current, previous);current = previous
    raise ValueError("registry_history_budget_exceeded")


def registry_history_git(registry, source):
    """Validate and return every committed canonical history node, including self."""
    current = registry;seen = set();result = {}
    for _ in range(1024):
        identity = digest(canonical(current))
        need(identity not in seen, "registry_history_cycle");seen.add(identity)
        relative = "data/ui/registry_history/" + identity + ".json"
        stored = json.loads(source.read(relative))
        need(canonical(stored) == canonical(current), "committed_registry_history_node_changed")
        result[identity] = canonical(stored);validate_registry(stored)
        parent = stored.get("parent_sha256")
        if parent is None:
            need(stored.get("generation") == 1, "registry_initial_generation_invalid")
            return result
        previous = json.loads(source.read("data/ui/registry_history/" + parent + ".json"))
        need(digest(canonical(previous)) == parent and previous["generation"] + 1 == stored["generation"],
             "registry_history_parent_digest_or_generation_mismatch")
        validate_registry(stored, previous);current = previous
    raise ValueError("registry_history_budget_exceeded")


def verify_executed_operator(operator):
    for relative in ("tools/build_ui_static_catalog.py", "tools/extract_grid_static_atlas_20261103.py"):
        declared = operator.read(relative).replace(b"\r\n", b"\n")
        actual = (ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
        need(declared == actual, "executed_generator_does_not_match_operator_commit:" + relative)
        if relative == "tools/build_ui_static_catalog.py":
            need(digest(declared)==EXECUTED_GENERATOR_LF_SHA256,"loaded_generator_does_not_match_operator_commit")


def build(game, content_revision, lua, previous=None, operator=None, atlas_reference=None):
    operator = operator or game;atlas_reference = atlas_reference or game
    if getattr(operator,"input_origin", "").startswith("UNIT_TEST") is False:
        verify_executed_operator(operator)
    records, auxiliary = make_catalog(game, lua, operator, atlas_reference)
    lua_binary = Path(lua).resolve(strict=True)
    need(lua_binary.is_file() and lua_binary.stat().st_size<=32*1024*1024,"bounded_explicit_lua_binary_required")
    lua_sha256 = digest(lua_binary.read_bytes())
    old_errors = (previous or {}).get("public_enums", {}).get("grid_errors", ["", "grid_validation_failed"])
    errors = [*old_errors, *sorted(set(auxiliary["grid"]["errors"]) - set(old_errors))]
    auxiliary["grid"]["errors"] = errors
    registry = update_registry(records, previous, {"grid_errors": errors})
    record_ids = {row["key"]: row["id"] for row in registry["records"]}
    for metric in auxiliary["selected"]["metric_paths"]:
        metric["record"] = record_ids[metric["key"]]
    source_hashes = {name: digest(raw) for name, raw in sorted(game.cache.items())}
    operator_hashes = {name: digest(raw) for name, raw in sorted(operator.cache.items())}
    reference_hashes = {name: digest(raw) for name, raw in sorted(atlas_reference.cache.items())}
    revisions = dict(game=game.revision, content=content_revision, operator=operator.revision,
                     atlas_reference=atlas_reference.revision)
    registry_sha = digest(canonical(registry))
    schema = dict(wire_format=1, registry_format=FORMAT, records=registry["records"], fields=registry["fields"],
                  definitions=records, auxiliary=auxiliary, source_hashes=source_hashes,
                  source_binary_hashes=game.binary_hashes, operator_hashes=operator_hashes,
                  atlas_reference_hashes=reference_hashes, source_revisions=revisions, execution_lua_sha256=lua_sha256)
    schema_sha = digest(canonical(schema))
    data = dict(sha256=schema_sha, registry_sha256=registry_sha, **schema)
    script = ('// AUTO-GENERATED account-free display definitions; no reward authority.\n(function(){"use strict";\n'
              'var cfg=GameUI.CustomUIConfig();if(cfg.SurvivalUICatalog&&cfg.SurvivalUICatalog.Data&&cfg.SurvivalUICatalog.Data.sha256===' + json.dumps(schema_sha) + ')return;\nvar data=' + canonical(data).decode().strip() + ';\n'
              'var byId=Object.create(null),byKey=Object.create(null),fieldIds=Object.create(null),zeroFields=Object.create(null),archiveRows=Object.create(null),archiveFields=Object.create(null);data.records.forEach(function(row){byId[row.id]=row;byKey[row.key]=row.id;});data.fields.forEach(function(row){fieldIds[row.name]=row.id;});\n'
              'data.auxiliary.archive_projection.zero_fields.forEach(function(name){zeroFields[name]=true;});Object.keys(data.auxiliary.archive_projection.pages).forEach(function(category){var page=data.auxiliary.archive_projection.pages[category];page.rows.forEach(function(row){var id=byKey[row.key],fields=Object.create(null);archiveRows[id]=row;archiveFields[id]=fields;Object.keys(row.dynamic).forEach(function(name){fields[row.dynamic[name]]=true;});if(fields.count)fields.count_hi=true;if(page.filtered)fields.visible=true;});});\n'
              'function freeze(value){if(!value||typeof value!=="object"||Object.isFrozen(value))return;Object.keys(value).forEach(function(key){freeze(value[key]);});Object.freeze(value);}\n'
              'freeze(data);freeze(byId);freeze(byKey);freeze(fieldIds);cfg.SurvivalUICatalog={Data:data,ById:byId,ByKey:byKey,FieldIds:fieldIds,\n'
              'Resolve:function(id,sha){var row=byId[id];return sha===data.sha256&&row&&!row.tombstone?row:null;},\n'
              'Definition:function(id,sha){var row=this.Resolve(id,sha);return row?data.definitions[row.key]:null;},\n'
              'ArchiveScope:function(category,sha){return sha===data.sha256?data.auxiliary.archive_projection.pages[category]||null:null;},\n'
              'ArchiveSparseDefault:function(category,id,name,known,mask,sha){var row=this.Resolve(id,sha),template=archiveRows[id];if(!row||row.category!==category||!template||!archiveFields[id][name]||known!==1||mask!==data.auxiliary.archive_projection.zero_mask)return undefined;if(name==="known")return template.dynamic.count_known?1:undefined;return zeroFields[name]||name==="count_hi"?0:undefined;}};\n})();\n').encode()
    lookup = dict(sha256=schema_sha, registry_sha256=registry_sha, format=FORMAT,
                  records={row["id"]: row for row in registry["records"]},
                  by_key={row["key"]: row["id"] for row in registry["records"]},
                  fields={row["id"]: row for row in registry["fields"]},
                  field_by_name={row["name"]: row["id"] for row in registry["fields"]},
                  archive_projection=auxiliary["archive_projection"], grid=auxiliary["grid"], selected=auxiliary["selected"])
    server = ("-- AUTO-GENERATED display wire identities only; no reward rules.\nreturn " + lua_literal(lookup) + "\n").encode()
    manifest = dict(kind="IMMUTABLE_PUBLIC_UI_CATALOG_PROTOTYPE_NOT_CONNECTED", game_revision=game.revision,
                    content_revision=content_revision, schema_sha256=schema_sha, registry_sha256=registry_sha,
                    source_revisions=revisions, operator_hashes=operator_hashes, atlas_reference_hashes=reference_hashes,
                    execution_lua_sha256=lua_sha256,
                    content_blob_inputs_read=0, content_revision_is_compile_pair_only=True,
                    source_hashes=source_hashes, source_binary_hashes=game.binary_hashes, records=len(registry["records"]), active_records=len(records),
                    fields=len(registry["fields"]), domain_counts={domain: sum(row["domain"] == domain for row in records.values()) for domain in ("archive", "daily", "lottery", "hud", "wire", "grid", "selected")},
                    csv_runtime_config_rows_equal=True, runtime_connected=False, workshop_uploaded=False,
                    outputs={CATALOG_PATH: digest(script), LOOKUP_PATH: digest(server), REGISTRY_PATH: registry_sha})
    return {CATALOG_PATH: script, LOOKUP_PATH: server, REGISTRY_PATH: canonical(registry), MANIFEST_PATH: canonical(manifest)}, registry


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--content-source-revision", required=True)
    parser.add_argument("--operator-source-revision", required=True)
    parser.add_argument("--atlas-reference-revision", required=True)
    parser.add_argument("--output-directory", type=Path, default=OUTPUT)
    parser.add_argument("--registry", default=REGISTRY_PATH, help="Repository-relative committed registry path")
    parser.add_argument("--initialize-registry", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--lua", default=shutil.which("lua5.1") or shutil.which("lua") or "C:/Program Files/lua/bin/lua5.1.exe")
    args = parser.parse_args(argv)
    game = GitSource(ROOT, args.source_revision)
    GitSource(CONTENT, args.content_source_revision)
    operator = GitSource(ROOT, args.operator_source_revision)
    atlas_reference = GitSource(ROOT, args.atlas_reference_revision)
    verify_executed_operator(operator)
    target = args.output_directory.resolve()
    need(target.is_relative_to(ROOT / "output"), "prototype_output_must_remain_beneath_output")
    need(not Path(args.registry).is_absolute() and ".." not in args.registry.replace("\\", "/").split("/"),
         "registry_must_be_an_immutable_repository_path")
    registry_path = args.registry.replace("\\", "/")
    previous = json.loads(game.read(registry_path)) if game.exists(registry_path) else None
    historical = {}
    if previous is not None:
        need(not args.initialize_registry, "cannot_reinitialize_an_existing_registry")
        historical = registry_history_git(previous, game)
    else: need(args.initialize_registry, "explicit_initial_registry_required")
    outputs, registry = build(game, args.content_source_revision, args.lua, previous, operator, atlas_reference)
    verify_executed_operator(operator)
    for identity, raw in historical.items(): outputs["registry_history/" + identity + ".json"] = raw
    history = target / "registry_history" / (digest(canonical(registry)) + ".json")
    outputs[str(history.relative_to(target)).replace("\\", "/")] = canonical(registry)
    for relative, raw in outputs.items():
        path = target / relative
        if args.check:
            need(path.is_file() and path.read_bytes() == raw, "generated_catalog_out_of_date:" + relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.parent.name == "registry_history" and path.exists():
                need(path.read_bytes() == raw, "immutable_registry_history_changed")
            else: path.write_bytes(raw)
    summary = json.loads(outputs[MANIFEST_PATH])
    print(json.dumps({key: summary[key] for key in ("kind", "schema_sha256", "registry_sha256", "records", "fields", "domain_counts", "runtime_connected", "workshop_uploaded")}))


if __name__ == "__main__":
    main()
