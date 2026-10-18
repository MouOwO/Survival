"""Compile exactly two ticket recipes and three shared Panorama scripts.

PNG masters remain byte-identical dependencies. Source2 alone builds GPU size
and mips; this tool neither imports Pillow nor crops, rescales or reencodes PNGs.
Without --apply it performs read-only source checks. Candidate sources may live
under output/.../panorama/src while Content/runtime retain their normal paths.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / 'content/dota_addons/Survival/panorama'
RUNTIME = ROOT / 'panorama'
WORK = ROOT / 'output/lottery_user_tickets_20261018'
IMAGES = 'images/custom_game/lottery_ticket_user_v1'
MASTERS = ROOT / 'art/ui/sources/custom_game/lottery_ticket_user_v1'
EXPECTED = {
    'normal': 'b7b9e059ad52bae51af4b5ca1a5924fb2089f3f0ea99510b10560a2045743d45',
    'special': '11c0551a0f0ef5dfe52fcd95388f45bf2d7cc9f876db0b5c01cf807c3082e10b',
}
SCRIPTS = (
    'scripts/custom_game/common/item_resources.js',
    'scripts/custom_game/lottery_gw2.js',
    'scripts/custom_game/lottery_handoff_bb9968eef7.js',
)


def need(value, message):
    if not value:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def child(root, relative):
    path = (root / relative).resolve()
    need(path.is_relative_to(root.resolve()) and path != root.resolve(), 'Path escaped intended root: ' + str(relative))
    return path


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def check_recipe(path, name):
    text = path.read_text(encoding='utf-8-sig')
    expected = 'panorama/' + IMAGES + '/' + name + '.png'
    inputs = re.findall(r'"m_fileName"\s+"string"\s+"([^"]+)"', text)
    need(inputs == [expected], 'Ticket recipe must reference only its original PNG: ' + name)
    for key, kind, value in (('m_outputFormat', 'string', 'BGRA8888'), ('m_outputTypeString', 'string', '2D'),
                             ('m_bNoLod', 'bool', '1')):
        need(re.search('"' + key + r'"\s+"' + kind + r'"\s+"' + value + '"', text), 'Unexpected recipe setting: ' + key)
    cap = re.findall(r'"m_nOutputMaxDimension"\s+"int"\s+"([0-9]+)"', text)
    need(len(cap) == 1, 'Ticket recipe needs one explicit native dimension cap')
    # No input processor can silently alter the original 3:2 composition.
    algorithms = re.findall(r'"m_algorithm"\s+"string"\s+"([^"]*)"', text)
    need(algorithms in (['Box'], ['']) and 'm_imageProcessorArray' not in text,
         'Only native Box mip filtering or the original NPOT/no-mip path is permitted')
    need(re.search(r'"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+"(?:Box)?"', text),
         'Explicit native mip setting is required')
    return int(cap[0]), algorithms[0]


def plan(source_root):
    compiler = ENGINE / 'game/bin/win64/resourcecompiler.exe'
    need(compiler.is_file(), 'Native Source2 resource compiler is missing')
    dependencies, inputs, builds = [], [], []
    for name, expected in EXPECTED.items():
        master = MASTERS / (name + '.png')
        png = child(source_root, IMAGES + '/' + name + '.png')
        recipe = child(source_root, IMAGES + '/' + name + '_png.vtex')
        need(digest(master) == expected and digest(png) == expected, 'Original PNG SHA mismatch: ' + name)
        raw = png.read_bytes()
        need(raw[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II', raw, 16) == (1536, 1024), 'Original PNG dimensions changed: ' + name)
        cap, mip_algorithm = check_recipe(recipe, name)
        relative = png.relative_to(source_root).as_posix()
        dependencies.append(dict(id=name, source=png, relative=relative, sha256=expected))
        inputs.append(dict(source=master, sha256=expected))
        relative = recipe.relative_to(source_root).as_posix()
        builds.append(dict(id=name, kind='texture', source=recipe, relative=relative, sha256=digest(recipe),
            runtime=relative + '_c', maximum_dimension=cap, mip_algorithm=mip_algorithm))
    for relative in SCRIPTS:
        source = child(source_root, relative)
        need(source.is_file(), 'Missing reviewed shared script: ' + relative)
        builds.append(dict(id=source.stem, kind='script', source=source, relative=relative,
            sha256=digest(source), runtime=relative.removesuffix('.js') + '.vjs_c'))
    inputs += dependencies + builds
    need(len(builds) == 5 and len(dependencies) == 2, 'Unexpected ticket compile scope')
    return compiler, dependencies, builds, inputs


def check_sources(inputs):
    for row in inputs:
        need(digest(row['source']) == row['sha256'], 'Reviewed input changed: ' + str(row['source']))


def native_info(path):
    # Reuse the existing resource parser; no image decoder/export is invoked.
    code = '''const fs=require('node:fs'),{textureInfo}=require(process.argv[1]);
const value=textureInfo(fs.readFileSync(process.argv[2]));
let expected=0;for(let n=0;n<value.mipLevels;n++)expected+=Math.max(1,value.width>>n)*Math.max(1,value.height>>n)*4;
let alphaMin=255,alphaMax=0,transparentTexels=0;
for(let n=3;n<value.payload.length;n+=4){const a=value.payload[n];alphaMin=Math.min(alphaMin,a);alphaMax=Math.max(alphaMax,a);if(a===0)transparentTexels++;}
process.stdout.write(JSON.stringify({...value,payload:undefined,payloadBytes:value.payload.length,expectedPayloadBytes:expected,
alphaMin,alphaMax,transparentTexels}));'''
    result = subprocess.run(['node', '-e', code, str(ROOT / 'tools/test_construction_grid_resources.cjs'), str(path)],
        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    need(result.returncode == 0, 'Cannot inspect compiled ticket texture: ' + result.stderr[:500])
    return json.loads(result.stdout)


def compile_assets(source_root, report_path, apply):
    compiler, dependencies, builds, inputs = plan(source_root)
    check_sources(inputs)
    if not apply:
        return dict(status='CHECK_ONLY', source_root=str(source_root), vtex_recipes=2, js_files=3,
            png_dependencies=2, source_pixels_modified=False, other_resources_compiled=0,
            source_hashes={str(row['source'].relative_to(ROOT)): row['sha256'] for row in inputs})
    work = WORK / ('compile_' + datetime.now().strftime('%Y%m%d_%H%M%S_%f') + '_' + uuid.uuid4().hex[:8])
    work.mkdir(parents=True)
    targets, by_target = [], {}
    def snapshot(root, relative, kind):
        path = child(root, relative);saved = work / 'before' / kind / relative
        previous = digest(path)
        if previous:
            saved.parent.mkdir(parents=True, exist_ok=True);shutil.copyfile(path, saved)
            need(digest(saved) == previous and digest(path) == previous, 'Concurrent write during backup')
        row = dict(path=str(path), relative=relative, kind=kind, before_sha256=previous,
            backup=str(saved), touched=False, owned_sha256=None)
        targets.append(row);by_target[str(path)] = row
    for row in dependencies + builds:snapshot(CONTENT, row['relative'], 'content')
    for row in builds:snapshot(RUNTIME, row['runtime'], 'runtime')
    write_json(work / 'before.json', dict(targets=targets, source_root=str(source_root)))
    records = []
    try:
        for row in dependencies + builds:
            check_sources(inputs)
            path = child(CONTENT, row['relative']);state = by_target[str(path)]
            need(digest(path) == state['before_sha256'], 'Concurrent Content write before compilation')
            path.parent.mkdir(parents=True, exist_ok=True);state['touched'] = True
            try:shutil.copyfile(row['source'], path)
            finally:state['owned_sha256'] = digest(path)
            need(digest(path) == row['sha256'], 'Copied source differs: ' + row['relative'])
        for row in builds:
            check_sources(inputs)
            artifact = child(RUNTIME, row['runtime']);state = by_target[str(artifact)]
            need(digest(artifact) == state['before_sha256'], 'Concurrent runtime write before compilation')
            started = time.time_ns();state['touched'] = True
            try:
                result = subprocess.run([str(compiler), '-i', str(child(CONTENT, row['relative'])),
                    '-game', str(ENGINE / 'game/dota'), '-fshallow', '-nop4'],
                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            finally:state['owned_sha256'] = digest(artifact)
            log = result.stdout + result.stderr;(work / (row['id'] + '.log')).write_text(log, encoding='utf-8')
            need(result.returncode == 0 and re.search(r'OK: [1-9][0-9]* compiled, 0 failed,', log), 'Native compile failed: ' + row['relative'])
            need(artifact.is_file() and artifact.stat().st_size > 0 and artifact.stat().st_mtime_ns >= started - 2_000_000_000,
                 'Missing or stale native output: ' + row['runtime'])
            record = {key: value for key, value in row.items() if key != 'source'}
            record.update(compiled_sha256=digest(artifact), compiled_bytes=artifact.stat().st_size)
            if row['kind'] == 'texture':
                info = native_info(artifact);record['native_info'] = info
                write_json(work / (row['id'] + '_native_info.json'), info)
                need(info['format'] == 28 and info['depth'] == 1 and info['flags'] & 8, 'Ticket texture is not BGRA8888/NO_LOD')
                need(abs(info['width'] * 2 - info['height'] * 3) <= 2,
                     'Native engine changed the original 3:2 ticket ratio: ' + json.dumps(info))
                cap = row['maximum_dimension']
                need(0 < info['width'] <= 1536 and 0 < info['height'] <= 1024,
                     'Native texture exceeds the unmodified original dimensions')
                record['dimension_cap_honored'] = cap == 0 or max(info['width'], info['height']) <= cap
                if row['mip_algorithm'] == 'Box':
                    need(record['dimension_cap_honored'], 'Native engine ignored the declared texture cap')
                    need(info['mipLevels'] == max(info['width'], info['height']).bit_length() and info['mipLevels'] > 1,
                         'Native engine did not generate the full ticket mip chain')
                else:
                    need(info['mipLevels'] == 1, 'Native NPOT/no-mip setting was not preserved')
                need(info['payloadBytes'] == info['expectedPayloadBytes'], 'Ticket mip payload is incomplete')
                need(info['alphaMin'] == 0 and info['alphaMax'] > 0 and info['transparentTexels'] > 0,
                     'Native ticket texture lost transparent alpha')
            compiled = child(work / 'compiled', row['runtime']);compiled.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(artifact, compiled);record['compiled_snapshot'] = str(compiled)
            need(digest(compiled) == record['compiled_sha256'], 'Compiled snapshot mismatch')
            records.append(record);print('LOTTERY_TICKET_COMPILED ' + row['relative'], flush=True)
        check_sources(inputs)
        for row in dependencies + builds:
            need(digest(child(CONTENT, row['relative'])) == row['sha256'], 'Final Content source drift')
        for record in records:
            need(digest(child(RUNTIME, record['runtime'])) == record['compiled_sha256'], 'Final runtime drift')
        report = dict(status='PASS', source_root=str(source_root), backup=str(work), records=records,
            vtex_recipes=2, js_files=3, png_dependencies_byte_identical=True,
            source_pixels_modified=False, original_aspect_preserved=True, other_resources_compiled=0)
        write_json(work / 'result.json', report);write_json(report_path, report)
        return report
    except Exception as error:
        recovery = []
        for state in reversed(targets):
            if not state['touched']:continue
            try:
                root = CONTENT if state['kind'] == 'content' else RUNTIME
                path = child(root, state['relative'])
                need(digest(path) == state['owned_sha256'], 'Concurrent write retained during recovery')
                if state['before_sha256']:
                    saved = Path(state['backup']);need(digest(saved) == state['before_sha256'], 'Backup digest mismatch')
                    shutil.copyfile(saved, path)
                elif path.is_file():path.unlink()
                need(digest(path) == state['before_sha256'], 'Recovery digest mismatch')
            except Exception as restore_error:recovery.append(str(restore_error))
        report = dict(status='FAILED', error=str(error), backup=str(work), records=records,
            rollback_errors=recovery, scoped_outputs_restored=not recovery, source_pixels_modified=False)
        write_json(work / 'failure.json', report);write_json(report_path, report)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path('panorama/src'))
    parser.add_argument('--report', type=Path, default=Path('output/lottery_user_tickets_20261018/compile.json'))
    choice = parser.add_mutually_exclusive_group()
    choice.add_argument('--apply', action='store_true')
    choice.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    source_root = child(ROOT, args.source_root) if not args.source_root.is_absolute() else args.source_root.resolve()
    report_path = child(ROOT, args.report) if not args.report.is_absolute() else args.report.resolve()
    need(source_root.is_relative_to(ROOT) and report_path.is_relative_to(ROOT), 'Keep source/report inside the workspace')
    print(json.dumps(compile_assets(source_root, report_path, args.apply), ensure_ascii=False, indent=2))
