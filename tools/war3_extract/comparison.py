"""Compare reviewed original-map facts with the current normalized v3 contract.

Pure reference reporting: no file IO, game writes, inferred identity by global
unit name, or use of current-spec values to fill holes in the original map.
"""
from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
from decimal import Decimal
import math
import re

CURRENT_FILE = "data/balance/human_spec_v3/normalized.json"
MODE_IDS = {"standard": 1, "cold": 2, "scourge": 3, "rich": 4,
            "pure": 5, "ruins": 6, "celestial": 7}
SPECIAL_IDENTITIES = {
    "火焰巨魔": ("wild_material", "h030"), "冰烬挽歌": ("wild_material", "h031"),
    "合成宝石": ("wild_material", "h06S"), "冰之幽魂": ("wild_material", "h099"),
    "概率掉落熔火核心": ("wild_material", "h02Z"), "概率掉落精华": ("wild_material", "h08Q"),
    "真实": ("ten_commandments", "h08Z"), "信仰": ("ten_commandments", "h08R"),
    "安息": ("ten_commandments", "h08S"), "忍耐": ("ten_commandments", "h08T"),
    "无欲": ("ten_commandments", "h08U"), "戒杀": ("ten_commandments", "h08V"),
    "沉默": ("ten_commandments", "h08W"), "纯洁": ("ten_commandments", "h08X"),
    "敬神": ("ten_commandments", "h08Y"), "慈爱": ("ten_commandments", "h090"),
}
ROOM_IDENTITIES = {"木头房": "h02U", "金币房": "h02S", "属性房": "h02T", "大属性房": "h02V"}
BUILDING_IDENTITIES = {"挑战山岭巨人": "h0AH", "挑战树人": "h0AI", "挑战红龙": "h0AJ",
                       "挑战剑圣": "h0AK", "挑战炼金术师": "h0AG"}
BASE_FIELDS = {"health": "hp", "war3_armor": "armor", "attack": "attack1_base",
               "attack_interval": "attack1_interval"}


