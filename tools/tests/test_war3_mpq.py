"""Bounds, compression and named-member regression tests for the read-only MPQ reader."""
import bz2
import io
import struct
import sys
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from war3_extract import mpq


def encrypt(words, key):
    result, second = bytearray(), 0xEEEEEEEE
    for offset in range(0, len(words), 4):
        word = struct.unpack_from("<I", words, offset)[0]
        second = (second + mpq.CRYPT[0x400 + (key & 255)]) & mpq.MASK
        result.extend(struct.pack("<I", word ^ ((key + second) & mpq.MASK)))
        key = ((((~key & mpq.MASK) << 21) + 0x11111111) | (key >> 11)) & mpq.MASK
        second = (word + second + (second << 5) + 3) & mpq.MASK
    return bytes(result)


def fixture(name, payload, size=None, flags=0x81000000):
    hashes = struct.pack("<IIHHI", mpq.name_hash(name, 1), mpq.name_hash(name, 2), 0, 0, 0)
    blocks = struct.pack("<IIII", 64, len(payload), len(payload) if size is None else size, flags)
    header = struct.pack("<4sIIHHIIII", b"MPQ\x1a", 32, 64 + len(payload), 0, 0, 32, 48, 1, 1)
    return header + encrypt(hashes, mpq.name_hash("(hash table)", 3)) + encrypt(blocks, mpq.name_hash("(block table)", 3)) + payload


class MPQTests(unittest.TestCase):
    def test_named_raw_and_empty_members(self):
        for payload in [b"", b"reference facts"]:
            blob = fixture("Units\\Test.slk", payload)
            archive = mpq.MPQ(io.BytesIO(blob), len(blob))
            record = archive.lookup("units/test.slk")[0]
            self.assertEqual(archive.extract("Units\\Test.slk", archive.blocks[record["block_index"]]), payload)
            self.assertEqual(archive.lookup("missing"), [])

    def test_compressed_member_and_decompression_bounds(self):
        original = b"unit values\n" * 500
        for method, compressed in [(2, zlib.compress(original)), (16, bz2.compress(original))]:
            payload = bytes([method]) + compressed
            blob = fixture("test", payload, len(original), 0x81000200)
            archive = mpq.MPQ(io.BytesIO(blob), len(blob))
            self.assertEqual(archive.extract("test", archive.blocks[0]), original)
            with self.assertRaises(mpq.Unsupported):
                mpq.decompress(payload, len(original) - 1)
            with self.assertRaises(mpq.Unsupported):
                mpq.decompress(payload[:-3], len(original))
        with self.assertRaises(mpq.Unsupported):
            mpq.decompress(b"\x08unknown", 100)

    def test_source_and_member_bounds_reject(self):
        with self.assertRaises(mpq.Unsupported):
            mpq.MPQ(io.BytesIO(b"not a map"), 9)
        original = fixture("x", b"hello")
        with self.assertRaises(mpq.Unsupported):
            mpq.MPQ(io.BytesIO(original), len(original) - 1)
        damaged = bytearray(original)
        struct.pack_into("<I", damaged, 16, 0xFFFF0000)
        with self.assertRaises(mpq.Unsupported):
            mpq.MPQ(io.BytesIO(damaged), len(damaged))
        archive = mpq.MPQ(io.BytesIO(original), len(original))
        with self.assertRaises(mpq.Unsupported):
            archive.extract("x", archive.blocks[0], 4)
        with self.assertRaises(mpq.Unsupported):
            archive.read(archive.archive_size - 1, 2)


if __name__ == "__main__":
    unittest.main()
