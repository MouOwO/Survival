"""Validate installed sources and VPK payloads without local timestamps or logs."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT.parents[2] / 'content/dota_addons/survival'


def installed_source(source, relative):
    source, installed = Path(source), CONTENT / relative
    a, b = source.read_bytes(), installed.read_bytes()
    if source.suffix in {'.vmdl', '.obj', '.vmat', '.vpcf', '.vmap'}:
        a, b = a.replace(b'\r\n', b'\n'), b.replace(b'\r\n', b'\n')
    assert a == b, f'Installed source differs: {relative}'


def verify_map_vpk(path):
    """Read VPK directory records and verify each entry's payload CRC32."""
    path = Path(path)
    data = path.read_bytes()
    magic, version, tree_size = struct.unpack_from('<III', data)
    assert magic == 0x55AA1234 and version in (1, 2), path
    cursor = 28 if version == 2 else 12
    tree_end = cursor + tree_size
    assert tree_end <= len(data), path

    def string():
        nonlocal cursor
        end = data.index(b'\0', cursor, tree_end)
        value = data[cursor:end].decode('utf-8')
        cursor = end + 1
        return value

    entries = []
    while extension := string():
        while directory := string():
            while name := string():
                crc, preload_size, archive, offset, size, terminator = struct.unpack_from('<IHHIIH', data, cursor)
                cursor += 18
                assert terminator == 0xFFFF and cursor + preload_size <= tree_end, path
                preload = data[cursor:cursor + preload_size]
                cursor += preload_size
                if archive == 0x7FFF:
                    payload = data[tree_end + offset:tree_end + offset + size]
                else:
                    stem = path.stem.removesuffix('_dir')
                    with path.with_name(f'{stem}_{archive:03}.vpk').open('rb') as stream:
                        stream.seek(offset)
                        payload = stream.read(size)
                entry = f'{directory}/{name}.{extension}'
                assert len(payload) == size, (path, entry, 'truncated payload')
                assert zlib.crc32(preload + payload) == crc, (path, entry, 'CRC mismatch')
                entries.append(entry)
    assert cursor == tree_end and any(p.endswith('.vmap_c') for p in entries), path
    return len(entries)
