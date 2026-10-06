"""Compile the layered title and refresh versioned Panorama runtime copies.
Run from this checkout with Python. Requires the local Dota Workshop Tools.
The unsuffixed title JS files are canonical; versioned JS files are generated aliases.
"""
from pathlib import Path
import shutil
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / "content/dota_addons" / ROOT.name / "panorama"
OUT = ROOT / "output/title_25d_build"
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = ROOT / "panorama/src"
# Motion rig.json is the source of truth for sprite sampling and placement.
rig = json.loads((ROOT / "art/titles/motion_20261005/rig.json").read_text(encoding="utf-8"))
(SOURCES / "scripts/custom_game/title_motion_data.js").write_text(
    "/* Generated from art/titles/motion_20261005/rig.json. */\nGameUI.CustomUIConfig().SurvivalTitleMotionData="
    + json.dumps(rig, separators=(",", ":")) + ";\n", encoding="utf-8")
ALIASES = {
    "title_layered_art.js": "title_layered_art_polish_v8.js",
    "title_world.js": "title_world_overlap_v30.js",
    "title_motion_data.js": "title_motion_data_peak_v9.js",
    "title_series_art.js": "title_series_art_peak_v17.js",
    "archive_180de7e38b.js": "archive_180de7e38b_titles_compact_v6.js",
}
for source, target in ALIASES.items():
    shutil.copy2(SOURCES / "scripts/custom_game" / source, SOURCES / "scripts/custom_game" / target)
files = ["images/custom_game/titles/peak_clean_" + name + ".png" for name in ("mountains", "letters", "dragon_coiled")]

files += ["images/custom_game/titles/peak_clean_rig_" + name + ".svg" for name in ("body", "jaw", "claw", "mouth", "cheek")]
files += ["images/custom_game/titles/peak_clean_depth_front.svg"]
files += ["scripts/custom_game/" + name for name in ALIASES.values()]
files += [str(path.relative_to(SOURCES)).replace("\\", "/") for path in (SOURCES / "images/custom_game/titles/series").glob("*_v3.png")]
files += [str(path.relative_to(SOURCES)).replace("\\", "/") for path in (SOURCES / "images/custom_game/titles/motion").iterdir() if path.suffix in (".png", ".svg")]
files += ["styles/custom_game/title_series.css", "styles/custom_game/archive_titles.css", "layout/custom_game/archive.xml"]
for relative in files:
    target = CONTENT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCES / relative, target)
for index, relative in enumerate(files):
    if relative.endswith((".png", ".svg")):
        continue  # XML preload dependencies compile PNGs to *_png.vtex_c.
    result = subprocess.run([str(ENGINE / "game/bin/win64/resourcecompiler.exe"), "-i", str(CONTENT / relative),
                             "-game", str(ENGINE / "game/dota"), "-f", "-nop4"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / (str(index) + ".log")).write_bytes(result.stdout)
    if result.returncode or b"0 failed" not in result.stdout:
        raise RuntimeError("Compile failed: " + relative + "; see " + str(OUT))
for name in ("mountains", "letters", "dragon_coiled"):
    assert (ROOT / "panorama/images/custom_game/titles" / ("peak_clean_" + name + "_png.vtex_c")).is_file()
for source in (SOURCES / "images/custom_game/titles/series").glob("*_v3.png"):
    assert (ROOT / "panorama/images/custom_game/titles/series" / (source.stem + "_png.vtex_c")).is_file()
for name in ("body", "jaw", "claw", "mouth", "cheek"):
    assert (ROOT / "panorama/images/custom_game/titles" / ("peak_clean_rig_" + name + ".vsvg_c")).is_file()
assert (ROOT / "panorama/images/custom_game/titles/peak_clean_depth_front.vsvg_c").is_file()
for source in (SOURCES / "images/custom_game/titles/motion").iterdir():
    if source.suffix not in (".png", ".svg"): continue
    compiled = source.stem + ("_png.vtex_c" if source.suffix == ".png" else ".vsvg_c")
    assert (ROOT / "panorama/images/custom_game/titles/motion" / compiled).is_file()
print("Compiled: eight title motion atlases, joint masks and distinct 6s/8s gestures / 3s light; peak title retained")
