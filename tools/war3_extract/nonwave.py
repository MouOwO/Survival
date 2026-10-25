"""Extract reference-only non-wave rules from one supported original map revision.

Usage: python tools/war3_extract/nonwave.py --jass war3map.j --raw-root extracted
       --units units_base.json --output reference-output

This is a static source-specific audit, not a JASS interpreter. Its reviewed line
ranges are used only after a full SHA-256 check. Output includes source indexes
and short formulas, never full JASS bodies or mutations of game monster data.
"""
from __future__ import annotations

import argparse
from collections import Counter
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import war3_extract_units as unit_parser

SUPPORTED_JASS_SHA256 = "52e54249dbe147fbcb042636fe991ac493ed9eb96afee56403b9e0ba413448e3"
MAX_SOURCE_BYTES = 32 * 1024 * 1024
EXPECTED_CLASSES = {
    "rebirth": 10, "ten_commandments": 10, "wild_material": 6,
    "wild_advanced_material": 7, "wild_blueprint": 7, "four_rooms": 4,
    "training_target": 2, "building_challenge": 5, "archive_shadow": 4,
    "archive_beast_hunt": 16, "archive_dragon": 9, "seasonal_social_challenge": 8,
}


class ExtractionError(ValueError):
    def __init__(self, code, detail):
        self.code = code
        super().__init__(f"{code}: {detail}")


def bounded_read(path):
    path = Path(path)
    if path.stat().st_size > MAX_SOURCE_BYTES:
        raise ExtractionError("source_too_large", str(path))
    return path.read_bytes()


def check_revision(blob):
    actual = hashlib.sha256(blob).hexdigest()
    if actual != SUPPORTED_JASS_SHA256:
        raise ExtractionError("unsupported_source_revision",
            f"expected {SUPPORTED_JASS_SHA256}, got {actual}")
    return actual


def resolve_member(raw_root, member):
    """Find an extracted member, rejecting conflicting duplicate extractions."""
    root = Path(raw_root)
    relative = Path(*member.replace("\\", "/").split("/"))
    direct = root / relative
    if direct.is_file():
        return direct
    candidates = sorted(p for p in root.rglob(relative.name) if p.is_file())
    if not candidates:
        raise ExtractionError("missing_source_member", member)
    digests = {hashlib.sha256(bounded_read(p)).hexdigest() for p in candidates}
    if len(digests) != 1:
        raise ExtractionError("ambiguous_source_member", member)
    return candidates[0]


class SourceIndex:
    def __init__(self, jass_path, raw_root):
        self.jass_path = Path(jass_path)
        blob = bounded_read(self.jass_path)
        # Fail before inspecting any revision-dependent source ranges or files.
        self.jass_sha256 = check_revision(blob)
        self.lines = blob.decode("utf-8-sig").splitlines()
        self.functions = {}
        current = None
        for number, line in enumerate(self.lines, 1):
            match = re.match(r"function (\w+) takes", line)
            if match:
                current = {"name": match[1], "start_line": number}
                self.functions[match[1]] = current
            elif line == "endfunction" and current:
                current["end_line"] = number
                current = None
        self.paths, self.tables = {}, {}
        for member in ["Units/UnitBalance.slk", "Units/UnitData.slk", "Units/UnitWeapons.slk",
                       "Units/UnitAbilities.slk", "Units/ItemData.slk"]:
            path = resolve_member(raw_root, member)
            rows, _ = unit_parser.parse_slk(bounded_read(path), member)
            self.paths[member] = path
            self.tables[member] = {
                raw: {**{key: cell["value"] for key, cell in row.items()},
                      "_sources": {key: cell["source"]["line"] for key, cell in row.items()}}
                for raw, row in rows.items()
            }
        self.balances = self.tables["Units/UnitBalance.slk"]
        self.item_sha256 = hashlib.sha256(bounded_read(self.paths["Units/ItemData.slk"])).hexdigest()

    @staticmethod
    def raw(value):
        return int(value, 16).to_bytes(4, "big").decode("ascii")

    def source(self, start, end=None):
        end = start if end is None else end
        function = next((f for f in self.functions.values()
                         if f["start_line"] <= start <= f["end_line"]), None)
        span = "\n".join(self.lines[start-1:end]).encode("utf-8")
        return {"member": "war3map.j", "line": start, "end_line": end,
                "function": function["name"] if function else None,
                "source_sha256": self.jass_sha256,
                "span_utf8_lf_sha256": hashlib.sha256(span).hexdigest()}


