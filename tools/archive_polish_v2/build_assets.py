"""Package centered vector glyphs and a single antialiased archive icon ring.

The v1 glyph paths, palette and strokes remain byte-for-byte unchanged inside a
translation group. Bounds were measured with alpha > 16 at 512x512, then mapped
to the original 64px viewBox. These are bounds centers, not alpha mass centers.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/ui/sources/custom_game/archive_polish_v1/nav"
DESTINATIONS = (ROOT / "art/ui/sources/custom_game/archive_polish_v2", ROOT / "panorama/src/images/custom_game/archive_polish_v2")
# name, measured viewBox bounding-box center, frozen v1 source hash
GLYPHS = (
    ("beast", (32, 32.5), "ea2796d13e8c61b9f264a299f201ca7122d0609c27e8334da1dc03da40de0afc"),
    ("boss", (32, 32.5), "19ecd92daf5a198685a0e0f5dc42c19c0e3c101d75f7e73b7d554be4d407ddee"),
    ("building", (32, 30.5), "0588a3a7149f05d65cadd6a7f17cab15701456724022d0e8fefa679352441eb7"),
    ("clear", (32, 31.5), "908db3f2b575f2dbbd8cafac8e95633386f71886b1fe8d26ffc8ad23dcb327fe"),
    ("endless", (32, 32), "0f7fb6d3eb1f53a2cf5df609e40f8e7ae38eacf823435ff947c2ec4d6d26813c"),
    ("ex", (32, 33.5625), "3dcaefe70a767bbcdd20ad76150d45af6c927a7032bf3691b6996e1c9cbc3c62"),
    ("fishing", (35, 27.5), "cf228f1ad62e17fb4ce7aaf43b917b3adec385cb7ed095a616055c837682a9d5"),
    ("fragment", (30, 34), "c600f075b64985fa784e47875ccd830671140974be6d2f1034f12f697ee56ee3"),
    ("friend", (32, 33), "f09813076810d71b90597eeec98b63d41e071d1da8789718ebf9b47d49cb14d7"),
    ("gift", (32, 32.9375), "b9d7787ae9fc98a3a37c109a30c46885f6d3d9deedf86ae910e15a62df6e2a5f"),
    ("map_level", (32, 32), "23f5063096d5c43ba4a305209973d17b45659b582f7d8cd1fdb0a6210d403c3e"),
    ("pet", (32, 30), "7f64f4dd33444980e938c3487463b4420db97c9d1944760ea079bb98d55dc05f"),
    ("points", (32, 32), "718097ab9690e35139b495aaf3deeb4cf70c3fac2bf75c07d0ca901704f030d6"),
    ("shadow", (32, 32), "34da450a04799c0c3950a5f4534d61fe5257e36a0151f528ea8c239dd80b4bb9"),
    ("starjoy_points", (32, 32), "26c93574044a834f09d81073bb986ae5c1ac30a96c318e16d7104314cd35abf0"),
    ("titles", (32, 30.5), "08aa8a641aa346297081a3b766bb55612e2d96ba2d6e5ff95d3ab9647d0507e5"),
    ("work", (32, 32), "90c738be2e6eb28271076ebba2b46b2783e6eea3c536951d78bba5e222d49d92"),
)

RING = '''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 72 72">
  <defs>
    <linearGradient id="archiveGold" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#e4d19a"/>
      <stop offset="26%" stop-color="#cbb77b"/>
      <stop offset="52%" stop-color="#ab9862"/>
      <stop offset="78%" stop-color="#807047"/>
      <stop offset="100%" stop-color="#655332"/>
    </linearGradient>
  </defs>
  <circle cx="36" cy="36" r="35" fill="none" stroke="#111410" stroke-width="1"/>
  <circle cx="36" cy="36" r="33.5" fill="none" stroke="url(#archiveGold)" stroke-width="2"/>
  <circle cx="36" cy="36" r="32" fill="none" stroke="#25281e" stroke-width="1"/>
</svg>
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_or_check(relative: str, data: bytes, apply: bool) -> None:
    for base in DESTINATIONS:
        path = base / relative
        if apply:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        else:
            # Git may normalize the canonical art mirror to CRLF on Windows.
            assert path.read_bytes().replace(b"\r\n", b"\n") == data, "Stale vector asset: " + str(path)


def main(apply: bool) -> None:
    records = []
    for name, center, expected in GLYPHS:
        source = SOURCE / (name + ".svg")
        original_raw = source.read_bytes()
        raw = original_raw.replace(b"\r\n", b"\n")
        assert expected in (sha(raw), sha(raw.replace(b"\n", b"\r\n"))), "Frozen v1 source changed: " + name
        source_root = ET.fromstring(raw)
        assert source_root.attrib["viewBox"] == "0 0 64 64"
        text = raw.decode("utf-8").strip()
        match = re.fullmatch(r'<svg\s[^>]*>(.*)</svg>', text, re.DOTALL)
        assert match, "Unexpected v1 SVG structure"
        inner = match.group(1)
        offset = (32 - center[0], 32 - center[1])
        data = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 64 64">'
                f'<g transform="translate({offset[0]:g} {offset[1]:g})">' + inner + '</g></svg>\n').encode("utf-8")
        target_root = ET.fromstring(data)
        assert list(target_root)[0].tag == "{http://www.w3.org/2000/svg}g"
        assert len(list(list(target_root)[0])) == len(list(source_root)), "Source glyph structure changed"
        for before, after in zip(source_root, list(target_root)[0]):
            assert ET.tostring(before) == ET.tostring(after), "Path, palette or stroke changed"
        write_or_check("nav/" + name + ".svg", data, apply)
        assert source.read_bytes() == original_raw, "Old SVG was changed"
        records.append({"name": name, "sourceSha256": expected, "sourceBoundsCenter": list(center),
                        "translation": list(offset), "targetBoundsCenter": [32, 32], "size": [256, 256],
                        "viewBox": [0, 0, 64, 64], "sha256": sha(data)})
    assert len(records) == 17
    ring = RING.encode("utf-8")
    ring_root = ET.fromstring(ring)
    circles = ring_root.findall("{http://www.w3.org/2000/svg}circle")
    assert len(circles) == 3 and all(c.attrib["cx"] == c.attrib["cy"] == "36" for c in circles)
    assert all(c.attrib["fill"] == "none" for c in circles)
    write_or_check("icon_ring.svg", ring, apply)
    report = {"status": "PASS_CENTERED_ARCHIVE_VECTORS", "checkOnly": not apply,
              "glyphCount": 17, "originalGlyphPathsPaletteStrokesUnchanged": True,
              "measurement": {"rasterSize": [512, 512], "visibleAlphaThreshold": 16, "method": "visible bounds center"},
              "records": records, "ring": {"size": [256, 256], "viewBox": [0, 0, 72, 72],
              "center": [36, 36], "transparentCenter": True, "goldStrokeAt72px": 2, "sha256": sha(ring)},
              "productionCodeChanged": False, "compiled": False, "nativeGameVerified": False}
    if apply:
        out = ROOT / "output/archive_original_skin_20261018/polish_v2_assets.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "checkOnly": not apply, "glyphs": len(records), "ring": "icon_ring.svg"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    main(parser.parse_args().apply)
