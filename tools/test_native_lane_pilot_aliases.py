"""Generator and byte preservation checks; no Dota or shared source mutations."""
from pathlib import Path
import copy
import tempfile

import build_native_lane_pilot as builder
from build_wave_monster_cosmetics import parse_kv


def main():
    outputs, original = builder.build()
    npc_path = builder.ROOT / 'scripts/npc/npc_units_custom.txt'
    assert original == (builder.ROOT / 'output/native_lane_pilot_20261013/pre_change/npc_units_custom.txt').read_bytes()
    assert builder.without_include(npc_path.read_bytes())[0] == original
    for relative, data in outputs.items():
        assert (builder.ROOT / relative).read_bytes() == data
    src = parse_kv(original.decode('utf-8-sig'))['DOTAUnits']
    alias = parse_kv(outputs[builder.OUTPUTS[0]].decode())['DOTAUnits']
    assert len(alias) == 2
    negative_count = 0
    for key in builder.SPECS:
        source = src['npc_survival_wave_named_' + key]
        candidate = alias['npc_survival_tools_lane_' + key]
        expected = copy.deepcopy(source)
        expected['BaseClass'] = 'npc_dota_creep_lane'
        assert candidate == expected
        for field, value in [('AttackRange', '999'), ('Ability1', 'creep_piercing'),
                             ('Model', 'models/invalid.vmdl'), ('ProjectileSpeed', '999')]:
            wrong = copy.deepcopy(candidate)
            wrong[field] = value
            assert wrong != expected
            negative_count += 1
    with tempfile.TemporaryDirectory(prefix='native_lane_generator_', dir=builder.ROOT / 'output') as directory:
        temp = Path(directory)
        assert temp.resolve().is_relative_to((builder.ROOT / 'output').resolve())
        path = temp / 'scripts/npc/npc_units_custom.txt'
        path.parent.mkdir(parents=True)
        path.write_bytes(original)
        first, preserved = builder.build(temp)
        assert preserved == original
        path.write_bytes(first['scripts/npc/npc_units_custom.txt'])
        second, preserved = builder.build(temp)
        assert first == second and preserved == original
        duplicate = path.read_bytes().replace(b'"DOTAUnits"', b'#base "npc_tools_native_lane_pilot.txt"\n"DOTAUnits"', 1)
        path.write_bytes(duplicate)
        try:
            builder.build(temp)
        except AssertionError:
            pass
        else:
            raise AssertionError('duplicate/unmanaged include accepted')
    print(f'NATIVE_LANE_GENERATOR_PASS 2 aliases, {negative_count} extra-field negative controls, exact dirty-source preservation, idempotence and duplicate include rejection')


if __name__ == '__main__':
    main()