def numeric(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def equal(left, right):
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left == right
    if numeric(left) and numeric(right):
        return math.isclose(left, right, rel_tol=1e-9, abs_tol=1e-9)
    return left == right


def multiply(left, right):
    return float(Decimal(str(left)) * Decimal(str(right)))


def _indexes(rows, key):
    result = defaultdict(list)
    for row in rows:
        if isinstance(row, dict):
            result[row.get(key)].append(row)
    return result


class Comparison:
    def __init__(self, units_data, wave_rules, nonwave_data, current_spec):
        self.units = _indexes(units_data.get("units", []), "raw_id")
        self.waves = wave_rules
        self.nonwave = nonwave_data
        self.current = current_spec
        self.nonwave_rows = nonwave_data.get("units", [])
        self.result = {
            "schema": "war3_current_contract_comparison/v1",
            "source_contract": "reference_only",
            "policy": {"current_contract": CURRENT_FILE,
                "preserve_current_user_corrections": True, "writes_game_data": False,
                "current_spec_used_to_fill_original_values": False,
                "numeric_tolerance": {"relative": 1e-9, "absolute": 1e-9},
                "original_jass_sha256": wave_rules.get("source", {}).get("sha256") or
                    nonwave_data.get("provenance", {}).get("jass_sha256")},
            "current_corrections_preserved": deepcopy(current_spec.get("corrections_already_included", [])),
            "matches": [], "differences": [], "unmatched": [], "limits": [
                "这是当前配置契约与原图静态证据的对照，差异不自动表示游戏 bug，也不授权覆盖现有数值。",
                "health/attack/armor 保留小数；本报告不把护甲向下取整后的显示值作为内部数值。",
                "攻击基数、原生骰子、英雄属性和伤害事件修正分别保留，未模拟 Warcraft 引擎最终面板或每次伤害。",
                "存档表为现有最终值；原图参考值只乘一次 item.scale，不再套当前 scale 或任何难度倍率。",
                "名称只用于已经确认类别中的显式绑定；不会搜索所有同名单位来填补缺失分类或原始值。",
                "模式解锁、当前临时验收入口和存档写入策略不由原图数值对照推断。",
            ],
        }

    def missing(self, category, key, field, reason, current=None):
        self.result["unmatched"].append({"category": category, "key": str(key), "field": field,
                                         "current": current, "reason": reason})

    def record(self, category, key, field, current, original, source, pointer,
               reason="按明确身份对应后比较相同基础字段。", basis="base_value", **details):
        if current is None or original is None:
            self.missing(category, key, field, "缺少当前或原图字段；不使用另一份数据补齐。", current)
            return
        row = {"category": category, "key": str(key), "field": field,
               "current": deepcopy(current), "original": deepcopy(original),
               "current_source": {"file": CURRENT_FILE, "json_pointer": pointer},
               "source": deepcopy(source), "reason": reason, "comparison_basis": basis, **deepcopy(details)}
        match = equal(current, original)
        if numeric(current) and numeric(original):
            row["current_minus_original"] = float(Decimal(str(current)) - Decimal(str(original)))
        if not match:
            row["decision"] = "retain_current_contract"
        self.result["matches" if match else "differences"].append(row)

    def original_unit(self, raw, category, key):
        candidates = self.units.get(raw, [])
        if len(candidates) != 1:
            self.missing(category, key, "identity", f"原图 rawID {raw} 不存在或不唯一，拒绝按名称代替。")
            return None
        return candidates[0]

    def member(self, cls, raw, key):
        candidates = [r for r in self.nonwave_rows if r.get("class") == cls and r.get("raw_id") == raw]
        if len(candidates) != 1:
            self.missing(cls, key, "identity", f"缺少唯一已确认分类 {cls}/{raw}；同名单位不作为替代。")
            return None
        return candidates[0]

    @staticmethod
    def unit_source(unit, field, binding=None):
        return {"unit_field": unit.get("provenance", {}).get(field), "identity_binding": binding,
                "raw_id": unit["raw_id"]}

    def native_hp(self, unit, scale=1):
        coefficient = self.waves.get("hero_native_inputs", {}).get("coefficients", {}).get("StrHitPointBonus", {})
        hp, strength = unit.get("hp"), unit.get("strength")
        if unit.get("primary_attribute") in ("STR", "AGI", "INT"):
            if not all(numeric(v) for v in [hp, strength, coefficient.get("value")]):
                return None, {"object_hp": hp, "scale": scale, "hero_native_hp_verified": False}
            value = (Decimal(str(hp)) + Decimal(str(strength)) * Decimal(str(coefficient["value"]))) * Decimal(str(scale))
            return float(value), {"object_hp": hp, "hero_strength": strength,
                "strength_hp_coefficient": coefficient["value"], "coefficient_source": coefficient.get("source"),
                "strength_source": unit.get("provenance", {}).get("strength"), "scale": scale,
                "hero_native_hp_verified": False, "derivation": "(SLK.HP + STR * StrHitPointBonus) * scale"}
        return multiply(hp, scale) if numeric(hp) else None, {"object_hp": hp, "scale": scale}

    def base(self, category, key, current, raw, pointer, binding=None, *, hero_hp=False):
        unit = self.original_unit(raw, category, key)
        if unit is None:
            return
        for field, original_field in BASE_FIELDS.items():
            if field not in current:
                continue
            original = unit.get(original_field)
            details = {"raw_id": raw}
            basis = "base_value"
            reason = "按已确认 rawID 比较 SLK 基础字段；不叠加模式或难度倍率。"
            if hero_hp and field == "health":
                original, hp_details = self.native_hp(unit)
                details.update(hp_details)
                basis = "hero_hp_input_derived_before_spawn_multiplier"
                reason = "原图参考输入由 SLK.HP 与独立 Misc 每点力量生命系数推导；未实机验证 native setter，保留现有修正版。"
            elif field == "attack":
                details["attack_dice"] = {"count": unit.get("attack1_dice"), "sides": unit.get("attack1_sides"),
                    "count_source": unit.get("provenance", {}).get("attack1_dice"),
                    "sides_source": unit.get("provenance", {}).get("attack1_sides")}
                basis = "SLK_damage_base_component"
                reason = "仅比较当前基础攻击与 SLK.dmgplus1；骰子、英雄主属性、0x12 原生读取口径及伤害事件另计。"
            elif hero_hp and field == "war3_armor":
                basis = "object_armor_vs_corrected_contract"
                reason = "当前表已包含用户约定的护甲修正；这里列出原始 SLK.def，差异不表示应撤销该修正。"
            self.record(category, key, field, current[field], original,
                self.unit_source(unit, original_field, binding), f"{pointer}/{field}", reason, basis, **details)
        if "flying" in current:
            movement = unit.get("movement_type")
            if movement in ("fly", "foot", "horse", "amph", "float"):
                self.record(category, key, "flying", current["flying"], movement == "fly",
                    self.unit_source(unit, "movement_type", binding), f"{pointer}/flying",
                    "只比较原单位 movement_type；不推测运行时模型或移动能力覆盖。")
            else:
                self.missing(category, key, "flying", "原单位 movement_type 无法可靠判定。", current["flying"])

    def compare_wave_bases(self):
        arrays = defaultdict(list)
        for row in self.waves.get("wave_unit_arrays", []):
            arrays[row.get("array"), row.get("wave")].append(row)
        for section, array, category in [("waves", "udg_GW", "wave"), ("attack_bosses", "udg_BOSS", "attack_boss")]:
            for key, current in self.current.get(section, {}).items():
                candidates = arrays.get((array, int(key)), [])
                if len(candidates) != 1:
                    self.missing(category, key, "identity", f"缺少唯一 {array}[{key}] 原始绑定。")
                    continue
                binding = candidates[0]
                self.base(category, key, current, binding["rawid"], f"/{section}/{key}", binding.get("source"),
                          hero_hp=category == "attack_boss")
        for wave, variants in self.current.get("special_rotation", {}).items():
            for index, current in enumerate(variants):
                position = current.get("position")
                array = {2: "xgdg_CAAA", 3: "xgdg_xAAA"}.get(position)
                candidates = arrays.get((array, int(wave)), []) if array else []
                key = f"wave{wave}/slot{position}"
                if len(candidates) != 1:
                    self.missing("special_rotation", key, "identity", "轮换 position 缺少唯一原始数组绑定。")
                    continue
                binding = candidates[0]
                self.base("special_rotation", key, current, binding["rawid"],
                          f"/special_rotation/{wave}/{index}", binding.get("source"))

    def compare_nonwave(self):
        for index, current in enumerate(self.current.get("rebirth_bosses", [])):
            match = re.fullmatch(r"转生BOSS(10|[1-9])", current.get("name", ""))
            if not match:
                self.missing("rebirth", current.get("name"), "identity", "未知转生名称，不按列表序号推断。")
                continue
            order = int(match[1]); raw = "h02" + "IJKLMNOPQR"[order-1]
            member = self.member("rebirth", raw, current["name"])
            if member:
                self.base("rebirth", current["name"], current, raw, f"/rebirth_bosses/{index}", member.get("source"))
        for section, identities in [("rooms", ROOM_IDENTITIES), ("special_bosses", SPECIAL_IDENTITIES)]:
            for index, current in enumerate(self.current.get(section, [])):
                name = current.get("name")
                identity = identities.get(name)
                if not identity:
                    self.missing(section, name, "identity", "不在已确认原图类别绑定中；不按全局同名搜索。")
                    continue
                cls, raw = ("four_rooms", identity) if section == "rooms" else identity
                member = self.member(cls, raw, name)
                if member is None:
                    continue
                self.base(cls, name, current, raw, f"/{section}/{index}", member.get("source"))
                if "count" in current:
                    self.record(cls, name, "count", current["count"], member.get("initial_count"),
                        member.get("source"), f"/{section}/{index}/count",
                        "四房按每人每房首次生成数；野外/十戒按原图全图预置数。保留当前数量契约。",
                        "spawn_count", raw_id=raw, count_scope=member.get("count_scope"))
        for index, current in enumerate(self.current.get("building_challenges", [])):
            name = current.get("name"); raw = BUILDING_IDENTITIES.get(name)
            if not raw:
                self.missing("building_challenge", name, "identity", "未知建筑挑战名称。")
                continue
            member = self.member("building_challenge", raw, name)
            if member:
                for field, original_field in [("fixed_health", "hp_flat"), ("health_coefficient", "hp_next_wave_multiplier"),
                                              ("fixed_attack", "attack_flat"), ("attack_coefficient", "attack_next_wave_multiplier")]:
                    self.record("building_challenge", name, field, current.get(field),
                        member.get("coefficients", {}).get(original_field), member.get("source"),
                        f"/building_challenges/{index}/{field}",
                        "比较建筑挑战公式系数；next-wave 为 udg_GW[udg_BC+1]，不使用占位单位默认 HP。", raw_id=raw)

    def compare_archives(self):
        for index, current in enumerate(self.current.get("save_challenges", [])):
            name, boss = current.get("name", ""), current.get("boss")
            cls = ("archive_shadow" if name.startswith("虚空之影") else
                   "archive_beast_hunt" if name.startswith("神兽狩猎-") else
                   "archive_dragon" if name.startswith("秘法牢笼-") else None)
            candidates = [r for r in self.nonwave_rows if r.get("class") == cls and r.get("name") == boss] if cls and boss else []
            if len(candidates) != 1:
                self.missing("save_challenges", name, "identity", "当前类别前缀和 boss 字段没有唯一原图类别绑定；不以同名其他单位替代。")
                continue
            member = candidates[0]; unit = self.original_unit(member["raw_id"], cls, name)
            if unit is None:
                continue
            scale = member.get("entry_item_scale")
            if not numeric(scale):
                self.missing(cls, name, "scale", "原图 ItemData.scale 缺失，不使用当前 scale 补齐。")
                continue
            pointer = f"/save_challenges/{index}"
            source = {"identity_binding": member.get("mapping_source"), "spawn": member.get("source"),
                      "item": member.get("entry_item_source"), "unit_fields": unit.get("provenance")}
            self.record(cls, name, "scale", current.get("scale"), scale, source, pointer + "/scale",
                        "scale 仅用于核对原图物品输入；当前表列最终值不会再次乘 scale。", raw_id=unit["raw_id"])
            self.record(cls, name, "count", current.get("count"), member.get("initial_count"), source, pointer + "/count",
                        "比较单次挑战生成数，作用范围另列。", count_scope=member.get("count_scope"))
            hp, hp_details = self.native_hp(unit, scale)
            self.record(cls, name, "health", current.get("health"), hp, source, pointer + "/health",
                "当前为约定最终值；原图参考为 (SLK.HP+STR×Misc系数)×原物品scale，native setter与显示舍入未实机验证。保留当前值。",
                "hero_native_hp_reference_vs_current_final", raw_id=unit["raw_id"], **hp_details)
            self.record(cls, name, "war3_armor", current.get("war3_armor"), unit.get("armor"), source, pointer + "/war3_armor",
                "原图出生公式护甲×1；当前最终表包含约定修正。此差异不是应撤销修正的证据。",
                "object_armor_vs_corrected_contract", raw_id=unit["raw_id"])
            original_attack = multiply(unit["attack1_base"], scale) if numeric(unit.get("attack1_base")) else None
            self.record(cls, name, "attack", current.get("attack"), original_attack, source, pointer + "/attack",
                "当前表是最终攻击口径；original 仅为 SLK.dmgplus1×原物品scale。骰子、主属性和0x12作用位置仍需native验证，不能据此把+2差异判为bug。",
                "final_attack_vs_scaled_base_component", raw_id=unit["raw_id"],
                attack_dice={"count": unit.get("attack1_dice"), "sides": unit.get("attack1_sides")},
                native_attack_verified=False)
            interval = unit.get("attack1_interval")
            self.record(cls, name, "attack_speed", current.get("attack_speed"), 100 / interval if numeric(interval) and interval else None,
                source, pointer + "/attack_speed", "仅按 100÷基础攻击间隔换算；不混同运行时攻速加成。", "interval_conversion")

    def compare_modes(self):
        bound = defaultdict(list)
        hidden = set()
        for row in self.waves.get("difficulty_rows_all_variants", []):
            identity = row.get("mode_id"), row.get("difficulty")
            if row.get("directly_bound_to_matching_N_label") and row.get("selector_mode_compatible"):
                bound[identity].append(row)
            elif row.get("directly_bound_to_matching_N_label"):
                hidden.add(identity)
        fields = {"hp_multiplier": "xgdg_pAAA", "armor_multiplier": "xgdg_LAAA",
                  "challenge_hp_multiplier": "xgdg_oBAA", "challenge_armor_multiplier": "xgdg_MBAA"}
        profiles = defaultdict(list)
        for row in self.waves.get("main_schedule_profiles", []):
            profiles[row.get("mode_id"), row.get("difficulty")].append(row)
        for mode, difficulties in self.current.get("modes", {}).items():
            for difficulty, current in difficulties.items():
                identity = MODE_IDS.get(mode), int(difficulty); key = f"{mode}/N{difficulty}"
                candidates = bound.get(identity, [])
                if len(candidates) != 1:
                    reason = "原图有对应代码但选择器不允许该模式按钮；不当作可达主值。" if identity in hidden else "没有唯一可达原图难度行。"
                    self.missing("mode_multiplier", key, "identity", reason)
                else:
                    original = candidates[0]
                    for field, variable in fields.items():
                        self.record("mode_multiplier", key, field, current.get(field), original.get("multipliers", {}).get(variable),
                            {"callback": original.get("source"), "assignments": original.get("assignments"),
                             "selector": original.get("selector_provenance")}, f"/modes/{mode}/{difficulty}/{field}",
                            "只使用匹配 N 标签且模式按钮可达的原图行；排除旧回调遗留分支。")
                schedules = profiles.get(identity, [])
                if len(schedules) == 1:
                    schedule = schedules[0]
                    self.record("wave_schedule", key, "total_waves", current.get("total_waves"), schedule.get("total_waves"),
                        schedule.get("total_waves_sources_refs"), f"/modes/{mode}/{difficulty}/total_waves")
                    if isinstance(current.get("total_waves"), int):
                        self.record("attack_boss_schedule", key, "waves", list(range(5, current["total_waves"] + 1, 5)),
                            schedule.get("assault_boss_waves"), schedule.get("total_waves_sources_refs"),
                            f"/modes/{mode}/{difficulty}/total_waves", "按每5波一只比较完整出场波次。", "assault_schedule")

    def compare_spawn_formulas(self):
        pairs = {"首怪/大怪": "leader_non_scourge", "天灾小怪": "ordinary_scourge",
                 "天灾精英": "elite_scourge", "天灾首怪": "leader_scourge"}
        for index, current in enumerate(self.current.get("spawn_rules", [])):
            rule_key = pairs.get(current.get("类型"))
            if not rule_key:
                continue
            original = self.waves.get("derived_rules", {}).get(rule_key)
            if not original:
                self.missing("spawn_formula", current.get("类型"), "rule", "原图未提供该规则结构。")
                continue
            for label, field in [("HP", "hp_factor"), ("护甲", "armor_factor"), ("攻击", "attack_factor")]:
                match = re.search(re.escape(label) + r"×([\d.]+)", current.get("公式", ""))
                value = original.get(field)
                parsed = re.fullmatch(r"(?:(\d+(?:\.\d+)?)\*)?(?:pAAA|LAAA)", value or "")
                if match and parsed:
                    self.record("spawn_formula", current["类型"], field, float(match[1]), float(parsed[1] or 1),
                        original.get("sources_refs"), f"/spawn_rules/{index}/公式", "比较基础模式倍率之外的角色系数；首怪与精英不叠乘。", "role_factor")
                else:
                    self.missing("spawn_formula", current["类型"], field, "公式未落在已支持的显式乘数语法，不猜测。")

    def compare_counts(self):
        profiles = self.waves.get("main_schedule_profiles", [])
        for index, current in enumerate(self.current.get("counts", [])):
            mode = current.get("mode_id")
            groups = {}
            for profile in profiles:
                difficulty = profile.get("difficulty")
                if profile.get("mode_id") != MODE_IDS.get(mode) or not isinstance(difficulty, int):
                    continue
                if not current.get("min_difficulty", 1) <= difficulty <= current.get("max_difficulty", 50):
                    continue
                if profile.get("dialog_mode_compatible") is False:
                    continue
                for band in profile.get("bands", []):
                    low = max(current.get("min_wave", 1), band.get("wave_min", 1))
                    high = min(current.get("max_wave", 30), band.get("wave_max", 30))
                    for start, end, field in [(low, min(high, 3), "actual_units_on_wave_1_2_3"),
                                              (max(low, 4), high, "actual_units_on_other_waves")]:
                        if start > end or band.get(field) is None:
                            continue
                        signature = (start, end, band[field], band.get("spawn_interval_seconds"),
                                     band.get("timer_iterations"), band.get("time_relationship_to_next_wave"))
                        group = groups.setdefault(signature, {"difficulties": [], "source": []})
                        group["difficulties"].append(difficulty)
                        for reference in band.get("assignment_sources_refs", []):
                            if reference not in group["source"]:
                                group["source"].append(reference)
            if not groups:
                self.missing("wave_count", f"{mode}/counts{index}", "identity", "没有与当前数量范围相交的可达原图调度。")
            for (low, high, count, interval, iterations, timing), group in groups.items():
                difficulties = sorted(set(group["difficulties"]))
                key = f"{mode}/N{','.join(map(str, difficulties))}/wave{low}-{high}"
                source = {"scheduler": group["source"],
                          "actual_count_rule": self.waves.get("derived_rules", {}).get("actual_count", {}).get("sources_refs")}
                self.record("wave_count", key, "count", current.get("count"), count, source, f"/counts/{index}/count",
                    "原图按回调分支统计名义实际生成数，前3波可能少于计时器次数1只；回调读取全局波次，跨波时不保证归属于捕获波。保留当前总数契约。",
                    "nominal_actual_count_from_original_timer", timer_iterations=iterations,
                    timing=timing, difficulties=difficulties)
                self.record("wave_count", key, "spawn_interval", current.get("spawn_interval"), interval, source,
                            f"/counts/{index}/spawn_interval", "比较原图发怪计时器间隔。", "spawn_timer_interval")

    def finish(self):
        represented = {r.get("raw_id") for r in self.result["matches"] + self.result["differences"] if r.get("raw_id")}
        for row in self.nonwave_rows:
            if row.get("class") in ("wild_advanced_material", "wild_blueprint", "training_target", "seasonal_social_challenge"):
                self.missing(row["class"], row.get("key"), "current_spec", "当前 normalized.json 没有可确认的对应条目，保留原图记录，不自动接入。")
        self.result["limits"].append("波次数量区分计时器次数与名义实际生成数；跨波计时器和玩家存档修正不构成每个捕获波次的实机数量保证。")
        self.result["summary"] = {
            "matches": len(self.result["matches"]), "differences": len(self.result["differences"]),
            "unmatched": len(self.result["unmatched"]), "distinct_compared_raw_ids": len(represented),
            "differences_by_category": dict(Counter(r["category"] for r in self.result["differences"]))}
        return self.result


def compare_current(units_data: dict, wave_rules: dict, nonwave_data: dict, current_spec: dict) -> dict:
    """Return a new reference report; never mutate any of the four input objects."""
    comparison = Comparison(units_data, wave_rules, nonwave_data, current_spec)
    comparison.compare_wave_bases()
    comparison.compare_nonwave()
    comparison.compare_archives()
    comparison.compare_modes()
    comparison.compare_spawn_formulas()
    comparison.compare_counts()
    return comparison.finish()
