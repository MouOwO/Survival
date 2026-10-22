"""Repackage an existing signed legacy inline VPK into native-safe volumes.

No runtime code is rebuilt. The published whole-file SHA256 and pinned signed
inventory must both match before any output is written. Default is read-only.
This does not install files, change subscriptions or upload to Workshop.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import tempfile

import stream_workshop_vpk as pack


def repair(source: Path, candidate: Path, output: Path, expected_sha256: str, *, build=False):
    source = pack.handoff.regular_path(source)
    output = pack.handoff.regular_path(output)
    candidate = pack.handoff.regular_path(candidate)
    if (not re.fullmatch(r"[1-9][0-9]{0,19}", source.stem) or source.suffix != ".vpk"
            or int(source.stem) > 0xFFFFFFFFFFFFFFFF):
        raise ValueError("Source must have its confirmed numeric Workshop ID basename")
    if (not output.is_dir() or pack.runtime.within(output, pack.handoff.INSTALL)
            or pack.runtime.within(output, candidate) or pack.runtime.within(candidate, output)
            or pack.runtime.within(output, source.parent)):
        raise ValueError("Output must be a separate existing external directory")
    if not re.fullmatch(r"[a-f0-9]{64}", expected_sha256):
        raise ValueError("Supply the published whole-VPK SHA256")
    manifest = pack.handoff.decode_json(pack.read_metadata(candidate / pack.handoff.MANIFEST, pack.MAX_MANIFEST))
    document = pack.handoff.decode_json(pack.read_metadata(candidate / pack.handoff.SIGNATURE, pack.MAX_SIGNATURE))
    pack.runtime.validate_manifest(manifest)
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    signature = pack.verify_signed_snapshot(manifest, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    # This preserves an already published release. It deliberately reads no
    # candidate runtime files and never substitutes today's development guards.
    if pack.runtime.digest(source) != expected_sha256:
        raise ValueError("Source differs from the published VPK SHA256")
    original = pack.verify_vpk(source, manifest, allow_legacy_inline=True)
    with source.open("rb") as read:
        header = pack.HEADER.unpack(read.read(pack.HEADER.size))
        tree = bytearray(read.read(header[2]))
    entries = pack.read_tree(tree)
    if any(entry["archive"] != pack.INLINE for entry in entries):
        raise ValueError("Repair source must be the original inline package")
    rebuilt, ordered, total = pack.make_tree(manifest["files"])
    if [entry["path"] for entry in entries] != [entry["row"]["path"] for entry in ordered]:
        raise ValueError("Original package ordering differs from the signed inventory")
    plan = pack.archive_plan(ordered, pack.ARCHIVE_BYTES)
    target = output / source.name
    volumes = [output / f"{source.stem}_{i:03}.vpk" for i in range(len(plan))]
    if any(item.exists() or item.is_symlink() for item in [target, *volumes]):
        raise ValueError("Refusing to replace an existing package/archive")
    result = {"status": "VERIFIED_REPAIR_DRY_RUN", "dry_run": not build,
              "source_sha256": expected_sha256, "content_sha256": manifest["content_sha256"],
              "release_sequence": signature["release_sequence"], "signature_valid": True,
              "full_input_hash_verification": True, "payload_changed": False,
              "workshop_upload_performed": False, "ready_for_upload": False,
              "output": str(target), "layout": "external_archives", "files": len(entries),
              "payload_bytes": total, "container_bytes": pack.HEADER.size + len(tree) + total + 48,
              "original_verification": original}
    if not build:
        return result
    with tempfile.TemporaryDirectory(prefix=".vpk-repair-", dir=output) as temporary:
        staging = Path(temporary)
        original_by_path = {entry["path"]: entry for entry in entries}
        staged = []
        with source.open("rb") as read:
            for index, group in enumerate(plan):
                item = staging / volumes[index].name
                offset = 0
                with item.open("xb") as write:
                    for entry in group:
                        old = original_by_path[entry["row"]["path"]]
                        read.seek(pack.HEADER.size + header[2] + old["offset"])
                        left = old["bytes"]
                        while left:
                            block = read.read(min(pack.CHUNK, left))
                            if not block:
                                raise ValueError("Source truncated during repair")
                            write.write(block)
                            left -= len(block)
                        struct.pack_into("<IHHIIH", rebuilt, entry["crc_position"], old["crc32"],
                                         0, index, offset, old["bytes"], 0xFFFF)
                        offset += old["bytes"]
                    write.flush()
                    os.fsync(write.fileno())
                staged.append(item)
        directory = staging / target.name
        prefix = (pack.HEADER.pack(pack.MAGIC, 2, len(rebuilt), 0, 0, 48, 0) + rebuilt
                  + hashlib.md5(rebuilt, usedforsecurity=False).digest() + pack.md5().digest())
        directory.write_bytes(prefix + hashlib.md5(prefix, usedforsecurity=False).digest())
        verification = pack.verify_vpk(directory, manifest)
        inventory = pack.package_inventory(directory)
        if pack.runtime.digest(source) != expected_sha256:
            raise ValueError("Source changed during repair")
        published = []
        try:
            for src, dst in zip([*staged, directory], [*volumes, target]):
                os.link(src, dst)
                published.append(dst)
        except BaseException:
            for item in reversed(published):
                item.unlink()
            raise
    result.update(status="REPACKAGED_AND_FULLY_VERIFIED_NATIVE_TEST_PENDING", dry_run=False,
                  package_files=inventory, verification=verification, vpk_sha256=inventory[0]["sha256"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    result = repair(args.source, args.candidate, args.output_dir, args.expected_sha256, build=args.build)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
