"""Approved compatibility policy carried inside an immutable settlement bundle."""
import re

UPGRADE_COMMANDS = frozenset({
    'clear', 'boss_kill', 'endless', 'endless_reconcile', 'challenge',
    'social_draw', 'promotion', 'daily_init', 'daily_claim',
    'work_upgrade', 'building_upgrade', 'starjoy_reconcile',
    'welfare_reconcile', 'vip_claim', 'vip_purchase', 'title_equip',
})


def parse(data):
    rules = data.get('compatible_config_hashes', {})
    if not isinstance(rules, dict):
        raise ValueError('bundle_compatibility_invalid')
    result = {}
    for digest, rule in rules.items():
        if not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('bundle_compatibility_hash_invalid')
        if not isinstance(rule, dict) or set(rule) != {'commands', 'upgrade_commands'}:
            raise ValueError('bundle_compatibility_rule_invalid')
        for values in rule.values():
            if not isinstance(values, list) or any(not isinstance(value, str)
                    or not re.fullmatch(r'[a-z_]+', value) for value in values):
                raise ValueError('bundle_compatibility_commands_invalid')
            if len(values) != len(set(values)):
                raise ValueError('bundle_compatibility_commands_invalid')
        commands, upgrades = frozenset(rule['commands']), frozenset(rule['upgrade_commands'])
        if not upgrades <= commands or not upgrades <= UPGRADE_COMMANDS:
            raise ValueError('bundle_compatibility_upgrade_invalid')
        result[digest] = {'commands': commands, 'upgrade_commands': upgrades}
    return result


def accepts(bundle, digest, kind):
    if digest == bundle.hash:
        return True
    rule = getattr(bundle, 'compatible_config_hashes', {}).get(digest) if isinstance(digest, str) else None
    return rule is not None and isinstance(kind, str) and kind in rule['commands']


def upgrades(bundle, digest, kind):
    rule = getattr(bundle, 'compatible_config_hashes', {}).get(digest) if isinstance(digest, str) else None
    return rule is not None and isinstance(kind, str) and kind in rule['upgrade_commands']
