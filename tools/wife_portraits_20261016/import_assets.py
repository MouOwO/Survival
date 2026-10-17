"""Import exactly forty reviewed wife portraits without touching gameplay data.

Default is read-only. --apply freezes and backs up the existing scoped files,
copies original PNG bytes, then patches only wife CSV/catalog records. Generated
masters are never resized or otherwise edited by this tool.
"""
from __future__ import annotations

import argparse
import copy
import csv
from datetime import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'output/wife_portraits_20261016'
MANIFEST = ROOT / 'data/ui/wife_portraits_v1.json'
ICON_CSV = ROOT / 'data/csv/存档系统/archive_item_icons.csv'
CATALOG = ROOT / 'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js'
ART_STATUS = 'generated_wife_portrait_v1'
IDS = tuple(f'wife_{index:02}' for index in range(1, 41))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def checked_child(root, relative):
    root = Path(root).resolve()
    target = root / relative
    if not target.resolve().is_relative_to(root):
        raise ValueError(f'Path escapes expected root: {relative}')
    cursor = target
    while cursor != root:
        if cursor.is_symlink() or (cursor.exists() and os.path.isjunction(cursor)):
            raise ValueError(f'Unexpected linked destination: {target}')
        cursor = cursor.parent
    return target


def csv_rows(path):
    return list(csv.DictReader(io.StringIO(Path(path).read_text(encoding='utf-8-sig'))))


def catalog_objects(text):
    """Return exact JSON object spans so unrelated objects remain byte-identical."""
    marker = text.index('entries=') + len('entries=')
    start = text.index('[', marker)
    decoder, offset, result = json.JSONDecoder(), start + 1, []
    while True:
        while text[offset].isspace() or text[offset] == ',':
            offset += 1
        if text[offset] == ']':
            return start, offset + 1, result
        value, length = decoder.raw_decode(text[offset:])
        if not isinstance(value, dict):
            raise ValueError('Every icon catalog entry must be an object')
        result.append((offset, offset + length, value))
        offset += length


def patch_catalog(text, replacements):
    _, _, objects = catalog_objects(text)
    found, changes = set(), []
    for start, end, entry in objects:
        ident = entry.get('item_id')
        if entry.get('category_id') == 'wife':
            if ident not in replacements or ident in found:
                raise ValueError(f'Unexpected or duplicate wife catalog entry: {ident}')
            found.add(ident)
            changes.append((start, end, json.dumps(replacements[ident], ensure_ascii=False, separators=(',', ':'))))
    if found != set(IDS):
        raise ValueError('The current catalog must contain exactly wife_01..wife_40')
    for start, end, replacement in reversed(changes):
        text = text[:start] + replacement + text[end:]
    return text


def patch_icon_csv(raw, replacements):
    """Preserve every existing non-wife physical CSV line verbatim."""
    lines = raw.splitlines(keepends=True)
    header = next(csv.reader([lines[0].decode('utf-8-sig').rstrip('\r\n')]))
    found, result = set(), []
    for line in lines:
        values = next(csv.reader([line.decode('utf-8-sig').rstrip('\r\n')]))
        row = dict(zip(header, values))
        if row.get('category_id') != 'wife':
            result.append(line)
            continue
        ident = row.get('item_id')
        if ident not in replacements or ident in found:
            raise ValueError(f'Unexpected or duplicate wife CSV mapping: {ident}')
        found.add(ident)
        updated = dict(row)
        updated.update({key: value for key, value in replacements[ident].items() if key in header})
        stream = io.StringIO(newline='')
        ending = '\r\n' if line.endswith(b'\r\n') else '\n' if line.endswith(b'\n') else ''
        csv.DictWriter(stream, fieldnames=header, lineterminator=ending).writerow(updated)
        result.append(stream.getvalue().encode('utf-8'))
    if found != set(IDS):
        raise ValueError('The current CSV must contain exactly wife_01..wife_40')
    return b''.join(result)


def new_catalog_entry(existing, asset):
    entry = copy.deepcopy(existing)
    for key in ('icon_path', 'runtime_uri', 'source_width', 'source_height', 'sha256'):
        entry[key] = asset[key]
    entry.update(art_status=ART_STATUS, small_runtime_uri=asset['runtime_uri'], alpha_bounds=asset['alpha_bounds'])
    entry.pop('reused_from', None)
    return entry


def recipe(icon_path):
    template = (ROOT / 'panorama/src/images/custom_game/archive_gpu_regular/head_v5_ex_27.vtex').read_text(encoding='utf-8')
    return template.replace('panorama/images/custom_game/archive_portraits_v3/ex_27.png', 'panorama/images/' + icon_path)


