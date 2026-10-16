"""Build collection-grid thumbnails without changing the approved portrait masters.

The active catalog supplies the original identities and GPU payload baseline.
Only the dedicated thumbnail directory and its manifest are written. --check
regenerates everything in memory and compares the existing output byte for byte.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import struct

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_SET = "collection_portraits_compact_v1"
SIZE = 128
POOLS = ("ex", "friend", "wife", "beast")
SOURCE_DIRS = {
    "ex": "panorama/src/images/custom_game/archive_portraits_v3",
    "friend": "panorama/src/images/custom_game/archive_portraits_v3",
    "wife": "panorama/src/images/custom_game/wife_portraits_v1",
    "beast": "panorama/src/images/custom_game/archive_items_v2",
}
OUTPUT_DIR = "panorama/src/images/custom_game/" + ASSET_SET
MANIFEST = "data/ui/" + ASSET_SET + ".json"
MIP_LEVELS = SIZE.bit_length()
PAYLOAD_BYTES = sum(max(1, SIZE >> level) ** 2 * 4 for level in range(MIP_LEVELS))


def sha256(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def texture_recipe(identity: str) -> bytes:
    return f'''<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{{
"m_inputTextureArray" "element_array" [ "CDmeInputTexture" {{ "m_name" "string" "0" "m_fileName" "string" "panorama/images/custom_game/{ASSET_SET}/{identity}.png" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" }} ]
"m_outputTypeString" "string" "2D"
"m_outputFormat" "string" "BGRA8888"
"m_outputClearColor" "vector4" "0 0 0 0"
"m_nOutputMinDimension" "int" "0"
"m_nOutputMaxDimension" "int" "{SIZE}"
"m_bNoLod" "bool" "1"
"m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" {{ "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" {{ "m_algorithm" "string" "Box" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" }} "m_outputColorSpace" "string" "srgb" }} ]
}}
'''.encode("utf-8")


def legacy_payload_bytes(blob: bytes) -> int:
    """Read the native resource payload offset; never infer it from PNG size."""
    if len(blob) < 16:
        raise ValueError("Truncated legacy GPU resource")
    payload_offset = struct.unpack_from("<I", blob)[0]
    table = 8 + struct.unpack_from("<I", blob, 8)[0]
    count = struct.unpack_from("<I", blob, 12)[0]
    if not (table + count * 12 <= payload_offset <= len(blob)):
        raise ValueError("Invalid legacy GPU resource header")
    return len(blob) - payload_offset


def catalog(source_root: Path) -> dict[str, dict]:
    source = (source_root / "panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js").read_text(encoding="utf-8-sig")
    start = source.index("entries=") + len("entries=")
    rows, _ = json.JSONDecoder().raw_decode(source[start:])
    result = {}
    for row in rows:
        if row.get("category_id") not in POOLS:
            continue
        identity = row["item_id"]
        if identity in result:
            raise ValueError("Duplicate collection portrait: " + identity)
        result[identity] = row
    expected = {f"{pool}_{number:02}" for pool in POOLS for number in range(1, 41)}
    if set(result) != expected:
        raise ValueError("The source catalog must contain all 160 collection portraits")
    return result


def build(source_root: Path) -> tuple[dict[str, bytes], dict]:
    rows = catalog(source_root)
    outputs: dict[str, bytes] = {}
    records = []
    baseline = 0
    for pool in POOLS:
        for number in range(1, 41):
            identity = f"{pool}_{number:02}"
            row = rows[identity]
            source_path = SOURCE_DIRS[pool] + "/" + identity + ".png"
            if row.get("icon_path") != source_path.removeprefix("panorama/src/images/"):
                raise ValueError("Unexpected master identity: " + identity)
            original = (source_root / source_path).read_bytes()
            source_hash = sha256(original)
            if row.get("sha256") != source_hash:
                raise ValueError("The approved master SHA differs: " + identity)
            with Image.open(io.BytesIO(original)) as image:
                image.load()
                original_size = list(image.size)
                if image.format != "PNG" or image.mode != "RGBA" or image.width != image.height:
                    raise ValueError("Expected a square RGBA PNG master: " + identity)
                # Filter associated color and alpha together. Transparent RGB
                # never leaks into visible edge texels; masters remain untouched.
                thumbnail = image.convert("RGBa").resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGBA")
                stream = io.BytesIO()
                thumbnail.save(stream, format="PNG", compress_level=9, optimize=False)
                png = stream.getvalue()
            texture = texture_recipe(identity)
            png_path = OUTPUT_DIR + "/" + identity + ".png"
            texture_path = OUTPUT_DIR + "/" + identity + ".vtex"
            outputs[png_path] = png
            outputs[texture_path] = texture
            legacy_uri = row.get("runtime_uri", "")
            if not legacy_uri.startswith("s2r://panorama/images/custom_game/") or not legacy_uri.endswith(".vtex"):
                raise ValueError("Unexpected legacy texture URI: " + identity)
            payload = legacy_payload_bytes((source_root / (legacy_uri.removeprefix("s2r://") + "_c")).read_bytes())
            baseline += payload
            records.append({
                "id": identity,
                "category_id": pool,
                "source": source_path,
                "source_sha256": source_hash,
                "source_dimensions": original_size,
                "png": png_path,
                "png_sha256": sha256(png),
                "texture": texture_path,
                "texture_sha256": sha256(texture),
                "runtime_uri": "s2r://panorama/images/custom_game/" + ASSET_SET + "/" + identity + ".vtex",
                "legacy_runtime_uri": legacy_uri,
                "legacy_payload_bytes": payload,
            })
    manifest = {
        "schema_version": 1,
        "asset_set": ASSET_SET,
        "usage": "collection_grid_only",
        "dimensions": [SIZE, SIZE],
        "pixel_format": "RGBA",
        "resize": {"algorithm": "Lanczos", "alpha": "premultiplied", "color_space": "srgb_encoded"},
        "texture": {"output_format": "BGRA8888", "no_lod": True, "mip_algorithm": "Box", "mip_levels": MIP_LEVELS, "payload_bytes_per_texture": PAYLOAD_BYTES},
        "count": len(records),
        "legacy_payload_bytes": baseline,
        "target_payload_bytes": len(records) * PAYLOAD_BYTES,
        "items": records,
    }
    outputs[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return outputs, manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT, help="Repository containing approved masters and the active catalog")
    parser.add_argument("--output-root", type=Path, default=ROOT, help="Repository receiving only the dedicated thumbnail assets")
    parser.add_argument("--check", action="store_true", help="Compare generated bytes without writing any files")
    args = parser.parse_args()
    source_root, output_root = args.source_root.resolve(), args.output_root.resolve()
    outputs, manifest = build(source_root)
    for relative, blob in outputs.items():
        target = output_root / relative
        if args.check:
            if not target.is_file() or target.read_bytes() != blob:
                raise ValueError("Generated output differs: " + relative)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(blob)
    if args.check:
        expected = {Path(name).name for name in outputs if name.startswith(OUTPUT_DIR + "/")}
        actual = {p.name for p in (output_root / OUTPUT_DIR).iterdir() if p.suffix in (".png", ".vtex")}
        if actual != expected:
            raise ValueError("Unexpected or missing files in the dedicated thumbnail directory")
    print(json.dumps({"result": "COLLECTION_PORTRAIT_THUMBNAILS_CHECK_PASS" if args.check else "COLLECTION_PORTRAIT_THUMBNAILS_BUILT", "count": manifest["count"], "dimensions": manifest["dimensions"], "legacy_payload_bytes": manifest["legacy_payload_bytes"], "target_payload_bytes": manifest["target_payload_bytes"], "originals_untouched": True}))


if __name__ == "__main__":
    main()
