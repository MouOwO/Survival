"""Build a NEW signed web-auth candidate from the immutable signed WS4 release.

Default is a read-only plan. Only --build may create the explicit new external
candidate, its narrowly scoped trusted-source directory, and optional VPK output.
No Workshop upload, installed addon mutation, gameplay/resource refresh, or key
copying is performed.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import stream_workshop_vpk as pack
import protect_runtime_lua

BASE = Path("D:/Survival_发布候选/20261023_ws4_auth_v03")
BASE_SHA = "a8ad3b474799bbc07821b568120ec442a2c25a74826fe2e0e92696a09ca36335"
BASE_COUNT = 6623
MINIMUM_SEQUENCE = 2026102401
PATCH_BASELINE_COMMIT = "641e836c1a2b82f03f300e53dd567bd6a06ede81"
PROTECTED_COUNT = 180
CONFIG = "scripts/vscripts/config/player_web_auth.lua"
MODULE = "scripts/vscripts/systems/player_web_auth.lua"
PATCHED_LUA = (
    "scripts/vscripts/systems/player_profile_providers/http_fishing_provider.lua",
    "scripts/vscripts/systems/startup_loading_service.lua",
)
COMPILED = (
    "panorama/scripts/custom_game/player_web_auth.vjs_c",
    "panorama/styles/custom_game/player_web_auth.vcss_c",
    "panorama/layout/custom_game/startup_loading.vxml_c",
)
ALLOWLIST = frozenset((CONFIG, MODULE, *PATCHED_LUA, *COMPILED))
POLICY_FILES = ("tools/release_security/protection_policy.json",
                "tools/release_security/trusted_public_key.pem")
LUA_COMPILER = Path("C:/Program Files/lua/bin/luac5.1.exe")


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def lf(raw):
    return raw.replace(b"\r\n", b"\n")


def git(*args, root=ROOT):
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, timeout=60)
    need(result.returncode == 0, "Git operation failed: " + " ".join(args[:3]))
    return result.stdout


def task_diff(relative, *, root=ROOT, baseline=PATCH_BASELINE_COMMIT):
    """Include committed and uncommitted task changes against its fixed start."""
    need(relative in PATCHED_LUA, "Unreviewed text diff path")
    return git("diff", "--no-ext-diff", "--no-textconv", "--no-color", "--src-prefix=a/",
               "--dst-prefix=b/", baseline, "--", relative, root=root)


def patch_bytes(base_raw, diff, relative):
    """Strict reviewed hunks, not replacement by today's complete source file."""
    need(relative in PATCHED_LUA, "Unreviewed text patch path")
    expected_header = ("diff --git a/" + relative + " b/" + relative).encode()
    lines = diff.splitlines(keepends=True)
    headers = [line.rstrip(b"\r\n") for line in lines if line.startswith(b"diff --git ")]
    need(headers == [expected_header], "Text patch must affect exactly its allowlisted file")
    need(("--- a/" + relative).encode() in diff and ("+++ b/" + relative).encode() in diff,
         "Unexpected text patch file identity")
    need(not any(marker in diff for marker in (b"GIT binary patch", b"rename from ", b"copy from ",
                                               b"deleted file mode", b"new file mode")), "Non-text patch rejected")
    normalized = lf(base_raw)
    crlf = b"\r\n" in base_raw
    need(not crlf or normalized.replace(b"\n", b"\r\n") == base_raw, "Mixed newline baseline rejected")
    old_hunks, current = [], None
    for line in lines:
        if line.startswith(b"@@ "):
            if current is not None:
                old_hunks.append(b"".join(current))
            current = []
        elif current is not None:
            if line.startswith((b" ", b"-")):
                current.append(line[1:])
            elif not line.startswith((b"+", b"\\ No newline")):
                raise ValueError("Unsupported unified patch grammar")
    if current is not None:
        old_hunks.append(b"".join(current))
    need(old_hunks, "No reviewed patch hunks")
    last_end = 0
    for old in old_hunks:
        need(old and normalized.count(old) == 1, "Frozen patch context absent or ambiguous")
        start = normalized.index(old)
        need(start >= last_end, "Frozen patch contexts overlap or reorder")
        last_end = start + len(old)
    with tempfile.TemporaryDirectory(prefix="ws4-reviewed-patch-") as folder:
        work = Path(folder)
        target = work / relative
        target.parent.mkdir(parents=True)
        target.write_bytes(normalized)
        for options in (("--check",), ()):
            result = subprocess.run(["git", "-c", "core.autocrlf=false", "apply", "--whitespace=error-all", *options],
                                    cwd=work, input=lf(diff), capture_output=True, timeout=30)
            need(result.returncode == 0, "Reviewed diff does not strictly apply to frozen source: " + relative)
        output = target.read_bytes()
    need(output != normalized, "Reviewed patch made no change")
    return output.replace(b"\n", b"\r\n") if crlf else output