def unit_base(raw, rows, source):
    """Normalize selected facts from the unit extractor, retaining its provenance."""
    if raw not in rows:
        raise ExtractionError("missing_unit_record", raw)
    u = rows[raw]
    for required in ["hp", "armor", "attack1_base", "attack1_dice", "attack1_sides", "attack1_interval"]:
        if not isinstance(u.get(required), (int, float)) or isinstance(u.get(required), bool):
            raise ExtractionError("missing_unit_stat", f"{raw}.{required}")
    fields = {"hp": "hp", "armor": "armor", "attack1_base": "attack1_base",
              "attack1_dice": "attack1_dice", "attack1_sides": "attack1_sides",
              "attack_interval": "attack1_interval", "attack_range": "attack1_range",
              "hero_primary": "primary_attribute", "hero_strength": "strength",
              "hero_agility": "agility", "hero_intelligence": "intelligence"}
    result = {"raw_id": raw, "name": u.get("name"),
              "name_source": u.get("provenance", {}).get("name")}
    for destination, key in fields.items():
        provenance = u.get("provenance", {}).get(key, {})
        result[destination] = {"value": u.get(key),
            "member": provenance.get("file", "").replace("\\", "/"),
            "line": provenance.get("line"), "provenance": provenance}
    for destination, member, key in [("points", "Units/UnitData.slk", "points"),
                                      ("abilities", "Units/UnitAbilities.slk", "abilList")]:
        table = source.tables[member].get(raw, {})
        result[destination] = {"value": table.get(key), "member": member,
                               "line": table.get("_sources", {}).get(key)}
    return result


def load_units(path):
    payload = json.loads(bounded_read(path))
    if payload.get("schema") != "war3_units_base_v1" or not isinstance(payload.get("units"), list):
        raise ExtractionError("unsupported_units_schema", "expected war3_units_base_v1")
    rows = {}
    for unit in payload["units"]:
        raw = unit.get("raw_id")
        if not isinstance(raw, str) or len(raw) != 4 or raw in rows:
            raise ExtractionError("invalid_unit_identity", str(raw))
        rows[raw] = unit
    return rows


