"""Bounded reader for standard format-0 MPQ archives and named members.

Supports raw, zlib and bzip2 sectors plus standard named-file encryption.
Unsupported formats fail explicitly. No game code or native DLL is loaded.
"""
from __future__ import annotations

import bz2
import hashlib
import math
import struct
import zlib

LIMIT = 32 * 1024 * 1024
MASK = 0xFFFFFFFF


class Unsupported(ValueError):
    pass


def crypt_table():
    table = [0] * 0x500
    seed = 0x100001
    for low in range(256):
        for high in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            first = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            table[low + high * 256] = first | (seed & 0xFFFF)
    return table


CRYPT = crypt_table()


def name_hash(name, kind):
    first, second = 0x7FED7FED, 0xEEEEEEEE
    for char in name.replace('/', '\\').upper().encode('ascii'):
        first = (CRYPT[(kind << 8) + char] ^ (first + second)) & MASK
        second = (char + first + second + (second << 5) + 3) & MASK
    return first


def decrypt(blob, key):
    result = bytearray(blob)
    second = 0xEEEEEEEE
    for offset in range(0, len(blob) - 3, 4):
        second = (second + CRYPT[0x400 + (key & 255)]) & MASK
        word = struct.unpack_from('<I', blob, offset)[0] ^ ((key + second) & MASK)
        struct.pack_into('<I', result, offset, word)
        key = ((((~key & MASK) << 21) + 0x11111111) | (key >> 11)) & MASK
        second = (word + second + (second << 5) + 3) & MASK
    return bytes(result)


def decompress(blob, expected):
    if len(blob) == expected:
        return blob
    if not blob:
        raise Unsupported('empty compressed sector')
    compression, payload = blob[0], blob[1:]
    if compression == 2:
        decoder = zlib.decompressobj()
        result = decoder.decompress(payload, expected + 1)
    elif compression == 16:
        decoder = bz2.BZ2Decompressor()
        result = decoder.decompress(payload, max_length=expected + 1)
    else:
        raise Unsupported(f'unsupported compression mask 0x{compression:02x}')
    if len(result) != expected or not decoder.eof:
        raise Unsupported('compressed output exceeds declared length or is incomplete')
    return result


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


class MPQ:
    def __init__(self, stream, length):
        self.stream, self.length = stream, length
        stream.seek(0)
        prefix = stream.read(1024 * 1024)
        candidates = [offset for offset in range(0, len(prefix) - 31, 512)
                      if prefix[offset:offset + 4] == b'MPQ\x1a']
        if not candidates:
            raise Unsupported('no standard MPQ header in the first MiB')
        self.base = candidates[0]
        self.header = struct.unpack_from('<4sIIHHIIII', prefix, self.base)
        _, header_size, archive_size, version, shift, hashes, blocks, hash_count, block_count = self.header
        if version != 0 or header_size != 32:
            raise Unsupported('only standard format-0 MPQ headers are supported')
        if not 0 <= shift <= 15 or hash_count > 1_000_000 or block_count > 1_000_000:
            raise Unsupported('archive table or sector-size bound exceeded')
        if not hash_count or hash_count & (hash_count - 1):
            raise Unsupported('hash table size must be a power of two')
        if archive_size < header_size or self.base + archive_size > length:
            raise Unsupported('archive size outside source bounds')
        self.archive_size, self.sector_size = archive_size, 512 << shift
        self.hash_bytes = decrypt(self.read(hashes, hash_count * 16), name_hash('(hash table)', 3))
        self.block_bytes = decrypt(self.read(blocks, block_count * 16), name_hash('(block table)', 3))
        self.hashes = list(struct.iter_unpack('<IIHHI', self.hash_bytes))
        self.blocks = list(struct.iter_unpack('<IIII', self.block_bytes))

    def read(self, offset, count):
        if offset < 0 or count < 0 or offset + count > self.archive_size:
            raise Unsupported('archive read outside declared bounds')
        self.stream.seek(self.base + offset)
        result = self.stream.read(count)
        if len(result) != count:
            raise Unsupported('short archive read')
        return result

    def lookup(self, name):
        wanted = name_hash(name, 1), name_hash(name, 2)
        start = name_hash(name, 0) & (len(self.hashes) - 1)
        found = []
        for step in range(len(self.hashes)):
            index = (start + step) & (len(self.hashes) - 1)
            first, second, locale, platform, block = self.hashes[index]
            if block == MASK:
                break
            if block != MASK - 1 and (first, second) == wanted:
                if block >= len(self.blocks):
                    raise Unsupported('hash entry points outside block table')
                found.append({'hash_index': index, 'block_index': block,
                              'locale': locale, 'platform': platform})
        return sorted(found, key=lambda item: (item['locale'] != 0, item['platform'] != 0, item['locale']))

    def extract(self, name, block, limit=LIMIT):
        offset, packed, length, flags = block
        if length > min(limit, LIMIT) or packed > LIMIT:
            raise Unsupported('member exceeds extraction limit')
        if not flags & 0x80000000 or flags & (0x02000000 | 0x00100000):
            raise Unsupported('deleted or patch member')
        if flags & 0x100:
            raise Unsupported('PKWARE implode is not supported')
        if length == 0:
            return b''
        blob = self.read(offset, packed)
        encrypted = bool(flags & 0x10000)
        key = name_hash(name.replace('/', '\\').rsplit('\\', 1)[-1], 3)
        if flags & 0x20000:
            key = ((key + offset) ^ length) & MASK
        if flags & 0x1000000:
            if encrypted:
                blob = decrypt(blob, key)
            return decompress(blob, length) if flags & 0x200 else self.exact(blob, length)
        sectors = math.ceil(length / self.sector_size)
        if flags & 0x200:
            count = sectors + 1 + bool(flags & 0x4000000)
            table_length = count * 4
            if table_length > len(blob):
                raise Unsupported('truncated sector offset table')
            table = decrypt(blob[:table_length], (key - 1) & MASK) if encrypted else blob[:table_length]
            offsets = struct.unpack('<' + 'I' * count, table)
            if offsets[0] < table_length or offsets[-1] > len(blob) or any(a > b for a, b in zip(offsets, offsets[1:])):
                raise Unsupported('invalid sector offsets')
            output = []
            for sector in range(sectors):
                payload = blob[offsets[sector]:offsets[sector + 1]]
                if encrypted:
                    payload = decrypt(payload, (key + sector) & MASK)
                expected = min(self.sector_size, length - sector * self.sector_size)
                output.append(decompress(payload, expected))
            return self.exact(b''.join(output), length)
        if encrypted:
            blob = b''.join(decrypt(blob[i * self.sector_size:(i + 1) * self.sector_size],
                                    (key + i) & MASK) for i in range(sectors))
        return self.exact(blob, length)

    @staticmethod
    def exact(blob, length):
        if len(blob) != length:
            raise Unsupported('raw member length differs from declared length')
        return blob
