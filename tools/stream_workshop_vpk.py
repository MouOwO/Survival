"""Stream an authenticated runtime candidate into native-safe Valve VPK v2 files.

Default is read-only. --build creates <workshop-id>.vpk and, for large payloads,
numbered 1 GiB archives in an existing external
directory, never in Dota or the candidate. No upload, compression, payload
changes, private keys, or Valve binary modifications are performed. The VPK
container has no RSA signature; authenticity comes from the pinned Ed25519
release manifest verified BEFORE packaging. Native map loading remains a
separate test, not a consequence of this format check.
"""
from __future__ import annotations

import argparse
import base64
from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_test_release as handoff

runtime = handoff.runtime
protect_data = handoff.protect_data
MAGIC = 0x55AA1234
INLINE = 0x7FFF
U32_MAX = 0xFFFFFFFF
MAX_INLINE_BYTES = 0x7FFFFFFF
ARCHIVE_BYTES = 1024 * 1024 * 1024
CHUNK = 1024 * 1024
MAX_TREE = 16 * 1024 * 1024
MAX_MANIFEST = 16 * 1024 * 1024
MAX_SIGNATURE = 64 * 1024
HEADER = struct.Struct("<7I")
ENTRY = struct.Struct("<IHHIIH")


def md5():
    return hashlib.md5(usedforsecurity=False)


def read_metadata(path: Path, maximum: int) -> bytes:
    with path.open("rb") as stream:
        raw = stream.read(maximum + 1)
    if len(raw) > maximum:
        raise ValueError("Release metadata exceeds its bounded read limit: " + path.name)
    return raw


def inventory_unchanged(candidate: Path, snapshots: dict[str, bytes]) -> None:
    for name, expected in snapshots.items():
        try:
            unchanged = read_metadata(protect_data.source_path(candidate, name), len(expected)) == expected
        except (ValueError, OSError) as error:
            raise ValueError("Signed inventory changed during verification/packaging") from error
        if not unchanged:
            raise ValueError("Signed inventory changed during verification/packaging")


def verify_signed_snapshot(manifest: dict, document: dict, public_path: Path,
                           minimum: int, expected_key_id: str) -> dict:
    """Verify the bounded snapshots, never reopen attacker-swappable JSON."""
    public = handoff.serialization.load_pem_public_key(public_path.read_bytes())
    sequence = document.get("release_sequence")
    if type(sequence) is not int or not minimum <= sequence < 2**64:
        raise ValueError("Release sequence is below the trusted minimum or invalid")
    if (not isinstance(public, handoff.Ed25519PublicKey) or document.get("schema") != 2
            or document.get("algorithm") != "Ed25519"
            or protect_data.public_id(public) != expected_key_id
            or document.get("key_id") != protect_data.public_id(public)
            or document.get("content_sha256") != manifest["content_sha256"]):
        raise ValueError("Signature identity mismatch")
    public.verify(base64.b64decode(document["signature"], validate=True),
                  protect_data.DOMAIN + struct.pack(">Q", sequence) + runtime.manifest_payload(manifest))
    return {"signature_valid": True, "release_sequence": sequence,
            "content_sha256": manifest["content_sha256"], "key_id": expected_key_id}


def authenticate(candidate: Path) -> tuple[Path, dict, dict, dict]:
    candidate = handoff.regular_path(candidate)
    if (runtime.within(candidate, handoff.INSTALL)
            or runtime.within(handoff.ROOT, candidate)):
        raise ValueError("Candidate must be external to the Dota installation/development addon")
    snapshots = {name: read_metadata(protect_data.source_path(candidate, name), maximum)
                 for name, maximum in ((handoff.MANIFEST, MAX_MANIFEST), (handoff.SIGNATURE, MAX_SIGNATURE))}
    manifest = handoff.decode_json(snapshots[handoff.MANIFEST])
    document = handoff.decode_json(snapshots[handoff.SIGNATURE])
    runtime.validate_manifest(manifest)
    for row in manifest["files"]:
        protect_data.source_path(candidate, row["path"])
    policy, public_path = handoff.trusted_policy(handoff.POLICY)
    inventory_unchanged(candidate, snapshots)
    signature = verify_signed_snapshot(manifest, document, public_path,
                                       policy["integrity"]["minimum_release_sequence"],
                                       policy["integrity"]["trusted_key_id"])
    inventory_unchanged(candidate, snapshots)
    if signature["content_sha256"] != manifest["content_sha256"]:
        raise ValueError("Signed content identity differs from parsed inventory")
    handoff.require_single_map(candidate)
    handoff.require_reviewed_gate(candidate, manifest)
    handoff.configured_ids(candidate)
    if not runtime.verify(candidate, manifest)["ok"]:
        raise ValueError("Candidate failed full inventory/hash verification")
    inventory_unchanged(candidate, snapshots)
    return candidate, manifest, signature, snapshots