def extract_rules(e, rows):
    ITEMS = e.tables["Units/ItemData.slk"]
    src = e.source
    def base(raw):
        return unit_base(raw, rows, e)
    def creates(raw):
        code = f"0x{raw.encode().hex().upper()}"
        return [src(n) for n in range(10902, 11204)
                if "CreateUnit(" in e.lines[n-1] and code in e.lines[n-1]]
    def unit(raw, cls, key, **kwargs):
        b = base(raw)
        return {"class": cls, "key": key, "raw_id": raw, "name": b["name"],
                "base_ref": f"unit_bases.json#/{raw}",
                "attack_interval": b["attack_interval"]["value"],
                "status": "confirmed_static_original_map", **kwargs}
    def product(a, b):
        return float(Decimal(str(a)) * Decimal(str(b)))

    rules = {
        'schema': 'original_map_nonwave_rules/v1',
        'provenance': {
            'read_only': True, 'map_code_executed': False,
            'human_spec_or_spreadsheet_used_as_evidence': False,
            'source_jass': str(e.jass_path),
            'jass_sha256': e.jass_sha256,
            'item_slk_sha256': e.item_sha256,
        },
        'symbols': {
            'mode': 'xgdg_tDAA: 1常规,2极寒,3天灾,4丰饶,5纯净,6归墟,7天域',
            'N': 'xgdg_nAAA 当前难度编号',
            'p': 'xgdg_pAAA 波次血量/基础攻击倍率',
            'L': 'xgdg_LAAA 波次护甲倍率',
            'o': 'xgdg_oBAA 中立/四房血量倍率',
            'M': 'xgdg_MBAA 中立/四房护甲倍率',
            'current_wave': 'udg_BC', 'next_wave_unit': 'udg_GW[udg_BC + 1]',
            'current_wave_armor': 'xgdg_GDAA（波次spawn写入的护甲缓存）',
            'native_attack_initial': 'GetUnitState(created_unit, ConvertUnitState(0x12)) before runtime multiplication',
            'native_hp_initial': 'GetUnitState(created_unit, UNIT_STATE_MAX_LIFE) before runtime multiplication',
            'native_armor_initial': 'GetUnitState(created_unit, ConvertUnitState(0x20)) before runtime multiplication',
        },
        'setter_contract': {
            '0x12': 'JASS sets attack base with SetUnitState; SLK dmgplus1 separately retained',
            '0x20': 'armor', 'UNIT_STATE_MAX_LIFE': 'maximum HP',
            '0x25': 'attack interval', '0x51': 'attack speed multiplier',
            'attack_dice_scope': 'The non-wave setters below do not alter dice1 or sides1. '
                'A base*factor + dice contribution interpretation is consistent with this code; '
                'native Warcraft engine handling of 0x12, hero attributes, rounding and displayed full attack '
                'is not proven by static JASS. Do not multiply SLK min/max as if they were the setter operand.',
            'derived_values_scope': 'SLK-only products are reference arithmetic, not asserted engine snapshots. '
                'Hero raws have Primary=STR and STR=AGI=INT=1; native hero stat and map gameplay constant '
                'effects remain distinct from these products.',
        },
        'shared_rules': {}, 'units': [], 'unresolved_or_original_inconsistencies': [],
    }

    rules['shared_rules']['neutral_initial'] = {
        'eligibility': 'alive && owner=PLAYER_NEUTRAL_AGGRESSIVE && SLK.points!=100',
        'selection_source': src(41305, 41307), 'enumeration_source': src(41338, 41341),
        'sequence': ['save original x/y/facing', 'multiply current native attack base',
                     'multiply current native armor/maxHP once', 'life=100%'],
        'attack_formula': 'native_attack_initial * ((mode in [3,6,7]) ? (3 + N) : (1.8 + 0.2*N))',
        'hp_formula': 'native_hp_initial * o', 'armor_formula': 'native_armor_initial * M',
        'source': src(41308, 41331),
        'special_case': {
            'raw_id': 'h02I', 'when': 'mode in [2,3]',
            'hp_formula': 'native_hp_initial * o / 2',
            'armor_formula': 'native_armor_initial * M / 2', 'source': src(41318, 41325),
        },
    }
    rules['shared_rules']['neutral_respawn'] = {
        'eligibility': 'dead neutral && SLK.points!=100 && original saved x!=0 && ability A09B absent',
        'delay_seconds': 2, 'source': src(41808, 41824), 'spawn_source': src(41418, 41442),
        'sequence': ['create a fresh unit of same rawID at saved x/y', 'multiply fresh native attack base',
                     'multiply fresh native armor/maxHP once', 'life=100%'],
        'attack_formula': 'native_attack_initial * ((mode == 3) ? (3 + N) : (1.8 + 0.2*N))',
        'hp_formula': 'native_hp_initial * o', 'armor_formula': 'native_armor_initial * M',
        'special_case': {'raw_id': 'h02I', 'when': 'mode in [2,3]',
            'hp_formula': 'native_hp_initial * o / 2',
            'armor_formula': 'native_armor_initial * M / 2', 'source': src(41427, 41434)},
        'no_accumulation': 'A fresh CreateUnit precedes the setters; no multiplication of a previously scaled corpse.',
    }

    # All ten rebirth bosses are neutral preplacements and use the shared initial/respawn rules.
    for i, raw in enumerate(['h02I','h02J','h02K','h02L','h02M','h02N','h02O','h02P','h02Q','h02R'], 1):
        refs = creates(raw)
        rules['units'].append(unit(raw, 'rebirth', f'rebirth_{i}', order=i,
            initial_count=len(refs), count_scope='whole_map_preplaced', source=refs,
            formula_ref=['neutral_initial','neutral_respawn']))

    ten = ['h08Z','h08R','h08S','h08T','h08U','h08V','h08W','h08X','h08Y','h090']
    for i, raw in enumerate(ten, 1):
        refs = creates(raw)
        rules['units'].append(unit(raw, 'ten_commandments', f'ten_commandments_{i}', order=i,
            initial_count=len(refs), count_scope='whole_map_preplaced', source=refs,
            order_source={'member':'Units/UnitBalance.slk','field':'goldcost',
                          'value':e.balances[raw].get('goldcost'),
                          'line':e.balances[raw]['_sources'].get('goldcost')},
            formula_ref=['neutral_initial','neutral_respawn']))

    for raw, key in [('h02Z','fire_core'),('h099','ice_wraith'),('h06S','synthesis_gem'),
                     ('h030','fire_troll'),('h031','ice_ember_boss'),('h08Q','essence')]:
        refs = creates(raw)
        rules['units'].append(unit(raw, 'wild_material', key,
            initial_count=len(refs), count_scope='whole_map_preplaced', source=refs,
            formula_ref=['neutral_initial','neutral_respawn']))

    rules['shared_rules']['advanced_material_rebuild'] = {
        'source': src(41236, 41297),
        'sequence':['remove eligible units in region141','for each of7 regions spawn1 blueprint and3 paired material mobs',
                    'multiply current native attack base,armor,maxHP; full life; save original position'],
        'attack_formula':'native_attack_initial * (3 + N)',
        'armor_formula':'native_armor_initial * M','hp_formula':'native_hp_initial * o',
        'first_setters':src(41274,41279),'second_setters':src(41283,41290),
        'note':'Unlike initial neutral and neutral respawn, the rebuild does not branch by mode for attack.',
    }
    for letter in 'IJKLMNOPQRSTUV':
        raw = f'h0C{letter}'; refs = creates(raw)
        rules['units'].append(unit(raw, 'wild_advanced_material' if letter<'P' else 'wild_blueprint',
            f'advanced_{raw}', initial_count=len(refs), count_scope='whole_map_preplaced', source=refs,
            rebuild_count=3 if letter<'P' else 1,
            formula_ref=['neutral_initial','advanced_material_rebuild'],
            generic_neutral_respawn=False,
            no_respawn_reason='SLK abilList contains A09B; original generic death handler skips its respawn timer.',
            no_respawn_source=src(41815,41822)))

    rules['shared_rules']['four_rooms'] = {
        'mapping_source':src(41041,41046), 'spawn_source':src(41089,41121),
        'spawn_count':10, 'count_scope':'per_player_per_room, spawned only when its group is empty',
        'attack_formula':'native_attack_initial * (1.8 + 0.2*N)',
        'hp_formula':'native_hp_initial * o','armor_formula':'native_armor_initial * M',
        'setters_source':src(41110,41115),
        'no_double_scale':'All four raws have SLK.points=100 and are excluded by the global neutral initial filter.',
        'lethal_handling':'Ability A05V intercepts lethal damage: eventDamage=0, hide, pause, invulnerable.',
        'lethal_source':src(32084,32092),
        'lethal_ability_evidence':'All four room raws have abilList=A05V in UnitAbilities.slk; see unit_bases abilities fields.',
        'reset_interval_seconds':1.2,'reset_timer_source':src(41063,41070),
        'reset_condition':'active player, in corresponding room, and room reset gate permits',
        'reset_source':src(40913,40926),
        'reset_sequence':['show hidden unit','remove invulnerability','life=100%','unpause','move to room center',
                          'armor = SLK.def*M','life=100%'],
        'reset_no_double_scale':'HP and attack are not multiplied again on show; armor is replaced from SLK base.',
    }
    for i,(raw,item) in enumerate([('h02U','I027'),('h02S','I028'),('h02T','I029'),('h02V','I02A')],1):
        rules['units'].append(unit(raw,'four_rooms',f'room_{i}',order=i,entry_item=item,
            entry_item_prio=ITEMS[item]['prio'],initial_count=10,count_scope='per_player_per_room',
            source=[src(41040+i),src(41107,41115)],formula_ref=['four_rooms']))

    # Two separate training targets are not ordinary four-room mobs.
    rules['units'].append(unit('h0CA','training_target','endless_growth_target',initial_count=1,
        count_scope='per_active_player',formula={'hp':'SLK.HP','armor':'SLK.def','attack_base':'SLK.dmgplus1'},
        source=[src(41047,41058)],special_rules=[
            {'rule':'incoming event damage is forced to zero','source':src(32219,32222)},
            {'rule':'worker attacks may be stopped while xgdg_HDAA gate is false','source':src(33068,33074)}]))
    rules['units'].append(unit('h0AL','training_target','temporary_dummy',initial_count=1,
        count_scope='per reward activation',formula={'hp':'SLK.HP','armor':'SLK.def','attack_base':'SLK.dmgplus1'},
        source=[src(44143,44148)],timed_life_seconds=30,special_rules=[
            {'rule':'attacker gets +100 bonus damage if attacker state0x15>50','source':src(33665,33670)}]))

    building = [
        ('A052','h0AH',100,2,5000,4,24012),
        ('A051','h0AI',200,2.2,10000,4.5,24041),
        ('A053','h0AJ',300,2.4,15000,5,24070),
        ('A04Z','h0AK',400,2.6,20000,5.5,24099),
        ('A050','h0AG',400,2.8,25000,7,24130),
    ]
    for i,(ability,raw,ac,am,hc,hm,line) in enumerate(building,1):
        rules['units'].append(unit(raw,'building_challenge',f'building_challenge_{i}',order=i,
            ability_id=ability,initial_count=1,count_scope='per cast',
            formula={'attack_base':f'{ac} + SLK[next_wave_unit].dmgplus1 * p * {am}',
                     'hp':f'{hc} + SLK[next_wave_unit].HP * p * {hm}',
                     'armor':'current_wave_armor'},
            coefficients={'attack_flat':ac,'attack_next_wave_multiplier':am,
                          'hp_flat':hc,'hp_next_wave_multiplier':hm},
            multiplier_type='wave p plus formula coefficients; armor copies current-wave cached armor',
            source=[src(line,line+5)],time_limit_seconds=60,
            failure_rule='wall life<=50% or timeout; monster death is success',
            example_resolution_source=src(23777,23818),
            native_interval_override=False))
    rules['unresolved_or_original_inconsistencies'].append({
        'key':'four_additional_building_spells_are_toggles',
        'fact':'A054/A055 and A056/A057 pass the same trigger condition but toggle abilities/flags; '
               'their action branches do not create challenge monsters. They are not missing monster definitions.',
        'source':src(24152,24179),'status':'confirmed_nonspawn_control_branches'})

    # Resolve item.prio to the exact original wxAA unit array and keep item.scale as source data.
    wx={}
    for n in range(23272,23301):
        m=re.search(r'set xgdg_wxAA\[(\d+)\]=0x([0-9A-F]{8})',e.lines[n-1])
        if m: wx[int(m[1])] = (e.raw(m[2]),n)
    archive_items={
        'archive_shadow':['I09Y','I09X','I09Z','I09P'],
        'archive_beast_hunt':['I09Q','I09S','I09T','I09U','I0KS','I0KT','I0KU','I0KR',
                              'I0UH','I0UI','I0UJ','I0UK','I10Q','I10P','I10O','I10R'],
        'archive_dragon':['I09W','I09R','I09V','I0UA','I0UB','I0UC','I11J','I11K','I11L'],
    }
    archive_spawns={'archive_shadow':(29930,29940,29945,29946,29947,29948),
                    'archive_beast_hunt':(29972,29998,30001,30002,30003,30004),
                    'archive_dragon':(30019,30045,30049,30050,30051,30052)}
    rules['shared_rules']['archive_fixed_challenge']={
        'mapping_source':src(23272,23300), 'item_to_unit':'xgdg_wxAA[SLK.item[entry_item].prio]',
        'attack_formula':'native_attack_initial * SLK.item[entry_item].scale',
        'hp_formula':'native_hp_initial * SLK.item[entry_item].scale',
        'armor_formula':'native_armor_initial * 1',
        'difficulty_independent':True,
        'eligibility_note':'points=100 and spawned for an enemy player, not neutral; no shared neutral multiplier.',
        'sequence':['create from wxAA[item.prio]','read item.scale','multiply attack base','armor*=1','multiply maxHP','life=100%'],
        'source':[src(29940,29949),src(29998,30006),src(30045,30053)],
        'never_rescale_final_reference':'derived_slk_products already include item.scale; no second scale or p/L/o/M.',
    }
    for cls, itemlist in archive_items.items():
        cond,spawn,scale_line,atk_line,armor_line,hp_line=archive_spawns[cls]
        for i,item in enumerate(itemlist,1):
            it=ITEMS[item]; raw,mapping_line=wx[it['prio']]; b=base(raw); scale=it['scale']
            rules['units'].append(unit(raw,cls,f'{cls}_{i}',order=i,entry_item=item,
                entry_item_prio=it['prio'],entry_item_scale=scale,
                entry_item_source={'member':'Units/ItemData.slk',
                    'prio_line':it['_sources']['prio'],'scale_line':it['_sources']['scale']},
                mapping_source=src(mapping_line),source=[src(cond),src(spawn),src(scale_line,hp_line)],
                initial_count=1,count_scope='per_active_player' if cls=='archive_shadow' else 'one_per_item_use_in_shared_mode_arena',
                multiplier_type='entry item scale only, all difficulties identical',
                formula_ref=['archive_fixed_challenge'],
                derived_slk_products={
                    'hp':product(b['hp']['value'],scale),
                    'armor':b['armor']['value'],
                    'attack_base':product(b['attack1_base']['value'],scale),
                    'unmodified_attack_dice':b['attack1_dice']['value'],
                    'unmodified_attack_sides':b['attack1_sides']['value'],
                    'scope':'direct SLK products; hero native-stat/engine details excluded, see setter_contract'},
                native_interval_override=False))

    # Original social / seasonal challenges use a different p/L/L path from archive challenges.
    extras=[('I0IR','H0CB',30083,30093,30099,1),('I0SR','H0CY',30119,30129,30135,1),
            ('I0Y1','H0DC',30155,30165,30171,1),('I10J','H0DE',30191,30201,30207,1),
            ('I148','H0DP',30227,30237,30243,1),('I135','H0DN',30263,30273,30279,1),
            ('I0N0','H0CH',30299,30312,30318,10),('I0W6','H0D9',30339,30349,30355,1)]
    for item,raw,condition,spawn,stat,count in extras:
        rules['units'].append(unit(raw,'seasonal_social_challenge',f'seasonal_{raw}',entry_item=item,
            initial_count=count,count_scope='per_active_player',
            formula={'attack_base':'native_attack_initial * p',
                     'armor':'native_armor_initial * L','hp':'native_hp_initial * L'},
            multiplier_type='wave attack p; HP and armor both use L (not p)',
            source=[src(condition),src(spawn),src(stat,stat+2)],native_interval_override=False))

    rules['unresolved_or_original_inconsistencies'] += [
        {'key':'neutral_initial_vs_respawn_modes6_7',
         'fact':'mode6/7 initial attack multiplier=3+N; generic respawn multiplier=1.8+0.2N. '
                'This is present in the original source and has not been silently repaired.',
         'source':[src(41313,41316),src(41422,41425)]},
        {'key':'advanced_rebuild_attack_mode_branch',
         'fact':'Advanced materials rebuild always uses3+N; initial preplacement and generic respawn use different mode branches.',
         'source':[src(41276),src(41287),src(41313,41316),src(41422,41425)]},
        {'key':'unused_duplicate_wuyu_h091',
         'fact':'h091 also has Name=无欲 but is absent from all literal CreateUnit sites and wxAA/QAAA arrays. '
                'Active ten-commandment5 is h08U. h091 must not substitute for it.',
         'base_ref':'unit_bases.json#/h091','status':'source_defined_but_active_spawn_not_found'},
        {'key':'native_engine_damage_and_hero_base',
         'fact':'Native ConvertUnitState0x12 semantics and hero attribute/gameplay-constant effects are not engine-executed here. '
                'All data preserves dmgplus1,dice,sides,hero primary attributes and exact runtime expressions.'},
    ]


    raw_ids = sorted({r["raw_id"] for r in rules["units"]} | {"h091"})
    return rules, {raw: base(raw) for raw in raw_ids}


