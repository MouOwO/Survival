"""Mechanically crop original GW2 UI material, retaining the archive contract.

No image generation, painting, sharpening, color grading or alpha flattening is
performed.  WindowRegion follows XNA Rectangle(x, y, width, height), hence the
Pillow crop box is (40, 26, 953, 717).  Run with Python 3 and Pillow.
"""
from __future__ import annotations

import hashlib
import io
import json
import re
import argparse
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / "output/archive_original_skin_20261018"
INCOMING = TASK / "source_audit"
REFERENCES = ROOT / "art/ui/references/gw2_original_v1"
BASELINE = TASK / "baseline"
MANIFEST = ROOT / "tools/archive_parchment/asset_manifest.json"
ASSET_ROOT = ROOT / "art/ui/sources/custom_game/archive_parchment_v1"
MIRROR_ROOT = ROOT / "panorama/src/images/custom_game/archive_parchment_v1"
KEYS = ("window_background", "header_strip", "sidebar_background", "content_background")
SOURCE_HASHES = {
    "155985.png": "55fa3b7a13da5bc1f187b3fe2ca9e85a0321c9cf1f383a1797c9a9a667dba89f",
    "titlebar-inactive.png": "f65dde3c0aafcc71e667dacede1d9ceebc4b23a1327bcaf6374c498af0b999a2",
    "window-topright.png": "41712117a29c4ff17a7cda4d8419d73d1bc5a6fe089042ab1666688aa7802da1",
}
SOURCE_SIZES = {"155985.png": (1024, 1024), "titlebar-inactive.png": (1024, 64), "window-topright.png": (128, 64)}
SIZES = {"window_background": (1164, 860), "header_strip": (1164, 56), "sidebar_background": (326, 782), "content_background": (790, 782)}
GUARDED = (
    "panorama/src/scripts/custom_game/archive_v10.js",
    "panorama/src/styles/custom_game/archive_v10.css",
    "panorama/src/scripts/custom_game/archive_parchment_data.js",
    "panorama/src/layout/custom_game/archive.xml",
    "panorama/src/layout/custom_game/archive_parchment_assets.xml",
)
FILTER = Image.Resampling.LANCZOS


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def alpha_stats(image: Image.Image) -> dict:
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    return {"extrema": list(alpha.getextrema()), "zero_pixels": histogram[0],
            "partial_pixels": sum(histogram[1:255]), "opaque_pixels": histogram[255]}


def backup() -> dict:
    """Create the task baseline once; never replace an earlier baseline."""
    receipt = BASELINE / "hashes.json"
    if receipt.exists():
        recorded = json.loads(receipt.read_text(encoding="utf-8"))
        for item in recorded["files"]:
            assert sha((BASELINE / item["path"]).read_bytes()) == item["sha256"], "Baseline changed"
        return recorded
    assert not BASELINE.exists(), "Existing incomplete baseline needs inspection"
    paths = [MANIFEST] + [base / (key + ".png") for key in KEYS for base in (ASSET_ROOT, MIRROR_ROOT)]
    records = []
    for path in paths:
        data = path.read_bytes()
        saved = BASELINE / relative(path)
        saved.parent.mkdir(parents=True, exist_ok=True)
        saved.write_bytes(data)
        records.append({"path": relative(path), "sha256": sha(data), "bytes": len(data)})
    result = {"createdUtc": datetime.now(timezone.utc).isoformat(), "files": records}
    receipt.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def reference_sources(apply: bool) -> dict[str, Image.Image]:
    """Keep exact downloaded bytes and provenance alongside canonical art."""
    report_source = INCOMING / "source_report.json"
    if not report_source.exists():
        report_source = REFERENCES / "source_report.json"
    report_data = report_source.read_bytes()
    source_report = json.loads(report_data)
    by_name = {asset["name"]: asset for asset in source_report["assets"]}
    if apply:
        REFERENCES.mkdir(parents=True, exist_ok=True)
    result = {}
    for name, expected in SOURCE_HASHES.items():
        source = INCOMING / name
        if not source.exists():
            source = REFERENCES / name
        data = source.read_bytes()
        assert sha(data) == expected == by_name[name]["sha256"], "Original asset hash mismatch: " + name
        image = Image.open(io.BytesIO(data))
        assert image.mode == "RGBA" and image.size == SOURCE_SIZES[name], "Original RGBA size mismatch"
        assert image.getchannel("A").getextrema()[0] < 255, "Original alpha lost"
        dest = REFERENCES / name
        if dest.exists():
            assert dest.read_bytes() == data, "Existing canonical reference changed"
        else:
            assert apply, "Canonical reference has not been installed: " + name
            dest.write_bytes(data)
        result[name] = image.copy()
    dest_report = REFERENCES / "source_report.json"
    if dest_report.exists():
        assert dest_report.read_bytes() == report_data, "Existing provenance changed"
    else:
        assert apply, "Canonical provenance has not been installed"
        dest_report.write_bytes(report_data)
    return result


