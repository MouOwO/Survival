"""Plan, or explicitly sign, the fixed WS4-MP-09 direct four-player diagnostic.

The default only reads public review inputs and the signed v08 baseline. Only
--build creates the fixed NEW candidate/trust directories. It never installs,
starts Dota, calls a network service, uploads, rebuilds protected Lua or copies
a private key. Removing the single reviewed insertion reconstructs v08's main
module byte for byte, including its terminal return statement.
Only the new candidate omits the dormant entry-map VPK; v08 and checkout files
remain intact. One new public probe replaces that one path in the file count.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_stackable_candidate as previous

web, pack = previous.web, previous.pack
ROOT = previous.ROOT
BASE = Path("D:/Survival_发布候选/20261025_ws4_ui_stackable_v08")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9"
BASE_FILES, BASE_SEQUENCE = 6630, 2026102503
RELEASE_SEQUENCE, REVISION = 2026102504, "WS4-MP-09"
DESTINATION = Path("D:/Survival_发布候选/20261025_ws4_multiplayer_v09")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
PACKAGE_OUTPUT = Path("D:/Survival_工坊输出/20261025_ws4_multiplayer_v09")
MAIN, WEB_CONFIG = previous.MAIN, previous.WEB_CONFIG
POLICY_MODULE, LUA_POLICY_SHA = previous.POLICY_MODULE, previous.LUA_POLICY_SHA
ADDONINFO = "addoninfo.txt"
PROBE = "scripts/vscripts/systems/workshop_network_probe.lua"
ENTRY_MAP = "maps/ws4_entry.vpk"
MODIFIED, ADDED = frozenset((ADDONINFO, MAIN)), frozenset((PROBE,))
REMOVED = frozenset((ENTRY_MAP,))
ALLOWLIST = MODIFIED | ADDED
BEGIN = b"-- BEGIN WS4-MP-09 NETWORK PROBE WRAPPER\r\n"
END = b"-- END WS4-MP-09 NETWORK PROBE WRAPPER\r\n"
TAIL = b"return M\r\n"
# Filled only after the independent source review is complete. No caller flags
# can bypass these review pins or substitute an overlay directory.
ADDONINFO_SHA = "079accc9976da77481a465a883a2e9991ed217828b5f41cd159bf19258a1d197"
WRAPPER_SHA = "1f0e57e8a939fe9f777ccbbf343950a2236bf988c009ee92a856c5e9bd59d47a"
PROBE_SHA = "378970193a5db27e2522de05680436a2d0789b60434d4388a846f992a0618eea"
LAYOUT = {"addoninfo": {"maps": "template_map", "isplayable": "1", "enablepickrules": "0",
                        "ws4_entry": {"maxplayers": "1"}, "template_map": {"maxplayers": "4"}}}


def require_review_pins():
    web.need(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)
                 for value in (ADDONINFO_SHA, WRAPPER_SHA, PROBE_SHA)),
             "Multiplayer source review pins are not finalized")


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, metadata = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v08 candidate identity mismatch")
    web.need(signature["release_sequence"] == BASE_SEQUENCE, "Unexpected v08 release sequence")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"], "v08 checkout key pin differs")
    web.need(RELEASE_SEQUENCE > BASE_SEQUENCE
             and RELEASE_SEQUENCE >= pinned["integrity"]["minimum_release_sequence"],
             "v09 sequence is below the trusted release floor")
    pack.runtime.require_production(base)
    pack.handoff.configured_ids(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "Frozen web authorization must stay enabled")
    return base, manifest, signature, metadata


def protected_paths(manifest):
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    web.need(web.sha(pack.runtime.canonical_bytes(policy)) == LUA_POLICY_SHA,
             "Reviewed Lua protection policy changed")
    web.protect_runtime_lua.check_policy(policy)
    paths = [row["path"] for row in web.protect_runtime_lua.selected_files(
        [row["path"] for row in manifest["files"]], policy)]
    web.need(len(paths) == len(set(paths)) == 180 and POLICY_MODULE in paths
             and not set(paths) & ALLOWLIST, "Frozen 180-module protection selection differs")
    return paths


def wrapper_bytes(source):
    web.need(source.count(BEGIN) == source.count(END) == 1,
             "Main source must contain exactly one reviewed wrapper")
    start, finish = source.index(BEGIN), source.index(END) + len(END)
    web.need(start < finish and source[finish:] == TAIL,
             "Reviewed wrapper must immediately precede the exact terminal return M")
    raw = source[start:finish]
    web.need(web.sha(raw) == WRAPPER_SHA, "Reviewed multiplayer wrapper changed")
    return raw


def insert_wrapper(frozen, wrapper):
    web.need(frozen.endswith(b"\r\n\r\n" + TAIL) and BEGIN not in frozen and END not in frozen,
             "Frozen v08 must retain its exact terminal return M without a prior wrapper")
    web.need(wrapper.startswith(BEGIN) and wrapper.endswith(END) and web.sha(wrapper) == WRAPPER_SHA,
             "Reviewed multiplayer wrapper changed")
    return frozen[:-len(TAIL)] + wrapper + frozen[-len(TAIL):]


def capture_inputs(base):
    paths = {name: pack.protect_data.source_path(ROOT, name) for name in ALLOWLIST}
    source = {name: path.read_bytes() for name, path in paths.items()}
    web.need(web.sha(source[ADDONINFO]) == ADDONINFO_SHA
             and pack.handoff.kv(source[ADDONINFO].decode("utf-8-sig")) == LAYOUT,
             "Reviewed addoninfo must expose only template_map 4 and retain entry 1 metadata")
    old_info = pack.protect_data.source_path(base, ADDONINFO).read_bytes()
    web.need(old_info.count(b'"maps"              "ws4_entry"') == 1
             and source[ADDONINFO] == old_info.replace(b'"maps"              "ws4_entry"',
                                                     b'"maps"              "template_map"', 1),
             "Only the frozen addoninfo default map token may change")
    web.need(web.sha(source[PROBE]) == PROBE_SHA and REVISION.encode("ascii") in source[PROBE],
             "Reviewed public network diagnostic source changed")
    wrapper = wrapper_bytes(source[MAIN])
    frozen = pack.protect_data.source_path(base, MAIN).read_bytes()
    return {paths[name]: raw for name, raw in source.items()}, {
        ADDONINFO: source[ADDONINFO], MAIN: insert_wrapper(frozen, wrapper), PROBE: source[PROBE]}


def trust_names():
    web.need(len(pack.handoff.GATE_FILES) == 7 and MAIN in pack.handoff.GATE_FILES
             and set(pack.handoff.ENTRY_GATE_FILES) == {
                 "scripts/vscripts/systems/workshop_entry.lua", "scripts/vscripts/addon_game_mode_client.lua"},
             "Reviewed frozen gate inventory differs")
    return (*pack.handoff.GATE_FILES, *pack.handoff.ENTRY_GATE_FILES,
            pack.handoff.ACCESS_FILE, *web.POLICY_FILES)


def trust_inputs(base):
    snapshots = {}
    for name in trust_names():
        path = pack.protect_data.source_path(BASE_TRUSTED, name)
        raw = path.read_bytes()
        if name not in web.POLICY_FILES:
            web.need(pack.protect_data.source_path(base, name).read_bytes() == raw,
                     "Frozen gate trust snapshot differs from signed v08")
        snapshots[path] = raw
    for name in (*web.POLICY_FILES, "tools/lua_protection_policy.json"):
        path = pack.protect_data.source_path(ROOT, name)
        snapshots[path] = path.read_bytes()
    return snapshots


def require_review_unchanged(snapshots, head):
    for path, raw in snapshots.items():
        web.need(pack.protect_data.source_path(path.parent, path.name).read_bytes() == raw,
                 "Reviewed multiplayer input changed during build")
    web.need(web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip() == head,
             "Reviewed HEAD changed during build")


def require_base_unchanged(base, baseline, metadata):
    pack.handoff.regular_path(base)
    pack.inventory_unchanged(base, metadata)
    web.need(pack.runtime.verify(base, baseline)["ok"], "Immutable v08 candidate disappeared or changed")


def audit_changes(baseline, candidate, patches, protected):
    pack.runtime.validate_manifest(baseline)
    pack.runtime.validate_manifest(candidate)
    before, after = ({row["path"]: row for row in doc["files"]} for doc in (baseline, candidate))
    web.need(before.keys() - after.keys() == REMOVED and after.keys() - before.keys() == ADDED,
             "Multiplayer runtime may omit only the old entry map and add only the probe")
    web.need(baseline["file_count"] == len(before) == BASE_FILES
             and candidate["file_count"] == len(after) == BASE_FILES,
             "Multiplayer release must replace one old entry map with one probe and retain exactly 6630 files")
    web.need(set(patches) == ALLOWLIST, "Multiplayer replacements must match the three-file allowlist")
    changed = {name for name in before.keys() & after.keys() if before[name] != after[name]}
    web.need(changed == MODIFIED, "Only addoninfo and the reviewed main insertion may modify v08")
    web.need(len(protected) == len(set(protected)) == 180 and POLICY_MODULE in protected
             and set(protected) <= before.keys() and not set(protected) & ALLOWLIST
             and set(protected) == set(protected_paths(baseline)),
             "The complete protected 180-module inventory must remain intact")
    web.need(all(before[name] == after[name] for name in protected), "A protected runtime module changed")
    for name, raw in patches.items():
        web.need(after[name]["sha256"] == web.sha(raw) and after[name]["bytes"] == len(raw),
                 "Multiplayer overlay changed during staging")
    main = patches[MAIN]
    wrapper = wrapper_bytes(main)
    frozen = main[:main.index(BEGIN)] + TAIL
    web.need(main == insert_wrapper(frozen, wrapper)
             and len(frozen) == before[MAIN]["bytes"] and web.sha(frozen) == before[MAIN]["sha256"],
             "Removing the sole wrapper insertion must restore the entire frozen main body")
    web.need(web.sha(patches[ADDONINFO]) == ADDONINFO_SHA
             and pack.handoff.kv(patches[ADDONINFO].decode("utf-8-sig")) == LAYOUT
             and web.sha(patches[PROBE]) == PROBE_SHA, "Reviewed multiplayer patch pins changed")
    return [{"path": name, "before": before.get(name), "after": after.get(name)}
            for name in sorted(ALLOWLIST | REMOVED)]


def trusted_snapshot(destination, trusted):
    trusted.mkdir(parents=True, exist_ok=False)
    for name in trust_names():
        origin = destination if name == MAIN else BASE_TRUSTED
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(origin, name).read_bytes())


def stage_runtime(base, destination, baseline, patches):
    """Copy reviewed files individually; never mutate or remove an old file."""
    pack.runtime.validate_manifest(baseline)
    web.need(set(patches) == ALLOWLIST, "Multiplayer replacements must match the three-file allowlist")
    web.need(REMOVED <= {row["path"] for row in baseline["files"]}, "Frozen entry map is missing")
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        if row["path"] in REMOVED:
            continue
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    for name, raw in patches.items():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def build(args):
    web.need(args.sequence == RELEASE_SEQUENCE, "Multiplayer v09 requires the fixed 2026102504 sequence")
    require_review_pins()
    if args.build:
        web.need(args.destination is not None and args.trusted_source is not None
                 and args.destination.absolute() == DESTINATION.absolute()
                 and args.trusted_source.absolute() == TRUSTED_DESTINATION.absolute(),
                 "Multiplayer v09 requires its fixed new candidate/trusted directories")
        web.need(args.package_output is None or args.package_output.absolute() == PACKAGE_OUTPUT.absolute(),
                 "Multiplayer v09 package output differs from the fixed external directory")
    base, baseline, signature, metadata = authenticate_base()
    protected = protected_paths(baseline)
    head = web.git("rev-parse", "HEAD", root=ROOT).decode("ascii").strip()
    snapshots, patches = capture_inputs(base)
    snapshots.update(trust_inputs(base))
    result = dict(ok=True, status="READ_ONLY_PLAN", revision=REVISION, base_content_sha256=BASE_SHA,
                  base_files=BASE_FILES, base_signature_sequence=signature["release_sequence"],
                  release_sequence=args.sequence, allowed_changes=sorted(ALLOWLIST),
                  allowed_removals=sorted(REMOVED), expected_files=BASE_FILES,
                  reviewed_head=head, patches={name: web.sha(raw) for name, raw in patches.items()},
                  wrapper_sha256=WRAPPER_SHA, protected_modules_preserved=180, protected_modules_rebuilt=0,
                  frozen_main_body_preserved=True, development_main_body_substituted=False,
                  default_map="template_map", declared_max_players=4,
                  dormant_entry_map_omitted_from_new_candidate=True, original_entry_map_preserved=True,
                  online_authentication_changed=False, online_cheats_allowed=False, four_account_only=True,
                  real_money_payments=False, alias_install_performed=False, workshop_upload_performed=False,
                  game_started=False, multiplayer_hosting_verified=False)
    require_review_unchanged(snapshots, head)
    if not args.build:
        return result
    web.need(args.signing_key is not None, "--build requires --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    web.need(web.LUA_COMPILER.is_file(), "Reviewed Lua 5.1 compiler is unavailable")
    stage_runtime(base, destination, baseline, patches)
    manifest = pack.runtime.manifest(destination)
    changed = audit_changes(baseline, manifest, patches, protected)
    pack.runtime.require_production(destination)
    pack.handoff.require_single_map(destination)
    web.need(pack.handoff.configured_ids(destination) == pack.handoff.configured_ids(base),
             "Frozen four-account access list changed")
    web.protect_runtime_lua.syntax_check([destination / MAIN, destination / PROBE], web.LUA_COMPILER)
    require_base_unchanged(base, baseline, metadata)
    require_review_unchanged(snapshots, head)
    trusted_snapshot(destination, trusted)
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        _, authenticated, signed, _ = pack.authenticate(destination)
        web.need(authenticated["content_sha256"] == manifest["content_sha256"]
                 and signed["key_id"] == signature["key_id"], "Signed multiplayer identity or key mismatch")
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    require_review_unchanged(snapshots, head)
    result.update(status="SIGNED_MULTIPLAYER_DIAGNOSTIC_REQUIRES_NATIVE_TEST",
                  content_sha256=manifest["content_sha256"], files=manifest["file_count"], changed=changed,
                  signature_valid=signed["signature_valid"], all_other_runtime_bytes_preserved=True,
                  plaintext_substitution=False, private_key_copied=False, destination=str(destination),
                  trusted_source=str(trusted), packaged=packaged, lua_syntax="PASS", native_dota_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_multiplayer_provenance.json", result)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--sequence", type=int, default=RELEASE_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    return result


def main():
    try:
        result = build(parser().parse_args())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(ok=False, error="multiplayer_candidate_build_failed", detail=str(error)[:500]),
                         ensure_ascii=True))
        return 2
    print(json.dumps(result, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