def make_tree(rows: list[dict]) -> tuple[bytearray, list[dict], int]:
    """Only metadata is retained in RAM; offsets are unsigned file-data offsets."""
    groups = {}
    total = 0
    for row in rows:
        length = row["bytes"]
        if type(length) is not int or not 0 <= length <= U32_MAX or total + length > U32_MAX:
            raise ValueError("Single-inline VPK data must be <4 GiB (uint32 offsets/lengths)")
        path = row["path"]
        if not runtime.safe_relative(path) or any(ord(c) < 32 for c in path):
            raise ValueError("Unsafe VPK path")
        folder, _, leaf = path.rpartition("/")
        base, dot, extension = leaf.rpartition(".")
        if not dot:
            base, extension = leaf, " "
        if not base or extension == "" or (dot and extension == " "):
            raise ValueError("Ambiguous VPK filename: " + path)
        groups.setdefault(extension, {}).setdefault(folder or " ", []).append((base, row))
        total += length
    tree, ordered, offset = bytearray(), [], 0

    def append(raw):
        if len(tree) + len(raw) > MAX_TREE:
            raise ValueError("VPK directory tree exceeds the bounded metadata limit")
        tree.extend(raw)

    def string(value):
        append(value.encode("utf-8") + b"\0")

    for extension, folders in sorted(groups.items()):
        string(extension)
        for folder, files in sorted(folders.items()):
            string(folder)
            for base, row in sorted(files):
                string(base)
                crc_position = len(tree)
                append(ENTRY.pack(0, 0, INLINE, offset, row["bytes"], 0xFFFF))
                ordered.append({"row": row, "offset": offset, "crc_position": crc_position})
                offset += row["bytes"]
            string("")
        string("")
    string("")
    if len(tree) > MAX_TREE:
        raise ValueError("VPK directory tree exceeds the bounded metadata limit")
    return tree, ordered, total


def hash_range(stream, length: int, *hashes) -> None:
    while length:
        block = stream.read(min(CHUNK, length))
        if not block:
            raise ValueError("Truncated VPK section")
        for digest in hashes:
            digest.update(block)
        length -= len(block)


def copy_payload(source: Path, stream, row: dict) -> int:
    before = source.stat()
    actual, crc = 0, 0
    hashes = {"md5": md5(), "sha256": hashlib.sha256()}
    with source.open("rb") as read:
        while block := read.read(CHUNK):
            actual += len(block)
            if actual > row["bytes"]:
                raise ValueError("Payload grew while packaging: " + row["path"])
            crc = zlib.crc32(block, crc)
            for digest in hashes.values():
                digest.update(block)
            stream.write(block)
    after = source.stat()
    if ((before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns)
            or actual != row["bytes"]
            or any(digest.hexdigest() != row[name] for name, digest in hashes.items())):
        raise ValueError("Payload changed/hash mismatch while packaging: " + row["path"])
    return crc & U32_MAX


def write_vpk(candidate: Path, stream, tree: bytearray, ordered: list[dict], total: int) -> None:
    if HEADER.size + len(tree) + total + 48 > MAX_INLINE_BYTES:
        raise ValueError("Inline VPK exceeds native-safe size; use external archives")
    # Inline data, no preload, no archive-MD5 table, complete other-MD5 section.
    # Official overthrow map VPKs use this same 0/48/0 section arrangement.
    stream.write(HEADER.pack(MAGIC, 2, len(tree), total, 0, 48, 0))
    stream.write(tree)
    for entry in ordered:
        row = entry["row"]
        crc = copy_payload(protect_data.source_path(candidate, row["path"]), stream, row)
        struct.pack_into("<I", tree, entry["crc_position"], crc)
    data_end = HEADER.size + len(tree) + total
    if stream.tell() != data_end:
        raise ValueError("Unexpected data offset after streaming payload")
    stream.seek(HEADER.size)
    stream.write(tree)
    stream.seek(data_end)
    stream.write(hashlib.md5(tree, usedforsecurity=False).digest())
    stream.write(md5().digest())  # MD5 of the empty archive-MD5 section.
    stream.flush()
    stream.seek(0)  # Python file offsets/seek are 64-bit, even past signed32.
    whole = md5()
    hash_range(stream, data_end + 32, whole)
    stream.seek(data_end + 32)
    stream.write(whole.digest())
    stream.flush()
    os.fsync(stream.fileno())


