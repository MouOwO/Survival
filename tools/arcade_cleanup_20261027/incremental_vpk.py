"""Authenticate a thin release and rebuild only changed SHOP02 VPK volumes.

Default is read-only. --build creates a NEW full candidate view and complete
VPK directory, never modifies the immutable base or submits a Steam update.
Unchanged loose resources and (by default) unchanged archives are hard linked;
this program only opens those names for reading. Replacements always get new
exclusive files. The normal full runtime/VPK validators remain mandatory.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stream_workshop_vpk as pack

ROOT = Path(__file__).resolve().parents[2]
ITEM = "3824360109"
BASE = Path("D:/Survival_发布候选/20261026_ws4_native_shop_v04")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_VPK = Path("D:/Survival_工坊输出/20261026_ws4_native_shop_v04/3824360109.vpk")
BASE_CONTENT = "b38b10b76aaa4674c8a2d0ffc436922723a793f4b71665916956b4323f40b744"
BASE_SEQUENCE, BASE_COUNT = 2026102604, 6637
NATIVE_SEQUENCE, HELPER_SEQUENCE = 2026102705, 2026102706
BASE_PACKAGE = [
    {"name": ITEM + ".vpk", "bytes": 273555, "sha256": "75a90c772844287890f58c156d08aba1680e3fba8ed69d89fc7a638e8c53845b"},
    {"name": ITEM + "_000.vpk", "bytes": 1073593907, "sha256": "22ab8ca03f51d2a522bbcc676fc26b03647215cbcc05e3feaa932d23f03c17ab"},
    {"name": ITEM + "_001.vpk", "bytes": 1068730788, "sha256": "68cfc41f2c46f91ade8396ebe3f3597da03ab2d1f5bb06577feee49182cddff0"},
    {"name": ITEM + "_002.vpk", "bytes": 1072379183, "sha256": "94a2a3b26731ea2a15fe0fad8116eb9043cb8bf960139a26c95e810192d56141"},
    {"name": ITEM + "_003.vpk", "bytes": 552124410, "sha256": "c813a8b6a25e19a9d38dcb6a5e05421bc115d0b2d9af4869071ea18c1ca078a7"},
]
RESERVE = 256 * 1024 * 1024
METADATA = {pack.handoff.MANIFEST: pack.MAX_MANIFEST,
            pack.handoff.SIGNATURE: pack.MAX_SIGNATURE}


def need(condition, message):
    if not condition:
        raise ValueError(message)


@contextmanager
def trusted_source(root):
    """Historical gate bytes are audited against their own frozen snapshot."""
    root = pack.handoff.regular_path(root)
    old = pack.handoff.ROOT, pack.handoff.POLICY
    pack.handoff.ROOT = root
    pack.handoff.POLICY = root / "tools/release_security/protection_policy.json"
    try:
        yield
    finally:
        pack.handoff.ROOT, pack.handoff.POLICY = old


def snapshot(path):
    st = path.stat()
    return st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns


def metadata(root):
    values = {name: pack.read_metadata(pack.protect_data.source_path(root, name), limit)
              for name, limit in METADATA.items()}
    manifest, signature = [pack.handoff.decode_json(values[name]) for name in METADATA]
    pack.runtime.validate_manifest(manifest)
    return manifest, signature, values


def all_files(root):
    names = set()
    for current, folders, files in os.walk(root, followlinks=False):
        for name in [*folders, *files]:
            need(not pack.protect_data.linked(Path(current) / name), "Thin release contains a link/junction")
        names.update((Path(current) / name).relative_to(root).as_posix() for name in files)
    return names


def external(path, *, exists=True):
    path = pack.handoff.regular_path(path, must_exist=exists)
    need(not pack.runtime.within(path, pack.handoff.INSTALL)
         and not pack.runtime.within(path, ROOT), "New artifacts must be external to Dota/source")
    return path


def ancestor(path):
    while not path.exists():
        path = path.parent
    return path


def disjoint(paths):
    for i, left in enumerate(paths):
        for right in paths[i + 1:]:
            need(not pack.runtime.within(left, right) and not pack.runtime.within(right, left),
                 "Base, overlay, view and output directories must not overlap")


def read_entries(path):
    with path.open("rb") as stream:
        header = stream.read(pack.HEADER.size)
        need(len(header) == pack.HEADER.size, "Truncated base VPK header")
        magic, version, size, data, archive, other, signature = pack.HEADER.unpack(header)
        need(magic == pack.MAGIC and version == 2 and 1 <= size <= pack.MAX_TREE
             and (data, archive, other, signature) == (0, 0, 48, 0),
             "Expected authenticated external-archive base VPK")
        return pack.read_tree(stream.read(size))


def rotation_plan(entries, old, new):
    """Keep each existing path in its old archive, including after size changes."""
    previous = {row["path"]: row for row in old["files"]}
    current = {row["path"]: row for row in new["files"]}
    assignments = {row["path"]: row["archive"] for row in entries}
    indices = sorted(set(assignments.values()))
    need(indices and indices == list(range(len(indices))), "Base archives must be contiguous external volumes")
    need(set(assignments) == set(previous), "Base VPK paths differ from base manifest")
    tree, ordered, _ = pack.make_tree(new["files"])
    groups = [[] for _ in indices]
    for item in ordered:
        index = assignments.get(item["row"]["path"], indices[-1])
        groups[index].append(item)
    modified = set()
    for index, group in enumerate(groups):
        need(group, "Removing an entire base archive requires a separately reviewed repack")
        total = sum(item["row"]["bytes"] for item in group)
        need(total <= pack.ARCHIVE_BYTES, "Changed archive exceeds native-safe limit: " + str(index))
        old_paths = {path for path, archive in assignments.items() if archive == index}
        new_paths = {item["row"]["path"] for item in group}
        if old_paths != new_paths or any(previous.get(path) != current[path] for path in new_paths):
            modified.add(index)
    return tree, groups, modified


def validate_merged(base, overlay, old, new, review_root):
    old_rows = {row["path"]: row for row in old["files"]}
    new_rows = {row["path"]: row for row in new["files"]}
    changed = {path for path, row in new_rows.items() if old_rows.get(path) != row}
    need(all_files(overlay) == changed | set(METADATA),
         "Thin release must contain exactly changed/added runtime paths and full signed metadata")
    sources = {path: pack.protect_data.source_path(overlay if path in changed else base, path)
               for path in new_rows}
    for path, row in new_rows.items():
        need(pack.runtime.checksums(sources[path]) == {key: row[key] for key in ("bytes", "md5", "sha256")},
             "Merged runtime hash mismatch: " + path)
    # Full select/critical/admission checks run again through pack.authenticate
    # on the materialized view BEFORE any VPK payload is written.
    need(pack.runtime.CRITICAL <= new_rows.keys(), "Thin release removes critical runtime files")
    profile_root = overlay if pack.runtime.RELEASE_PROFILE in changed else base
    pack.runtime.require_production(profile_root)
    ids_root = overlay if pack.handoff.ACCESS_FILE in changed else base
    need(pack.handoff.configured_ids(ids_root) == pack.handoff.configured_ids(base),
         "Thin release changes the four-account roster")
    for relative in pack.handoff.GATE_FILES:
        need(relative in sources and pack.runtime.digest(sources[relative]) ==
             pack.runtime.digest(pack.protect_data.source_path(review_root, relative)),
             "Merged admission guard differs from reviewed source: " + relative)
    return sources, changed


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def copy_new(source, destination, row):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("xb") as stream:
        pack.copy_payload(source, stream, row)
        stream.flush()
        os.fsync(stream.fileno())


def remove_owned_tree(root):
    """Only used for a new view owned by this invocation, never for the base."""
    need(root.is_absolute() and root.name and root != root.parent, "Invalid owned cleanup root")
    if not root.exists():
        return
    need(not pack.protect_data.linked(root), "Owned cleanup root became linked")
    # Unlinking hard-link names never opens or truncates the shared base file.
    for current, folders, files in os.walk(root, topdown=False, followlinks=False):
        for name in files:
            (Path(current) / name).unlink()
        for name in folders:
            entry = Path(current) / name
            need(not pack.protect_data.linked(entry), "Owned cleanup directory became linked")
            entry.rmdir()
    root.rmdir()


def materialize(view, sources, changed, manifest, signed_metadata):
    need(not view.exists(), "Candidate view must be a new directory")
    view.mkdir(parents=True, exist_ok=False)
    try:
        rows = {row["path"]: row for row in manifest["files"]}
        for relative, source in sources.items():
            target = view / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if relative in changed:
                copy_new(source, target, rows[relative])
                need(not os.path.samefile(source, target), "Replacement must have an independent inode")
            else:
                os.link(source, target)  # Read-only here and throughout packaging.
        for name, raw in signed_metadata.items():
            write_new(view / name, raw)
    except BaseException:
        remove_owned_tree(view)
        raise


def capacity(view, output, changed_bytes, rewritten_bytes, index_bytes, reuse_bytes):
    required = {}
    for path, amount in ((view, changed_bytes + sum(METADATA.values())),
                         (output, rewritten_bytes + index_bytes + reuse_bytes)):
        disk = ancestor(path)
        dev = disk.stat().st_dev
        if dev not in required:
            required[dev] = {"root": str(disk.anchor), "path": disk, "required_bytes": RESERVE}
        required[dev]["required_bytes"] += amount
    result = []
    for row in required.values():
        free = shutil.disk_usage(row.pop("path")).free
        need(free >= row["required_bytes"], "Insufficient disk space for bounded build: " + row["root"])
        result.append(dict(row, free_bytes=free, reserve_bytes=RESERVE))
    return result


def build_volumes(view, output, base_vpk, tree, groups, changed, manifest, reuse):
    """Exclusive new files only; publish the verified directory index last."""
    output.mkdir(parents=True, exist_ok=True)
    need(not list(output.iterdir()), "VPK output directory must be empty")
    published = []
    with tempfile.TemporaryDirectory(prefix=".incremental-vpk-", dir=output) as temporary:
        staging = Path(temporary)
        try:
            for index, group in enumerate(groups):
                target = staging / f"{ITEM}_{index:03}.vpk"
                if index not in changed:
                    source = base_vpk.with_name(target.name)
                    if reuse == "hardlink":
                        os.link(source, target)  # Never opened with a writable mode.
                    else:
                        with source.open("rb") as read, target.open("xb") as write:
                            shutil.copyfileobj(read, write, pack.CHUNK)
                            write.flush(); os.fsync(write.fileno())
                else:
                    with target.open("xb") as stream:
                        offset = 0
                        for item in group:
                            row = item["row"]
                            crc = pack.copy_payload(pack.protect_data.source_path(view, row["path"]), stream, row)
                            struct.pack_into("<IHHIIH", tree, item["crc_position"], crc, 0, index,
                                             offset, row["bytes"], 0xFFFF)
                            offset += row["bytes"]
                        stream.flush(); os.fsync(stream.fileno())
                    continue
                # Reused rows retain their authenticated CRC, but use newly
                # generated tree positions/offsets (ordering can change).
                old_entries = {row["path"]: row for row in read_entries(base_vpk)}
                offset = 0
                for item in group:
                    previous = old_entries[item["row"]["path"]]
                    need(previous["offset"] == offset, "Unchanged archive ordering differs")
                    struct.pack_into("<IHHIIH", tree, item["crc_position"], previous["crc32"], 0,
                                     index, offset, item["row"]["bytes"], 0xFFFF)
                    offset += item["row"]["bytes"]
            directory = staging / f"{ITEM}.vpk"
            prefix = (pack.HEADER.pack(pack.MAGIC, 2, len(tree), 0, 0, 48, 0) + tree
                      + hashlib.md5(tree, usedforsecurity=False).digest() + pack.md5().digest())
            write_new(directory, prefix + hashlib.md5(prefix, usedforsecurity=False).digest())
            verification = pack.verify_vpk(directory, manifest)
            inventory = pack.package_inventory(directory)
            need(pack.runtime.verify(view, manifest)["ok"], "Candidate changed during incremental packaging")
            for source in [*pack.package_paths(directory)[1:], directory]:
                target = output / source.name
                os.link(source, target)  # Atomic no-clobber, index last.
                published.append(target)
            need(set(output.iterdir()) == set(published) | {staging},
                 "Another writer changed the VPK output directory")
            return verification, inventory
        except BaseException:
            for target in reversed(published):
                target.unlink()
            raise


def run(overlay, candidate_view, output_dir, *, build=False, reuse="hardlink",
        sequence=NATIVE_SEQUENCE, review_root=ROOT):
    need(sequence in (NATIVE_SEQUENCE, HELPER_SEQUENCE), "Unexpected reviewed release sequence")
    need(reuse in {"hardlink", "copy"}, "Invalid archive reuse mode")
    overlay, view, output = (external(overlay), external(candidate_view, exists=False),
                             external(output_dir, exists=False))
    base, base_vpk = external(BASE), external(BASE_VPK)
    review_root = pack.handoff.regular_path(review_root)
    disjoint([base, overlay, view, output, base_vpk.parent])
    need(not view.exists(), "Candidate view must be a new directory")
    need(not output.exists() or output.is_dir() and not list(output.iterdir()), "VPK output directory must be empty")
    need(ancestor(view).stat().st_dev == base.stat().st_dev,
         "Candidate view must share the base volume for bounded read-only hard links")
    if reuse == "hardlink":
        need(ancestor(output).stat().st_dev == base_vpk.stat().st_dev,
             "Hard-linked archive reuse requires the same volume; use --reuse copy for another drive")
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with trusted_source(BASE_TRUSTED):
        _, old, base_signed, base_metadata = pack.authenticate(base)
    need(old["content_sha256"] == BASE_CONTENT and old["file_count"] == BASE_COUNT
         and base_signed["release_sequence"] == BASE_SEQUENCE
         and base_signed["key_id"] == policy["integrity"]["trusted_key_id"], "Immutable SHOP02 identity differs")
    need(pack.package_inventory(base_vpk) == BASE_PACKAGE, "Immutable SHOP02 VPK inventory differs")
    pack.verify_vpk(base_vpk, old)
    package_snapshots = {path: snapshot(path) for path in pack.package_paths(base_vpk)}
    new, document, signed_metadata = metadata(overlay)
    signature = pack.verify_signed_snapshot(new, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(signature["release_sequence"] == sequence and sequence > BASE_SEQUENCE,
         "Thin release sequence differs from reviewed new release")
    sources, changed_paths = validate_merged(base, overlay, old, new, review_root)
    tree, groups, rewritten = rotation_plan(read_entries(base_vpk), old, new)
    sizes = [sum(item["row"]["bytes"] for item in group) for group in groups]
    spaces = capacity(view, output, sum(row["bytes"] for row in new["files"] if row["path"] in changed_paths),
                      sum(sizes[index] for index in rewritten), pack.HEADER.size + len(tree) + 48,
                      sum(sizes[index] for index in range(len(groups)) if index not in rewritten) if reuse == "copy" else 0)
    result = dict(schema=1, status="VERIFIED_INCREMENTAL_DRY_RUN", dry_run=not build,
        output=str(output / (ITEM + ".vpk")), candidate=str(view), base_content_sha256=BASE_CONTENT,
        content_sha256=new["content_sha256"], release_sequence=sequence, files=new["file_count"],
        trusted_key_id=signature["key_id"], signature_valid=True, full_input_hash_verification=True,
        layout="external_archives", payload_bytes=new["bytes"],
        container_bytes=new["bytes"] + pack.HEADER.size + len(tree) + 48,
        max_archive_bytes=pack.ARCHIVE_BYTES, changed_runtime_paths=sorted(changed_paths),
        deleted_runtime_paths=sorted({row["path"] for row in old["files"]} - sources.keys()),
        rebuilt_archives=sorted(rewritten), reused_archives=sorted(set(range(len(groups))) - rewritten),
        archive_reuse=reuse, physical_rebuilt_bytes=sum(sizes[index] for index in rewritten),
        disk_preflight=spaces, payload_changed=False, workshop_upload_performed=False,
        native_dota_read_test="NOT_RUN", native_over_2gib_read_test="NOT_RUN", ready_for_upload=False)
    if not build:
        return result
    owned_view = False
    try:
        materialize(view, sources, changed_paths, new, signed_metadata)
        owned_view = True
        with trusted_source(review_root):
            _, verified, verified_signature, view_metadata = pack.authenticate(view)
        need(verified == new and verified_signature == signature, "Materialized candidate identity differs")
        verification, inventory = build_volumes(view, output, base_vpk, tree, groups, rewritten, new, reuse)
        pack.inventory_unchanged(base, base_metadata)
        pack.inventory_unchanged(overlay, signed_metadata)
        pack.inventory_unchanged(view, view_metadata)
        need(all(snapshot(path) == value for path, value in package_snapshots.items()), "Base VPK changed during build")
        need(pack.package_inventory(base_vpk) == BASE_PACKAGE and pack.runtime.verify(base, old)["ok"],
             "Immutable SHOP02 changed during build")
        result.update(status="BUILT_AND_VERIFIED_FOR_NATIVE_TEST_ONLY", dry_run=False,
            verification=verification, package_files=inventory, vpk_sha256=inventory[0]["sha256"],
            immutable_base_unchanged=True, full_runtime_validator_passed=True)
        return result
    except BaseException:
        # A failed post-build check is never a publishable artifact. Preserve
        # output for diagnosis if it already passed construction; report fails.
        if owned_view and not (output / (ITEM + ".vpk")).exists():
            remove_owned_tree(view)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--candidate-view", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--review-source", type=Path, default=ROOT)
    parser.add_argument("--reuse", choices=("hardlink", "copy"), default="hardlink")
    parser.add_argument("--sequence", type=int, choices=(NATIVE_SEQUENCE, HELPER_SEQUENCE), default=NATIVE_SEQUENCE)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = run(args.overlay, args.candidate_view, args.output_dir, build=args.build,
                     reuse=args.reuse, sequence=args.sequence, review_root=args.review_source)
    except Exception as error:
        print(json.dumps(dict(ok=False, status="BLOCKED_DO_NOT_UPLOAD", error=str(error),
                              workshop_upload_performed=False), ensure_ascii=True))
        return 1
    print(json.dumps(result, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
