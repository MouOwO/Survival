"""Compile only the reviewed V10 PNG recipes; verify native dimensions and alpha.

PNG files are byte-identical dependencies, never direct compiler inputs. The
matching <id>_v10.vtex_c names are loaded by explicit Panorama s2r:// URIs.
--apply writes scoped Content dependencies/runtime files with rollback backups;
without it, this tool only validates the selected source scope.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import time

from PIL import Image

from import_assets import ROOT, DATA_RELATIVE, checked_child, json_bytes, sha256, texture_recipe


WORK = ROOT / 'output/shop_v10_20261017'


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(json_bytes(data))


def texture_info(raw: bytes) -> dict:
    """Read Source 2 texture DATA and its uncompressed BGRA8888 payload."""
    if len(raw) < 16:
        raise ValueError('Compiled texture header is incomplete')
    payload_offset, table_offset, block_count = struct.unpack_from('<I4xII', raw)
    table = 8 + table_offset
    if not (table + block_count * 12 <= payload_offset <= len(raw)):
        raise ValueError('Invalid Source 2 block table bounds')
    data = None
    for index in range(block_count):
        at = table + index * 12
        relative, size = struct.unpack_from('<II', raw, at + 4)
        offset = at + 4 + relative
        if offset + size > payload_offset:
            raise ValueError('Invalid Source 2 resource block bounds')
        if raw[at:at + 4] == b'DATA':
            data = raw[offset:offset + size]
    if data is None or len(data) < 28 or struct.unpack_from('<H', data)[0] != 1:
        raise ValueError('Missing or unsupported texture DATA header')
    flags = struct.unpack_from('<H', data, 2)[0]
    width, height, depth = struct.unpack_from('<HHH', data, 20)
    return {'flags': flags, 'width': width, 'height': height, 'depth': depth,
            'format': data[26], 'mip_levels': data[27], 'payload': raw[payload_offset:]}


def native_audit(record: dict) -> dict:
    png = checked_child(ROOT, record['destination']).read_bytes()
    raw = checked_child(ROOT, record['runtime']).read_bytes()
    info = texture_info(raw)
    expected = (record['width'], record['height'], 1, 28, 1)
    actual = tuple(info[key] for key in ('width', 'height', 'depth', 'format', 'mip_levels'))
    if actual != expected or info['flags'] & 8 != 8:
        raise ValueError(f'{record["id"]}: native dimensions/format/NO_LOD mismatch: {actual}, flags={info["flags"]}')
    payload = info.pop('payload')
    with Image.open(io.BytesIO(png)) as image:
        image.load()
        expected_pixels = image.tobytes('raw', 'BGRA')
        alpha = image.getchannel('A').tobytes()
    if len(payload) != record['width'] * record['height'] * 4:
        raise ValueError(f'{record["id"]}: incomplete BGRA8888 native payload')
    native_alpha = payload[3::4]
    if native_alpha != alpha:
        raise ValueError(f'{record["id"]}: native alpha differs from original PNG')
    if payload != expected_pixels:
        offset = next(index for index, pair in enumerate(zip(payload, expected_pixels)) if pair[0] != pair[1])
        raise ValueError(f'{record["id"]}: native BGRA pixels differ from source at byte {offset}')
    return {
        'id': record['id'], **info, 'format_name': 'BGRA8888',
        'runtime': record['runtime'], 'runtime_sha256': sha256(raw), 'runtime_bytes': len(raw),
        'payload_bytes': len(payload), 'source_png_sha256': sha256(png),
        'native_pixels_exact': True, 'native_alpha_exact': True,
        'transparent_texels': native_alpha.count(0),
        'center_alpha': native_alpha[(record['height'] // 2) * record['width'] + record['width'] // 2],
    }


def scoped_plan(ids: list[str] | None) -> tuple[Path, Path, list[dict]]:
    manifest = json.loads(checked_child(ROOT, DATA_RELATIVE).read_text(encoding='utf-8'))
    assets = manifest['assets']
    if len({asset['id'] for asset in assets}) != len(assets):
        raise ValueError('Duplicate reviewed graphic IDs')
    if ids:
        if len(set(ids)) != len(ids) or set(ids) - {asset['id'] for asset in assets}:
            raise ValueError('Choose distinct, reviewed V10 graphic IDs only')
        assets = [asset for asset in assets if asset['id'] in ids]
    engine = ROOT.parents[2]
    content = engine / 'content/dota_addons/Survival/panorama'
    compiler = engine / 'game/bin/win64/resourcecompiler.exe'
    if not compiler.is_file():
        raise ValueError('Native texture compiler is missing')
    for asset in assets:
        png = checked_child(ROOT, asset['destination']).read_bytes()
        recipe = checked_child(ROOT, asset['recipe']).read_bytes()
        if sha256(png) != asset['sha256'] or sha256(recipe) != asset['recipe_sha256']:
            raise ValueError(f'Original PNG or generated recipe changed: {asset["id"]}')
        if recipe != texture_recipe(asset['id']):
            raise ValueError(f'Unexpected recipe input/settings: {asset["id"]}')
        expected_runtime = f'panorama/images/custom_game/shop_v10_v1/{asset["id"]}_v10.vtex_c'
        if asset['runtime'] != expected_runtime:
            raise ValueError(f'Panorama texture runtime mapping differs: {asset["id"]}')
        expected_uri = f's2r://panorama/images/custom_game/shop_v10_v1/{asset["id"]}_v10.vtex'
        if asset['runtime_uri'] != expected_uri:
            raise ValueError(f'Explicit Panorama texture URI differs: {asset["id"]}')
    return compiler, content, assets


def compile_assets(apply: bool, ids: list[str] | None) -> dict:
    compiler, content, assets = scoped_plan(ids)
    if not apply:
        return {'success': True, 'mode': 'check', 'texture_count': len(assets),
                'other_resources_compiled': 0, 'ids': [asset['id'] for asset in assets]}
    run_dir = WORK / ('texture_compile_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    run_dir.mkdir(parents=True)
    targets, copied = [], []
    for asset in assets:
        for kind, repo_relative in [('png', asset['destination']), ('recipe', asset['recipe'])]:
            relative = Path(repo_relative).relative_to('panorama/src')
            source = checked_child(ROOT, repo_relative)
            target = checked_child(content, relative)
            copied.append((source, target))
            targets.append({'kind': kind, 'path': target, 'relative': relative})
        runtime_relative = Path(asset['runtime']).relative_to('panorama')
        targets.append({'kind': 'runtime', 'path': checked_child(ROOT / 'panorama', runtime_relative), 'relative': runtime_relative})
    for record in targets:
        path = record['path']
        record['existed'] = path.is_file()
        record['backup'] = run_dir / 'before' / record['kind'] / record['relative']
        record['sha256'] = sha256(path.read_bytes()) if record['existed'] else None
        if record['existed']:
            record['backup'].parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, record['backup'])
    write_json(run_dir / 'before.json', {'targets': [{key: str(value) if isinstance(value, Path) else value for key, value in record.items()} for record in targets]})
    audits = []
    try:
        for source, target in copied:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            if source.read_bytes() != target.read_bytes():
                raise ValueError(f'Copied input differs: {source.name}')
        for asset in assets:
            recipe_relative = Path(asset['recipe']).relative_to('panorama/src')
            recipe = checked_child(content, recipe_relative)
            started = time.time_ns()
            result = subprocess.run(
                [str(compiler), '-i', str(recipe), '-game', str(ROOT.parents[1] / 'dota'), '-fshallow', '-nop4'],
                capture_output=True, text=True, encoding='utf-8', errors='replace',
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=180,
            )
            log = result.stdout + result.stderr
            log_path = run_dir / (asset['id'] + '.log')
            log_path.write_text(log, encoding='utf-8')
            if result.returncode or '0 failed' not in log:
                raise RuntimeError(f'Native texture compile failed: {asset["id"]}; log={log_path}')
            runtime = checked_child(ROOT, asset['runtime'])
            if not runtime.is_file() or runtime.stat().st_mtime_ns < started - 2_000_000_000:
                raise ValueError(f'Native texture is missing or stale: {asset["id"]}')
            audits.append(native_audit(asset))
            print('SHOP_V10_TEXTURE_PASS ' + asset['id'] + f' {asset["width"]}x{asset["height"]} BGRA8888 exact_alpha exact_pixels', flush=True)
        # Source PNGs and recipes must remain byte-identical after compilation.
        scoped_plan(ids)
        for source, target in copied:
            if source.read_bytes() != target.read_bytes():
                raise ValueError(f'Input drift during native compile: {source.name}')
        report = {'success': True, 'at_utc': datetime.now(timezone.utc).isoformat(),
                  'texture_count': len(audits), 'other_resources_compiled': 0,
                  'backup': str(run_dir), 'png_bytes_unchanged': True,
                  'dimensions_preserved': True, 'native_pixels_exact': True,
                  'native_alpha_exact': True, 'records': audits}
        write_json(run_dir / 'result.json', report)
        write_json(WORK / ('assets_compile.json' if not ids else 'assets_compile_probe.json'), report)
        return report
    except Exception as error:
        rollback_errors = []
        for record in reversed(targets):
            try:
                path = record['path']
                if record['kind'] == 'runtime':
                    checked_child(ROOT / 'panorama', record['relative'])
                else:
                    checked_child(content, record['relative'])
                if record['existed']:
                    shutil.copyfile(record['backup'], path)
                elif path.is_file():
                    path.unlink()
            except Exception as rollback_error:
                rollback_errors.append(str(rollback_error))
        write_json(run_dir / 'failure.json', {'success': False, 'error': str(error), 'rollback_errors': rollback_errors})
        raise


def audit_assets(ids: list[str] | None) -> dict:
    _, _, assets = scoped_plan(ids)
    records, failures = [], []
    for asset in assets:
        try:
            records.append(native_audit(asset))
        except (OSError, ValueError) as error:
            failures.append({'id': asset['id'], 'error': str(error)})
    report = {'success': not failures, 'at_utc': datetime.now(timezone.utc).isoformat(),
              'mode': 'audit_only', 'texture_count': len(assets), 'passed_count': len(records),
              'other_resources_compiled': 0, 'records': records, 'failures': failures}
    write_json(WORK / 'assets_audit.json', report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--apply', action='store_true')
    modes.add_argument('--audit-only', '--check-native', dest='audit_only', action='store_true',
                       help='Read every existing native texture and compare all dimensions, pixels and alpha without compiling')
    parser.add_argument('--ids', nargs='+', help='Optional reviewed graphic IDs for a focused first compile')
    args = parser.parse_args()
    report = audit_assets(args.ids) if args.audit_only else compile_assets(args.apply, args.ids)
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, ensure_ascii=False))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
