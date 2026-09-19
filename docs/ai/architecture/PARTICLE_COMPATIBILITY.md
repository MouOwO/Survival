# Particle and cosmetic material compatibility (2026-09-14)

The installed Dota build no longer recognizes `C_INIT_RandomLifeTime` and
`C_INIT_RandomRotation` in the custom Monkey King staff-drop particle. Eight
addon particle source files also retained these old initializers. Their source
is in the content repository; the compiled `.vpcf_c` files are in game.

`tools/update_particle_compatibility.py --write` converts them to
`C_INIT_InitFloat`. Lifetime uses field 1, rotation uses field 4, and rotation
speed uses field 5. The current native Monkey King particles use **degrees** for
these float initializers. The staff keeps its 0.28-second lifetime and -90-degree
rotation. Recompile changed sources with the installed resourcecompiler.

The native `spring_meteor.vfx` shader also reports inconsistent
`DepthPassBatchID` values. Addon-local material overrides use `hero.vfx` for six
dependencies: crystal melee creep, Troll Warlord crystal blade, Winter Wyvern
Frost Thorn head/back crystals, Weaver Dimension Ripper arm crystals, and the
Bristlebot goo projectile. `tools/build_compatible_cosmetic_materials.py`
rebuilds these from the installed VPK using Valve's resourceinfo and compiler.
The content repository holds the `.vmat` sources and extracted color/normal/
cutout textures; game holds their compiled resources, including generated
default shader textures. No base-game files are replaced.

Models and their original texture maps remain in use. Animated crystal
refraction/color cycling is replaced by ordinary hero lighting with mild self
illumination. These overrides should be revisited when Valve fixes the shader;
do not blindly delete the compiled resources while retaining source overrides.

Validation includes resource compilation, inspecting the compiled staff lifetime
and rotation, scanning project resource dependencies for remaining uses of the
shader, and loading `template_map` followed by `addhero` in the actual client.
Diagnostic logs/results are under ignored `output/particle_compat/` and
`output/particle_compat_verification.json`.
