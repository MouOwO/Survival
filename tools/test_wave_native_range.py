"""Current melee roster, repeatable generator and real birth integration; no Dota."""
from pathlib import Path
import contextlib
import csv
import io
import json
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
import sync_wave_unit_names as sync
from build_wave_monster_cosmetics import parse_kv

ROOT = Path(__file__).resolve().parents[1]
LUA = r'C:\Program Files\lua\bin\lua5.1.exe'
CSV_ROOT = Path('data/csv/怪物与波次系统')


def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + json.dumps(k) + ']=' + lua(v) for k, v in value.items()) + '}'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return json.dumps(value, ensure_ascii=False)


def table(name):
    return list(csv.DictReader(line for line in (ROOT / CSV_ROOT / name).read_text(
        encoding='utf-8-sig').splitlines() if line and not line.startswith('#')))


def main():
    archetypes = {r['archetype_id']: r for r in table('monster_archetypes.csv')}
    formal = set()
    batches = 0
    for name in ['wave_definitions.csv', 'rich_wave_definitions.csv', 'recorded_mode_wave_definitions.csv']:
        rows = [r for r in table(name) if r['enabled'] == '1']
        batches += len(rows)
        formal.update(r['archetype_id'] for r in rows)
        for row in rows:
            definition = archetypes[row['archetype_id']]
            assert definition['attack_type'] == 'melee' and definition['attack_range'] == '128', row['wave_id']
    assert len(formal) == 44 and batches == 2246
    assert archetypes['dwarf_white_rifle']['attack_range'] == '128'
    # Separate challenge definitions retain their authored ranged contracts.
    for identity in ['ten_sin_08', 'challenge_06_morphling']:
        assert archetypes[identity]['attack_type'] == 'ranged'
        assert archetypes[identity]['attack_range'] == '536'
    current = parse_kv((ROOT / 'scripts/npc/npc_units_custom.txt').read_text(encoding='utf-8-sig'))['DOTAUnits']
    for identity in formal:
        native = current[archetypes[identity]['unit_name']]
        assert native['AttackCapabilities'] == 'DOTA_UNIT_CAP_MELEE_ATTACK', identity
        assert native['AttackRange'] == '128' and 'ProjectileModel' not in native, identity
    assert not any(name.startswith('npc_survival_range_') for name in current)
    files = [str(CSV_ROOT / name) for name in ['monster_archetypes.csv', 'wave_definitions.csv']]
    files += ['scripts/npc/npc_units_custom.txt', 'resource/addon_schinese.txt',
              'resource/localization/addon_schinese.txt']
    files += ['scripts/vscripts/config/generated/' + name + '.lua'
              for name in ['monster_archetypes', 'wave_definitions', 'wave_native_range_aliases']]
    with tempfile.TemporaryDirectory(prefix='survival_wave_melee_') as directory:
        temp = Path(directory)
        for relative in files:
            target = temp / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        previous = sync.ROOT
        sync.ROOT = temp
        try:
            for _ in range(2):
                with contextlib.redirect_stdout(io.StringIO()):
                    sync.main()
                for relative in files:
                    assert (temp / relative).read_text(encoding='utf-8-sig') == (ROOT / relative).read_text(
                        encoding='utf-8-sig'), 'generated source drift: ' + relative
        finally:
            sync.ROOT = previous
        fixture = temp / 'actual_native_unit_kv.lua'
        fixture.write_text('return ' + lua(current) + '\n', encoding='utf-8')
        subprocess.run([LUA, str(ROOT / 'tools/test_wave_native_range.lua'), str(fixture)], cwd=ROOT, check=True)
    subprocess.run([LUA, 'scripts/vscripts/tests/test_enemy_range_spawn_policy.lua'], cwd=ROOT, check=True)
    print('WAVE_MELEE_GENERATOR_PASS: 44 melee archetypes/native units, 2246 batches, 128 base range; '
          'zero ranged aliases/projectiles; rebuild twice identical; separate ranged challenges preserved')


if __name__ == '__main__':
    main()