def validate_compiled(raw, relative):
    """Validate bounded Source 2 resource headers and every declared block."""
    need(relative in COMPILED and 28 <= len(raw) <= 4 * 1024 * 1024, "Compiled overlay absent or oversized")
    size, header_version, _, offset, count = struct.unpack_from("<IHHII", raw)
    table = 8 + offset
    need(size == len(raw) and header_version == 12 and 1 <= count <= 64
         and 16 <= table <= len(raw) - 12 * count, "Compiled Source 2 header invalid")
    tags = []
    for index in range(count):
        entry = table + index * 12
        tag, displacement, length = struct.unpack_from("<4sII", raw, entry)
        start = entry + 4 + displacement
        need(all(32 <= char <= 126 for char in tag) and start >= table + count * 12
             and start + length <= len(raw), "Compiled Source 2 block invalid")
        tags.append(tag)
    need(b"DATA" in tags, "Compiled Source 2 DATA block missing")


def read_overlay(directory):
    directory = pack.handoff.regular_path(directory)
    need(directory.is_dir(), "Compiled overlay must be a directory")
    actual = set()
    for path in directory.rglob("*"):
        need(not pack.protect_data.linked(path), "Compiled overlay links are forbidden")
        if path.is_file():
            actual.add(path.relative_to(directory).as_posix())
    need(actual == set(COMPILED), "Compiled overlay must contain exactly the three reviewed resources")
    result = {}
    for name in COMPILED:
        raw = pack.protect_data.source_path(directory, name).read_bytes()
        validate_compiled(raw, name)
        result[name] = raw
    return result


def authenticated_base():
    base = pack.handoff.regular_path(BASE)
    manifest_raw = pack.read_metadata(base / pack.handoff.MANIFEST, pack.MAX_MANIFEST)
    signature_raw = pack.read_metadata(base / pack.handoff.SIGNATURE, pack.MAX_SIGNATURE)
    manifest, signature = pack.handoff.decode_json(manifest_raw), pack.handoff.decode_json(signature_raw)
    pack.runtime.validate_manifest(manifest)
    need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_COUNT,
         "Immutable WS4 baseline identity mismatch")
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    verified = pack.verify_signed_snapshot(manifest, signature, public,
                                          policy["integrity"]["minimum_release_sequence"],
                                          policy["integrity"]["trusted_key_id"])
    need(pack.runtime.verify(base, manifest)["ok"], "Immutable WS4 baseline byte verification failed")
    pack.inventory_unchanged(base, {pack.handoff.MANIFEST: manifest_raw, pack.handoff.SIGNATURE: signature_raw})
    pack.handoff.require_single_map(base)
    pack.handoff.configured_ids(base)
    return base, manifest, verified