def read_tree(raw: bytes) -> list[dict]:
    position, entries, seen = 0, [], set()

    def string():
        nonlocal position
        end = raw.find(b"\0", position)
        if end < 0:
            raise ValueError("Unterminated VPK tree string")
        value = raw[position:end].decode("utf-8", errors="strict")
        position = end + 1
        return value

    while extension := string():
        while folder := string():
            while base := string():
                if position + ENTRY.size > len(raw):
                    raise ValueError("Truncated VPK directory entry")
                crc, preload, archive, offset, length, terminator = ENTRY.unpack_from(raw, position)
                position += ENTRY.size
                if preload != 0 or archive > INLINE or terminator != 0xFFFF:
                    raise ValueError("Expected zero-preload VPK entry with valid archive/terminator")
                path = ("" if folder == " " else folder + "/") + base
                path += "" if extension == " " else "." + extension
                if not runtime.safe_relative(path) or path.casefold() in seen:
                    raise ValueError("Unsafe/duplicate VPK entry path")
                seen.add(path.casefold())
                entries.append({"path": path, "offset": offset, "bytes": length,
                                "crc32": crc, "archive": archive})
    if position != len(raw):
        raise ValueError("Unexpected trailing VPK tree bytes")
    return entries


def verify_vpk(path: Path, manifest: dict, *, allow_legacy_inline=False) -> dict:
    """Independently parse the written VPK, then stream every entry and digest."""
    expected = {row["path"]: row for row in manifest["files"]}
    with ExitStack() as opened:
        stream = opened.enter_context(path.open("rb"))
        header = stream.read(HEADER.size)
        if len(header) != HEADER.size:
            raise ValueError("Truncated VPK header")
        magic, version, tree_size, data_size, archive_size, other_size, signature_size = HEADER.unpack(header)
        if (magic != MAGIC or version != 2 or not 1 <= tree_size <= MAX_TREE
                or archive_size != 0 or other_size != 48 or signature_size != 0):
            raise ValueError("Unexpected VPK v2 header/section layout")
        data_start = HEADER.size + tree_size
        data_end = data_start + data_size
        if data_end + 48 > MAX_INLINE_BYTES and not allow_legacy_inline:
            raise ValueError("Inline VPK exceeds native-safe size; rebuild with external archives")
        if os.fstat(stream.fileno()).st_size != data_end + 48:
            raise ValueError("VPK section/file size mismatch")
        raw = stream.read(tree_size)
        if len(raw) != tree_size:
            raise ValueError("Truncated VPK tree")
        entries = read_tree(raw)
        if len(entries) != len(expected) or {entry["path"] for entry in entries} != set(expected):
            raise ValueError("VPK inventory differs from authenticated manifest")
        offsets, archives = {}, {}
        for entry in entries:
            row = expected[entry["path"]]
            archive = entry["archive"]
            offset = offsets.get(archive, 0)
            if entry["offset"] != offset or entry["bytes"] != row["bytes"]:
                raise ValueError("VPK entry size/offset/overlap mismatch")
            offset += entry["bytes"]
            offsets[archive] = offset
            if archive == INLINE:
                if offset > data_size:
                    raise ValueError("VPK entry outside inline data section")
                payload, base = stream, data_start
            else:
                if data_size or INLINE in offsets:
                    raise ValueError("Mixed inline/external VPK layout")
                if archive not in archives:
                    archive_path = path.with_name(f"{path.stem}_{archive:03}.vpk")
                    if archive_path.is_symlink():
                        raise ValueError("VPK archive must be a regular file")
                    payload = opened.enter_context(archive_path.open("rb"))
                    if os.fstat(payload.fileno()).st_size > ARCHIVE_BYTES:
                        raise ValueError("VPK archive exceeds native-safe size")
                    archives[archive] = payload
                payload, base = archives[archive], 0
            payload.seek(base + entry["offset"])
            left, crc = entry["bytes"], 0
            hashes = {"md5": md5(), "sha256": hashlib.sha256()}
            while left:
                block = payload.read(min(CHUNK, left))
                if not block:
                    raise ValueError("Truncated VPK file data")
                crc = zlib.crc32(block, crc)
                for digest in hashes.values():
                    digest.update(block)
                left -= len(block)
            if crc & U32_MAX != entry["crc32"]:
                raise ValueError("VPK entry CRC32 mismatch: " + entry["path"])
            if any(digest.hexdigest() != row[name] for name, digest in hashes.items()):
                raise ValueError("VPK entry authenticated hash mismatch: " + entry["path"])
        if offsets.get(INLINE, 0) != data_size:
            raise ValueError("Unused VPK file-data bytes")
        if sum(offsets.values()) != manifest["bytes"]:
            raise ValueError("VPK total payload size mismatch")
        if sorted(archives) != list(range(len(archives))):
            raise ValueError("Noncontiguous VPK archives")
        for index, payload in archives.items():
            if os.fstat(payload.fileno()).st_size != offsets[index]:
                raise ValueError("VPK archive size mismatch/unused bytes")
        stream.seek(data_end)
        tree_hash, archive_hash, whole_hash = (stream.read(16) for _ in range(3))
        if tree_hash != hashlib.md5(raw, usedforsecurity=False).digest() or archive_hash != md5().digest():
            raise ValueError("VPK tree/archive section MD5 mismatch")
        stream.seek(0)
        whole = md5()
        hash_range(stream, data_end + 32, whole)
        if whole.digest() != whole_hash:
            raise ValueError("VPK whole-file MD5 mismatch")
    return {"vpk_version": 2, "files": len(entries), "payload_bytes": manifest["bytes"],
            "archive_count": len(archives),
            "crc32_verified": True, "manifest_dual_hashes_verified": True,
            "section_md5s_verified": True, "whole_vpk_md5_verified": True}


