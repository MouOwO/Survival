"""Build addon-local hero-shader fallbacks for broken spring_meteor materials.

Keeps the original models, color, normal and cutout textures. The animated
spring_meteor refraction is deliberately replaced with ordinary hero lighting.
Requires the installed Dota VPK and Valve resourceinfo/resourcecompiler tools.
Never writes to the base game's resources.
"""
import re
import subprocess
from pathlib import Path

from build_wave_monster_cosmetics import Vpk

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / "content/dota_addons/Survival"
BIN = ENGINE / "game/bin/win64"
OUT = ROOT / "output/particle_compat"
MATERIALS = [
    "materials/models/creeps/lane_creeps/creep_crystal_bad_melee/bad_melee_crystal.vmat",
    "materials/models/items/troll_warlord/mohawk_weapon_all/mohawk_weapon_crystal_blade.vmat",
    "materials/models/items/winter_wyvern/spring2021_frost_thorn_back/spring2021_frost_thorn_back_crystal.vmat",
    "materials/models/items/winter_wyvern/spring2021_frost_thorn_head/spring2021_frost_thorn_head_crystal.vmat",
    "materials/models/items/weaver/spring2021_dimension_ripper_arms/spring2021_dimension_ripper_arms_crystal.vmat",
    "materials/models/items/bristleback/bristlebot/dark_carnival_bristlebot_goo_proj_ball.vmat",
]


def run(exe, *args):
    result = subprocess.run([str(BIN / exe), *map(str, args)], capture_output=True, cwd=ROOT)
    text = result.stdout.decode("utf-8", errors="replace") + result.stderr.decode("utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(text)
    return text


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    vpk = Vpk(ENGINE / "game/dota/pak01_dir.vpk")
    for resource in MATERIALS:
        compiled = OUT / Path(resource + "_c").name
        compiled.write_bytes(vpk.read(resource + "_c"))
        data = run("resourceinfo.exe", "-i", compiled, "-b", "DATA", "-baremode")
        assert 'm_shaderName = "spring_meteor.vfx"' in data, resource
        textures = dict(re.findall(r'm_name = "([^"]+)"\s+m_pValue = resource:"([^"]+)"', data))
        target = CONTENT / resource
        target.parent.mkdir(parents=True, exist_ok=True)
        entries = {"Shader": "hero.vfx", "F_MORPH_SUPPORTED": "1",
                   "F_USE_HERO_EFFECTS_PROXY": "1", "F_USE_STATUS_EFFECTS_PROXY": "1"}
        for key, param, suffix in [("g_tColor", "TextureColor", "color"),
                                   ("g_tNormal", "TextureNormal", "normal"),
                                   ("g_tAlphaTest", "TextureTranslucency", "alpha")]:
            if key not in textures:
                continue
            texture = OUT / Path(textures[key] + "_c").name
            texture.write_bytes(vpk.read(textures[key] + "_c"))
            image = target.with_name("compat_" + suffix + ".tga")
            # resourceinfo appends _mip0; use a short temporary output path to
            # avoid its legacy Windows path limit for deeply nested cosmetics.
            extracted = OUT / ("extract_" + suffix + ".tga")
            mip = extracted.with_name(extracted.stem + "_mip0.tga")
            mip.unlink(missing_ok=True)
            run("resourceinfo.exe", "-i", texture, "-extract", "tga", extracted.relative_to(ROOT))
            if not mip.is_file():
                raise RuntimeError(f"Texture extraction failed: {mip}")
            image.write_bytes(mip.read_bytes())
            entries[param] = image.relative_to(CONTENT).as_posix()
        if "g_tAlphaTest" in textures:
            entries["F_ALPHA_TEST"] = "1"
            alpha = re.search(r'm_name = "g_flAlphaTestReference"\s+m_flValue = ([^\s]+)', data)
            entries["g_flAlphaTestReference"] = alpha.group(1) if alpha else "0.5"
        # A small constant self illumination keeps the crystal surfaces readable.
        entries["g_flSelfIllumBlendToFull"] = "0.2" if "crystal" in resource else "0.0"
        source = '// Addon compatibility fallback; see tools/build_compatible_cosmetic_materials.py.\n"Layer0"\n{\n'
        source += "".join(f'\t"{k}" "{v}"\n' for k, v in entries.items()) + "}\n"
        target.write_text(source, encoding="utf-8", newline="\n")
        log = run("resourcecompiler.exe", "-i", target, "-game", ENGINE / "game/dota", "-f", "-nop4")
        (OUT / (target.stem + ".compile.log")).write_text(log, encoding="utf-8")
        if "0 failed" not in log:
            raise RuntimeError(log)
        print(resource, "OK", flush=True)


if __name__ == "__main__":
    main()