def receipt_records(require_all=True):
    result = {}
    for path in sorted(WORK.glob('receipts_*.json')):
        payload = json.loads(path.read_text(encoding='utf-8'))
        entries = payload if isinstance(payload, list) else payload.get('entries', payload.get('receipts', payload.get('items', [])))
        for row in entries:
            ident = row.get('id') or f"wife_{int(row['index']):02}"
            result[ident] = (row, path)
    # Individually reviewed replacements override an earlier batch receipt.
    for path in sorted(WORK.glob('receipt_wife_*.json')):
        row = json.loads(path.read_text(encoding='utf-8'))
        ident = row.get('id') or path.stem.removeprefix('receipt_')
        result[ident] = (row, path)
    if set(result) - set(IDS):
        raise ValueError('Unknown portrait receipt IDs: ' + ','.join(sorted(set(result) - set(IDS))))
    if require_all and set(result) != set(IDS):
        raise ValueError('Forty reviewed receipts are required; missing=' + ','.join(sorted(set(IDS) - set(result))))
    return result


def audit_receipts():
    """Read-only partial inventory while the independent generators finish."""
    records, problems = [], []
    receipts = receipt_records(require_all=False)
    for ident, (receipt, file) in sorted(receipts.items()):
        original = receipt.get('source_path') or receipt.get('source') or receipt.get('original_file')
        if original and not Path(original).is_absolute():
            original = ROOT / original
        target = ROOT / f'panorama/src/images/custom_game/wife_portraits_v1/{ident}.png'
        exists = bool(original) and Path(original).is_file()
        record = {'id': ident, 'receipt': str(file.relative_to(ROOT)).replace('\\','/'),
                  'source_exists': exists, 'target_exists': target.is_file(),
                  'prompt': bool(receipt.get('prompt')), 'review': bool(receipt.get('review') or receipt.get('verified'))}
        if exists:
            record['source_sha256'] = sha(original)
            record['target_identical'] = target.is_file() and sha(target) == record['source_sha256']
        if not exists or not record['prompt'] or not record['review'] or not record.get('target_identical'):
            problems.append(ident)
        records.append(record)
    return {'status': 'PARTIAL_RECEIPT_AUDIT', 'read_only': True, 'receipts': len(records),
            'missing': sorted(set(IDS) - set(receipts)), 'problems': problems, 'records': records}


def build_manifest():
    source = json.loads((ROOT / 'data/reference/wife_tooltips_20261016.json').read_text(encoding='utf-8'))
    identities = json.loads((WORK / 'identity_audit.json').read_text(encoding='utf-8'))
    canonical = {row['id']: row for row in identities['items']}
    old = json.loads((ROOT / 'data/ui/archive_portraits_v3.json').read_text(encoding='utf-8'))
    old_hashes = {row['sha256'] for row in old.values()}
    receipts = receipt_records()
    assets, used_hashes = {}, set()
    for item in source['items']:
        ident = f"wife_{item['index']:02}"
        receipt, receipt_file = receipts[ident]
        original = receipt.get('source_path') or receipt.get('source') or receipt.get('original_file')
        if ident == 'wife_19':
            # This is the one already correctly named and generated Inori master.
            original = str(ROOT / 'panorama/src/images' / old['ex_27']['icon_path'])
        if not original or not Path(original).is_file():
            raise ValueError(f'Missing generated original for {ident}: {original}')
        original = Path(original).resolve()
        checksum = sha(original)
        if checksum in used_hashes:
            raise ValueError(f'Duplicate character portrait bytes: {ident}')
        used_hashes.add(checksum)
        if ident == 'wife_19':
            if checksum != old['ex_27']['sha256'] or 'Inori' not in old['ex_27']['prompt']:
                raise ValueError('wife_19 reuse must be the existing verified ex_27 Inori portrait')
            prompt, method = old['ex_27']['prompt'], 'reused_correct_character'
        else:
            if checksum in old_hashes:
                raise ValueError(f'{ident} must have a newly generated correct-character portrait')
            prompt, method = receipt.get('prompt', ''), 'new_generation'
            if not prompt or not receipt.get('output_hint'):
                raise ValueError(f'Missing built-in generation prompt or receipt: {ident}')
            if not receipt.get('review') and not receipt.get('verified'):
                raise ValueError(f'Missing character identity review: {ident}')
        with Image.open(original) as image:
            if image.format != 'PNG' or image.mode != 'RGBA' or image.width != image.height or image.width < 512:
                raise ValueError(f'Expected unmodified square RGBA PNG master >=512px: {ident}')
            alpha = image.getchannel('A')
            if alpha.getextrema()[0] != 0 or alpha.getextrema()[1] < 250:
                raise ValueError(f'Portrait lacks genuine transparent alpha/opaque subject: {ident}')
            bounds = alpha.point(lambda value: 255 if value > 16 else 0).getbbox()
            dimensions = (image.width, image.height)
        path = f'custom_game/wife_portraits_v1/{ident}.png'
        assets[ident] = {
            'id': ident, 'display_name': item['name'], 'canonical_name': canonical[ident]['canonical_name'],
            'series': canonical[ident]['franchise'], 'latin_name': canonical[ident]['latin_name'],
            'icon_path': path, 'runtime_uri': f's2r://panorama/images/custom_game/archive_gpu_regular/wife_v1_{item["index"]:02}.vtex',
            'recipe_path': f'panorama/src/images/custom_game/archive_gpu_regular/wife_v1_{item["index"]:02}.vtex',
            'source_width': dimensions[0], 'source_height': dimensions[1], 'alpha_bounds': bounds,
            'sha256': checksum, 'prompt': prompt, 'generator': 'built-in image_gen',
            'generation_kind': method, 'reused_from': 'ex_27' if ident == 'wife_19' else None,
            'original_file': str(original), 'receipt_file': str(receipt_file.relative_to(ROOT)).replace('\\', '/'),
            'receipt_sha256': sha(receipt_file), 'built_in_receipt': receipt,
        }
    return {'version': 1, 'art_status': ART_STATUS, 'items': assets,
            'gpu': {'format': 'BGRA8888', 'maximum_dimension': 512, 'mips': 1, 'no_lod': True, 'source_pixels_modified': False}}


