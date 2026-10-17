"""Compile only wife_v1_01..40.vtex and the existing icon-catalog JS.

No PNG input is compiled directly. PNG bytes are copied as recipe dependencies;
resourcecompiler performs the 512px GPU texture conversion internally. --apply
is required for Content/runtime writes. Frozen gameplay/UI sources are checked
before and after the forty-one explicit compiler invocations.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

from import_assets import ROOT, WORK, MANIFEST, CATALOG, IDS, ART_STATUS, sha, write_json, checked_child, check_snapshot


def plan():
    freeze = json.loads((WORK / 'compile_freeze.json').read_text(encoding='utf-8'))
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert manifest['art_status'] == ART_STATUS and set(manifest['items']) == set(IDS)
    check_snapshot(freeze['source_hashes'])
    check_snapshot(freeze['protected'])
    engine = ROOT.parents[2]
    compiler = engine / 'game/bin/win64/resourcecompiler.exe'
    assert compiler.is_file(), 'Native resourcecompiler.exe is missing'
    content = engine / 'content/dota_addons/Survival/panorama'
    runtime = ROOT / 'panorama'
    dependencies, records = [], []
    for ident in IDS:
        asset = manifest['items'][ident]
        relative = 'images/' + asset['icon_path']
        image = ROOT / 'panorama/src' / relative
        assert sha(image) == asset['sha256'], ident
        dependencies.append({'relative': relative, 'source': image, 'content': checked_child(content, relative)})
        relative = str(Path(asset['recipe_path']).relative_to('panorama/src')).replace('\\', '/')
        source = ROOT / asset['recipe_path']
        records.append({'id': ident, 'relative': relative, 'source': source,
                        'content': checked_child(content, relative), 'runtime': checked_child(runtime, relative + '_c')})
    relative = str(CATALOG.relative_to(ROOT / 'panorama/src')).replace('\\', '/')
    records.append({'id': 'icon_catalog', 'relative': relative, 'source': CATALOG,
                    'content': checked_child(content, relative), 'runtime': checked_child(runtime, relative.removesuffix('.js') + '.vjs_c')})
    assert len(records) == 41 and len(dependencies) == 40
    assert len({str(row['runtime']) for row in records}) == 41
    return freeze, manifest, compiler, content, dependencies, records


def compile_assets(apply=False):
    frozen, manifest, compiler, content, dependencies, records = plan()
    if not apply:
        return {'status': 'CHECK_ONLY', 'native_compile_files': 41, 'vtex_recipes': 40, 'js_files': 1,
                'png_dependencies_copied_without_reencoding': 40, 'other_resources_compiled': 0,
                'protected_files': len(frozen['protected']), 'native_flags': ['-fshallow', '-nop4'],
                'manifest_sha256': sha(MANIFEST)}
    work = WORK / ('compile_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    work.mkdir(parents=True)
    targets = []
    for kind, root, paths in [('content', content, [row['content'] for row in dependencies + records]),
                              ('runtime', ROOT / 'panorama', [row['runtime'] for row in records])]:
        for path in paths:
            relative = str(path.relative_to(root)).replace('\\', '/')
            backup = work / 'before' / kind / relative
            record = {'kind': kind, 'path': str(path), 'relative': relative, 'backup': str(backup),
                      'existed': path.is_file(), 'sha256': sha(path) if path.is_file() else None}
            if record['existed']:
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, backup)
            targets.append(record)
    write_json(work / 'before.json', {'targets': targets, 'freeze_sha256': sha(WORK / 'compile_freeze.json')})
    compiled = []
    try:
        for row in dependencies + records:
            row['content'].parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(row['source'], row['content'])
            assert sha(row['source']) == sha(row['content']), row['relative']
        check_snapshot(frozen['source_hashes'])
        check_snapshot(frozen['protected'])
        for row in records:
            started = time.time_ns()
            result = subprocess.run([str(compiler), '-i', str(row['content']), '-game', str(ROOT.parents[1] / 'dota'), '-fshallow', '-nop4'],
                                    capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    creationflags=subprocess.CREATE_NO_WINDOW, timeout=180)
            log = result.stdout + result.stderr
            (work / (row['id'] + '.log')).write_text(log, encoding='utf-8')
            if result.returncode != 0 or '0 failed' not in log:
                raise RuntimeError(f'Native compile failed: {row["relative"]}; log={work / (row["id"] + ".log")}')
            artifact = row['runtime']
            assert artifact.is_file() and artifact.stat().st_size > 0, row['relative']
            assert artifact.stat().st_mtime_ns >= started - 2_000_000_000, f'Stale artifact: {artifact}'
            compiled.append({'id': row['id'], 'relative': row['relative'], 'source_sha256': sha(row['source']),
                             'compiled_sha256': sha(artifact), 'compiled_bytes': artifact.stat().st_size})
            print('WIFE_RESOURCE_COMPILE_PASS ' + row['relative'], flush=True)
        check_snapshot(frozen['source_hashes'])
        check_snapshot(frozen['protected'])
        for row in dependencies + records:
            assert sha(row['source']) == sha(row['content']), row['relative']
        validation = subprocess.run([r'C:\Program Files\nodejs\node.exe', str(ROOT / 'tools/wife_portraits_20261016/audit_compiled.cjs')],
                                    cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace',
                                    creationflags=subprocess.CREATE_NO_WINDOW, timeout=90)
        (work / 'native_texture_audit.json').write_text(validation.stdout, encoding='utf-8')
        if validation.returncode:
            raise RuntimeError('Native wife texture audit failed: ' + validation.stderr)
        report = {'status': 'PASS_WIFE_PORTRAITS_COMPILED', 'native_compile_files': 41, 'vtex_recipes': 40, 'js_files': 1,
                  'png_dependencies_byte_identical': True, 'source_pixels_modified': False, 'gameplay_unchanged': True,
                  'protected_files_unchanged': len(frozen['protected']), 'other_resources_compiled': 0,
                  'manifest_sha256': sha(MANIFEST), 'backup': str(work), 'records': compiled,
                  'native_texture_audit': json.loads(validation.stdout)}
        write_json(work / 'result.json', report)
        write_json(WORK / 'compile_result.json', report)
        return report
    except Exception as error:
        rollback_errors = []
        for record in targets:
            try:
                path = Path(record['path'])
                checked_child(content if record['kind'] == 'content' else ROOT / 'panorama', record['relative'])
                if record['existed']:
                    shutil.copyfile(record['backup'], path)
                    assert sha(path) == record['sha256']
                elif path.is_file():
                    path.unlink()
            except Exception as rollback_error:
                rollback_errors.append(str(rollback_error))
        write_json(work / 'failure.json', {'status': 'FAILED', 'error': str(error), 'rollback_errors': rollback_errors,
                                          'scoped_outputs_restored': not rollback_errors})
        raise


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    print(json.dumps(compile_assets(args.apply), ensure_ascii=False))
