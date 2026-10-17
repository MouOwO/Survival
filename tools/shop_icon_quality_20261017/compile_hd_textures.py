"""Compile reviewed high-resolution originals and decode exact runtime pixels.

No PNG is resized or edited here. Source2 performs its authored texture build;
the preview PNG is only a format conversion of the compiled BGRA8888 payload.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT.parents[2]
CONTENT = ENGINE / 'content/dota_addons/Survival/panorama'
WORK = ROOT / 'output/shop_icon_quality_20261017/native_compiled'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def child(base, relative):
    path = (base / relative).resolve()
    if not path.is_relative_to(base.resolve()):
        raise ValueError(f'Path escaped intended directory: {relative}')
    return path


def texture(raw):
    payload, table_relative, count = struct.unpack_from('<I4xII', raw)
    table = 8 + table_relative
    for index in range(count):
        at = table + index * 12
        if raw[at:at + 4] != b'DATA':
            continue
        relative, size = struct.unpack_from('<II', raw, at + 4)
        data = raw[at + 4 + relative:at + 4 + relative + size]
        flags = struct.unpack_from('<H', data, 2)[0]
        width, height, depth = struct.unpack_from('<HHH', data, 20)
        return dict(width=width, height=height, depth=depth,
                    format=data[26], mipLevels=data[27], noLod=bool(flags & 8)), raw[payload:]
    raise ValueError('Compiled texture has no DATA block')


def run(apply):
    plan = json.loads((ROOT / 'output/shop_icon_quality_20261017/texture_plan.json').read_text(encoding='utf-8-sig'))
    selected = []
    for entry in plan['textures']:
        png, recipe = child(ROOT, entry['sourcePng']), child(ROOT, entry['recipe'])
        if digest(png) != entry['sourcePngSha256'] or digest(recipe) != entry['recipeSha256']:
            raise ValueError(f'Reviewed texture source changed: {entry["id"]}')
        recipe_text = recipe.read_text(encoding='utf-8')
        if str(Path(entry['sourcePng']).relative_to('panorama/src')).replace('\\', '/') not in recipe_text:
            # Input names are relative to addon Content, including panorama/.
            expected = entry['sourcePng'].replace('panorama/src/', 'panorama/')
            if expected not in recipe_text:
                raise ValueError(f'Unexpected recipe input: {entry["id"]}')
        selected.append((entry, png, recipe))
    if not apply:
        print(f'HD_TEXTURE_SCOPE_PASS {len(selected)} reviewed PNG/recipe pairs')
        return
    WORK.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')
    backup = WORK / ('backup_' + stamp)
    compiler = ENGINE / 'game/bin/win64/resourcecompiler.exe'
    records, restores = [], []
    try:
        for entry, png, recipe in selected:
            content_png = child(CONTENT, png.relative_to(ROOT / 'panorama/src'))
            content_recipe = child(CONTENT, recipe.relative_to(ROOT / 'panorama/src'))
            runtime = child(ROOT, entry['runtime'])
            for destination in (content_png, content_recipe, runtime):
                prior = backup / str(len(restores))
                if destination.exists():
                    prior.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(destination, prior)
                    restores.append((destination, prior))
            for source, destination in ((png, content_png), (recipe, content_recipe)):
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
            result = subprocess.run([str(compiler), '-i', str(content_recipe), '-game', str(ENGINE / 'game/dota'), '-fshallow', '-nop4'],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            log = result.stdout.decode('utf-8', errors='replace')
            (WORK / (entry['id'] + '.log')).write_text(log, encoding='utf-8')
            if result.returncode or '0 failed' not in log:
                raise ValueError(f'Native texture compile failed: {entry["id"]}')
            info, pixels = texture(runtime.read_bytes())
            if (info['format'] != entry['expectedFormat'] or info['mipLevels'] != entry['expectedMipLevels']
                    or not info['noLod'] or min(info['width'], info['height']) < entry['expectedMinimumDimension']
                    or info['depth'] != 1 or len(pixels) != info['width'] * info['height'] * 4):
                raise ValueError(f'Native texture quality mismatch: {entry["id"]}: {info}')
            if digest(png) != entry['sourcePngSha256'] or digest(recipe) != entry['recipeSha256']:
                raise ValueError(f'Texture source drift during build: {entry["id"]}')
            preview = WORK / (entry['id'] + '.png')
            Image.frombytes('RGBA', (info['width'], info['height']), pixels, 'raw', 'BGRA').save(preview)
            records.append({**entry, **info, 'formatName': 'BGRA8888', 'runtimeSha256': digest(runtime),
                            'previewPng': preview.relative_to(ROOT).as_posix(), 'previewPngSha256': digest(preview),
                            'pixelConversion': 'Exact compiled BGRA8888 payload to PNG; no resizing or filtering'})
            print(f'HD_TEXTURE_COMPILED {entry["id"]} {info["width"]}x{info["height"]}', flush=True)
    except Exception:
        for destination, prior in restores:
            shutil.copy2(prior, destination)
        raise
    manifest = {'status': 'PASS', 'at': datetime.now(timezone.utc).isoformat(), 'records': records,
                'scope': 'Reviewed high-resolution sources, native BGRA8888/no-LOD textures, exact decoded previews'}
    (WORK / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    run(parser.parse_args().apply)