def protected_paths():
    paths = set()
    # Freeze all authoritative game configuration, including the old bundle list.
    for directory, pattern in (('data/csv', '*.csv'), ('scripts/vscripts/config/generated', '*.lua')):
        paths.update(path for path in (ROOT / directory).rglob(pattern) if path != ICON_CSV)
    for directory in ('panorama/src/scripts', 'panorama/src/styles', 'panorama/src/layout',
                      'panorama/scripts', 'panorama/styles', 'panorama/layout'):
        paths.update(path for path in (ROOT / directory).rglob('*') if path.is_file() and
                     path != CATALOG and path != ROOT / 'panorama/scripts/custom_game/icons_remaining_5d5c1152eb.vjs_c')
    paths.add(ROOT / 'data/ui/archive_portraits_v3.json')
    for path in (ROOT / 'server/bundles').glob('*/bundle.json'):
        paths.add(path)
    for directory in ('panorama/src/images/custom_game/archive_portraits_v3',
                      'panorama/images/custom_game/archive_portraits_v3'):
        paths.update(path for path in (ROOT / directory).rglob('*') if path.is_file())
    for directory in ('panorama/src/images/custom_game/archive_gpu_regular',
                      'panorama/images/custom_game/archive_gpu_regular'):
        paths.update(path for path in (ROOT / directory).glob('head_v5_*') if path.is_file())
    return sorted(path for path in paths if path.is_file())


def snapshot(paths):
    return {str(path.relative_to(ROOT)).replace('\\', '/'): sha(path) for path in paths}


def check_snapshot(before):
    changed = [relative for relative, value in before.items() if not (ROOT / relative).is_file() or sha(ROOT / relative) != value]
    if changed:
        raise ValueError('Protected/concurrent files changed: ' + ', '.join(changed))


def verify_unrelated(before_csv, before_catalog, after_csv, after_catalog):
    def nonwife_csv(raw):
        lines = raw.splitlines(keepends=True)
        header = next(csv.reader([lines[0].decode('utf-8-sig').rstrip('\r\n')]))
        return b''.join(line for line in lines if dict(zip(header, next(csv.reader([line.decode('utf-8-sig').rstrip('\r\n')])))).get('category_id') != 'wife')
    if nonwife_csv(before_csv) != nonwife_csv(after_csv):
        raise ValueError('A non-wife CSV byte changed')
    def nonwife_catalog(text):
        _, _, objects = catalog_objects(text)
        return [(row['item_id'], text[start:end]) for start, end, row in objects if row.get('category_id') != 'wife']
    if nonwife_catalog(before_catalog) != nonwife_catalog(after_catalog):
        raise ValueError('A non-wife catalog object byte changed')
    old_start, old_end, _ = catalog_objects(before_catalog)
    new_start, new_end, _ = catalog_objects(after_catalog)
    if before_catalog[:old_start] != after_catalog[:new_start] or before_catalog[old_end:] != after_catalog[new_end:]:
        raise ValueError('The catalog controller changed')