def captured_patches(base, baseline):
    patches, provenance, snapshots = {}, {}, {}
    baseline_rows = {row["path"]: row for row in baseline["files"]}
    head = git("rev-parse", "HEAD").decode("ascii").strip()
    for name in PATCHED_LUA:
        diff = task_diff(name)
        original = pack.protect_data.source_path(base, name).read_bytes()
        need(len(original) == baseline_rows[name]["bytes"] and sha(original) == baseline_rows[name]["sha256"],
             "Frozen patch input changed after baseline verification")
        reviewed = pack.protect_data.source_path(ROOT, name).read_bytes()
        output = patch_bytes(original, diff, name)
        patches[name] = output
        snapshots[name] = sha(reviewed)
        provenance[name] = {"comparison_baseline_commit": PATCH_BASELINE_COMMIT,
                            "comparison_baseline_sha256": sha(git("show", PATCH_BASELINE_COMMIT + ":" + name)),
                            "head_sha256": sha(git("show", "HEAD:" + name)), "reviewed_sha256": sha(reviewed),
                            "frozen_sha256": sha(original), "diff_sha256": sha(diff), "result_sha256": sha(output)}
    for name in (CONFIG, MODULE):
        original = pack.protect_data.source_path(ROOT, name).read_bytes()
        snapshots[name] = sha(original)
        raw = original
        if name == CONFIG:
            need(raw.count(b"enabled = false") == 1 and b"enabled = true" not in raw,
                 "Public development web-auth configuration must be disabled")
            raw = raw.replace(b"enabled = false", b"enabled = true", 1)
            raw = re.sub(rb"^-- Disabled[^\r\n]*", b"-- Enabled only in this separately signed four-account test candidate.", raw, count=1)
        patches[name] = raw
        provenance[name] = {"reviewed_sha256": sha(original), "result_sha256": sha(raw), "new_runtime_module": True}
    return head, patches, provenance, snapshots


def protected_paths(manifest):
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    protect_runtime_lua.check_policy(policy)
    selected = protect_runtime_lua.selected_files([row["path"] for row in manifest["files"]], policy)
    need(len(selected) == PROTECTED_COUNT, "Frozen protected module selection differs from reviewed 180 modules")
    need(not {row["path"] for row in selected} & ALLOWLIST, "Protected modules cannot be patched")
    return [row["path"] for row in selected]


def audit_changes(baseline, candidate, patches, protected):
    old = {row["path"]: row for row in baseline["files"]}
    new = {row["path"]: row for row in candidate["files"]}
    need(not old.keys() - new.keys(), "Frozen runtime files were removed")
    changed = {name for name in new if name not in old or new[name] != old[name]}
    need(changed == set(patches) and changed == ALLOWLIST, "Candidate differs outside the seven-file review allowlist")
    for name, raw in patches.items():
        need(new[name]["sha256"] == sha(raw) and new[name]["bytes"] == len(raw), "Overlay changed while copying")
    for name in protected:
        need(old[name] == new[name], "Protected runtime module changed: " + name)
    need(candidate["file_count"] == baseline["file_count"] + 4, "Unexpected new runtime file count")
    return [{"path": name, "before": old.get(name), "after": new[name]} for name in sorted(changed)]


def output_paths(args, base):
    need(args.destination is not None, "--build requires --destination")
    destination = pack.protect_data.external(args.destination, source=base)
    trusted = pack.protect_data.external(args.trusted_source or destination.with_name(destination.name + "_trusted_source"), source=base)
    paths = [destination, trusted]
    if args.package_output is not None:
        paths.append(pack.protect_data.external(args.package_output, source=base))
    for path in paths:
        pack.handoff.regular_path(path, must_exist=False)
        need(not path.exists(), "Output already exists; choose a new external directory")
    for index, left in enumerate(paths):
        for right in paths[index + 1:]:
            need(not pack.runtime.within(left, right) and not pack.runtime.within(right, left), "Output directories overlap")
    key = pack.protect_data.external(args.signing_key)
    need(key.is_file(), "An external signing key is required")
    for path in paths:
        need(not pack.runtime.within(key, path) and not pack.runtime.within(path, key.parent), "Output overlaps the private key directory")
    return destination, trusted, paths[2] if len(paths) == 3 else None, key