def package_paths(path: Path) -> list[Path]:
    """Only derive sibling archives from a bounded, parsed directory tree."""
    with path.open("rb") as stream:
        header = stream.read(HEADER.size)
        if len(header) != HEADER.size:
            raise ValueError("Truncated VPK header")
        magic, version, tree_size, *_ = HEADER.unpack(header)
        if magic != MAGIC or version != 2 or not 1 <= tree_size <= MAX_TREE:
            raise ValueError("Unexpected VPK header")
        entries = read_tree(stream.read(tree_size))
    indices = sorted({row["archive"] for row in entries} - {INLINE})
    if indices != list(range(len(indices))):
        raise ValueError("Noncontiguous VPK archives")
    return [path] + [path.with_name(f"{path.stem}_{index:03}.vpk") for index in indices]


def package_inventory(path: Path) -> list[dict]:
    rows = []
    for item in package_paths(path):
        if item.is_symlink() or not item.is_file():
            raise ValueError("VPK package member must be a regular file")
        rows.append({"name": item.name, "bytes": item.stat().st_size,
                     "sha256": runtime.digest(item)})
    return rows


def archive_plan(ordered: list[dict], limit: int = ARCHIVE_BYTES) -> list[list[dict]]:
    archives = []
    used = limit
    for entry in ordered:
        size = entry["row"]["bytes"]
        if size > limit:
            raise ValueError("One resource exceeds the native-safe archive size")
        if not archives or used + size > limit:
            archives.append([])
            used = 0
        archives[-1].append(entry)
        used += size
    return archives


def build_archives(candidate, output_dir, workshop_id, tree, ordered, manifest, snapshots, result):
    """Publish data volumes first and the mountable directory last, without clobbering."""
    plan = archive_plan(ordered, ARCHIVE_BYTES)
    targets = [output_dir / f"{workshop_id}_{i:03}.vpk" for i in range(len(plan))]
    target = output_dir / f"{workshop_id}.vpk"
    if any(item.exists() or item.is_symlink() for item in [target, *targets]):
        raise ValueError("Refusing to replace an existing VPK/archive")
    published = []
    with tempfile.TemporaryDirectory(prefix=".vpk-volumes-", dir=output_dir) as temporary:
        staging = Path(temporary)
        staged = []
        for index, group in enumerate(plan):
            item = staging / targets[index].name
            offset = 0
            with item.open("xb") as stream:
                for entry in group:
                    crc = copy_payload(protect_data.source_path(candidate, entry["row"]["path"]),
                                       stream, entry["row"])
                    struct.pack_into("<IHHIIH", tree, entry["crc_position"], crc, 0, index,
                                     offset, entry["row"]["bytes"], 0xFFFF)
                    offset += entry["row"]["bytes"]
                stream.flush()
                os.fsync(stream.fileno())
            staged.append(item)
        directory = staging / target.name
        prefix = (HEADER.pack(MAGIC, 2, len(tree), 0, 0, 48, 0) + tree
                  + hashlib.md5(tree, usedforsecurity=False).digest() + md5().digest())
        with directory.open("xb") as stream:
            stream.write(prefix + hashlib.md5(prefix, usedforsecurity=False).digest())
            stream.flush()
            os.fsync(stream.fileno())
        verification = verify_vpk(directory, manifest)
        inventory = package_inventory(directory)
        inventory_unchanged(candidate, snapshots)
        if not runtime.verify(candidate, manifest)["ok"]:
            raise ValueError("Source inventory changed while packaging")
        inventory_unchanged(candidate, snapshots)
        try:
            for source, destination in zip([*staged, directory], [*targets, target]):
                os.link(source, destination)
                published.append(destination)
        except BaseException:
            # Only remove names we atomically created; never touch a competing writer's file.
            for item in reversed(published):
                item.unlink()
            raise
    result.update(status="BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY", dry_run=False,
                  verification=verification, package_files=inventory,
                  vpk_sha256=inventory[0]["sha256"])
    return result