def replace_json_value(text: str, key: str, value: object, indentation: int) -> str:
    pattern = r'(?m)^' + " " * indentation + re.escape(json.dumps(key)) + r': '
    matches = list(re.finditer(pattern, text))
    assert len(matches) == 1, "Ambiguous manifest field: " + key
    at = matches[0].end()
    _, consumed = json.JSONDecoder().raw_decode(text[at:])
    replacement = json.dumps(value, ensure_ascii=False, indent=2)
    replacement = replacement.replace("\n", "\n" + " " * indentation)
    return text[:at] + replacement + text[at + consumed:]


def main(apply: bool) -> None:
    before_guard = {path: sha((ROOT / path).read_bytes()) for path in GUARDED}
    before_manifest_bytes = MANIFEST.read_bytes()
    before_manifest = json.loads(before_manifest_bytes)
    non_target_images = {relative(base / (key + ".png")): sha((base / (key + ".png")).read_bytes())
                         for key in before_manifest["assets"] if key not in KEYS for base in (ASSET_ROOT, MIRROR_ROOT)}
    baseline = backup() if apply else json.loads((BASELINE / "hashes.json").read_text(encoding="utf-8"))
    originals = reference_sources(apply)

    # StandardWindow documents a rectangle in x/y/width/height coordinates.
    window_box = (40, 26, 40 + 913, 26 + 691)
    window_crop = originals["155985.png"].crop(window_box)
    window = window_crop.resize(SIZES["window_background"], FILTER)
    assert window.getchannel("A").tobytes() == window_crop.getchannel("A").resize(window.size, FILTER).tobytes()

    # Preserve the right cap's aspect ratio. Only the plain main title material
    # changes width; neither source includes baked title text or a close button.
    cap_width = round(128 * 56 / 64)
    main_width = 1164 - cap_width
    main_title = originals["titlebar-inactive.png"].resize((main_width, 56), FILTER)
    cap = originals["window-topright.png"].resize((cap_width, 56), FILTER)
    header = Image.new("RGBA", SIZES["header_strip"], (0, 0, 0, 0))
    header.paste(main_title, (0, 0))
    header.paste(cap, (main_width, 0))
    assert header.crop((0, 0, main_width, 56)).tobytes() == main_title.tobytes()
    assert header.crop((main_width, 0, 1164, 56)).tobytes() == cap.tobytes()
    assert header.getchannel("A").getextrema()[0] == 0, "Header transparency flattened"

    # These retained component nodes become empty overlays, so the original
    # background stays one continuous sheet instead of being printed three times.
    images = {"window_background": window, "header_strip": header,
              "sidebar_background": Image.new("RGBA", SIZES["sidebar_background"], (0, 0, 0, 0)),
              "content_background": Image.new("RGBA", SIZES["content_background"], (0, 0, 0, 0))}
    sources = {
        "window_background": ("art/ui/references/gw2_original_v1/155985.png", list(window_box),
                              "Original GW2 standard window material; mechanical WindowRegion crop and Lanczos resize; original alpha retained."),
        "header_strip": ("art/ui/references/gw2_original_v1/titlebar-inactive.png + art/ui/references/gw2_original_v1/window-topright.png", [0, 0, 1024, 64],
                         "Original text-free titlebar with independent 112x56 right cap; original alpha retained."),
        "sidebar_background": ("transparent overlay; original material supplied once by window_background", None,
                               "Transparent retained sidebar component; prevents duplicate material printing."),
        "content_background": ("transparent overlay; original material supplied once by window_background", None,
                               "Transparent retained content component; prevents duplicate material printing."),
    }

    # Prepare all bytes and metadata before touching the production art.
    output, updates, records = {}, {}, []
    for key in KEYS:
        image = images[key]
        assert image.mode == "RGBA" and image.size == SIZES[key]
        if key in ("sidebar_background", "content_background"):
            assert alpha_stats(image)["extrema"] == [0, 0]
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        data = buffer.getvalue()
        output[key] = data
        source, crop, usage = sources[key]
        item = dict(before_manifest["assets"][key])
        assert tuple(item["size"]) == image.size, "Existing asset contract changed"
        item.update(sha256=sha(data), source=source, crop=crop, usage=usage)
        if key == "header_strip":
            item["assembly"] = {"mainSourceBox": [0, 0, 1024, 64], "mainTargetBox": [0, 0, main_width, 56],
                                "capSourceBox": [0, 0, 128, 64], "capTargetBox": [main_width, 0, 1164, 56],
                                "filter": "Lanczos", "alpha": "preserved; no flattening"}
        updates[key] = item
        records.append({"key": key, "size": list(image.size), "sha256": sha(data), "bytes": len(data),
                        "alpha": alpha_stats(image), "source": source, "crop": crop})

    newline = "\r\n" if b"\r\n" in before_manifest_bytes else "\n"
    text = before_manifest_bytes.decode("utf-8").replace("\r\n", "\n")
    for key in KEYS:
        text = replace_json_value(text, key, updates[key], 4)
    text = replace_json_value(text, "material_source", "art/ui/references/gw2_original_v1/155985.png", 2)
    text = replace_json_value(text, "material_reference", "art/ui/references/gw2_original_v1/source_report.json", 2)
    text = replace_json_value(text, "source_policy", "Original GW2 window material cropped mechanically from asset 155985; titlebar uses documented BlishHUD embedded original UI aliases (dat IDs not independently established). Original alpha retained, no generated repaint/color grading/sharpening. Sidebar/content overlays are transparent. Existing approved controls/icons and all dynamic data remain unchanged.", 2)
    new_manifest = json.loads(text)
    for key in before_manifest["assets"]:
        if key not in KEYS:
            assert new_manifest["assets"][key] == before_manifest["assets"][key], "Non-target manifest asset changed"
    for key in before_manifest:
        if key not in ("assets", "material_source", "material_reference", "source_policy"):
            assert new_manifest[key] == before_manifest[key], "Unrelated manifest metadata changed"
    # Compare against this invocation, so deliberate future control updates do
    # not depend on an eternally fixed historical baseline.
    for key in before_manifest["assets"]:
        if key not in KEYS:
            pattern = r'(?m)^    ' + re.escape(json.dumps(key)) + r': '
            at_before = re.search(pattern, before_manifest_bytes.decode("utf-8").replace("\r\n", "\n")).end()
            source_text = before_manifest_bytes.decode("utf-8").replace("\r\n", "\n")
            _, count_before = json.JSONDecoder().raw_decode(source_text[at_before:])
            at_after = re.search(pattern, text).end()
            _, count_after = json.JSONDecoder().raw_decode(text[at_after:])
            assert source_text[at_before:at_before + count_before] == text[at_after:at_after + count_after], "Unrelated manifest record bytes changed"

    for key in KEYS:
        for base in (ASSET_ROOT, MIRROR_ROOT):
            if apply:
                (base / (key + ".png")).write_bytes(output[key])
            else:
                assert (base / (key + ".png")).read_bytes() == output[key], "Asset is stale: " + key
        assert (ASSET_ROOT / (key + ".png")).read_bytes() == (MIRROR_ROOT / (key + ".png")).read_bytes()
    manifest_bytes = text.replace("\n", newline).encode("utf-8")
    if apply:
        MANIFEST.write_bytes(manifest_bytes)
    else:
        assert before_manifest_bytes == manifest_bytes, "Manifest is stale"
    assert before_guard == {path: sha((ROOT / path).read_bytes()) for path in GUARDED}, "Production UI code changed during asset build"
    for path, expected in non_target_images.items():
        assert sha((ROOT / path).read_bytes()) == expected, "Non-target canonical image changed"
    report = {"status": "PASS_ORIGINAL_MATERIAL_CROPS", "atUtc": datetime.now(timezone.utc).isoformat(),
              "pillowVersion": PILLOW_VERSION, "baseline": relative(BASELINE), "baselineFileCount": len(baseline["files"]),
              "sourceHashes": SOURCE_HASHES, "sourceReport": relative(REFERENCES / "source_report.json"),
              "windowRegionXYWH": [40, 26, 913, 691], "windowPillowBox": list(window_box),
              "mechanicalOperationsOnly": True, "alphaFlattened": False, "colorGrading": False, "sharpening": False,
              "records": records, "guardedCodeUnchanged": before_guard, "nonTargetAssetsUnchanged": True,
              "contentSynchronized": False, "compiled": False, "nativeGameVerified": False}
    if apply:
        (TASK / "asset_build.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "checkOnly": not apply, "assets": list(KEYS), "report": relative(TASK / "asset_build.json")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="Back up and write the four mechanical crops")
    mode.add_argument("--check", action="store_true", help="Verify reproducibility without writing production files")
    main(parser.parse_args().apply)