def source_index(rules):
    found = {}
    def visit(value):
        if isinstance(value, dict):
            if value.get("member") == "war3map.j" and "line" in value:
                found[value["line"], value.get("end_line", value["line"])] = value
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(rules)
    return {"jass_sha256": SUPPORTED_JASS_SHA256,
            "spans": [found[key] for key in sorted(found)]}


def validate_rules(source, rules, bases, raw_root):
    jass=source.lines
    checks=[]


    def check(name,condition,detail=None):
        if not condition: raise ExtractionError('source_validation_failed', f'{name}: {detail}')
        checks.append({'name':name,'passed':True,'detail':detail})


    expected={'rebirth':10,'ten_commandments':10,'wild_material':6,'wild_advanced_material':7,
              'wild_blueprint':7,'four_rooms':4,'training_target':2,'building_challenge':5,
              'archive_shadow':4,'archive_beast_hunt':16,'archive_dragon':9,'seasonal_social_challenge':8}
    check('class_coverage',Counter(r['class'] for r in rules['units'])==expected,expected)
    check('unique_class_keys',len(set((r['class'],r['key']) for r in rules['units']))==88)
    check('all_base_refs_exist',all(r['raw_id'] in bases for r in rules['units']))

    # Independently check every recorded SLK field's source line contains that exact K value.
    slks={}
    verified=0
    for raw,b in bases.items():
        for field,value in b.items():
            if not isinstance(value,dict) or 'member' not in value:continue
            if not value['member'].endswith('.slk'):continue
            if value['value'] is None:continue
            if value['member'] not in slks:
                path=resolve_member(raw_root, value['member'])
                slks[value['member']]=path.read_text(encoding='utf-8-sig').splitlines()
            if not isinstance(value.get('line'), int) or not 1 <= value['line'] <= len(slks[value['member']]):
                raise ExtractionError('invalid_provenance_line', f'{raw}.{field}')
            text=slks[value['member']][value['line']-1]
            m=re.search(r'(?:^|;)K("(?:[^"]|"")*"|[^;]*)',text)
            check_value=m.group(1) if m else None
            if check_value is None: raise ExtractionError('invalid_provenance_line', str(value))
            if check_value.startswith('"'):check_value=check_value[1:-1].replace('""','"')
            else:check_value=float(check_value)
            if check_value != value['value']: raise ExtractionError('unit_source_mismatch', f'{raw}.{field}')
            verified+=1
    check('SLK_field_line_values',verified>800,{'verified_fields':verified})

    for r in rules['units']:
        if r['class'] in ['rebirth','ten_commandments','wild_material','wild_advanced_material','wild_blueprint']:
            hexcode='0x'+r['raw_id'].encode().hex().upper()
            literal=[n for n in range(10902,11204) if 'CreateUnit(' in jass[n-1] and hexcode in jass[n-1]]
            check('literal_preplacement_'+r['raw_id'],len(literal)==r['initial_count'],literal)

    ten=[r for r in rules['units'] if r['class']=='ten_commandments']
    check('ten_first_is_real',ten[0]['raw_id']=='h08Z' and ten[0]['name']=='真实')
    check('ten_original_last_four_HP',[bases[r['raw_id']]['hp']['value'] for r in ten[-4:]]==
          [50104960,55104960,60104960,70104960])
    check('ten_first_original_HP',bases['h08Z']['hp']['value']==19104960)
    check('duplicate_wuyu_not_active',all(r['raw_id']!='h091' for r in rules['units']))
    check('ice_wraith_original_count',next(r for r in rules['units'] if r['raw_id']=='h099')['initial_count']==10)

    archive=[r for r in rules['units'] if r['class'].startswith('archive_')]
    check('archive_29_unique_prio',sorted(r['entry_item_prio'] for r in archive)==list(range(1,30)))
    for r in archive:
        mapping=jass[r['mapping_source']['line']-1]
        check('archive_mapping_'+r['entry_item'],
              mapping==f"set xgdg_wxAA[{r['entry_item_prio']}]=0x{r['raw_id'].encode().hex().upper()}")
    check('archive_shadow_scale',[r['entry_item_scale'] for r in archive if r['class']=='archive_shadow']==[1.8,3.0,5.0,7.0])
    check('archive_no_difficulty_runtime_writes',all(
        not any(sym in jass[n-1] for sym in ['xgdg_pAAA','xgdg_LAAA','xgdg_oBAA','xgdg_MBAA'])
        for a,b in [(29940,29949),(29998,30006),(30045,30053)] for n in range(a,b+1)))
    check('neutral_attack_difference_preserved','xgdg_tDAA == 6' in jass[41313-1] and
          'xgdg_tDAA == 7' in jass[41313-1] and jass[41422-1]=='if ( ( xgdg_tDAA == 3 ) ) then')
    check('four_room_count10_source',jass[41109-1]=='exitwhen ydul_c > 10')
    check('four_room_lethal_ability',all(bases[r['raw_id']]['abilities']['value']=='A05V'
           for r in rules['units'] if r['class']=='four_rooms'))
    check('advanced_material_respawn_excluded_by_A09B',all(
          'A09B' in bases[r['raw_id']]['abilities']['value'] and r['generic_neutral_respawn'] is False
          and 'neutral_respawn' not in r['formula_ref']
          for r in rules['units'] if r['class'] in ['wild_advanced_material','wild_blueprint']))
    check('four_room_reset_from_base','"].def"' in jass[40922-1] and 'xgdg_MBAA' in jass[40922-1])
    check('building_fifth_attack_flat400','400.00' in jass[24131-1] and '2.80' in jass[24131-1])
    check('building_fifth_HP25000_and7','25000.00' in jass[24133-1] and '7.00' in jass[24133-1])
    check('building_next_wave_actual_identifier','udg_GW[( udg_BC + 1 )]' in jass[24013-1])
    check('seasonal_HP_uses_L',all('UNIT_STATE_MAX_LIFE' in jass[r['source'][2]['end_line']-1] and
           'xgdg_LAAA' in jass[r['source'][2]['end_line']-1] for r in rules['units'] if r['class']=='seasonal_social_challenge'))

    result={'passed':True,'checks':len(checks),'verified_SLK_fields':verified,'rows':88,
            'map_code_executed':False,'results':checks}
    return result


