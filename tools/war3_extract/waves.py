"""Static wave-rule evidence for one explicitly supported original-map snapshot.

No map script is executed. Numeric arithmetic uses a small AST whitelist.
Source-specific callback names and hand-labelled rules are guarded by the full
JASS SHA-256; another revision fails before applying those interpretations.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import math
import operator
import re
from collections import Counter, defaultdict
from decimal import Decimal, localcontext
from pathlib import Path

SUPPORTED_JASS_SHA256 = '52e54249dbe147fbcb042636fe991ac493ed9eb96afee56403b9e0ba413448e3'
MODE_NAMES = {1: '常规', 2: '极寒', 3: '天灾', 4: '丰饶', 5: '纯净', 6: '归墟', 7: '天域'}
MULTIPLIERS = ['xgdg_pAAA', 'xgdg_LAAA', 'xgdg_oBAA', 'xgdg_MBAA']
VARIABLE_NAMES = {'xgdg_tDAA': 'mode_id', 'xgdg_nAAA': 'difficulty',
                  'xgdg_pAAA': 'wave_hp_attack_multiplier', 'xgdg_LAAA': 'wave_armor_multiplier',
                  'xgdg_oBAA': 'challenge_stat_multiplier_pending_consumer_confirmation',
                  'xgdg_MBAA': 'challenge_armor_multiplier_pending_consumer_confirmation',
                  'udg_BC': 'current_wave', 'udg_GW': 'ordinary_wave_rawid',
                  'udg_BOSS': 'assault_boss_rawid', 'xgdg_CAAA': 'rotation_slot_2_rawid',
                  'xgdg_xAAA': 'rotation_slot_3_rawid'}


class UnsupportedSourceRevision(ValueError):
    """The input cannot use this snapshot-specific semantic interpretation."""


def require_supported_source(data):
    digest = hashlib.sha256(data).hexdigest()
    if digest != SUPPORTED_JASS_SHA256:
        raise UnsupportedSourceRevision(
            f'unsupported_source_revision: expected JASS SHA-256 {SUPPORTED_JASS_SHA256}, got {digest}')
    return digest


def safe_number(text):
    tree = ast.parse(text.strip(), mode='eval')
    def walk(n):
        if isinstance(n, ast.Constant) and type(n.value) in (int, float):
            if not math.isfinite(n.value): raise ValueError('non-finite arithmetic literal')
            return n.value
        if isinstance(n, ast.BinOp) and type(n.op) in (ast.Add, ast.Sub, ast.Mult, ast.Div):
            return {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv}[type(n.op)](walk(n.left), walk(n.right))
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, (ast.USub, ast.UAdd)):
            return (-1 if isinstance(n.op, ast.USub) else 1) * walk(n.operand)
        raise ValueError('not literal arithmetic: ' + text)
    result=walk(tree.body)
    if not math.isfinite(result): raise ValueError('non-finite arithmetic result')
    return result


def parse_hero_misc(path):
    """Read explicit numeric [Misc] coefficients, retaining their source lines."""
    path=Path(path)
    blob=path.read_bytes()
    fields={}; section=None
    wanted={'StrHitPointBonus','AgiDefenseBonus','AgiAttackSpeedBonus','StrAttackBonus'}
    for line_number,line in enumerate(blob.decode('utf-8-sig').splitlines(),1):
        stripped=line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            section=stripped[1:-1];continue
        if section!='Misc' or '=' not in line:continue
        key,value=line.split('=',1);key=key.strip()
        if key not in wanted:continue
        if key in fields:raise ValueError('duplicate hero coefficient: '+key)
        fields[key]={'value':safe_number(value),'source':{'file':path.name,'line':line_number}}
    result={'status':'parsed','source':{'path':str(path),'sha256':hashlib.sha256(blob).hexdigest()},
            'coefficients':fields,'missing_coefficients':sorted(wanted-set(fields)),
            'native_execution_verified':False,
            'hp_rule_before_spawn_multiplier':'object_HP + hero_STR * StrHitPointBonus',
            'attack_note':'Spawn setters modify native property0x12; primary attribute and dice contributions to final displayed or dealt damage are not native-verified. StrAttackBonus must not be silently added to the scaled base setter.',
            'reference_snapshot_hero_hp_examples':[]}
    # Independent object-table checkpoint inputs from the same archive. These
    # are explicitly reference examples, not a replacement for parsing the
    # unit tables accompanying another archive with an unchanged script.
    if 'StrHitPointBonus' in fields:
        for ident,hp,hpline,strline in [('H012',10000,25595,25608),('H013',30000,25631,25644),
                                      ('H014',150000,25667,25680),('H015',500000,25703,25716),
                                      ('H016',3000000,25739,25752),('H07C',8000000,25968,25981)]:
            result['reference_snapshot_hero_hp_examples'].append({
                'rawid':ident,'object_hp':hp,'hero_strength':1,
                'derived_native_hp_input':hp+fields['StrHitPointBonus']['value'],
                'source':{'file':r'Units\UnitBalance.slk','sha256':'0b2a73fd257928f97f29cb791e01e54bd576494b7213c14a24324339f6a0a300',
                          'hp_line':hpline,'strength_line':strline,
                          'scope':'Reference object table from the documented archive snapshot; not dynamically parsed by this wave module.'},
                'native_execution_verified':False})
    return result


def condition_value(text, values):
    """Three-valued static constraint evaluation; never calls JASS functions."""
    tree = ast.parse(re.sub(r'\btrue\b', 'True', re.sub(r'\bfalse\b', 'False', text)), mode='eval')
    def walk(n):
        if isinstance(n, ast.Constant): return n.value
        if isinstance(n, ast.Name): return values.get(n.id)
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.Not):
            a = walk(n.operand); return None if a is None else not a
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.USub):
            a = walk(n.operand); return None if a is None else -a
        if isinstance(n, ast.BinOp):
            a,b=walk(n.left),walk(n.right)
            if a is None or b is None: return None
            op={ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
                ast.Div: operator.truediv, ast.Mod: operator.mod}.get(type(n.op))
            return None if op is None else op(a,b)
        if isinstance(n, ast.BoolOp):
            parts=[walk(x) for x in n.values]
            if isinstance(n.op, ast.And):
                return False if False in parts else None if None in parts else True
            return True if True in parts else None if None in parts else False
        if isinstance(n, ast.Compare):
            a=walk(n.left); result=[]
            for op,bnode in zip(n.ops,n.comparators):
                b=walk(bnode)
                if a is None or b is None: result.append(None)
                else: result.append({ast.Eq: operator.eq, ast.NotEq: operator.ne, ast.Lt: operator.lt,
                                     ast.LtE: operator.le, ast.Gt: operator.gt, ast.GtE: operator.ge}[type(op)](a,b))
                a=b
            return False if False in result else None if None in result else True
        if isinstance(n, ast.Call) and isinstance(n.func,ast.Name):
            # Pure numeric syntax is recognized, not dispatched to map code.
            if n.func.id == 'ModuloInteger':
                a,b=[walk(x) for x in n.args]
                return None if a is None or b is None else a % b
            if n.func.id in ('I2R','R2I'): return walk(n.args[0])
        return None
    return walk(tree.body)


def guard_possible(guards, values):
    for g in guards:
        value=condition_value(g['condition'], values)
        if value is not None and bool(value) != g['branch']: return False
    return True


def split_args(text):
    depth = 0; quote = False; escaped = False; start = 0; result = []
    for i, c in enumerate(text):
        if quote:
            if escaped: escaped = False
            elif c == '\\': escaped = True
            elif c == '"': quote = False
        elif c == '"': quote = True
        elif c in '([': depth += 1
        elif c in ')]': depth -= 1
        elif c == ',' and depth == 0:
            result.append(text[start:i].strip()); start = i + 1
    result.append(text[start:].strip())
    return result


def rawid(value):
    try: return int(value, 16).to_bytes(4, 'big').decode('ascii')
    except (ValueError, UnicodeDecodeError, OverflowError): return None


def load_source(source):
    data = Path(source).read_bytes()
    require_supported_source(data)
    lines = data.decode('utf-8-sig').splitlines()
    functions = {}; records = []; current = None; stack = []
    for num, line in enumerate(lines, 1):
        if line.startswith('function '):
            current = line.split()[1]; functions[current] = {'function': current, 'line_start': num, 'line_end': None}; stack = []
        if line == 'endfunction':
            if current: functions[current]['line_end'] = num
            current = None; stack = []
            continue
        if not current: continue
        if line.startswith('if ') and line.endswith(' then'):
            stack.append({'line': num, 'condition': line[3:-5], 'branch': True})
            continue
        if line == 'else':
            assert stack, num
            stack[-1]['branch'] = False
            continue
        if line == 'endif':
            assert stack, num
            stack.pop(); continue
        records.append({'function': current, 'line': num, 'text': line,
                        'guards': [dict(s) for s in stack]})
    return data, lines, functions, records


def ref(record):
    return {'function': record['function'], 'line': record['line']}


def mode_for(record):
    for guard in reversed(record['guards']):
        match = re.fullmatch(r'\(\s*\(\s*xgdg_tDAA == (\d+)\s*\)\s*\)', guard['condition'])
        if match and guard['branch']: return int(match[1])
    return None


def button_for(record):
    for guard in reversed(record['guards']):
        if guard['branch'] and 'GetClickedButtonBJ()' in guard['condition']:
            found = re.search(r'(0x[0-9A-F]+)\)', guard['condition'])
            if found: return found[1]
    return None


def literal_difficulty_rows(lines, records):
    rows = []
    for rec in records:
        match = re.fullmatch(r'set xgdg_nAAA=(\d+)', rec['text'])
        if not match or mode_for(rec) is None: continue
        row = {'mode_id': mode_for(rec), 'mode_name': MODE_NAMES[mode_for(rec)],
               'difficulty': int(match[1]), 'button_key': button_for(rec),
               'source': ref(rec), 'guards': rec['guards'], 'multipliers': {},
               'assignments': [], 'loop_repeat': 0, 'multiplier_exact_decimal': {}}
        # Only adjacent straight-line constants + explicitly bounded ydul_u
        # multiplier loop following this difficulty assignment are evaluated.
        window = lines[rec['line']:rec['line'] + 21]
        for offset, line in enumerate(window, rec['line'] + 1):
            if line in ('else', 'endif') or line.startswith('if '): break
            m = re.fullmatch(r'set (xgdg_(?:pAAA|LAAA|oBAA|MBAA))=(.+)', line)
            if m:
                var, expression = m.groups()
                if var not in expression:
                    row['multipliers'][var] = safe_number(expression)
                    row['multiplier_exact_decimal'][var] = str(Decimal(expression.strip()))
                    row['assignments'].append({'variable': var, 'expression': expression, 'line': offset})
                else:
                    loop_limit = next((int(x.split('>')[1]) for x in window[:window.index(line)] if re.fullmatch(r'exitwhen ydul_u > \d+', x)), None)
                    assert loop_limit is not None, (offset, line)
                    row['loop_repeat'] = loop_limit
                    rewritten = re.sub(r'\b' + var + r'\b', '1', expression)
                    # multiplicative map loop: recover factor without JASS execution.
                    factor = safe_number(rewritten)
                    row['multipliers'][var] *= factor ** loop_limit
                    with localcontext() as context:
                        context.prec=50
                        row['multiplier_exact_decimal'][var] = str(Decimal(row['multiplier_exact_decimal'][var]) * Decimal(str(factor)) ** loop_limit)
                    row['assignments'].append({'variable': var, 'expression': expression, 'line': offset, 'repeat': loop_limit})
        rows.append(row)
    return rows


def binding_rows(records):
    result = []
    for rec in records:
        if 'DialogAddButton(' not in rec['text']: continue
        m = re.search(r', (0x[0-9A-F]+), DialogAddButton\(.+, "([^"]*)",', rec['text'])
        if m:
            label = re.sub(r'\|[Cc][0-9a-fA-F]{8}|\|r', '', m[2])
            result.append({'key': m[1], 'label': label, 'source': ref(rec), 'guards': rec['guards']})
    return result


def numeric_schedule_profiles(rows, scheduler):
    result=[]
    field_keys={'0xB259B269': 'spawn_interval_seconds', '0x8B1FFFFC': 'timer_iterations', '0x29F518A4': 'initial_remaining'}
    for r in rows:
        if not r['directly_bound_to_matching_N_label']: continue
        entry={'mode_id':r['mode_id'], 'mode_name':r['mode_name'], 'difficulty':r['difficulty'],
               'dialog_mode_compatible':r['selector_mode_compatible'],
               'total_waves':25 if r['difficulty']==1 else 30,
               'total_waves_sources':[26760,26761] if r['difficulty']==1 else [26760,26773],
               'assault_boss_waves':list(range(5,26 if r['difficulty']==1 else 31,5)),
               'wave_period_seconds':90, 'wave_period_sources':[26762,26774], 'bands':[]}
        for wave in (1,11):
            vals={'xgdg_tDAA':r['mode_id'], 'xgdg_nAAA':r['difficulty'],'udg_BC':wave}
            band={'wave_min':1 if wave==1 else 11,'wave_max':10 if wave==1 else entry['total_waves'], 'assignment_sources':[]}
            for rec in scheduler:
                if not guard_possible(rec['guards'],vals): continue
                if not re.match(r'call Save(?:Integer|Real)\(',rec['text']): continue
                args=split_args(rec['text'].split('(',1)[1][:-1])
                if args[2] not in field_keys: continue
                try: value=safe_number(args[3])
                except (SyntaxError, ValueError): continue
                band[field_keys[args[2]]]=value;band['assignment_sources'].append(rec['line'])
            assert band['timer_iterations']==band['initial_remaining'], band
            assert band['timer_iterations']>0,band
            band['actual_units_on_wave_1_2_3']=band['timer_iterations']-1 if wave==1 else None
            band['actual_units_on_other_waves']=band['timer_iterations']
            band['spawn_timer_duration_seconds']=band['timer_iterations']*band['spawn_interval_seconds']
            band['time_relationship_to_next_wave'] = ('overlap' if band['spawn_timer_duration_seconds']>90 else
                                                       'same_timestamp_boundary' if band['spawn_timer_duration_seconds']==90 else 'completes_before_next_wave')
            band['unit_count_scope']='nominal count per timer, not a captured-wave guarantee; callback reads global udg_BC at each tick'
            entry['bands'].append(band)
        result.append(entry)
    return result


def nominal_wave_compositions(profiles,array_rows):
    arrays=defaultdict(dict)
    for r in array_rows: arrays[r['array']][r['wave']]=r
    result=[]
    for profile in profiles:
        for wave in range(1,profile['total_waves']+1):
            band=profile['bands'][0 if wave<=10 else 1]
            boss=wave%5==0
            leader=wave not in (1,2,3,5,10,15,20,25,30)
            ordinary=band['timer_iterations']-1
            counts=Counter()
            raw=arrays['udg_GW'][wave]['rawid']
            if profile['mode_id'] in (3,6,7): counts[raw]=ordinary
            else:
                first_slot=1 if leader else 2
                for index in range(ordinary):
                    slot=(first_slot-1+index)%3+1
                    array='udg_GW' if slot==1 else 'xgdg_CAAA' if slot==2 else 'xgdg_xAAA'
                    counts[arrays[array].get(wave,arrays['udg_GW'][wave])['rawid']]+=1
            row={'mode_id':profile['mode_id'],'mode_name':profile['mode_name'],'difficulty':profile['difficulty'],
                 'wave':wave,'nominal_unit_count':ordinary+int(boss or leader),
                 'ordinary_callback_count':ordinary,
                 'ordinary_rawid_counts':dict(counts),
                 'scourge_random_role_split':{'elite_probability_percent':50,'ordinary_probability_percent':50} if profile['mode_id']==3 else None,
                 'leader':{'rawid':raw,'count':1,'stat_rule':'leader_scourge' if profile['mode_id']==3 else 'leader_non_scourge'} if leader else None,
                 'assault_boss':{'rawid':arrays['udg_BOSS'][wave]['rawid'],'count':1,'stat_rule':'assault_boss_ruins_celestial' if profile['mode_id'] in (6,7) else 'assault_boss'} if boss else None,
                 'spawn_interval_seconds':band['spawn_interval_seconds'],
                 'time_relationship_to_next_wave':band['time_relationship_to_next_wave'],
                 'scope':'nominal composition if global wave remains unchanged for timer duration; alive human home/player, no endgame shortcut or stop flag',
                 'array_sources':[arrays[array][wave]['source'] for array in arrays if wave in arrays[array]],
                 'rule_sources':[26223,26225,26292,26293,26341,26406,26410,26418,26424,26533,26748]}
            result.append(row)
    return result


def extract(jass, output, misc=None):
    """Write facts and nominal scenarios, returning the complete wave report.

    ``misc`` is optional; omitted engine coefficients stay explicitly unknown.
    The raw JASS and its entire functions are never copied to the output.
    """
    source=Path(jass)
    destination=Path(output)
    data, lines, functions, records = load_source(source)
    byline = {r['line']: r for r in records}
    rows = literal_difficulty_rows(lines, records)
    bindings = binding_rows(records)
    # Actual callback page binding at 20908/20994/21060/21126/21192.
    callbacks = []
    for rec in records:
        if 'TriggerAddCondition(ydl_trigger, Condition(function Trig______________2021___11___3____03_48_13_______uFunc002Func001Func0' in rec['text']:
            callback = re.search(r'function (\w+)', rec['text'])[1]
            prior = [b for b in bindings if b['source']['function'] == rec['function'] and b['source']['line'] < rec['line']]
            lower = max([c['source']['line'] for c in callbacks if c['source']['function'] == rec['function']] or [0])
            page_buttons = [b for b in prior if b['source']['line'] > lower]
            callbacks.append({'callback': callback, 'source': ref(rec), 'buttons': page_buttons})
    for row in rows:
        matches = [b for c in callbacks if c['callback'] == row['source']['function'] for b in c['buttons'] if b['key'] == row['button_key']]
        row['bound_labels'] = sorted(set(b['label'] for b in matches))
        row['directly_bound_to_matching_N_label'] = 'N' + str(row['difficulty']) in row['bound_labels']
        compatible_matches=[b for b in matches if b['label']=='N'+str(row['difficulty']) and guard_possible(b['guards'],{'xgdg_tDAA':row['mode_id']})]
        row['selector_mode_compatible'] = bool(compatible_matches)
        row['selector_provenance'] = [{'source':b['source'],'guards':b['guards']} for b in compatible_matches]
        row['page_callback_provenance'] = [c['source'] for c in callbacks if c['callback'] == row['source']['function']]
        row['classification'] = ('primary_dialog_row' if row['directly_bound_to_matching_N_label'] else
                                 'alternate_button_or_unbound_legacy_row')
    array_rows = []
    for rec in records:
        m = re.fullmatch(r'set (udg_GW|udg_BOSS|xgdg_CAAA|xgdg_xAAA)\[(\d+)\]=(0x[0-9A-F]+)', rec['text'])
        if m:
            array_rows.append({'array': m[1], 'wave': int(m[2]), 'rawid': rawid(m[3]), 'rawid_hex': m[3], 'source': ref(rec), 'guards': rec['guards']})
    interesting_names = {r['function'] for r in records if re.search(r'(?:SetUnitState|UnitDamageTarget).*\b(?:xgdg_pAAA|xgdg_LAAA)\b', r['text'])}
    # Capture ordered actual writes and their full control-flow guards. Do not
    # export entire functions or entire original script.
    formula_writes = [r for r in records if r['function'] in interesting_names and
                      re.search(r'^(?:call (?:SetUnitState|SetUnitLifePercentBJ|SetUnitMoveSpeed|SetUnitScale|SetUnitVertexColor|SetUnitName|TimerStart|StartTimerBJ|SaveInteger)|set xgdg_GDAA)|CreateUnit|UnitDamageTarget', r['text'])]
    # Wave scheduler facts are separate from the callback writes.
    scheduler = [r for r in records if r['function'] == 'Trig______________2024___6___5___14_48_54Actions' and
                 (re.search(r'Save(?:Real|Integer).*0x(?:B259B269|8B1FFFFC|29F518A4)', r['text']) or
                  re.search(r'set udg_BC=|StartTimerBJ\(udg_wavetimer|TimerStart', r['text']))]
    profiles=numeric_schedule_profiles(rows,scheduler)
    compositions=nominal_wave_compositions(profiles,array_rows)
    dynamic_side_effects = [r for r in records if r['function'] in interesting_names and re.search(r'(0x3F8387FA|0x63E6C20F|0x851E1C03)',r['text'])]
    wave_refs = [r for r in records if re.search(r'(gg_trg______________2024___6___5___14_48_54|function Trig______________2024___6___5___14_48_54)', r['text'])]
    damage_event_writes=[r for r in records if r['function']=='Trig______________2024___6___5___18_41_32Actions' and
                         ('YDWESetEventDamage(' in r['text'] or
                          ('call SaveReal(' in r['text'] and re.search(r'0x(?:6DD3A3AB|2D1E4992),',r['text'])))]
    flag_writes=[r for r in records if 'call SaveBoolean(' in r['text'] and re.search(r'0x(?:3F8387FA|63E6C20F|851E1C03),',r['text'])]
    all_multiplier_assignments=[r for r in records if re.match(r'set xgdg_(?:pAAA|LAAA|oBAA|MBAA|nAAA|tDAA)=',r['text'])]
    output = {'schema': 'original-map-wave-evidence-v1',
              'source': {'path': str(source), 'sha256': hashlib.sha256(data).hexdigest(), 'line_count': len(lines),
                         'map_archive_sha256': '824c2a062c6e6e28bfa39cb048ca82b6710f0923f87fd3cb9fad5c72987dfef1'},
              'method': 'Static text/control-flow extraction; literal arithmetic and finite multiplicative table-loop folding only. Never executes JASS or embedded EXExecuteScript.',
              'variables': VARIABLE_NAMES,
              'modes': [{'id': k, 'name': v,
                         'assignment_source':ref(byline[{1:12897,2:12917,3:12937,4:12957,5:13017,6:12974,7:12994}[k]]),
                         'name_display_source':ref(byline[{1:12914,2:12934,3:12954,4:12971,5:13060,6:12991,7:13011}[k]])} for k,v in MODE_NAMES.items()],
              'difficulty_rows_all_variants': rows, 'dialog_callback_bindings': callbacks,
              'wave_unit_arrays': array_rows, 'formula_writes_in_order': formula_writes,
              'wave_scheduler_writes_in_order': scheduler,
              'main_schedule_profiles':profiles,
              'nominal_composition_count':len(compositions),
              'player_modifier_flag_consumers': dynamic_side_effects,
              'player_modifier_flag_writes':flag_writes,
              'all_mode_difficulty_multiplier_assignments':all_multiplier_assignments,
              'main_wave_trigger_references': wave_refs,
              'global_damage_event_writes_in_order':damage_event_writes,
              'relevant_functions': [v for k,v in functions.items() if k in interesting_names or k == 'Trig______________2024___6___5___14_48_54Actions'],
              'unresolved': [
                  'No original map release string has yet been identified; archive hash identifies this snapshot, not a release number.',
                  'Mathematical difficulty-loop results preserve exact decimal coefficients; Warcraft JASS real arithmetic may incur single-precision rounding. No engine execution was used.',
                  'Player relic/archive modifier flags and endgame item shortcut are separate from baseline wave formulas. Full archive index9/key102 item name is not resolved in this wave-only extraction.',
                  'Main-chain first timer iteration on waves 1/2/3 emits no unit; actual units are configured iterations minus one. This is recorded as source behavior, not silently corrected.',
                  'The endgame shortcut uses a duplicated spawn callback with differing boss mode condition and celestial spawn count; it must not be merged into baseline rules.'
              ]}
    output['derived_rules']={
        'baseline_stat_names':{'hp':'UnitBalance.HP/current maximum life','attack':'native UnitState(0x12), object dmgplus1 is only read explicitly in fallback damage/summon formulas','armor':'native UnitState(0x20)'},
        'native_base_caveat':{'description':'These spawn formulas multiply the newly created unit native state. Hero assault bosses have additional native attribute-derived HP/armor/damage and attack dice. Object SLK HP and dmgplus1 are not by themselves a proof of the complete native initial value.',
                              'sources':[26234,26237,26243,26244,26246,26252,26253]},
        'ordinary':{'modes':[1,2,4,5,6,7],'hp_factor':'pAAA','attack_factor':'pAAA','armor_factor':'LAAA','sources':[26513,26514,26515]},
        'ordinary_scourge':{'mode':3,'probability_percent':50,'hp_factor':'3*pAAA','attack_factor':'pAAA','armor_factor':'2*LAAA','sources':[26351,26352,26394,26395,26396]},
        'elite_scourge':{'mode':3,'probability_percent':50,'hp_factor':'5*pAAA','attack_factor':'2*pAAA','armor_factor':'2*LAAA','scale':2,'sources':[26351,26352,26375,26376,26377,26381]},
        'leader_eligibility':{'timer_iteration':1,'waves_excluded':[1,2,3,5,10,15,20,25,30],'sources':[26292,26293]},
        'leader_non_scourge':{'modes':[1,2,4,5,6,7],'hp_factor':'10*pAAA','attack_factor':'4*pAAA','armor_factor':'2*LAAA','scale':2,'sources':[26322,26323,26324,26325,26342]},
        'leader_scourge':{'mode':3,'hp_factor':'2*pAAA','attack_factor':'2*pAAA','armor_factor':'LAAA','replaces_not_stacks_with_elite_or_ordinary':True,'scale':2,'sources':[26292,26322,26327,26328,26329,26350,26351]},
        'assault_boss':{'modes':[1,2,3,4,5],'wave_modulo':5,'hp_factor':'pAAA','attack_factor':'pAAA','armor_factor':'LAAA','sources':[26225,26234,26246,26252,26253]},
        'assault_boss_ruins_celestial':{'modes':[6,7],'wave_modulo':5,'hp_factor':'5*pAAA','attack_factor':'3*pAAA','armor_factor':'LAAA','sources':[26225,26236,26237,26243,26244]},
        'rotation':{'modes':[1,2,4,5],'cycle':['udg_GW[wave]','xgdg_CAAA[wave] if nonzero else udg_GW[wave]','xgdg_xAAA[wave] if nonzero else udg_GW[wave]'],
                    'first_tick_counter_increment_before_role_choice':True,'leader_resets_cycle_to_zero':True,
                    'cycle_resets_after_slot_3':True,'sources':[26223,26341,26406,26410,26411,26418,26419,26424,26430,26434,26435,26442,26443,26448,26481,26485,26486,26493,26494,26499,26748]},
        'dead_scourge_rotation_copy':{'description':'The mode3 rotation block under else(mode3) can never be reached; actual scourge takes its dedicated random elite/ordinary branches.',
                                     'sources':[26351,26404,26453,26455,26459,26467]},
        'no_alternate_rotation':{'modes':[3,6,7],'sources':[26351,26363,26392,26505,26506,26509,26510]},
        'actual_count':{'first_three_waves':'timer_iterations - 1','other_non_boss_waves':'timer_iterations; includes 1 leader on eligible wave',
                        'boss_waves':'timer_iterations; includes 1 assault boss, ordinary callback runs timer_iterations - 1 times',
                        'sources':[26225,26292,26293,26350,26533]},
        'mutable_player_flags':[
            {'key':'0x3F8387FA','effect':'next assault-boss attack multiplied by 0.5; flag consumed/reset false','sources':[26238,26239,26240,26247,26248,26249]},
            {'key':'0x63E6C20F','producer_name':'发情香','ability':'A08L','duration_seconds':60,'targets':'other playing human players',
             'effect':'speed set to 522 for boss/leader/ordinary; native state0x51 set1.3 for ordinary branch. Expiring flag does not itself restore stats on already spawned units.',
             'sources':[26256,26257,26333,26334,26384,26385,26522,26523,26524,44797,44798,44803,44805,44808,44379]},
            {'key':'0x851E1C03','producer_name':'隐形披风','ability':'A08J','duration_seconds':60,'targets':'other playing human players',
             'effect':'add ability Apiv to boss/leader/ordinary. Expiring flag does not itself remove ability from already spawned units.',
             'sources':[26260,26261,26337,26338,26527,26528,44841,44842,44847,44849,44852,44384]}
        ],
        'attack_event_low_native_attack_fallback':{'conditions':'native attack damage, enemy of Player0, native attack <=10, no special ability A06G',
                        'mode3_damage':'object dmgplus1 * pAAA * 2','other_mode_damage':'object dmgplus1 * pAAA',
                        'scope':'An additional UnitDamageTarget call in this branch; not evidence that the entire final native hit equals this expression.',
                        'sources':[31626,31627,31628,31631,31632,31634]},
        'global_damage_event_corrections':{'scope':'Additional combat-event rules, independent of spawn stat multipliers. Ability IDs and target/player state matter; this is not a native simulation of every final hit.',
                         'damage_at_entry':'GetEventDamage(), optionally adjusted before percentage stage',
                         'nonhero_source_delta_rules':[
                             {'source_ability':'A009','target_ability':'A03B','target_level':0,'additive_delta':0.90,'sources':[31948,31949,31950,31951]},
                             {'source_ability':'A002','target_ability':'A03B','target_level':1,'additive_delta':0.30,'sources':[31948,31956,31957,31958]},
                             {'source_ability':'A002','target_ability':'A03B','target_level':0,'additive_delta':-0.50,'sources':[31948,31956,31961,31962]},
                             {'source_ability':'A03N','additive_delta_formula':'0.05+0.05*ability_level','sources':[31948,31967,31968]}],
                         'final_percentage_stage':'adjusted_damage * (1 + max(delta,-0.90))',
                         'later_overrides':'Player home protections, shields, lethal-damage protections and special challenge immunity can change event damage afterwards; ordered raw writes retained separately.',
                         'sources':[31877,31878,31899,32000,32001,32002,32005,32006,32010,32025,32036,32044,32050]},
        'endgame_shortcut':{'items':['I0A4','I147'],'condition':'final-boss countdown not started and shortcut not active',
                           'sets_wave':'25 if N1 else30, sets pBAA=true and pauses ordinary wave timer',
                           'boss_empowered_mode':3,'baseline_main_boss_empowered_modes':[6,7],
                           'archive_flag_modifier':{'hashtable':'xgdg_fwAA[player]','parent_key':9,'child_key':102,'effect':'multiply HP/armor/attack by0.5 after baseline role factors on all shortcut spawned roles','sources':[36443,36444,36445,36446,36525,36526,36527,36528,36603,36604,36605,36606]},
                           'celestial_iterations':3,'celestial_spawn_interval_seconds':4,
                           'sources':[37108,37109,37110,37116,37118,37119,37121,37126,37128,36424,36425,36432,37258,37259,37260,37261,37314]},
        'first_wave_delay':{'seconds':150,'sources':[15717,17334,18757,19808,20720]},
        'wave_binding_timing':{'description':'Every spawn timer callback reads global udg_BC, not a saved wave index. In cold N11–19 the60*2s timer lasts120s while next wave starts at90s; later ticks therefore use next global wave. Cold N1–10 is exactly90s and callback ordering at the boundary is not established by static extraction.',
                               'sources':[26556,26234,26295,26431,26533,26657,26658,26659,26662,26663,26754,26774]},
        'office_mode':{'name':'上班','separate_mode_flag':'xgdg_WyAA','difficulty':1,'pAAA':1,'LAAA':1,'wave_timer_seconds':27000,
                       'description':'Separate UI path; not a baseline 常规N1 coefficient row.', 'sources':[13076,13077,13078,13079,21640,21641,21642]},
        'dialog_hidden_code_tiers':{'formula_exists_but_button_mode_guard_rejects':[
            {'mode':r['mode_id'],'difficulty':r['difficulty'],'formula_source':r['source']} for r in rows
            if r['directly_bound_to_matching_N_label'] and not r['selector_mode_compatible']],
            'mode_allowed_ranges':{1:[1,9],2:[1,50],3:[1,50],4:[1,22],5:[1,9],6:[1,45],7:[1,32]},
            'sources':[20872,20873,20874,21001,21071,21150]}
    }
    # Attach function names to every compact integer-line citation, including
    # conditions that do not appear in the statement records.
    ranges=list(functions.values())
    def attach_sources(obj):
        if isinstance(obj,dict):
            for value in list(obj.values()): attach_sources(value)
            for key in list(obj):
                value=obj[key]
                if isinstance(key,str) and key.endswith('sources') and isinstance(value,list) and value and all(type(n)is int for n in value):
                    obj[key+'_refs']=[{'line':n,'function':next((f['function'] for f in ranges if f['line_start']<=n<=f['line_end']),None)} for n in value]
        elif isinstance(obj,list):
            for value in obj:attach_sources(value)
    attach_sources(output['derived_rules'])
    attach_sources(output['main_schedule_profiles'])
    attach_sources(compositions)
    # Source-line assertions protect the hand-labelled summaries from drift.
    expected={26221:'function Trig______________2024___6___5___14_48_54Func005Func001Func020T',
              26322:'if ( ( xgdg_tDAA != 3 ) ) then',26351:'if ( ( xgdg_tDAA == 3 ) ) then',
              26352:'if ( ( Probability(50.00) == true ) ) then',
              20872:'if ( ( xgdg_tDAA != 1 ) and ( xgdg_tDAA != 5 ) ) then'}
    for n,text in expected.items(): assert lines[n-1].startswith(text),(n,lines[n-1])
    assert len([r for r in rows if r['directly_bound_to_matching_N_label']])==235
    assert len([r for r in rows if r['selector_mode_compatible']])==217
    assert len(array_rows)==44
    assert set(r['wave'] for r in array_rows if r['array']=='udg_GW')==set(range(1,31))
    primary={(r['mode_id'],r['difficulty']):r for r in rows if r['directly_bound_to_matching_N_label']}
    anchors={(1,1):(2,1.2),(1,2):(4,1.5),(2,2):(36,7),(3,1):(846,15),(4,2):(16,5),(5,2):(3,1.2),(6,2):(3207.1,22.1)}
    for key,(hp,armor) in anchors.items():
        assert abs(primary[key]['multipliers']['xgdg_pAAA']-hp)<1e-7,key
        assert abs(primary[key]['multipliers']['xgdg_LAAA']-armor)<1e-7,key
        assert len(primary[key]['multipliers'])==4,key
    selected=next(c for c in compositions if (c['mode_id'],c['difficulty'],c['wave'])==(4,2,8))
    assert selected['ordinary_rawid_counts']=={'h01Z':39,'h04X':20}, selected
    assert selected['leader']['rawid']=='h01Z' and selected['nominal_unit_count']==60,selected
    selected=next(c for c in compositions if (c['mode_id'],c['difficulty'],c['wave'])==(1,2,24))
    assert selected['ordinary_rawid_counts']=={'h023':20,'h054':20,'h053':19},selected
    output['validation']={'status':'PASS','checks':['299 variants','235 N-label matched rows','217 mode-compatible button rows',
                                                 'all30 wave rawIDs and6 assault boss rawIDs','8 multiplier anchors',
                                                 'rich N2 wave8=39 normal h01Z+20 alternate h04X+1leader',
                                                 'standard N2 wave24=20/20/19 rotation ordinary+1leader'],
                          'nominal_compositions':len(compositions)}
    output['hero_native_inputs']=parse_hero_misc(misc) if misc is not None else {
        'status':'not_provided',
        'note':'Supply --misc war3mapMisc.txt for explicit hero attribute coefficients; no default coefficient is assumed.'}
    destination.mkdir(parents=True, exist_ok=True)
    (destination/'wave_rules.json').write_text(json.dumps(output, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (destination/'difficulty_table.json').write_text(json.dumps({'source': output['source'], 'rows': rows}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (destination/'schedule_profiles.json').write_text(json.dumps({'source':output['source'],'profiles':profiles,'derived_rules':output['derived_rules'],'hero_native_inputs':output['hero_native_inputs']},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (destination/'nominal_wave_compositions.json').write_text(json.dumps({'source':output['source'],'scope':'See per-row scope and timing warnings; not original-engine simulation.','rows':compositions},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return output


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jass',type=Path,required=True,help='Extracted original war3map.j; never executed')
    parser.add_argument('--output',type=Path,required=True,help='Directory for structured JSON evidence')
    parser.add_argument('--misc',type=Path,help='Optional extracted war3mapMisc.txt with hero coefficients')
    args=parser.parse_args(argv)
    try:
        result=extract(args.jass,args.output,args.misc)
    except (ValueError, OSError) as exc:
        parser.exit(2,str(exc)+'\n')
    print(json.dumps({'source_sha256':result['source']['sha256'],
                      'difficulty_variants':len(result['difficulty_rows_all_variants']),
                      'primary_rows':len(result['main_schedule_profiles']),
                      'mode_compatible_rows':sum(r['selector_mode_compatible'] for r in result['difficulty_rows_all_variants']),
                      'nominal_compositions':result['nominal_composition_count'],
                      'validation':result['validation']['status'],
                      'output':str(args.output/'wave_rules.json')},ensure_ascii=False))


if __name__ == '__main__':
    main()
