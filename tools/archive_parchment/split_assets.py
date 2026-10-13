"""Reproducibly slice the approved archive art into independent UI assets.

The image model supplied the clean, text-free material plate. This script only
packages its slices and the approved controls/icons; no game data is baked in.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
REF = ROOT / "design_refs/archive_parchment_v1"
OUT = ROOT / "art/ui/sources/custom_game/archive_parchment_v1"
MIRROR = ROOT / "panorama/src/images/custom_game/archive_parchment_v1"
TOOLS = Path(__file__).resolve().parent
OUT.mkdir(parents=True, exist_ok=True)
MIRROR.mkdir(parents=True, exist_ok=True)
approved = Image.open(REF / "approved.png").convert("RGBA")
clean = Image.open(REF / "clean_plate.png").convert("RGBA")
resample = Image.Resampling.LANCZOS
plate = clean.crop((32, 20, 1435, 1075)).resize((1164, 860), resample)
assets = {}


def save(key, image, source, crop=None, usage=""):
    image = image.convert("RGBA")
    dest = OUT / (key + ".png")
    image.save(dest, optimize=True)
    payload = dest.read_bytes()
    (MIRROR / dest.name).write_bytes(payload)
    assets[key] = {
        "file": dest.relative_to(ROOT).as_posix(),
        "size": list(image.size),
        "sha256": hashlib.sha256(payload).hexdigest(),
        "source": source,
        "crop": crop,
        "usage": usage,
    }
    return image


def approved_slice(key, crop, size=None, usage=""):
    image = approved.crop(crop)
    if size:
        image = image.resize(size, resample)
    return save(key, image, "approved.png", list(crop), usage)


def plate_slice(key, crop, usage=""):
    return save(key, plate.crop(crop), "clean_plate.png / normalized plate", list(crop), usage)


def solid(key, color, size, usage=""):
    return save(key, Image.new("RGBA", size, color), "native control material", usage=usage)


save("window_background", plate, "clean_plate.png", [32, 20, 1435, 1075], "Text-free window substrate; no scenery or interface text.")
plate_slice("header_strip", (0, 0, 1164, 56), "Independent parchment title band.")
plate_slice("sidebar_background", (12, 62, 338, 844), "Second-level category surface.")
plate_slice("content_background", (356, 62, 1146, 844), "Third-level content surface.")

# The empty portion of the approved brush header excludes its lettering.
section = approved.crop((748, 200, 1293, 237)).resize((768, 34), resample)
brush_left = approved.crop((580, 200, 601, 237)).resize((22, 34), resample)
strip = Image.new("RGBA", (790, 34))
strip.alpha_composite(brush_left, (0, 0))
strip.alpha_composite(section, (22, 0))
save("section_strip", strip, "approved.png", [580, 200, 1293, 237], "Letter-free brush strip assembled from the empty left edge and right material.")
approved_slice("category_selected", (452, 367, 534, 400), (302, 36), "Empty end of the selected category, without name/icon.")
solid("category_hover", (170, 157, 111, 34), (302, 36), "Subtle hover overlay above the material.")
solid("row_background", (4, 5, 5, 92), (756, 84), "Alternating translucent list-row wash.")
solid("row_hover", (171, 155, 107, 29), (756, 84), "Pointer highlight; no game state baked in.")

track = approved.crop((990, 286, 1168, 305)).resize((304, 19), resample)
# The cropped interval begins inside the original track. Reuse its intact right
# edge for the left edge so this component also works without a CSS border.
track.paste(track.crop((302, 0, 304, 19)).transpose(Image.Transpose.FLIP_LEFT_RIGHT), (0, 0))
save("progress_track", track, "approved.png", [990, 286, 1168, 305], "Empty progress track; its original right edge also closes the left side.")
approved_slice("progress_fill", (862, 289, 972, 301), (300, 14), "Actual orange progress material; width driven by server progress.")
approved_slice("progress_glint", (972, 289, 981, 301), (9, 14), "Trailing light, displayed only when fill is known and nonzero.")
approved_slice("close", (1295, 69, 1322, 95), (30, 30), "Independent close button glyph.")
approved_slice("scroll_track", (1307, 260, 1325, 735), (14, 475), "Plain scroll material; native scroll thumb remains interactive.")
approved_slice("scroll_thumb", (544, 362, 555, 746), (12, 384), "Muted olive thumb material.")

# Stretch only the text-free right-hand portion of the empty search field.
approved_slice("search_background", (474, 246, 550, 274), (282, 32), "Input backing; all input text is rendered by Panorama.")

# Decorative circle rings, isolated from the approved art with transparent centers.
ring = approved.crop((1235, 252, 1298, 314)).resize((64, 64), resample)
ring_mask = Image.new("L", (64, 64), 0)
rd = ImageDraw.Draw(ring_mask)
rd.ellipse((2, 2, 62, 62), fill=255)
rd.ellipse((9, 9, 55, 55), fill=0)
ring.putalpha(ImageChops.multiply(ring.getchannel("A"), ring_mask))
save("icon_ring", ring, "approved.png", [1235, 252, 1298, 314], "Circular surround; the item graphic remains an independent live component.")

nav_ids = ["clear", "shadow", "map_level", "work", "gift", "fragment", "pet", "boss", "points", "shop", "endless", "fishing", "building", "friend", "ex", "beast"]
nav_y = [347, 384, 420, 456, 492, 528, 565, 601, 638, 674, 711, 747, 782, 819, 854, 891]
nav_icons = {}
for key, cy in zip(nav_ids, nav_y):
    box = (277, cy - 17, 313, cy + 18)
    icon = approved.crop(box).resize((64, 64), resample)
    mask = Image.new("L", (256, 256), 0)
    ImageDraw.Draw(mask).ellipse((7, 7, 249, 249), fill=255)
    icon.putalpha(mask.resize((64, 64), resample))
    save("nav_" + key, icon, "approved.png", list(box), "Decorative category emblem; no text or numeric data.")
    nav_icons[key] = "nav_" + key
# Additional real categories share fitting existing emblems, not invented data.
nav_icons["starjoy_points"] = "nav_points"
nav_icons["titles"] = "nav_gift"

emblem = approved.crop((586, 120, 671, 196)).resize((80, 80), resample)
mask = Image.new("L", (320, 320), 0)
ImageDraw.Draw(mask).ellipse((5, 5, 315, 315), fill=255)
emblem.putalpha(mask.resize((80, 80), resample))
save("archive_emblem", emblem, "approved.png", [586, 120, 671, 196], "Header emblem for the selected shadow archive.")

# Reuse the same material for the independent tooltip; alpha and its content
# remain independent so long descriptions can scroll without scaling text.
tip = plate.crop((430, 190, 850, 700)).resize((360, 420), resample)
shade = Image.new("RGBA", tip.size, (4, 5, 5, 125))
tip = Image.alpha_composite(tip, shade)
save("tooltip_background", tip, "clean_plate.png / normalized plate", [430, 190, 850, 700], "Dark tooltip material.")
frame = plate.resize((360, 420), resample)
mask = frame.getchannel("A")
ImageDraw.Draw(mask).rectangle((12, 12, 347, 407), fill=0)
frame.putalpha(mask)
save("tooltip_frame", frame, "clean_plate.png / normalized plate", usage="Rough outer edge with transparent center; nine-slice safe.")
solid("tooltip_shadow", (0, 0, 0, 95), (360, 420), "Tooltip drop-shadow backing.")

manifest = {
    "version": 1,
    "canvas": [1200, 900],
    "reference": "design_refs/archive_parchment_v1/approved.png",
    "material_source": "design_refs/archive_parchment_v1/clean_plate.png",
    "source_policy": "Approved image components + imagegen text-free material plate; dynamic labels, values and progress remain separate.",
    "assets": assets,
    "nav_icons": nav_icons,
}
(TOOLS / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
runtime_assets = {key: {"file": "file://{images}/custom_game/archive_parchment_v1/" + key + ".png", "size": asset["size"]} for key, asset in assets.items()}
data = {"version": 1, "canvas": [1200, 900], "assets": runtime_assets, "nav_icons": {key: runtime_assets[asset]["file"] for key, asset in nav_icons.items()}}
data_path = ROOT / "panorama/src/scripts/custom_game/archive_parchment_data.js"
data_path.write_text("// Generated by tools/archive_parchment/split_assets.py; art only, no game data.\n(function(){'use strict';GameUI.CustomUIConfig().ArchiveParchmentData=" + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";})();\n", encoding="utf-8")
images = [f'    <Image id="ArchiveParchmentPreload_{key}" src="{asset["file"]}" visible="false" hittest="false" style="visibility:collapse; width:0px; height:0px;" />' for key, asset in runtime_assets.items()]
xml = '<root>\n  <Panel visible="false" hittest="false" hittestchildren="false">\n' + "\n".join(images) + '\n  </Panel>\n</root>\n'
(ROOT / "panorama/src/layout/custom_game/archive_parchment_assets.xml").write_text(xml, encoding="utf-8")

work = REF / "work"
work.mkdir(parents=True, exist_ok=True)
columns, cell_w, cell_h = 4, 320, 190
sheet = Image.new("RGB", (columns * cell_w, ((len(assets) + columns - 1) // columns) * cell_h), "#272521")
draw = ImageDraw.Draw(sheet)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 17)
except OSError:
    font = ImageFont.load_default()
for index, (key, asset) in enumerate(assets.items()):
    x, y = (index % columns) * cell_w, (index // columns) * cell_h
    image = Image.open(ROOT / asset["file"]).convert("RGBA")
    image.thumbnail((cell_w - 24, cell_h - 50), resample)
    sheet.paste(image, (x + 12, y + 35), image)
    draw.text((x + 10, y + 9), key + " " + "x".join(map(str, asset["size"])), fill="#e3d3b2", font=font)
sheet.save(work / "components.png")
print(f"ARCHIVE_PARCHMENT_ASSETS_READY {len(assets)} independent PNGs; 18 category bindings")
