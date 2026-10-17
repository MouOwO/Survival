"""Import only the user-supplied V10 shop's independent graphic layers.

Run with --apply to copy original PNG bytes and regenerate the data module.
--check validates the source package and every generated repository file without
changing them. With neither flag, only the ignored import report is written.
No PSD, screenshot, composite, HTML inspector or raster-text PNG is imported.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path(
    'C:/Users/Administrator/Downloads/商城V10_分层PSD与组件素材包/shop_v10_layered'
)
SOURCE_MANIFEST = 'manifest.json'
SOURCE_COORDINATES = '组件坐标表.csv'
SOURCE_README = '先读.md'
ASSET_RELATIVE = Path('panorama/src/images/custom_game/shop_v10_v1')
MODULE_RELATIVE = Path('panorama/src/scripts/custom_game/shop_v10_assets.js')
DATA_RELATIVE = Path('data/ui/shop_v10_layers.json')
REPORT_RELATIVE = Path('output/shop_v10_20261017/assets_import.json')
GRAPHIC_KINDS = frozenset(('background', 'surface', 'control', 'icon', 'frame'))
EXCLUDED_KINDS = frozenset(('raster_text', 'game_context'))
CSV_TEXT_FIELDS = ('id', 'name', 'group', 'path', 'kind')
CSV_INTEGER_FIELDS = ('left', 'top', 'width', 'height', 'z')


def texture_recipe(layer_id: str) -> bytes:
    """Preserve NPOT UI dimensions: no input scaler, dimension cap or mip filter."""
    return f'''<!-- dmx encoding keyvalues2_noids 1 format vtex 1 -->
"CDmeVtex"
{{
    "m_inputTextureArray" "element_array" [ "CDmeInputTexture" {{ "m_name" "string" "0" "m_fileName" "string" "panorama/images/custom_game/shop_v10_v1/{layer_id}.png" "m_colorSpace" "string" "srgb" "m_typeString" "string" "2D" }} ]
    "m_outputTypeString" "string" "2D"
    "m_outputFormat" "string" "BGRA8888"
    "m_outputClearColor" "vector4" "0 0 0 0"
    "m_nOutputMinDimension" "int" "0"
    "m_nOutputMaxDimension" "int" "0"
    "m_bNoLod" "bool" "1"
    "m_textureOutputChannelArray" "element_array" [ "CDmeTextureOutputChannel" {{ "m_inputTextureArray" "string_array" [ "0" ] "m_srcChannels" "string" "rgba" "m_dstChannels" "string" "rgba" "m_mipAlgorithm" "CDmeImageProcessor" {{ "m_algorithm" "string" "" "m_stringArg" "string" "" "m_vFloat4Arg" "vector4" "0 0 0 0" }} "m_outputColorSpace" "string" "srgb" }} ]
}}
'''.encode('utf-8')


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def checked_child(base: Path, relative: str | Path) -> Path:
    """Reject traversal, drive paths and directory links for all scoped files."""
    base = base.resolve()
    relative = Path(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError(f'Expected a relative child path: {relative}')
    target = base / relative
    if not target.resolve().is_relative_to(base):
        raise ValueError(f'Path escapes expected root: {relative}')
    cursor = target
    while cursor != base:
        if cursor.is_symlink() or (cursor.exists() and os.path.isjunction(cursor)):
            raise ValueError(f'Linked asset paths are not imported: {relative}')
        cursor = cursor.parent
    return target


def write_if_changed(path: Path, raw: bytes) -> bool:
    if path.is_file() and path.read_bytes() == raw:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return True


def integer(value: object, field: str, layer_id: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f'{layer_id}.{field} must be an integer')
    return value


def read_package(source: Path) -> tuple[dict, list[dict], dict[str, bytes], dict]:
    manifest_path = checked_child(source, SOURCE_MANIFEST)
    coordinates_path = checked_child(source, SOURCE_COORDINATES)
    readme_path = checked_child(source, SOURCE_README)
    manifest_raw = manifest_path.read_bytes()
    coordinates_raw = coordinates_path.read_bytes()
    readme_raw = readme_path.read_bytes()
    manifest = json.loads(manifest_raw.decode('utf-8-sig'))
    layers = manifest.get('layers')
    if not isinstance(layers, list) or not layers:
        raise ValueError('manifest.layers must contain independent layers')
    bounds = manifest.get('ui_bounds', {})
    if bounds != {'left': 47, 'top': 54, 'width': 1380, 'height': 974}:
        raise ValueError('V10 UI bounds differ from the reviewed 1380x974 contract')
    csv_rows = list(csv.DictReader(io.StringIO(coordinates_raw.decode('utf-8-sig'))))
    coordinates = {row['id']: row for row in csv_rows}
    if len(csv_rows) != len(coordinates):
        raise ValueError('Duplicate IDs in component coordinates CSV')
    ids: set[str] = set()
    assets: dict[str, bytes] = {}
    records = []
    for layer in layers:
        layer_id = layer.get('id', '')
        if not isinstance(layer_id, str) or not re.fullmatch(r'[a-z][a-z0-9_]*', layer_id):
            raise ValueError(f'Unsafe or missing layer ID: {layer_id!r}')
        if layer_id in ids:
            raise ValueError(f'Duplicate manifest ID: {layer_id}')
        ids.add(layer_id)
        kind = layer.get('kind')
        if kind not in GRAPHIC_KINDS | EXCLUDED_KINDS:
            raise ValueError(f'Unknown layer kind is not whitelisted: {layer_id}: {kind}')
        if layer_id == 'game_context' and kind != 'game_context':
            raise ValueError('game_context must remain an excluded reference layer')
        expected_source_path = f'assets/{layer_id}.png'
        if layer.get('path') != expected_source_path:
            raise ValueError(f'Only independent assets/<id>.png files are allowed: {layer_id}')
        if PurePosixPath(expected_source_path).suffix != '.png':
            raise ValueError(f'Only PNG layers are imported: {layer_id}')
        if layer_id not in coordinates:
            raise ValueError(f'Manifest layer missing from CSV: {layer_id}')
        row = coordinates[layer_id]
        for field in CSV_TEXT_FIELDS:
            if row.get(field) != layer.get(field):
                raise ValueError(f'Manifest/CSV mismatch: {layer_id}.{field}')
        for field in CSV_INTEGER_FIELDS:
            value = integer(layer.get(field), field, layer_id)
            if int(row[field]) != value:
                raise ValueError(f'Manifest/CSV mismatch: {layer_id}.{field}')
        if layer['width'] <= 0 or layer['height'] <= 0:
            raise ValueError(f'Empty layer: {layer_id}')
        if kind != 'game_context':
            if (layer['left'] < bounds['left'] or layer['top'] < bounds['top']
                    or layer['left'] + layer['width'] > bounds['left'] + bounds['width']
                    or layer['top'] + layer['height'] > bounds['top'] + bounds['height']):
                raise ValueError(f'Layer is outside reviewed UI bounds: {layer_id}')
        raw = checked_child(source, expected_source_path).read_bytes()
        with Image.open(io.BytesIO(raw)) as image:
            if image.format != 'PNG' or image.size != (layer['width'], layer['height']):
                raise ValueError(f'PNG dimensions differ from manifest/CSV: {layer_id}')
            image.load()
            if kind in GRAPHIC_KINDS:
                if image.mode != 'RGBA':
                    raise ValueError(f'Reviewed graphic layer must retain RGBA: {layer_id}')
                alpha = image.getchannel('A')
                histogram = alpha.histogram()
                alpha_data = {
                    'mode': image.mode,
                    'minimum': alpha.getextrema()[0],
                    'maximum': alpha.getextrema()[1],
                    'transparent_pixels': histogram[0],
                    'translucent_pixels': sum(histogram[1:255]),
                    'opaque_pixels': histogram[255],
                    'center': alpha.getpixel((image.width // 2, image.height // 2)),
                }
                if layer_id == 'window_brush_edge' and alpha_data['center'] != 0:
                    raise ValueError('window_brush_edge must retain its transparent center')
                assets[layer_id] = raw
                records.append({
                    'id': layer_id,
                    'kind': kind,
                    'source_path': expected_source_path,
                    'destination': (ASSET_RELATIVE / f'{layer_id}.png').as_posix(),
                    'sha256': sha256(raw),
                    'recipe': (ASSET_RELATIVE / f'{layer_id}_v10.vtex').as_posix(),
                    'recipe_sha256': sha256(texture_recipe(layer_id)),
                    'runtime': f'panorama/images/custom_game/shop_v10_v1/{layer_id}_v10.vtex_c',
                    'runtime_uri': f's2r://panorama/images/custom_game/shop_v10_v1/{layer_id}_v10.vtex',
                    'bytes': len(raw),
                    'left': layer['left'],
                    'top': layer['top'],
                    'x': layer['left'] - bounds['left'],
                    'y': layer['top'] - bounds['top'],
                    'width': layer['width'],
                    'height': layer['height'],
                    'z': layer['z'],
                    'alpha': alpha_data,
                })
    if set(coordinates) != ids:
        raise ValueError('CSV and manifest contain different layer IDs')
    if 'window_brush_edge' not in assets:
        raise ValueError('Reviewed transparent window frame is missing')
    metadata = {
        'manifest_sha256': sha256(manifest_raw),
        'coordinates_sha256': sha256(coordinates_raw),
        'readme_sha256': sha256(readme_raw),
        'source_layer_count': len(layers),
        'source_kind_counts': dict(sorted(Counter(layer['kind'] for layer in layers).items())),
        'validated_png_count': len(layers),
    }
    return manifest, records, assets, metadata


def build_outputs(manifest: dict, records: list[dict], source_metadata: dict) -> tuple[bytes, bytes, dict]:
    bounds = manifest['ui_bounds']
    runtime_layers = {}
    for layer in manifest['layers']:
        if layer['kind'] == 'game_context':
            continue
        entry = {
            'x': layer['left'] - bounds['left'],
            'y': layer['top'] - bounds['top'],
            'width': layer['width'],
            'height': layer['height'],
            'z': layer['z'],
            'kind': layer['kind'],
        }
        if layer['kind'] in GRAPHIC_KINDS:
            entry['path'] = f's2r://panorama/images/custom_game/shop_v10_v1/{layer["id"]}_v10.vtex'
        else:
            # Reference copy only. The game binds live balances, prices and text.
            entry['text'] = layer.get('text', '')
        runtime_layers[layer['id']] = entry
    runtime = {
        'width': bounds['width'],
        'height': bounds['height'],
        'origin': {'left': bounds['left'], 'top': bounds['top']},
        'layers': runtime_layers,
    }
    module_raw = (
        '// Generated by tools/shop_v10_20261017/import_assets.py.\n'
        '// User-supplied V10 graphics; raster text is reference metadata only.\n'
        'GameUI.CustomUIConfig().SurvivalShopV10='
        + json.dumps(runtime, ensure_ascii=False, separators=(',', ':')) + ';\n'
    ).encode('utf-8')
    data = {
        'schema_version': 1,
        'package': 'shop_v10_layered',
        'source_description': manifest.get('source', '用户提供的最终商城V10分层素材'),
        'provenance': {
            'supplied_by': 'user',
            'import_authorization': '用户明确要求将其提供并确认的最终V10独立UI组件接入项目。',
            'license_note': '仅记录用户提供素材；本工具未引入外部素材或另行授予第三方许可。',
            **source_metadata,
        },
        'filter': {
            'included_kinds': sorted(GRAPHIC_KINDS),
            'excluded_kinds': sorted(EXCLUDED_KINDS),
            'graphic_layer_count': len(records),
            'raster_text_metadata_count': sum(layer['kind'] == 'raster_text' for layer in manifest['layers']),
            'excluded_game_context_count': sum(layer['kind'] == 'game_context' for layer in manifest['layers']),
            'excluded_files': ['reference/*', '*.psd', '*.html', 'composite previews', 'raster-text PNGs'],
            'png_transform': 'none; original PNG bytes copied without resizing, flattening, alpha conversion or re-encoding',
        },
        'width': runtime['width'],
        'height': runtime['height'],
        'origin': runtime['origin'],
        'texture_settings': {
            'format': 'BGRA8888',
            'no_lod': True,
            'mip_levels': 1,
            'dimension_scaling': 'none; original non-power-of-two width and height retained',
            'runtime_uri_mapping': 's2r://panorama/images/custom_game/shop_v10_v1/<id>_v10.vtex -> panorama/images/custom_game/shop_v10_v1/<id>_v10.vtex_c',
            'avoid_implicit_png_compilation': 'Explicit texture URIs prevent CSS/PNG weak references from regenerating default DXT5 textures.',
        },
        'assets': records,
        'layers': runtime_layers,
    }
    return module_raw, json_bytes(data), runtime


def run(source: Path, mode: str) -> dict:
    source = source.resolve(strict=True)
    manifest, records, assets, metadata = read_package(source)
    module_raw, data_raw, runtime = build_outputs(manifest, records, metadata)
    expected = {
        **{ASSET_RELATIVE / f'{layer_id}.png': raw for layer_id, raw in assets.items()},
        **{ASSET_RELATIVE / f'{layer_id}_v10.vtex': texture_recipe(layer_id) for layer_id in assets},
        MODULE_RELATIVE: module_raw,
        DATA_RELATIVE: data_raw,
    }
    asset_root = checked_child(ROOT, ASSET_RELATIVE)
    extras = sorted(path.name for path in asset_root.glob('*.png') if path.stem not in assets)
    if extras:
        raise ValueError(f'Unexpected existing files in scoped asset destination: {extras}')
    changed = []
    for relative, raw in expected.items():
        target = checked_child(ROOT, relative)
        if mode == 'apply':
            if write_if_changed(target, raw):
                changed.append(relative.as_posix())
        elif mode == 'check' and (not target.is_file() or target.read_bytes() != raw):
            raise ValueError(f'Generated file missing or different: {relative.as_posix()}')
    # Verify original byte identity after writing, independently of alpha metadata.
    if mode == 'apply':
        for relative, raw in expected.items():
            if checked_child(ROOT, relative).read_bytes() != raw:
                raise ValueError(f'Written bytes differ from source/generated data: {relative.as_posix()}')
    return {
        'at_utc': datetime.now(timezone.utc).isoformat(),
        'success': True,
        'mode': mode,
        'source_directory': str(source),
        **metadata,
        'graphic_layer_count': len(assets),
        'runtime_layer_count': len(runtime['layers']),
        'raster_text_metadata_count': sum(layer['kind'] == 'raster_text' for layer in runtime['layers'].values()),
        'copied_png_bytes': sum(map(len, assets.values())),
        'changed_files': changed,
        'module': {'path': MODULE_RELATIVE.as_posix(), 'sha256': sha256(module_raw)},
        'data': {'path': DATA_RELATIVE.as_posix(), 'sha256': sha256(data_raw)},
        'assets': records,
        'no_png_reencoding': True,
        'no_game_context_or_raster_text_pngs': True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--apply', action='store_true', help='Copy whitelisted PNG bytes and write the generated module/data')
    modes.add_argument('--check', action='store_true', help='Check every generated file without changing it')
    args = parser.parse_args()
    mode = 'apply' if args.apply else 'check' if args.check else 'plan'
    report_path = checked_child(ROOT, REPORT_RELATIVE)
    try:
        report = run(args.source, mode)
    except (OSError, ValueError, KeyError, TypeError) as error:
        report = {'at_utc': datetime.now(timezone.utc).isoformat(), 'success': False, 'mode': mode, 'error': str(error)}
        write_if_changed(report_path, json_bytes(report))
        print(f'SHOP_V10_ASSETS_FAILED: {error}', file=sys.stderr)
        return 1
    write_if_changed(report_path, json_bytes(report))
    print(f'SHOP_V10_ASSETS_{mode.upper()}_PASS: {report["graphic_layer_count"]} original RGBA PNGs; '
          f'{report["raster_text_metadata_count"]} text metadata layers; {report["runtime_layer_count"]} runtime layers; '
          f'{len(report["changed_files"])} changed files')
    print(f'MODULE_SHA256 {report["module"]["sha256"]}')
    print(f'DATA_SHA256 {report["data"]["sha256"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