def package(candidate: Path, output_dir: Path, workshop_id: str, *, build=False) -> dict:
    if (not isinstance(workshop_id, str) or not re.fullmatch(r"[1-9][0-9]{0,19}", workshop_id)
            or int(workshop_id) > 0xFFFFFFFFFFFFFFFF):
        raise ValueError("An explicit positive uint64 Workshop ID/package basename is required")
    output_dir = handoff.regular_path(output_dir)
    if not output_dir.is_dir():
        raise ValueError("Output must be an existing external directory")
    if (runtime.within(output_dir, handoff.INSTALL) or runtime.within(output_dir, handoff.ROOT)):
        raise ValueError("Output must be external to Dota/development addon")
    candidate, manifest, signature, snapshots = authenticate(candidate)
    if runtime.within(output_dir, candidate) or runtime.within(candidate, output_dir):
        raise ValueError("Candidate and output directory must not overlap")
    target = output_dir / (workshop_id + ".vpk")
    if target.exists() or target.is_symlink():
        raise ValueError("Refusing to replace an existing VPK")
    tree, ordered, total = make_tree(manifest["files"])
    container_bytes = HEADER.size + len(tree) + total + 48
    multipart = container_bytes > MAX_INLINE_BYTES
    if multipart:
        archive_plan(ordered, ARCHIVE_BYTES)
    result = {"schema": 1, "status": "VERIFIED_DRY_RUN", "dry_run": not build,
              "output": str(target), "content_sha256": manifest["content_sha256"],
              "release_sequence": signature["release_sequence"], "files": len(ordered),
              "trusted_key_id": signature["key_id"],
              "payload_bytes": total, "container_bytes": container_bytes,
              "layout": "external_archives" if multipart else "inline",
              "max_archive_bytes": ARCHIVE_BYTES,
              "signature_valid": True, "full_input_hash_verification": True,
              "payload_changed": False, "workshop_upload_performed": False,
              "native_dota_read_test": "NOT_RUN", "native_over_2gib_read_test": "NOT_RUN",
              "ready_for_upload": False}
    if not build:
        return result
    if multipart:
        return build_archives(candidate, output_dir, workshop_id, tree, ordered,
                              manifest, snapshots, result)
    handle, temporary_name = tempfile.mkstemp(prefix=".vpk-stream-", suffix=".part", dir=output_dir)
    temporary = Path(temporary_name)
    published = False
    try:
        with os.fdopen(handle, "w+b") as stream:
            write_vpk(candidate, stream, tree, ordered, total)
        verification = verify_vpk(temporary, manifest)
        inventory_unchanged(candidate, snapshots)
        vpk_sha256 = runtime.digest(temporary)
        if not runtime.verify(candidate, manifest)["ok"]:
            raise ValueError("Source inventory changed while packaging")
        inventory_unchanged(candidate, snapshots)
        # Hard link provides same-directory atomic no-clobber publication on
        # NTFS/POSIX; no rename-overwrite race and no partial final filename.
        os.link(temporary, target)
        published = True
        result.update(status="BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY", dry_run=False,
                      verification=verification, vpk_sha256=vpk_sha256)
        return result
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError as error:
            if not published:
                raise
            result["temporary_cleanup_error"] = str(error)
            result["temporary_file_retained"] = str(temporary)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workshop-id", required=True, help="Confirmed ID, or explicit numeric local test basename")
    parser.add_argument("--build", action="store_true", help="Create NEW external single VPK; never upload")
    args = parser.parse_args()
    try:
        result = package(args.candidate, args.output_dir, args.workshop_id, build=args.build)
    except Exception as error:
        print(json.dumps({"status": "BLOCKED_DO_NOT_UPLOAD", "error": type(error).__name__ + ": " + str(error),
                          "workshop_upload_performed": False, "ready_for_upload": False}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