def apply(manifest, check_only=True):
    assets = manifest['items']
    before_csv, before_catalog = ICON_CSV.read_bytes(), CATALOG.read_text(encoding='utf-8')
    existing = {row['item_id']: row for _, _, row in catalog_objects(before_catalog)[2] if row.get('category_id') == 'wife'}
    replacements = {ident: new_catalog_entry(existing[ident], asset) for ident, asset in assets.items()}
    after_csv = patch_icon_csv(before_csv, {ident: {'icon_path': asset['icon_path'], 'art_status': ART_STATUS} for ident, asset in assets.items()})
    after_catalog = patch_catalog(before_catalog, replacements)
    verify_unrelated(before_csv, before_catalog, after_csv, after_catalog)
    protected = snapshot(protected_paths())
    targets = [MANIFEST, ICON_CSV, CATALOG]
    for ident, asset in assets.items():
        targets.extend((checked_child(ROOT, 'panorama/src/images/' + asset['icon_path']), checked_child(ROOT, asset['recipe_path'])))
    if check_only:
        return {'status': 'CHECK_ONLY', 'items': 40, 'newly_generated': 39, 'correct_character_reused': ['wife_19'],
                'protected_files': len(protected), 'targets': len(targets), 'compile_scope': '40 VTEX recipes + icon catalog JS only'}
    backup = WORK / ('import_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    backup.mkdir(parents=True)
    records = []
    for path in targets:
        relative = str(path.relative_to(ROOT)).replace('\\', '/')
        existed = path.exists()
        record = {'relative': relative, 'existed': existed, 'before_sha256': sha(path) if existed else None}
        if existed:
            saved = backup / 'before' / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, saved)
        records.append(record)
    write_json(backup / 'before.json', {'protected': protected, 'targets': records})
    try:
        check_snapshot(protected)
        if ICON_CSV.read_bytes() != before_csv or CATALOG.read_text(encoding='utf-8') != before_catalog:
            raise ValueError('Scoped CSV/catalog changed concurrently before import')
        for asset in assets.values():
            image = ROOT / 'panorama/src/images' / asset['icon_path']
            image.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(asset['original_file'], image)
            if sha(image) != asset['sha256']:
                raise ValueError('Original PNG bytes changed during copy')
            vtex = ROOT / asset['recipe_path']
            vtex.parent.mkdir(parents=True, exist_ok=True)
            vtex.write_text(recipe(asset['icon_path']), encoding='utf-8', newline='')
        write_json(MANIFEST, manifest)
        ICON_CSV.write_bytes(after_csv)
        CATALOG.write_text(after_catalog, encoding='utf-8', newline='')
        verify_unrelated(before_csv, before_catalog, ICON_CSV.read_bytes(), CATALOG.read_text(encoding='utf-8'))
        check_snapshot(protected)
        source_files = [MANIFEST, ICON_CSV, CATALOG] + [ROOT / asset['recipe_path'] for asset in assets.values()] + [ROOT / 'panorama/src/images' / asset['icon_path'] for asset in assets.values()]
        frozen = {'version': 1, 'manifest_sha256': sha(MANIFEST), 'source_hashes': snapshot(source_files), 'protected': protected,
                  'import_backup': str(backup.relative_to(ROOT)).replace('\\', '/'), 'targets': records}
        write_json(WORK / 'compile_freeze.json', frozen)
        report = {'status': 'IMPORTED', 'items': 40, 'newly_generated': 39, 'correct_character_reused': ['wife_19'],
                  'protected_files_unchanged': len(protected), 'unrelated_catalog_objects_byte_identical': True,
                  'gameplay_unchanged': True, 'backup': str(backup), 'manifest_sha256': sha(MANIFEST)}
        write_json(backup / 'result.json', report)
        return report
    except Exception:
        # Restore only this operation's explicitly scoped targets; never reset Git.
        for record in records:
            path = checked_child(ROOT, record['relative'])
            if record['existed']:
                shutil.copyfile(backup / 'before' / record['relative'], path)
            elif path.is_file():
                path.unlink()
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true', help='Perform the scoped import; otherwise check only')
    parser.add_argument('--check-receipts', action='store_true', help='Read-only partial receipt inventory; allows generators to be unfinished')
    args = parser.parse_args()
    if args.check_receipts:
        if args.apply:
            parser.error('--check-receipts is read-only and cannot use --apply')
        print(json.dumps(audit_receipts(), ensure_ascii=False))
        return
    print(json.dumps(apply(build_manifest(), not args.apply), ensure_ascii=False))


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
