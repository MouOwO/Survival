"""Build five dedicated commerce icons from approved generated PNG masters.

Only commerce_art_v1 PNG/VTEX files and commerce_generated_art_v1.json are
written. --check regenerates all bytes in memory and performs no writes.
The input directory contains <id>.png and, by default, prompts.json. Prompts
may be an ID-to-string/object mapping or a list of objects with an `id` field.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path

from PIL import Image, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[1]
ASSET_SET = "commerce_art_v1"
SOURCE_DIR = "tools/art_sources/" + ASSET_SET
OUTPUT_DIR = "panorama/src/images/custom_game/" + ASSET_SET
MANIFEST = "data/ui/commerce_generated_art_v1.json"
SIZE = 128
MIP_LEVELS = SIZE.bit_length()
PAYLOAD_BYTES = sum(max(1, SIZE >> level) ** 2 * 4 for level in range(MIP_LEVELS))
ITEMS = (
    ("spirit_katana", "斩魄刀", "video_p151"),
    ("titan_shield", "泰坦护盾", "video_p016"),
    ("master_foreman", "熟练工头", "video_p028"),
    ("lament_seed", "悲叹之种", "video_p147"),
    ("swift_winch", "快速绞盘", "video_p110"),
)


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


def prompt_records(path: Path) -> dict[str, dict]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        data = data["items"]
    if isinstance(data, list):
        rows = {}
        for row in data:
            if not isinstance(row, dict) or not isinstance(row.get("id"), str):
                raise ValueError("Prompt list entries require a string id")
            if row["id"] in rows:
                raise ValueError("Duplicate prompt identity: " + row["id"])
            rows[row["id"]] = row
    elif isinstance(data, dict):
        rows = data
    else:
        raise ValueError("Prompts must be an ID mapping or a list")
    expected = {identity for identity, _, _ in ITEMS}
    if set(rows) != expected:
        raise ValueError("Prompts must contain exactly the five approved commerce identities")
    result = {}
    for identity in expected:
        row = rows[identity]
        if isinstance(row, str):
            row = {"prompt": row}
        if not isinstance(row, dict) or not isinstance(row.get("prompt"), str) or not row["prompt"].strip():
            raise ValueError("Missing generation prompt: " + identity)
        if row.get("id", identity) != identity:
            raise ValueError("Prompt identity mismatch: " + identity)
        result[identity] = row
    return result


def portable_path(path: Path, output_root: Path) -> str:
    """Keep actual input provenance relative to the target repository root."""
    try:
        return Path(os.path.relpath(path, output_root)).as_posix()
    except ValueError as error:
        raise ValueError("Inputs must share a filesystem volume with output-root for relative provenance") from error


def build(source_root: Path, prompts_path: Path, output_root: Path) -> tuple[dict[str, bytes], dict]:
    prompts = prompt_records(prompts_path)
    source_base = portable_path(source_root, output_root)
    outputs: dict[str, bytes] = {}
    records = []
    source_hashes = set()
    thumbnail_hashes = set()
    for identity, name, sku in ITEMS:
        prompt = prompts[identity]
        if prompt.get("name", name) != name:
            raise ValueError("Prompt display name differs: " + identity)
        source_name = identity + ".png"
        original = (source_root / source_name).read_bytes()
        source_hash = sha256(original)
        if prompt.get("source_sha256", source_hash) != source_hash:
            raise ValueError("Approved source SHA differs: " + identity)
        if source_hash in source_hashes:
            raise ValueError("Commerce masters must be distinct: " + identity)
        source_hashes.add(source_hash)
        with Image.open(io.BytesIO(original)) as image:
            image.load()
            if image.format != "PNG" or image.width != image.height or image.width < SIZE:
                raise ValueError("Expected a square PNG master of at least 128px: " + identity)
            source_size = list(image.size)
            source_mode = image.mode
            rgba = image.convert("RGBA")
            source_alpha = list(rgba.getchannel("A").getextrema())
            # Match the validated collection thumbnail pipeline. Associated color
            # is filtered with alpha so hidden transparent RGB cannot form halos.
            thumbnail = rgba.convert("RGBa").resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGBA")
            stream = io.BytesIO()
            thumbnail.save(stream, format="PNG", compress_level=9, optimize=False)
            png = stream.getvalue()
            alpha = thumbnail.getchannel("A")
            thumbnail_alpha = list(alpha.getextrema())
            bounds = alpha.point(lambda value: 255 if value > 32 else 0).getbbox()
        if bounds is None:
            raise ValueError("Commerce icon is fully transparent: " + identity)
        png_hash = sha256(png)
        if png_hash in thumbnail_hashes:
            raise ValueError("Commerce thumbnails must be distinct: " + identity)
        thumbnail_hashes.add(png_hash)
        texture = texture_recipe(identity)
        png_path = OUTPUT_DIR + "/" + source_name
        texture_path = OUTPUT_DIR + "/" + identity + ".vtex"
        outputs[png_path] = png
        outputs[texture_path] = texture
        records.append({
            "id": identity,
            "name": name,
            "product_sku": sku,
            "generator": prompt.get("generator", "built-in image_gen"),
            "prompt": prompt["prompt"],
            "source": portable_path(source_root / source_name, output_root),
            "source_sha256": source_hash,
            "source_dimensions": source_size,
            "source_mode": source_mode,
            "source_alpha_extrema": source_alpha,
            "png": png_path,
            "png_sha256": png_hash,
            "alpha_extrema": thumbnail_alpha,
            "alpha_bounds_over_32": list(bounds),
            "texture": texture_path,
            "texture_sha256": sha256(texture),
            "runtime_uri": "s2r://panorama/images/custom_game/" + ASSET_SET + "/" + identity + ".vtex",
        })
    manifest = {
        "schema_version": 1,
        "asset_set": ASSET_SET,
        "usage": "commerce_product_icons",
        "source_base": source_base,
        "prompts_source": portable_path(prompts_path, output_root),
        "prompts_sha256": sha256(prompts_path.read_bytes()),
        "dimensions": [SIZE, SIZE],
        "pixel_format": "RGBA",
        "resize": {"algorithm": "Lanczos", "alpha": "premultiplied", "color_space": "srgb_encoded", "sharpen": False, "quantize": False, "pillow_version": PILLOW_VERSION},
        "texture": {"output_format": "BGRA8888", "no_lod": True, "mip_algorithm": "Box", "mip_levels": MIP_LEVELS, "payload_bytes_per_texture": PAYLOAD_BYTES},
        "count": len(records),
        "target_payload_bytes": len(records) * PAYLOAD_BYTES,
        "items": records,
    }
    outputs[MANIFEST] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return outputs, manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT / SOURCE_DIR, help="Directory containing the five approved <id>.png masters; defaults to tools/art_sources/commerce_art_v1")
    parser.add_argument("--output-root", type=Path, default=ROOT, help="Repository receiving only the dedicated asset files and manifest")
    parser.add_argument("--prompts", type=Path, help="Prompt JSON; defaults to source-root/prompts.json")
    parser.add_argument("--check", action="store_true", help="Compare generated bytes without writing any files")
    args = parser.parse_args()
    source_root, output_root = args.source_root.resolve(), args.output_root.resolve()
    prompts_path = args.prompts.resolve() if args.prompts else source_root / "prompts.json"
    # Reject an accidental input/output overlap before any files are written.
    for identity, _, _ in ITEMS:
        if (source_root / (identity + ".png")).resolve() == (output_root / OUTPUT_DIR / (identity + ".png")).resolve():
            raise ValueError("Generated masters must be kept separate from thumbnails")
    outputs, manifest = build(source_root, prompts_path, output_root)
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
            raise ValueError("Unexpected or missing source files in the dedicated commerce icon directory")
    print(json.dumps({"result": "COMMERCE_ICON_ART_CHECK_PASS" if args.check else "COMMERCE_ICON_ART_BUILT", "count": manifest["count"], "dimensions": manifest["dimensions"], "target_payload_bytes": manifest["target_payload_bytes"], "originals_untouched": True}))


if __name__ == "__main__":
    main()
