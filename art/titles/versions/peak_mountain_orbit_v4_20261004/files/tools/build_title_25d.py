"""Compile the layered title and refresh versioned Panorama runtime copies.
Run from this checkout with Python. Requires the local Dota Workshop Tools.
The unsuffixed JS files are canonical; *_clean_v2.js are generated aliases.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / "content/dota_addons" / ROOT.name / "panorama"
OUT = ROOT / "output/title_25d_build"
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = ROOT / "panorama/src"
ALIASES = {
    "title_layered_art.js": "title_layered_art_orbit_v4.js",
    "title_world.js": "title_world_orbit_v4.js",
    "archive_180de7e38b.js": "archive_180de7e38b_clean_v2.js",
}
for source, target in ALIASES.items():
    shutil.copy2(SOURCES / "scripts/custom_game" / source, SOURCES / "scripts/custom_game" / target)
files = ["images/custom_game/titles/peak_clean_" + name + ".png" for name in ("mountains", "letters", "dragon", "head", "body")]

files += ["scripts/custom_game/" + name for name in ALIASES.values()]
files += ["styles/custom_game/archive_titles.css", "layout/custom_game/archive.xml"]
for relative in files:
    target = CONTENT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCES / relative, target)
for index, relative in enumerate(files):
    if relative.endswith(".png"):
        continue  # XML preload dependencies compile PNGs to *_png.vtex_c.
    result = subprocess.run([str(ENGINE / "game/bin/win64/resourcecompiler.exe"), "-i", str(CONTENT / relative),
                             "-game", str(ENGINE / "game/dota"), "-f", "-nop4"],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / (str(index) + ".log")).write_bytes(result.stdout)
    if result.returncode or b"0 failed" not in result.stdout:
        raise RuntimeError("Compile failed: " + relative + "; see " + str(OUT))
for name in ("mountains", "letters", "dragon", "head", "body"):
    assert (ROOT / "panorama/images/custom_game/titles" / ("peak_clean_" + name + "_png.vtex_c")).is_file()
print("Layered title compiled: five alpha textures, archive preview, 3s sweep, 3s dragon ascent / 5s period")
