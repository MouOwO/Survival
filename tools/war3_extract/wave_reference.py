"""Decimal reference values from extracted original-map facts, never game config.

These are main-wave, neutral-modifier predictions. They are not native-engine
measurements or complete displayed/dealt attack values. Conditional modifiers,
random branch counts and the divergent endgame shortcut stay explicit.
"""
from __future__ import annotations

import ast
import hashlib
import json
from decimal import Decimal, InvalidOperation, ROUND_FLOOR, localcontext


MAX_COMPACT_BYTES = 50 * 1024 * 1024


def decimal_value(value):
    if value is None:
        return None
    if isinstance(value, bool):
        raise ValueError('boolean is not a numeric source value')
    try:
        result = Decimal(str(value))
    except InvalidOperation as exc:
        raise ValueError('invalid numeric source value: ' + str(value)) from exc
    if not result.is_finite():
        raise ValueError('non-finite numeric source value')
    return result


def decimal_text(value):
    if value is None:
        return None
    if value == 0:
        return '0'
    text = format(value, 'f')
    return text.rstrip('0').rstrip('.') if '.' in text else text


def factor_value(expression, variables):
    """Evaluate only extracted literal arithmetic with the two named factors."""
    if not isinstance(expression, str):
        raise ValueError('conditional/non-string factor needs an explicit branch')
    tree = ast.parse(expression, mode='eval')

    def walk(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            return decimal_value(node.value)
        if isinstance(node, ast.Name) and node.id in variables:
            return variables[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = walk(node.operand)
            return -value if isinstance(node.op, ast.USub) else value
        if isinstance(node, ast.BinOp):
            left, right = walk(node.left), walk(node.right)
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Div):
                return left / right
        raise ValueError('unsupported factor expression: ' + expression)

    value = walk(tree.body)
    if not value.is_finite():
        raise ValueError('non-finite factor result')
    return value


def parse_misc(text):
    wanted = {'StrHitPointBonus', 'AgiDefenseBonus', 'AgiAttackSpeedBonus', 'StrAttackBonus'}
    fields = {}
    section = None
    for number, raw in enumerate(text.lstrip('\ufeff').splitlines(), 1):
        line = raw.strip()
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            continue
        if section != 'Misc' or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        if key not in wanted:
            continue
        if key in fields:
            raise ValueError('duplicate Misc coefficient: ' + key)
        fields[key] = {'value': decimal_text(decimal_value(value.strip())),
                       'source': {'file': 'war3mapMisc.txt', 'line': number}}
    return {'sha256_utf8_text': hashlib.sha256(text.encode('utf-8')).hexdigest(),
            'coefficients': fields, 'missing_coefficients': sorted(wanted - fields.keys())}


def _unit_inputs(unit):
    keys = ('hp', 'armor', 'attack1_base', 'strength', 'agility', 'intelligence',
            'attack1_dice', 'attack1_sides', 'attack1_interval')
    result = {key: decimal_text(decimal_value(unit.get(key))) for key in keys}
    result['name'] = unit.get('name_plain', unit.get('name'))
    result['primary_attribute'] = unit.get('primary_attribute')
    result['provenance'] = {key: unit.get('provenance', {}).get(key) for key in
                            keys + ('primary_attribute',)}
    return result


def _hero_state(unit):
    primary = unit.get('primary_attribute')
    if primary in ('STR', 'AGI', 'INT'):
        return True
    if primary == '_':
        return False
    return None


def _native_input(unit, field, coefficient, attribute, misc):
    base = decimal_value(unit.get(field))
    if base is None:
        return None
    hero = _hero_state(unit)
    if hero is False:
        return base
    factor = misc['coefficients'].get(coefficient)
    if factor is None:
        return None
    bonus = decimal_value(factor['value'])
    if bonus == 0:
        return base
    if hero is None:
        return None
    amount = decimal_value(unit.get(attribute))
    return None if amount is None else base + amount * bonus


def _source_hash(document):
    return document.get('source', {}).get('sha256')


def _difficulty_index(data):
    result = {}
    for row in data['rows']:
        if not row.get('directly_bound_to_matching_N_label'):
            continue
        key = f"{row['mode_id']}:N{row['difficulty']}"
        if key in result:
            raise ValueError('duplicate primary difficulty: ' + key)
        values = row.get('multiplier_exact_decimal', {})
        numeric = row.get('multipliers', {})
        p = decimal_value(values.get('xgdg_pAAA', numeric.get('xgdg_pAAA')))
        armor = decimal_value(values.get('xgdg_LAAA', numeric.get('xgdg_LAAA')))
        if p is None or armor is None:
            raise ValueError('missing extracted wave multiplier: ' + key)
        result[key] = {'mode_id': row['mode_id'], 'mode_name': row.get('mode_name'),
                       'difficulty': row['difficulty'], 'p_hp_attack': decimal_text(p),
                       'L_armor': decimal_text(armor),
                       'selector_mode_compatible': row.get('selector_mode_compatible'),
                       'source': row.get('source'), 'assignment_sources': row.get('assignments', [])}
    return result


def _roles(composition):
    split = composition.get('scourge_random_role_split')
    for ident, count in composition.get('ordinary_rawid_counts', {}).items():
        if split:
            yield ident, 'ordinary', 'ordinary_scourge', None, count, split.get('ordinary_probability_percent')
            yield ident, 'elite', 'elite_scourge', None, count, split.get('elite_probability_percent')
        else:
            yield ident, 'ordinary', 'ordinary', count, None, None
    for name in ('leader', 'assault_boss'):
        role = composition.get(name)
        if role:
            yield role['rawid'], name, role.get('stat_rule'), role.get('count'), None, None


def _conditional_refs(flags, role, rule_id):
    # Main-chain applicability from the extracted role paths. The dedicated
    # scourge branches do not reach the ordinary non-scourge flag checks.
    result = []
    for flag in flags:
        if flag == '0x3F8387FA' and role != 'assault_boss':
            continue
        if flag == '0x63E6C20F' and rule_id == 'ordinary_scourge':
            continue
        if flag == '0x851E1C03' and rule_id in ('ordinary_scourge', 'elite_scourge'):
            continue
        result.append(flag)
    return result


def build_reference(units_data: dict, wave_rules: dict, difficulty_data: dict,
                    composition_data: dict, misc_text: str) -> dict:
    """Join original extracted tables and formulas into compact role predictions.

    All Decimal values are serialized as plain decimal strings. Missing native
    inputs stay null, and unsupported conditional rules stay unresolved. Source
    function/line evidence is indexed once and referenced by every role row.
    """
    hashes = [_source_hash(item) for item in (wave_rules, difficulty_data, composition_data)]
    if any(value is None for value in hashes) or len(set(hashes)) != 1:
        raise ValueError('wave, difficulty and composition source hashes must match')
    units = {}
    for unit in units_data['units']:
        ident = unit['raw_id']
        if ident in units:
            raise ValueError('duplicate original unit: ' + ident)
        units[ident] = unit
    difficulties = _difficulty_index(difficulty_data)
    rules = wave_rules['derived_rules']
    misc = parse_misc(misc_text)
    rows = []
    unresolved = {}
    used_units = set()
    used_rules = set()
    unresolved_rules = {}
    wave_sources = {}
    observed = set()
    flags = {flag['key']: flag for flag in rules.get('mutable_player_flags', [])}
    field_names = ('hp_slk_product', 'hp_native_prediction', 'attack_base_setter_prediction',
                   'armor_slk_product', 'armor_native_prediction', 'armor_floor')
    with localcontext() as context:
        context.prec = 100
        for composition in composition_data['rows']:
            key = f"{composition['mode_id']}:N{composition['difficulty']}"
            if key not in difficulties:
                raise ValueError('composition has no primary difficulty: ' + key)
            difficulty = difficulties[key]
            p = decimal_value(difficulty['p_hp_attack'])
            armor = decimal_value(difficulty['L_armor'])
            wave = composition['wave']
            observed.add((composition['mode_id'], composition['difficulty'], wave))
            wave_sources.setdefault(str(wave), {'array_sources': composition.get('array_sources', []),
                                                'rule_source_refs': composition.get('rule_sources_refs', [])})
            for ident, role, rule_id, count, trials, probability in _roles(composition):
                row = {'mode_id': composition['mode_id'], 'mode_name': composition.get('mode_name'),
                       'difficulty': composition['difficulty'], 'wave': wave, 'raw_id': ident,
                       'role': role, 'rule_id': rule_id if isinstance(rule_id, str) else None,
                       'count': count, 'spawn_trials': trials,
                       'probability_percent': decimal_text(decimal_value(probability)),
                       'count_basis': 'random_branch_per_trial' if trials is not None else 'nominal_timer',
                       'p_hp_attack': decimal_text(p), 'L_armor': decimal_text(armor),
                       'hp_multiplier': None, 'attack_base_multiplier': None, 'armor_multiplier': None,
                       **{field: None for field in field_names},
                       'time_relationship_to_next_wave': composition.get('time_relationship_to_next_wave'),
                       'source_refs': {'difficulty': key, 'unit': ident, 'rule': rule_id if isinstance(rule_id, str) else None, 'wave': str(wave)},
                       'conditional_modifier_refs': _conditional_refs(flags, role, rule_id),
                       'status': 'baseline_prediction'}
                used_units.add(ident)
                unit = units.get(ident)
                rule = rules.get(rule_id) if isinstance(rule_id, str) else None
                issue = None
                if unit is None:
                    issue = 'missing_unit_data'
                elif not isinstance(rule, dict):
                    issue = 'unsupported_or_conditional_rule'
                else:
                    allowed_modes = rule.get('modes', [rule['mode']] if 'mode' in rule else None)
                    if allowed_modes is not None and composition['mode_id'] not in allowed_modes:
                        issue = 'rule_mode_mismatch'
                factors = None
                if issue is None:
                    try:
                        factors = [factor_value(rule[field], {'xgdg_pAAA': p, 'pAAA': p,
                                   'xgdg_LAAA': armor, 'LAAA': armor})
                                   for field in ('hp_factor', 'attack_factor', 'armor_factor')]
                    except (ValueError, SyntaxError, KeyError, ArithmeticError):
                        issue = 'unsupported_or_conditional_rule'
                if factors is not None:
                    used_rules.add(rule_id)
                    hp_factor, attack_factor, armor_factor = factors
                    row.update(hp_multiplier=decimal_text(hp_factor), attack_base_multiplier=decimal_text(attack_factor),
                               armor_multiplier=decimal_text(armor_factor))
                    hp = decimal_value(unit.get('hp'))
                    attack = decimal_value(unit.get('attack1_base'))
                    defense = decimal_value(unit.get('armor'))
                    native_hp = _native_input(unit, 'hp', 'StrHitPointBonus', 'strength', misc)
                    native_armor = _native_input(unit, 'armor', 'AgiDefenseBonus', 'agility', misc)
                    row.update(hp_slk_product=decimal_text(None if hp is None else hp * hp_factor),
                               hp_native_prediction=decimal_text(None if native_hp is None else native_hp * hp_factor),
                               attack_base_setter_prediction=decimal_text(None if attack is None else attack * attack_factor),
                               armor_slk_product=decimal_text(None if defense is None else defense * armor_factor),
                               armor_native_prediction=decimal_text(None if native_armor is None else native_armor * armor_factor),
                               armor_floor=decimal_text(None if native_armor is None else (native_armor * armor_factor).to_integral_value(rounding=ROUND_FLOOR)))
                    if any(row[field] is None for field in field_names):
                        issue = 'missing_numeric_or_native_input'
                if issue:
                    row['status'] = 'unresolved'
                    row['unresolved_reason'] = issue
                    issue_key = (issue, ident, str(rule_id))
                    unresolved.setdefault(issue_key, {'reason': issue, 'raw_id': ident,
                                                       'rule': rule_id, 'first_context': {'mode_id': composition['mode_id'],
                                                       'difficulty': composition['difficulty'], 'wave': wave}})
                    if issue == 'unsupported_or_conditional_rule':
                        unresolved_rules[str(rule_id)] = rule
                rows.append(row)
    provenance = {
        'units': {ident: _unit_inputs(units[ident]) for ident in sorted(used_units) if ident in units},
        'difficulties': difficulties,
        'rules': {name: {key: rules[name].get(key) for key in
                         ('hp_factor', 'attack_factor', 'armor_factor', 'sources_refs', 'sources', 'mode', 'modes')}
                  for name in sorted(used_rules)},
        'waves': wave_sources,
        'misc': misc,
    }
    coverage = []
    for profile in wave_rules.get('main_schedule_profiles', []):
        missing = [wave for wave in range(1, profile['total_waves'] + 1)
                   if (profile['mode_id'], profile['difficulty'], wave) not in observed]
        if missing:
            coverage.append({'mode_id': profile['mode_id'], 'difficulty': profile['difficulty'], 'missing_waves': missing})
    report = {'schema': 'war3_wave_role_reference_v1',
              'source': wave_rules['source'], 'unit_schema': units_data.get('schema'),
              'scenario': 'main_wave_baseline_no_optional_player_flags',
              'native_execution_verified': False,
              'counts': {'primary_difficulties': len(difficulties), 'composition_contexts': len(observed),
                         'role_rows': len(rows), 'used_unit_ids': len(used_units)},
              'provenance': provenance, 'conditional_modifiers': flags,
              'excluded_conditional_path': rules.get('endgame_shortcut'),
              'unresolved_rule_definitions': unresolved_rules,
              'limitations': [
                  'HP SLK product and native HP prediction are different columns. Hero prediction adds explicit Misc STR HP before the spawn multiplier; no native engine is executed.',
                  'Attack values predict only the SLK damage-base component passed through the base setter. They are not final panel damage, dice ranges, primary-attribute bonuses, armor-adjusted damage or combat-event damage.',
                  'Armor floor uses mathematical floor on predicted native armor, including negative values. Missing coefficients or attributes remain unresolved rather than defaulting to zero.',
                  'No optional player modifier or divergent endgame shortcut is silently applied. Applicable flags and their source rules are listed separately.',
                  'Scourge ordinary and elite rows are alternative branches for each trial; neither row count is a fixed50-percent allocation.',
                  'Counts are nominal per-timer compositions. Original callbacks read global wave; overlap and same-timestamp warnings are preserved per row.',
                  'All supplied N-label-matched formula rows are retained, including mode-hidden tiers. Dialog availability is recorded in the difficulty provenance.',
                  'Exact decimal mathematics is a reference prediction; original JASS real arithmetic and native state rounding can differ.',
              ],
              'unresolved': list(unresolved.values()), 'coverage_issues': coverage,
              'rows': rows}
    if len(json.dumps(report, ensure_ascii=False, separators=(',', ':')).encode('utf-8')) > MAX_COMPACT_BYTES:
        raise ValueError('reference exceeds50 MiB; refuse an oversized artifact')
    return report
