"""Plan, or explicitly sign, the exact seven-file WS4 UI QA overlay on v05.

Default operation only reads pinned inputs. It never reads a signing key or
creates a candidate. --build creates NEW external outputs, retaining the 180
protected modules and every other frozen runtime byte. No installation, game
startup, Workshop upload, gateway request or protection-policy expansion occurs.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_candidate as web

pack = web.pack
ROOT = web.ROOT
CONTENT = ROOT.parents[2] / "content/dota_addons/Survival"
BASE = Path("D:/Survival_发布候选/20261024_ws4_workshop_entry_v05")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "b4750e433bdd1b1ea2fab0de98d13b3660ed5d3ef80a10c63c46512eab10bc60"
BASE_FILES = 6630
BASE_SEQUENCE = 2026102405
RELEASE_SEQUENCE = 2026102501
REVISION = "WS4-UI-QA-06"
PATCH_BASELINE = "a1871d23247787e9f4e88231e224c1238c45323f"
LUA_POLICY_SHA = "68ea73480e0f909acc646cb9146278e9b4a8fce85fee1bcfb5850509ed8601db"
COMPILE_REPORT = ROOT / "output/ui_qa_20261025/compile/20261024T164024798Z/compile.json"
COMPILE_REPORT_SHA = "2565a9be6f1301295b520bced8755aeb39a690cd9bf29257060601c82127e22b"
LUA_PINS = {
    "scripts/vscripts/systems/payment_service.lua": {
        "patch_sha256": "1a9406e47098ee63bacbd6dc8126134f7053e54bc256935b9a06320e20ba8702",
        "source_sha256": "329060dfd888b5f19ed8024c7dc3c562f8f17c6023a427b4c87eb83982d0cad9",
    },
    "scripts/vscripts/systems/commerce_service.lua": {
        "patch_sha256": "c0f417ca6ddd7655e729be2a4ad3829f54f4bd2050aec3aca3ff6600e3794e5a",
        "source_sha256": "25fbfd0c2604add91f000808564dbd3adfaff48333dffd37a1f6ef2866829fa4",
    },
}
# Exact source and native-compiler outputs already reviewed by the owner agent.
# Source paths are relative to each Panorama tree, never supplied by a receipt.
JS_PINS = {
    "scripts/custom_game/topnav_remaining_5d5c1152eb.js": (
        "1f3fbd00344dba965d801cf212904f00935be61f406f9f7bee9f859ab1166d03",
        "93f59fb09ba5f219cd2381bdd5b4dc41ce0e71b0e7cde25549de04c560e78873", 137351),
    "scripts/custom_game/ui_layers.js": (
        "a7c2d9a27c5b6c0b617ac36e2774ba45a91c542bbf324a9e02469cd16d2adebc",
        "db94437a8bd5688386877ac415adbd9e9dce26eee612d0105089aa5b52e044a3", 11116),
    "scripts/custom_game/common/ui_components.js": (
        "58e0b854f7865b9bec574ddcdbf688ebcff70680f48b4a4b913768e588f5f57d",
        "b726918ed03a5f89ac76e667c7b9f44fa364ef75dc5f8b0abc7542934406d9bf", 20193),
    "scripts/custom_game/payment_test.js": (
        "a7b962270ce0e1afab45ca25bb2ce534e604deb18a6a59b693fb877843ee1094",
        "0eb01afa5a28022d056ad1697458e515f2d2772240c27c701ff0060339da261e", 51821),
    "scripts/custom_game/commerce_wallet.js": (
        "71b3c87c2665dcef36fac683d77a92f40e0114e3363d9e2c78768846904c4938",
        "58702efd75374eba9944814af920d0b575229fafcc4488bc17986c41e803167f", 13242),
}
COMPILED = frozenset("panorama/" + name[:-3] + ".vjs_c" for name in JS_PINS)
ALLOWLIST = frozenset(LUA_PINS) | COMPILED
POLICY_MODULE = "scripts/vscripts/core/release_policy.lua"
MAIN = "scripts/vscripts/addon_game_mode.lua"
RELEASE_PROFILE = "scripts/vscripts/config/release_profile.lua"
WEB_CONFIG = "scripts/vscripts/config/player_web_auth.lua"


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, _ = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v05 candidate identity mismatch")
    web.need(signature["release_sequence"] == BASE_SEQUENCE, "Unexpected v05 release sequence")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"], "v05 checkout key pin differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE
             and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "v06 sequence is below the trusted release floor")
    pack.runtime.require_production(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "Frozen player web authorization must stay enabled")
    return base, manifest, signature


def protected_paths(manifest):
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    web.need(web.sha(pack.runtime.canonical_bytes(policy)) == LUA_POLICY_SHA,
             "Reviewed Lua protection policy changed")
    web.protect_runtime_lua.check_policy(policy)
    rows = web.protect_runtime_lua.selected_files([r["path"] for r in manifest["files"]], policy)
    paths = [r["path"] for r in rows]
    web.need(len(paths) == len(set(paths)) == 180 and POLICY_MODULE in paths
             and not set(paths) & ALLOWLIST, "Frozen 180-module protection selection differs")
    return paths


def task_diff(relative):
    web.need(relative in LUA_PINS, "Unreviewed Lua patch path")
    return web.git("diff", "--no-ext-diff", "--no-textconv", "--no-color", "--src-prefix=a/",
                   "--dst-prefix=b/", PATCH_BASELINE, "--", relative, root=ROOT)


def patch_bytes(base_raw, diff, relative):
    """Apply unique, ordered text hunks to frozen bytes, preserving CRLF.

    This uses the same strict-context recipe as web.patch_bytes, with this
    builder's independent two-file allowlist rather than widening the old one.
    """
    web.need(relative in LUA_PINS, "Unreviewed Lua patch path")
    header = ("diff --git a/" + relative + " b/" + relative).encode("ascii")
    lines = diff.splitlines(keepends=True)
    web.need([x.rstrip(b"\r\n") for x in lines if x.startswith(b"diff --git ")] == [header],
             "Lua patch must affect exactly its allowlisted file")
    web.need(("--- a/" + relative).encode() in diff and ("+++ b/" + relative).encode() in diff,
             "Lua patch file identity differs")
    web.need(not any(marker in diff for marker in (b"GIT binary patch", b"rename from ", b"copy from ",
                                                  b"deleted file mode", b"new file mode")),
             "Non-text Lua patch rejected")
    normalized, crlf = web.lf(base_raw), b"\r\n" in base_raw
    web.need(not crlf or normalized.replace(b"\n", b"\r\n") == base_raw, "Mixed newline baseline rejected")
    hunks, current = [], None
    for line in lines:
        if line.startswith(b"@@ "):
            if current is not None:
                hunks.append(b"".join(current))
            current = []
        elif current is not None:
            if line.startswith((b" ", b"-")):
                current.append(line[1:])
            elif not line.startswith((b"+", b"\\ No newline")):
                raise ValueError("Unsupported Lua unified patch grammar")
    if current is not None:
        hunks.append(b"".join(current))
    web.need(hunks, "No reviewed Lua hunks")
    last_end = 0
    for old in hunks:
        web.need(old and normalized.count(old) == 1, "Frozen Lua patch context absent or ambiguous")
        start = normalized.index(old)
        web.need(start >= last_end, "Frozen Lua patch contexts overlap or reorder")
        last_end = start + len(old)
    with tempfile.TemporaryDirectory(prefix="ws4-uiqa-patch-") as folder:
        work = Path(folder)
        target = work / relative
        target.parent.mkdir(parents=True)
        target.write_bytes(normalized)
        for options in (("--check",), ()):
            reply = subprocess.run(["git", "-c", "core.autocrlf=false", "apply", "--whitespace=error-all", *options],
                                   cwd=work, input=web.lf(diff), capture_output=True, timeout=30)
            web.need(reply.returncode == 0, "Reviewed Lua diff does not strictly apply to v05")
        result = target.read_bytes()
    web.need(result != normalized, "Reviewed Lua patch made no change")
    return result.replace(b"\n", b"\r\n") if crlf else result


def compiled_data(raw, relative):
    """Bound native resource blocks and return its unique, nonoverlapping DATA."""
    web.need(relative in COMPILED and 28 <= len(raw) <= 4 * 1024 * 1024,
             "Compiled UI resource absent or oversized")
    size, version, _, offset, count = struct.unpack_from("<IHHII", raw)
    table = 8 + offset
    web.need(size == len(raw) and version == 12 and 1 <= count <= 64
             and 16 <= table <= len(raw) - count * 12, "Compiled UI header invalid")
    blocks, data = [], []
    for index in range(count):
        entry = table + index * 12
        tag, displacement, length = struct.unpack_from("<4sII", raw, entry)
        start = entry + 4 + displacement
        web.need(all(32 <= c <= 126 for c in tag) and start >= table + count * 12
                 and start + length <= len(raw), "Compiled UI block invalid")
        web.need(not any(start < end and begin < start + length for begin, end in blocks),
                 "Compiled UI blocks overlap")
        blocks.append((start, start + length))
        if tag == b"DATA":
            data.append(raw[start:start + length])
    web.need(len(data) == 1, "Compiled UI must contain exactly one DATA block")
    return data[0]


def read_compiled_inputs(report_path, overlay=None):
    report_path = pack.handoff.regular_path(report_path)
    receipt_raw = pack.protect_data.source_path(report_path.parent, report_path.name).read_bytes()
    web.need(web.sha(receipt_raw) == COMPILE_REPORT_SHA, "Reviewed compile receipt changed")
    receipt = pack.handoff.decode_json(receipt_raw)
    web.need(receipt.get("ok") is True and receipt.get("check_only") is False
             and receipt.get("compiled_files") == 5
             and len(receipt.get("scope", [])) == 5 and set(receipt["scope"]) == set(JS_PINS),
             "Compile receipt scope or successful build status differs")
    rows = receipt.get("results", [])
    web.need(isinstance(rows, list) and len(rows) == 5
             and {r.get("relative") for r in rows} == set(JS_PINS), "Compile receipt results differ")
    rows = {r["relative"]: r for r in rows}
    runtime_root = ROOT
    if overlay is not None:
        runtime_root = pack.handoff.regular_path(overlay)
        web.need(runtime_root.is_dir(), "Compiled overlay must be a directory")
        actual = set()
        for path in runtime_root.rglob("*"):
            web.need(not pack.protect_data.linked(path), "Compiled overlay links are forbidden")
            if path.is_file():
                actual.add(path.relative_to(runtime_root).as_posix())
        web.need(actual == COMPILED, "Compiled overlay must contain exactly the five reviewed resources")
    snapshots, patches = {report_path: receipt_raw}, {}
    for name, (source_sha, runtime_sha, byte_count) in JS_PINS.items():
        row = rows[name]
        web.need(row.get("source_sha256") == row.get("content_sha256") == source_sha
                 and row.get("runtime_sha256") == runtime_sha and row.get("runtime_bytes") == byte_count,
                 "Compile receipt hash association differs: " + name)
        game_source = pack.protect_data.source_path(ROOT, "panorama/src/" + name)
        content_source = pack.protect_data.source_path(CONTENT, "panorama/" + name)
        raw_source = game_source.read_bytes()
        web.need(web.sha(raw_source) == source_sha and content_source.read_bytes() == raw_source,
                 "Reviewed game/content JS source differs: " + name)
        relative = "panorama/" + name[:-3] + ".vjs_c"
        runtime_path = pack.protect_data.source_path(runtime_root, relative)
        raw = runtime_path.read_bytes()
        web.need(len(raw) == byte_count and web.sha(raw) == runtime_sha,
                 "Reviewed compiled JS differs: " + name)
        web.need(compiled_data(raw, relative) == raw_source,
                 "Compiled DATA is not the exact reviewed JS source: " + name)
        snapshots.update({game_source: raw_source, content_source: raw_source, runtime_path: raw})
        patches[relative] = raw
    return snapshots, patches


def capture_inputs(base, report_path, overlay=None):
    snapshots, patches = read_compiled_inputs(report_path, overlay)
    diffs = {}
    for name, pin in LUA_PINS.items():
        source_path = pack.protect_data.source_path(ROOT, name)
        source = source_path.read_bytes()
        diff = task_diff(name)
        web.need(web.sha(source) == pin["source_sha256"] and web.sha(diff) == pin["patch_sha256"],
                 "Reviewed Lua source or patch changed: " + name)
        original = web.git("show", PATCH_BASELINE + ":" + name, root=ROOT)
        frozen = pack.protect_data.source_path(base, name).read_bytes()
        web.need(web.lf(frozen) == web.lf(original), "Frozen Lua differs from the fixed patch baseline: " + name)
        patched = patch_bytes(frozen, diff, name)
        web.need(web.lf(patched) == web.lf(source), "Reviewed Lua patch result differs from source: " + name)
        snapshots[source_path] = source
        diffs[name], patches[name] = diff, patched
    web.need(set(patches) == ALLOWLIST, "Reviewed UI QA inputs must affect exactly seven runtime paths")
    return snapshots, patches, diffs


def require_review_unchanged(snapshots, diffs, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw,
                 "Reviewed UI QA input changed during build")
    for name, diff in diffs.items():
        web.need(task_diff(name) == diff, "Reviewed Lua patch changed during build")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head,
             "Reviewed HEAD changed during build")


def audit_changes(baseline, candidate, patches, protected):
    before = {r["path"]: r for r in baseline["files"]}
    after = {r["path"]: r for r in candidate["files"]}
    web.need(before.keys() == after.keys(), "UI QA runtime additions/removals are forbidden")
    web.need(baseline["file_count"] == candidate["file_count"] == len(after) == BASE_FILES,
             "UI QA release must retain exactly 6630 runtime files")
    web.need(set(patches) == ALLOWLIST, "UI QA replacements must match the seven-file allowlist")
    changed = {name for name in before if before[name] != after[name]}
    web.need(changed == ALLOWLIST, "Only the seven reviewed UI QA runtime files may change")
    web.need(len(protected) == len(set(protected)) == 180 and POLICY_MODULE in protected
             and not set(protected) & ALLOWLIST and set(protected) <= before.keys(),
             "The protected 180-module set must remain intact")
    web.need(set(protected) == set(protected_paths(baseline)), "Protected inventory differs from the pinned policy")
    web.need(all(before[name] == after[name] for name in protected), "A protected runtime module changed")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw),
                 "UI QA overlay changed during staging")
    return [{"path": name, "before": before[name], "after": after[name]} for name in sorted(changed)]


def trusted_snapshot(destination):
    """Copy only the already authenticated v05 gates and pinned public policy."""
    web.need(len(pack.handoff.GATE_FILES) == 7 and MAIN in pack.handoff.GATE_FILES
             and set(pack.handoff.ENTRY_GATE_FILES) == {
                 "scripts/vscripts/systems/workshop_entry.lua", "scripts/vscripts/addon_game_mode_client.lua"},
             "Reviewed frozen gate inventory differs")
    names = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
             pack.handoff.ACCESS_FILE, *web.POLICY_FILES)
    destination.mkdir(parents=True, exist_ok=False)
    for name in names:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(BASE_TRUSTED, name).read_bytes())


def trust_inputs(base):
    """Capture the frozen trust files too; later copies must not drift."""
    snapshots = {}
    gates = (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES, pack.handoff.ACCESS_FILE)
    for name in (*gates, *web.POLICY_FILES):
        path = pack.protect_data.source_path(BASE_TRUSTED, name)
        raw = path.read_bytes()
        if name in gates:
            web.need(pack.protect_data.source_path(base, name).read_bytes() == raw,
                     "Frozen gate trust snapshot differs from signed v05")
        snapshots[path] = raw
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        path = pack.protect_data.source_path(ROOT, name)
        snapshots[path] = path.read_bytes()
    return snapshots


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "WS4 UI QA v06 requires the fixed 2026102501 sequence")
    base, baseline, signature = authenticate_base()
    protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches, diffs = capture_inputs(base, args.compile_report, args.compiled_overlay)
    snapshots.update(trust_inputs(base))
    result = {"ok": True, "status": "READ_ONLY_PLAN", "revision": REVISION,
              "base_content_sha256": BASE_SHA, "base_files": BASE_FILES,
              "base_signature_sequence": signature["release_sequence"], "release_sequence": args.sequence,
              "allowed_changes": sorted(ALLOWLIST), "expected_files": BASE_FILES,
              "reviewed_head": head, "patch_baseline_commit": PATCH_BASELINE,
              "lua_patch_sha256": {name: web.sha(raw) for name, raw in diffs.items()},
              "compile_receipt_sha256": COMPILE_REPORT_SHA,
              "patches": {name: web.sha(raw) for name, raw in sorted(patches.items())},
              "protected_modules_preserved": len(protected), "protected_modules_rebuilt": 0,
              "game_content_js_sources_equal": True, "compiled_DATA_equals_reviewed_source": True,
              "online_authentication_changed": False, "online_cheats_allowed": False,
              "four_account_only": True, "real_money_payments": False,
              "alias_install_performed": False, "workshop_upload_performed": False, "game_started": False}
    require_review_unchanged(snapshots, diffs, head)
    if not args.build:
        return result
    web.need(args.signing_key is not None, "--build requires --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler is unavailable")
    web.protect_runtime_lua.syntax_check([pack.protect_data.source_path(ROOT, name) for name in LUA_PINS],
                                       web.LUA_COMPILER)
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        pack.protect_data.source_path(destination, name).write_bytes(raw)
    manifest = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, manifest, patches, protected)
    pack.runtime.require_production(destination)
    pack.handoff.require_single_map(destination)
    web.protect_runtime_lua.syntax_check([destination / name for name in LUA_PINS], web.LUA_COMPILER)
    require_review_unchanged(snapshots, diffs, head)
    trusted_snapshot(trusted)
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"], "Signed UI QA identity mismatch")
        web.need(signed["key_id"] == signature["key_id"], "Signed UI QA key differs from authenticated v05")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    require_review_unchanged(snapshots, diffs, head)
    result.update(status="SIGNED_UI_QA_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  files=manifest["file_count"], changed=changed, signature_valid=signed["signature_valid"],
                  all_other_runtime_bytes_preserved=True, frozen_main_body_preserved=True,
                  plaintext_substitution=False, private_key_copied=False,
                  destination=str(destination), trusted_source=str(trusted), packaged=packaged,
                  lua_syntax="PASS", native_dota_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_ui_qa_provenance.json", result)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--compiled-overlay", type=Path)
    result.add_argument("--compile-report", type=Path, default=COMPILE_REPORT)
    result.add_argument("--sequence", type=int, default=RELEASE_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    return result


def main():
    try:
        print(json.dumps(build(parser().parse_args()), ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, struct.error, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": "ui_qa_candidate_build_failed", "detail": str(error)[:500]},
                         ensure_ascii=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
