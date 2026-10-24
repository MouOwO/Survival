"""Build the narrowly scoped WS4-WEB-04 diagnostic candidate from signed v03.

Default is a read-only plan. Only --build writes explicit new external outputs.
The existing 180 protected modules, admission policy and release configuration
remain byte-identical. No installation, upload, key creation or game launch occurs.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_candidate as web

pack = web.pack
ROOT = web.ROOT
BASE = Path("D:/Survival_发布候选/20261024_ws4_web_auth_v03")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "549750458285ba1de04436dbeaa0249f5bd587dcf6f6cb914feb84d81d0587d9"
BASE_FILES = 6627
BASE_SEQUENCE = 2026102403
MINIMUM_SEQUENCE = 2026102404
REVISION = "WS4-WEB-04"
MODULE = "scripts/vscripts/systems/player_web_auth.lua"
COMPILED = "panorama/scripts/custom_game/player_web_auth.vjs_c"
UI_SOURCE = "panorama/src/scripts/custom_game/player_web_auth.js"
ALLOWLIST = frozenset((MODULE, COMPILED))
POLICY_MODULE = "scripts/vscripts/core/release_policy.lua"
RELEASE_PROFILE = "scripts/vscripts/config/release_profile.lua"
WEB_CONFIG = "scripts/vscripts/config/player_web_auth.lua"


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, _ = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v03 candidate identity mismatch")
    web.need(signature["release_sequence"] == BASE_SEQUENCE, "Unexpected v03 release sequence")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"],
             "v03 trusted key differs from checkout pin")
    pack.runtime.require_production(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "v03 web authorization must stay enabled")
    return base, manifest, signature


def read_overlay(directory):
    directory = pack.handoff.regular_path(directory)
    web.need(directory.is_dir(), "Compiled overlay must be a directory")
    actual = set()
    for path in directory.rglob("*"):
        web.need(not pack.protect_data.linked(path), "Compiled overlay links are forbidden")
        if path.is_file():
            actual.add(path.relative_to(directory).as_posix())
    web.need(actual == {COMPILED}, "Diagnostic overlay must contain exactly the single reviewed vjs resource")
    raw = pack.protect_data.source_path(directory, COMPILED).read_bytes()
    web.validate_compiled(raw, COMPILED)
    return {COMPILED: raw}


def audit_changes(baseline, candidate, patches, protected):
    before = {row["path"]: row for row in baseline["files"]}
    after = {row["path"]: row for row in candidate["files"]}
    web.need(before.keys() == after.keys(), "Runtime inventory additions/removals are forbidden")
    web.need(baseline["file_count"] == candidate["file_count"] == len(after) == BASE_FILES,
             "Diagnostic release must retain exactly 6627 runtime files")
    web.need(set(patches) == ALLOWLIST, "Diagnostic replacements must match the two-file allowlist")
    changed = {name for name in before if before[name] != after[name]}
    web.need(changed == ALLOWLIST, "Only the two reviewed diagnostic runtime files may change")
    web.need(len(protected) == len(set(protected)) == 180 and POLICY_MODULE in protected,
             "The protected 180-module set including the central policy must remain intact")
    web.need(not set(protected) & ALLOWLIST and set(protected) <= before.keys(),
             "Diagnostic files must stay outside the protected module set")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw),
                 "Diagnostic overlay changed during staging")
    web.need(all(before[name] == after[name] for name in protected), "A protected runtime module changed")
    return [{"path": name, "before": before[name], "after": after[name]} for name in sorted(changed)]


def build(args):
    web.need(args.sequence == MINIMUM_SEQUENCE, "WS4-WEB-04 requires the fixed v04 release sequence")
    base, baseline, signature = authenticate_base()
    protected = web.protected_paths(baseline)
    head = web.git("rev-parse", "HEAD").decode("ascii").strip()
    source = pack.protect_data.source_path(ROOT, MODULE).read_bytes()
    ui_source = pack.protect_data.source_path(ROOT, UI_SOURCE).read_bytes()
    web.need(REVISION.encode("ascii") in source, "Reviewed Lua source is missing WS4-WEB-04 diagnostics")
    snapshots = {MODULE: source, UI_SOURCE: ui_source}
    result = {"ok": True, "status": "READ_ONLY_PLAN", "revision": REVISION,
              "base_content_sha256": BASE_SHA, "base_files": BASE_FILES,
              "base_signature_sequence": signature["release_sequence"], "release_sequence": args.sequence,
              "allowed_changes": sorted(ALLOWLIST), "protected_modules_preserved": len(protected),
              "reviewed_head": head, "sources": {name: web.sha(raw) for name, raw in snapshots.items()},
              "online_cheats_allowed": False, "four_account_only": True,
              "workshop_upload_performed": False, "game_started": False}
    if not args.build:
        return result
    web.need(args.compiled_overlay is not None and args.signing_key is not None,
             "--build requires --compiled-overlay and --signing-key")
    web.need(args.sequence > signature["release_sequence"], "Release sequence must advance")
    patches = {MODULE: source, **read_overlay(args.compiled_overlay)}
    destination, trusted, package_output, key = web.output_paths(args, base)
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler is unavailable")
    # Check plaintext syntax before creating any candidate output. No protected
    # modules are transformed or rebuilt in this diagnostic-only release.
    web.protect_runtime_lua.syntax_check([pack.protect_data.source_path(ROOT, MODULE)], web.LUA_COMPILER)
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        (destination / name).write_bytes(raw)
    manifest = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, manifest, patches, protected)
    web.protect_runtime_lua.syntax_check([destination / MODULE], web.LUA_COMPILER)
    for name, raw in snapshots.items():
        web.need(pack.protect_data.source_path(ROOT, name).read_bytes() == raw,
                 "Reviewed diagnostic source changed during build")
    web.need(web.git("rev-parse", "HEAD").decode("ascii").strip() == head, "Reviewed HEAD changed during build")
    trusted.mkdir(parents=True, exist_ok=False)
    for name in (*pack.handoff.GATE_FILES, pack.handoff.ACCESS_FILE, *web.POLICY_FILES):
        origin = BASE_TRUSTED if name in web.POLICY_FILES else base
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(origin, name).read_bytes())
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"], "Signed diagnostic identity mismatch")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    result.update(status="SIGNED_DIAGNOSTIC_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  files=manifest["file_count"], changed=changed, signature_valid=signed["signature_valid"],
                  protected_modules_rebuilt=0, plaintext_substitution=False,
                  all_other_runtime_bytes_preserved=True, private_key_copied=False,
                  destination=str(destination), trusted_source=str(trusted), packaged=packaged,
                  lua_syntax="PASS", native_dota_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_web_auth_diagnostic_provenance.json", result)
    return result


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
        print(json.dumps(build(parser().parse_args()), ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": "web_auth_diagnostic_build_failed", "detail": str(error)[:500]},
                         ensure_ascii=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
