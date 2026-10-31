"""Read-only portrait release audit; optional decoder copies live only in output.

This verifies wiring and bytes, not rendered cosmetics or native performance.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'tools'))
import stream_workshop_vpk as vpk

SHA = lambda raw: hashlib.sha256(raw).hexdigest()
ASSET = 'monster_boss_rebirth_05_lucid_torment'
JAVASCRIPT = ('monster_portrait_scenes', 'monster_portrait_renderer', 'combat_stats',
              'portrait_presentation', 'topnav_remaining_5d5c1152eb')


def blocks(raw):
    if len(raw) < 16:
        raise ValueError('Truncated native resource')
    declared, header, version, relative, count = struct.unpack_from('<IHHII', raw)
    table = 8 + relative
    if header != 12 or declared != len(raw) or not 0 < count <= 64 or table + count * 12 > len(raw):
        raise ValueError('Invalid native resource table')
    result = {}
    for index in range(count):
        at = table + index * 12
        kind, offset, size = struct.unpack_from('<4sII', raw, at)
        start = at + 4 + offset
        if kind in result or start < table + count * 12 or start + size > len(raw):
            raise ValueError('Invalid native resource block')
        result[kind] = raw[start:start + size]
    return version, result


def legacy_decoder_copy(raw):
    """Drop unsupported edit metadata in a disposable copy, never runtime bytes."""
    version, resources = blocks(raw)
    selected = [(kind, data) for kind, data in resources.items() if kind != b'RED2']
    start = 16 + len(selected) * 12
    table, payload = bytearray(), bytearray()
    for index, (kind, data) in enumerate(selected):
        at = 16 + index * 12
        table += struct.pack('<4sII', kind, start + len(payload) - at - 4, len(data))
        payload += data
    return struct.pack('<IHHII', start + len(payload), 12, version, 8, len(selected)) + table + payload


def directory(path):
    with path.open('rb') as stream:
        raw = stream.read(vpk.HEADER.size)
        if len(raw) != vpk.HEADER.size:
            raise ValueError('Truncated VPK')
        magic, version, size, *_ = vpk.HEADER.unpack(raw)
        if magic != vpk.MAGIC or version != 2 or not 0 < size <= vpk.MAX_TREE:
            raise ValueError('Unexpected VPK format')
        rows = vpk.read_tree(stream.read(size))
    return {row['path']: row for row in rows}


def stored(path, row):
    if not 0 <= row['archive'] < vpk.INLINE or row['bytes'] > 4 * 1024 * 1024:
        raise ValueError('Only bounded external portrait inputs may be read')
    archive = path.with_name(path.stem + '_%03d.vpk' % row['archive'])
    with archive.open('rb') as stream:
        stream.seek(row['offset'])
        raw = stream.read(row['bytes'])
    if len(raw) != row['bytes'] or zlib.crc32(raw) & 0xffffffff != row['crc32']:
        raise ValueError('Installed VPK CRC differs')
    return raw


def layout(path, decoder, folder, label):
    source = folder / (label + '_decoder_copy.vxml_c')
    decoded = folder / (label + '.xml')
    source.write_bytes(legacy_decoder_copy(path.read_bytes()))
    result = subprocess.run([str(decoder), '-i', str(source), '-o', str(decoded), '-d'],
                            capture_output=True, timeout=60)
    (folder / (label + '_decoder.log')).write_bytes(result.stdout + result.stderr)
    if result.returncode or not decoded.is_file():
        raise ValueError('Layout decoder failed; original resource was not modified')
    tree = ET.fromstring(decoded.read_bytes())
    return ET.tostring(tree, encoding='utf8'), [node.attrib['src'] for node in tree.findall('./scripts/include')]


def run(args):
    args.report.parent.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((args.view / '_release_manifest.json').read_bytes())
    manifest_rows = {row['path']: row for row in manifest['files']}
    art = json.loads((ROOT / 'art/portraits/monsters/manifest.json').read_bytes())
    spec = art['assets'][ASSET]
    paths = ['panorama/scripts/custom_game/' + name + '.vjs_c' for name in JAVASCRIPT]
    paths += ['panorama/layout/custom_game/survival_hud.vxml_c', 'maps/' + spec['map'] + '.vpk',
              'scripts/vscripts/ui/portrait_metadata.lua']
    installed = directory(args.installed) if args.installed else None
    result = {'status': 'READ_ONLY_PORTRAIT_INPUT_AUDIT', 'release_content': manifest['content_sha256'],
              'selection_sample': ASSET, 'components': spec['components'], 'map': spec['map'],
              'files': {}, 'rendered_cosmetics_verified': False, 'FPS_measured': False}
    for name in paths:
        raw = (args.view / name).read_bytes()
        if SHA(raw) != manifest_rows[name]['sha256']:
            raise ValueError('VIEW input differs from its manifest: ' + name)
        item = {'bytes': len(raw), 'sha256': SHA(raw), 'manifest_matches': True}
        if installed is not None:
            item['installed_exact'] = stored(args.installed, installed[name]) == raw
            if not item['installed_exact']:
                raise ValueError('Steam installed portrait input differs: ' + name)
        if name.endswith('.vjs_c'):
            _, data = blocks(raw)
            source = ROOT / ('panorama/src/scripts/custom_game/' + Path(name).stem.replace('.vjs', '') + '.js')
            item['script_DATA_matches_source'] = data[b'DATA'].replace(b'\r\n', b'\n') == source.read_bytes().replace(b'\r\n', b'\n')
        result['files'][name] = item
    if args.decoder:
        folder = args.report.parent / (args.report.stem + '_decoder')
        folder.mkdir(exist_ok=False)
        released, includes = layout(args.view / paths[5], args.decoder, folder, 'published')
        development, _ = layout(ROOT / paths[5], args.decoder, folder, 'development')
        result['layout_semantically_matches_development'] = released == development
        result['actual_script_order'] = [Path(name).stem for name in includes]
        keys = [result['actual_script_order'].index(name) for name in ('monster_portrait_scenes', 'monster_portrait_renderer', 'combat_stats')]
        result['catalog_renderer_combat_order_correct'] = keys == sorted(keys)
    with args.report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({key: result[key] for key in ('status', 'release_content', 'selection_sample', 'components',
          'layout_semantically_matches_development', 'catalog_renderer_combat_order_correct') if key in result}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--view', type=Path, required=True)
    parser.add_argument('--installed', type=Path)
    parser.add_argument('--decoder', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    run(parser.parse_args())
