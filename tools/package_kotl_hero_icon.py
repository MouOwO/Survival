"""Package Valve's compiled hero portrait under a custom ability-icon path."""
from pathlib import Path
from build_wave_monster_cosmetics import Vpk

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'panorama/images/heroes/npc_dota_hero_keeper_of_the_light_png.vtex_c'
TARGET = 'panorama/images/spellicons/survival/native/portrait_keeper_of_the_light_png.vtex_c'

if __name__ == '__main__':
    data = Vpk(ROOT / '../../dota/pak01_dir.vpk').read(SOURCE)
    assert len(data) > 100, 'Invalid native hero portrait'
    target = ROOT / TARGET
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    print('KOTL_HERO_ICON_PACKAGED: original compiled Valve texture, no image conversion')
