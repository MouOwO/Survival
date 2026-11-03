"""Build an account-free three-domain UI catalogue from immutable Git blobs.

Prototype outputs stay under output/: no running Lua/JS, CSV, reward rule,
database, installed package or Workshop state is changed. Numeric identities
are append-only; the preserved registry history proves IDs were not recycled.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CONTENT = Path("D:/SteamLibrary/steamapps/common/dota 2 beta/content/dota_addons/Survival")
OUTPUT = ROOT / "output/ui_static_catalog_20261103"
REGISTRY_PATH = "data/ui/ui_static_catalog_registry.json"
CATALOG_PATH = "panorama/src/scripts/custom_game/common/ui_static_catalog.js"
LOOKUP_PATH = "scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"
MANIFEST_PATH = "data/ui/ui_static_catalog_manifest.json"
FORMAT = 1
MAX_RECORD = 65535
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
        result.append(row)
    return result


class GitSource:
    def __init__(self, repository, revision):
        self.repository = Path(repository).resolve()
        need(re.fullmatch(r"[a-f0-9]{40}", revision or "") is not None, "immutable_git_revision_required")
        self.revision = revision
        self.cache = {}
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


def archive_projection_seed(source, lua):
    """Run immutable read-only projectors; all game/HTTP/write APIs are refused."""
    names = source.git("ls-tree", "-r", "--name-only", source.revision, "scripts/vscripts").decode().splitlines()
    paths = {name[len("scripts/vscripts/"):-4]: name for name in names if name.endswith(".lua")}
    overrides = {"systems/player_profile_service", "core/scheduler", "core/test_access_policy",
                 "systems/archive_http_adapter", "systems/match_setup_service",
                 "debug/mode_unlock_test", "debug/offline_logic_test"}
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


def make_catalog(source, lua):
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
    auxiliary = {name: [public_definition(row) for row in tables[name] if row.get("enabled") is not False] for name in
                 ("archive_daily_rules", "archive_daily_schedule", "archive_social_rules", "archive_building_rules", "archive_daily_limits")}
    auxiliary["fragment_levels"] = [{key: row[key] for key in ("fragment_id", "level", "required_total", "description") if key in row}
                                     for row in tables["archive_fragment_levels"] if row.get("enabled") is not False]
    auxiliary["lottery_public"] = public
    auxiliary["lottery_config_hash"] = seed["config_hash"]
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
    return ids, keys


def update_registry(records, previous=None):
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
    if previous and rows == previous["records"] and previous["fields"] == fields(): result = previous
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


def build(game, content_revision, lua, previous=None):
    records, auxiliary = make_catalog(game, lua)
    registry = update_registry(records, previous)
    source_hashes = {name: digest(raw) for name, raw in sorted(game.cache.items())}
    registry_sha = digest(canonical(registry))
    schema = dict(wire_format=1, registry_format=FORMAT, records=registry["records"], fields=registry["fields"],
                  definitions=records, auxiliary=auxiliary, source_hashes=source_hashes)
    schema_sha = digest(canonical(schema))
    data = dict(sha256=schema_sha, registry_sha256=registry_sha, **schema)
    script = ('// AUTO-GENERATED account-free display definitions; no reward authority.\n(function(){"use strict";\nvar data=' + canonical(data).decode().strip() + ';\n'
              'var byId=Object.create(null),byKey=Object.create(null),zeroFields=Object.create(null),archiveRows=Object.create(null),archiveFields=Object.create(null);data.records.forEach(function(row){byId[row.id]=row;byKey[row.key]=row.id;});\n'
              'data.auxiliary.archive_projection.zero_fields.forEach(function(name){zeroFields[name]=true;});Object.keys(data.auxiliary.archive_projection.pages).forEach(function(category){var page=data.auxiliary.archive_projection.pages[category];page.rows.forEach(function(row){var id=byKey[row.key],fields=Object.create(null);archiveRows[id]=row;archiveFields[id]=fields;Object.keys(row.dynamic).forEach(function(name){fields[row.dynamic[name]]=true;});if(fields.count)fields.count_hi=true;if(page.filtered)fields.visible=true;});});\n'
              'function freeze(value){if(!value||typeof value!=="object")return;Object.keys(value).forEach(function(key){freeze(value[key]);});Object.freeze(value);}\n'
              'freeze(data);freeze(byId);freeze(byKey);GameUI.CustomUIConfig().SurvivalUICatalog={Data:data,ById:byId,ByKey:byKey,\n'
              'Resolve:function(id,sha){var row=byId[id];return sha===data.sha256&&row&&!row.tombstone?row:null;},\n'
              'Definition:function(id,sha){var row=this.Resolve(id,sha);return row?data.definitions[row.key]:null;},\n'
              'ArchiveScope:function(category,sha){return sha===data.sha256?data.auxiliary.archive_projection.pages[category]||null:null;},\n'
              'ArchiveSparseDefault:function(category,id,name,known,mask,sha){var row=this.Resolve(id,sha),template=archiveRows[id];if(!row||row.category!==category||!template||!archiveFields[id][name]||known!==1||mask!==data.auxiliary.archive_projection.zero_mask)return undefined;if(name==="known")return template.dynamic.count_known?1:undefined;return zeroFields[name]||name==="count_hi"?0:undefined;}};\n})();\n').encode()
    lookup = dict(sha256=schema_sha, registry_sha256=registry_sha, format=FORMAT,
                  records={row["id"]: row for row in registry["records"]},
                  by_key={row["key"]: row["id"] for row in registry["records"]},
                  fields={row["id"]: row for row in registry["fields"]},
                  field_by_name={row["name"]: row["id"] for row in registry["fields"]},
                  archive_projection=auxiliary["archive_projection"])
    server = ("-- AUTO-GENERATED display wire identities only; no reward rules.\nreturn " + lua_literal(lookup) + "\n").encode()
    manifest = dict(kind="IMMUTABLE_PUBLIC_UI_CATALOG_PROTOTYPE_NOT_CONNECTED", game_revision=game.revision,
                    content_revision=content_revision, schema_sha256=schema_sha, registry_sha256=registry_sha,
                    source_hashes=source_hashes, records=len(registry["records"]), active_records=len(records),
                    fields=len(registry["fields"]), domain_counts={domain: sum(row["domain"] == domain for row in records.values()) for domain in ("archive", "daily", "lottery", "hud", "wire")},
                    csv_runtime_config_rows_equal=True, runtime_connected=False, workshop_uploaded=False,
                    outputs={CATALOG_PATH: digest(script), LOOKUP_PATH: digest(server), REGISTRY_PATH: registry_sha})
    return {CATALOG_PATH: script, LOOKUP_PATH: server, REGISTRY_PATH: canonical(registry), MANIFEST_PATH: canonical(manifest)}, registry


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--content-source-revision", required=True)
    parser.add_argument("--output-directory", type=Path, default=OUTPUT)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--initialize-registry", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--lua", default=shutil.which("lua5.1") or shutil.which("lua") or "C:/Program Files/lua/bin/lua5.1.exe")
    args = parser.parse_args(argv)
    game = GitSource(ROOT, args.source_revision)
    GitSource(CONTENT, args.content_source_revision)
    target = args.output_directory.resolve()
    need(target.is_relative_to(ROOT / "output"), "prototype_output_must_remain_beneath_output")
    existing = args.registry or (target / REGISTRY_PATH)
    previous = json.loads(existing.read_bytes()) if existing.is_file() else None
    if previous is not None:
        need(not args.initialize_registry, "cannot_reinitialize_an_existing_registry")
        registry_history(previous, target / "registry_history")
    else: need(args.initialize_registry, "explicit_initial_registry_required")
    outputs, registry = build(game, args.content_source_revision, args.lua, previous)
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
