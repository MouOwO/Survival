"""Scoped real preset writer regression; never switches the live outfit/config."""
from __future__ import annotations

import csv
import io
import json
import subprocess
import tempfile
from pathlib import Path

import tower_skin_presets as presets
from build_configs import build


ROOT = presets.ROOT
CSV = presets.RES / 'tower_visual_profiles.csv'
COLORS = {
    'color_r': '25|219|241',
    'color_sr': '180|95|255',
    'color_ssr': '255|52|83',
}
LEGACY_LAYERS = ('core', 'detail', 'detail_ssr', 'crown')
LUA = Path('C:/Program Files/lua/bin/lua5.1.exe')
protected_paths = [CSV, presets.GEN / 'tower_visual_profiles.lua', presets.PRESETS / 'active.json']
protected = {path: path.read_bytes() for path in protected_paths}
original_res = presets.RES
output = ROOT / 'output/death_willow_contract'
output.mkdir(parents=True, exist_ok=True)
cases = []

try:
    with tempfile.TemporaryDirectory(prefix='preset_', dir=output) as directory:
        temporary = Path(directory)
        presets.RES = temporary
        target = temporary / 'tower_visual_profiles.csv'
        runner = temporary / 'check_profile.lua'
        runner.write_text('''local profiles = assert(loadfile(arg[1]))()
local death = assert(profiles.by_id.class_1)
assert(death.native_base == "willow_shadow_realm")
assert(table.concat(death.color_r, "|") == "25|219|241")
assert(table.concat(death.color_sr, "|") == "180|95|255")
assert(table.concat(death.color_ssr, "|") == "255|52|83")
assert(table.concat(death.color, "|") == "25|219|241")
assert(death.radius_r == 96 and death.radius_sr == 108 and death.radius_ssr == 120 and death.alpha == 0.95)
for _, key in ipairs({"core", "detail", "detail_ssr", "crown"}) do assert(not death[key] or death[key] == "") end
for _, row in ipairs(profiles.rows) do
    if row.profile_id ~= "class_1" then
        assert(row.color_r == nil and row.color_sr == nil and row.color_ssr == nil)
    end
end
print("DEATH_PRESET_GENERATED_LUA_PASS")
''', encoding='utf-8')

        for legacy_schema in (False, True):
            for preset in 'ABC':
                raw = list(csv.reader(io.StringIO(protected[CSV].decode('utf-8-sig'))))
                if legacy_schema:
                    indices = [i for i, name in enumerate(raw[0]) if name not in COLORS]
                    raw = [[row[i] if i < len(row) else '' for i in indices] for row in raw]
                stream = io.StringIO(newline='')
                csv.writer(stream, lineterminator='\n').writerows(raw)
                target.write_text(stream.getvalue(), encoding='utf-8', newline='')
                rows = presets.table(target)[2]
                stale = next(row for row in rows if row['profile_id'] == 'class_1')
                stale.update(native_base='dazzle_weave', color='1|2|3', alpha='0.4',
                             core='bases/death', detail='bases/detail_death',
                             detail_ssr='bases/detail_death_ssr', crown='bases/detail_motes')
                for key in COLORS:
                    if key in stale:
                        stale[key] = '4|5|6'
                presets.save(target, rows)
                before = {row['profile_id']: dict(row) for row in presets.table(target)[2]}

                # Execute the same writer used by --preset, with only its CSV
                # destination redirected; no alternate implementation in tests.
                presets.write_base_profiles(preset)
                head, comments, actual_rows = presets.table(target)
                actual = {row['profile_id']: row for row in actual_rows}
                death = actual['class_1']
                assert death['native_base'] == 'willow_shadow_realm'
                assert {key: death[key] for key in COLORS} == COLORS
                assert death['color'] == COLORS['color_r'] and death['alpha'] == '0.95'
                assert [death['radius_' + tier] for tier in ('r', 'sr', 'ssr')] == ['96', '108', '120']
                assert all(death[key] == '' for key in LEGACY_LAYERS)
                types = next(row for row in comments if row[0].startswith('#types:'))
                assert all(types[head.index(key)] == 'list' for key in COLORS)
                assert len(head) == len(set(head)), 'legacy migration must not duplicate optional fields'
                for profile_id, original in before.items():
                    row = actual[profile_id]
                    if profile_id == 'ultimate':
                        assert all(row[key] == value for key, value in original.items()), 'UR stays unchanged'
                    elif profile_id != 'class_1':
                        assert row['native_base'] == original['native_base'], 'other routes retain their base'
                        number = int(profile_id.split('_')[1]) - 1
                        assert row['color'] == presets.COLORS[preset][number]
                        assert row['alpha'] == ('0.9' if preset == 'A' else '0.95')
                        assert row['enabled'] == ('0' if profile_id == 'class_4' else '1')
                        changed = {'color', 'alpha', 'core', 'detail', 'detail_ssr', 'crown',
                                   'enabled', 'native_base', 'radius_r', 'radius_sr', 'radius_ssr'}
                        assert all(row[key] == value for key, value in original.items() if key not in changed)
                    if profile_id != 'class_1':
                        assert all(row[key] == '' for key in COLORS), 'tier palette is exclusive to death'

                generated = temporary / 'tower_visual_profiles.lua'
                build(target, generated)
                result = subprocess.run([str(LUA), str(runner), str(generated)], cwd=ROOT,
                                        capture_output=True, text=True, encoding='utf-8', errors='replace')
                assert result.returncode == 0, result.stdout + result.stderr
                cases.append({'preset': preset, 'legacy_schema': legacy_schema,
                              'native_base': death['native_base'], 'generated_lua_pass': True})

        # Verify the committed/generated runtime module matches only this table.
        target.write_bytes(protected[CSV])
        generated = temporary / 'tower_visual_profiles.lua'
        build(target, generated)
        assert generated.read_bytes() == protected[presets.GEN / 'tower_visual_profiles.lua']
finally:
    presets.RES = original_res
    assert all(path.read_bytes() == content for path, content in protected.items()), 'scoped test mutated live configuration'

active = json.loads(protected[presets.PRESETS / 'active.json'].decode('utf-8'))['preset']
(output / 'preset_validation.json').write_text(json.dumps({
    'status': 'PASS', 'cases': cases, 'live_configuration_unchanged': True,
    'active_preset': active, 'production_generation_matches_csv': True,
}, indent=2) + '\n', encoding='utf-8')
print(f'DEATH_BASE_PRESETS_PASS presets=3 schema_cases=6 generated_lua=6 active={active} live_unchanged=true')