def run(jass, raw_root, units, output):
    source = SourceIndex(jass, raw_root)
    rules, bases = extract_rules(source, load_units(units))
    rules["provenance"]["units_input_sha256"] = hashlib.sha256(bounded_read(units)).hexdigest()
    rules["provenance"]["raw_source_sha256"] = {
        member: hashlib.sha256(bounded_read(path)).hexdigest() for member, path in source.paths.items()}
    validation = validate_rules(source, rules, bases, raw_root)
    counts = Counter(r["class"] for r in rules["units"])
    archive = [r for r in rules["units"] if r["class"].startswith("archive_")]
    summary = {"rows": len(rules["units"]), "distinct_units": len(bases),
               "classes": dict(counts), "archive_rows": len(archive),
               "jass_sha256": source.jass_sha256, "validation_checks": validation["checks"]}
    outputs = {"challenge_rules.json": rules, "unit_bases.json": bases,
        "archive_final_reference.json": {"schema": "original_map_archive_slk_products/v1",
            "scope": "SLK-only reference products already include item.scale. No difficulty multiplier. See setter_contract.",
            "rows": archive}, "source_index.json": source_index(rules),
        "summary.json": summary, "validation.json": validation}
    destination = Path(output)
    destination.mkdir(parents=True, exist_ok=True)
    for filename, payload in outputs.items():
        (destination / filename).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jass", type=Path, required=True)
    parser.add_argument("--raw-root", type=Path, required=True)
    parser.add_argument("--units", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        summary = run(args.jass, args.raw_root, args.units, args.output)
    except (ExtractionError, OSError, ValueError, KeyError) as error:
        print(json.dumps({"error": getattr(error, "code", "invalid_source_data"),
                          "detail": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