@contextmanager
def trusted_root(directory):
    old_root, old_policy = pack.handoff.ROOT, pack.handoff.POLICY
    pack.handoff.ROOT = directory
    pack.handoff.POLICY = directory / POLICY_FILES[0]
    try:
        yield
    finally:
        pack.handoff.ROOT, pack.handoff.POLICY = old_root, old_policy


def build(args):
    base, baseline, signature = authenticated_base()
    protected = protected_paths(baseline)
    head, patches, sources, snapshots = captured_patches(base, baseline)
    plan = {"ok": True, "status": "READ_ONLY_PLAN", "base_content_sha256": BASE_SHA,
            "base_files": BASE_COUNT, "release_sequence": args.sequence,
            "reviewed_head": head, "patch_baseline_commit": PATCH_BASELINE_COMMIT,
            "allowed_changes": sorted(ALLOWLIST),
            "protected_modules_preserved": len(protected), "workshop_upload_performed": False}
    if not args.build:
        return plan
    need(args.compiled_overlay is not None and args.signing_key is not None,
         "--build requires --compiled-overlay and --signing-key")
    need(args.sequence >= MINIMUM_SEQUENCE and args.sequence > signature["release_sequence"], "Release sequence must advance")
    patches.update(read_overlay(args.compiled_overlay))
    destination, trusted, package_output, key = output_paths(args, base)
    need(LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler is unavailable")
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        original = pack.protect_data.source_path(base, row["path"])
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
    for name, raw in patches.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    candidate = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, candidate, patches, protected)
    for name in (CONFIG, MODULE, *PATCHED_LUA):
        result = subprocess.run([str(LUA_COMPILER), "-p", str(destination / name)], capture_output=True, timeout=30)
        need(result.returncode == 0, "Candidate Lua syntax check failed: " + name)
    for name, expected in snapshots.items():
        need(sha(pack.protect_data.source_path(ROOT, name).read_bytes()) == expected, "Reviewed source changed during build")
    need(git("rev-parse", "HEAD").decode("ascii").strip() == head, "Reviewed HEAD changed during build")
    trusted.mkdir(parents=True, exist_ok=False)
    for name in (*pack.handoff.GATE_FILES, pack.handoff.ACCESS_FILE):
        raw = patches.get(name)
        if raw is None:
            raw = pack.protect_data.source_path(base, name).read_bytes()
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
    for name in POLICY_FILES:
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(ROOT, name).read_bytes())
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, candidate)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        need(authenticated["content_sha256"] == candidate["content_sha256"], "Signed candidate identity mismatch")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    provenance = {**plan, "status": "SIGNED_CANDIDATE_REQUIRES_NATIVE_TEST", "release_sequence": args.sequence,
                  "content_sha256": candidate["content_sha256"], "files": candidate["file_count"],
                  "base_signature_sequence": signature["release_sequence"], "signature_valid": signed["signature_valid"],
                  "sources": sources, "changed": changed, "private_key_copied": False,
                  "trusted_source_files": [*pack.handoff.GATE_FILES, pack.handoff.ACCESS_FILE, *POLICY_FILES],
                  "destination": str(destination), "trusted_source": str(trusted), "packaged": packaged,
                  "all_other_base_files_preserved": True, "lua_syntax": "PASS", "native_dota_smoke": "NOT_RUN"}
    pack.runtime.atomic_write_json(destination / "_web_auth_provenance.json", provenance)
    return provenance


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--compiled-overlay", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--sequence", type=int, default=MINIMUM_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    return result


def main():
    try:
        report = build(parser().parse_args())
        print(json.dumps(report, ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": "candidate_build_failed", "detail": str(error)[:500]}, ensure_ascii=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
