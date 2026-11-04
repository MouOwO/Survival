"""Dynamic complete-candidate signing/VPK primitives; no SDK/install/journal.

Every build re-derives the complete raw ledger and checks the full unsigned
tree. A signing call is explicit and requires a pre-existing external key.
Source commits, original0104 metadata, archive bytes and all loaded tools are
rechecked. A signed package still requires ordinary/native/publish admission.
"""
from __future__ import annotations

from contextlib import contextmanager
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import cryptography

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
from complete_delivery_release_20261103 import build_release, ledger, production
import release_pending_inventory as pending

ROOT = TOOLS.parent
FRESH_EXECUTED_LF_SHA256 = {}


def _fresh_primitive(label, name):
    # Execute the exact bytes whose digest is retained, not a second later file
    # read or a previously cached historical publisher module. Parents stay
    # immutable; all policy adaptation is private to this package instance.
    path = ROOT / name
    raw = path.read_bytes()
    spec = importlib.util.spec_from_file_location(label, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(raw, str(path), "exec"), module.__dict__)
    FRESH_EXECUTED_LF_SHA256[name] = hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()
    return module


_protect_data = _fresh_primitive("complete_delivery_crypto", "tools/release_security/protect_data.py")
_handoff = _fresh_primitive("complete_delivery_handoff", "tools/publish_test_release.py")
_handoff.protect_data = _protect_data
pack = _fresh_primitive("complete_delivery_stream", "tools/stream_workshop_vpk.py")
pack.handoff, pack.protect_data, pack.runtime = _handoff, _protect_data, _handoff.runtime
inc = _fresh_primitive("complete_delivery_incremental", "tools/arcade_cleanup_20261027/incremental_vpk.py")
inc.pack = pack
ITEM = "3824360109"
TOOL = "tools/complete_delivery_release_20261103/package.py"
MAX_VOLUMES = 64
MAX_GIT_BYTES = 512 * 1024 * 1024
MAX_GIT_BLOB = 128 * 1024 * 1024
need = ledger.need
SIGNING_PYTHON_SHA256 = ledger.sha(Path(sys.executable).read_bytes())


def _lf(raw):
    return raw.replace(b"\r\n", b"\n")


def _loaded_paths():
    return sorted({TOOL, "tools/complete_delivery_release_20261103/build_release.py",
                   "tools/complete_delivery_release_20261103/ledger.py",
                   "tools/complete_delivery_release_20261103/production.py",
                   "tools/release_pending_inventory.py", "tools/build_runtime_release.py",
                   "tools/protect_runtime_lua.py", "tools/arcade_cleanup_20261027/incremental_vpk.py",
                   "tools/stream_workshop_vpk.py", "tools/publish_test_release.py",
                   "tools/release_security/protect_data.py", "tools/lua_protection_policy.json",
                   "tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem",
                   *production.LOADED_OPERATOR_LF_HASHES})


LOADED_OPERATOR_SHA256 = {name: ledger.sha(_lf((ROOT / name).read_bytes())) for name in _loaded_paths()}
for _name, _loaded in FRESH_EXECUTED_LF_SHA256.items():
    need(LOADED_OPERATOR_SHA256[_name] == _loaded, "primitive_changed_during_exact_byte_import:" + _name)
# Modules providing their own import-time identity must agree with the snapshot
# taken here. Existing immutable packaging primitives are retained byte-for-byte.
for _name, _module in (("tools/complete_delivery_release_20261103/production.py", production),
                       ("tools/complete_delivery_release_20261103/build_release.py", build_release),
                       ("tools/complete_delivery_release_20261103/ledger.py", ledger),
                       ("tools/release_pending_inventory.py", pending),
                       ("tools/protect_runtime_lua.py", production.protection),
                       ("tools/build_runtime_release.py", pack.runtime)):
    need(LOADED_OPERATOR_SHA256[_name] == _module.EXECUTED_SOURCE_LF_SHA256,
         "cached_loaded_operator_differs_before_package_import:" + _name)


def verify_operator(revision):
    """Only fixed operator bytes execute; an uncommitted wrapper cannot sign."""
    ledger.revision(revision)
    result = []; counts = Counter()
    for path, loaded in sorted(LOADED_OPERATOR_SHA256.items()):
        raw = pending._git(ROOT, "show", revision + ":" + path, counts=counts)
        actual = (ROOT / path).read_bytes()
        need(ledger.sha(_lf(raw)) == ledger.sha(_lf(actual)) == loaded,
             "loaded_package_operator_not_exact_commit:" + path)
        result.append({"path": path, "revision": revision, "git_sha256": ledger.sha(raw),
                       "loaded_lf_sha256": loaded, "normalization": "CRLF_TO_LF"})
    return result


def external_tree(rows):
    """External VPK offsets are per-volume, so total payload need not fit u32."""
    by_path = {}
    for row in rows:
        name = ledger.path(row["path"])
        need(name not in by_path and type(row["bytes"]) is int and 0 <= row["bytes"] <= pack.ARCHIVE_BYTES,
             "unique_native_sized_resource_required")
        by_path[name] = row
    # The historical make_tree assumes one inline payload. Use its canonical
    # path encoding only; build_volumes fills every entry's real CRC/length and
    # per-archive offset before any index is published.
    tree, ordered, _ = pack.make_tree([{**row, "bytes": 0} for row in rows])
    for item in ordered:
        item["row"] = by_path[item["row"]["path"]]
    return tree, ordered


def rotation_plan(entries, before, after, changed, removed, *,
                  empty_volume_policy="reject", allow_new_volumes=True):
    """O(N+K log K+K*A) metadata; A<=64. No payload/native/IO calls.

    Existing survivors retain their original archive. Only changed/additions
    can move to fix overflow. Empty interior archives require a separate repack;
    explicitly selected trim_trailing drops only a completely empty suffix.
    """
    need(empty_volume_policy in ("reject", "trim_trailing") and type(allow_new_volumes) is bool,
         "explicit_empty_volume_and_growth_policy_required")
    old, current = ledger.parent_rows(before), ledger.parent_rows(after)
    assignments = {}
    for entry in entries:
        name = ledger.path(entry["path"])
        need(name not in assignments and type(entry["archive"]) is int and 0 <= entry["archive"] < pack.INLINE,
             "unique_external_baseline_assignment_required")
        need(name in old and entry["bytes"] == old[name]["bytes"], "baseline_assignment_size_mismatch")
        assignments[name] = entry["archive"]
    indices = sorted(set(assignments.values()))
    need(indices and indices == list(range(len(indices))) and len(indices) <= MAX_VOLUMES
         and set(assignments) == set(old), "complete_contiguous_baseline_assignments_required")
    need(set(changed) == {name for name in current if old.get(name) != current[name]}
         and set(removed) == set(old) - set(current), "exact_reviewed_changes_and_deletions_required")
    tree, ordered = external_tree(after["files"])
    placed = {name: assignments.get(name, indices[-1]) for name in current}
    sizes = [0] * len(indices)
    for name, row in current.items(): sizes[placed[name]] += row["bytes"]
    moves = []
    for index in range(len(indices)):
        if sizes[index] <= pack.ARCHIVE_BYTES: continue
        candidates = sorted((name for name in changed if placed[name] == index),
                            key=lambda name: (-current[name]["bytes"], name))
        for name in candidates:
            amount = current[name]["bytes"]
            target = next((dest for dest in reversed(range(len(sizes)))
                           if dest != index and sizes[dest] + amount <= pack.ARCHIVE_BYTES), None)
            if target is None and allow_new_volumes:
                need(len(sizes) < MAX_VOLUMES, "external_volume_count_budget_exceeded")
                target = len(sizes); sizes.append(0)
            if target is None: continue
            placed[name] = target; sizes[index] -= amount; sizes[target] += amount
            moves.append({"path": name, "old_archive": index, "new_archive": target, "bytes": amount})
            if sizes[index] <= pack.ARCHIVE_BYTES: break
        need(sizes[index] <= pack.ARCHIVE_BYTES, "changed_resources_cannot_fit_without_unchanged_repack")
    groups = [[] for _ in sizes]
    for item in ordered: groups[placed[item["row"]["path"]]].append(item)
    dropped = []
    if empty_volume_policy == "trim_trailing":
        while groups and not groups[-1]:
            dropped.append(len(groups)-1); groups.pop(); sizes.pop()
    need(groups and all(groups), "empty_volume_requires_explicit_trailing_trim_or_separate_repack")
    need(all(placed[name] == archive for name, archive in assignments.items()
             if name in current and name not in changed), "unchanged_resource_archive_moved")
    rewritten = {assignments[name] for name in removed}
    for index, group in enumerate(groups):
        old_names = {name for name, value in assignments.items() if value == index}
        new_names = {item["row"]["path"] for item in group}
        if old_names != new_names or any(old.get(name) != current[name] for name in new_names):
            rewritten.add(index)
    rewritten.update(dropped)
    return {"tree": tree, "groups": groups, "rewritten": rewritten, "moves": moves,
            "dropped_empty_archives": sorted(dropped), "sizes": sizes,
            "empty_volume_policy": empty_volume_policy,
            "assignments": {name: placed[name] for name in sorted(placed)}}


def _git_sources(pins, source_raw, source_facts):
    """Re-read exact dual immutable Git objects, never trust supplied fact flags."""
    need(isinstance(source_raw, dict) and set(source_raw) == set(source_facts), "exact_source_bytes_and_facts_required")
    total = 0
    groups = {role: [] for role in ("game", "content")}
    for key, raw in source_raw.items():
        role, name = ledger.source_id(key).split(":", 1)
        fact = source_facts[key]
        need(fact.get("commit") == pins[role] and type(raw) is bytes and len(raw) <= MAX_GIT_BLOB,
             "source_fact_revision_or_size_invalid")
        total += len(raw); need(total <= MAX_GIT_BYTES, "source_recheck_byte_budget_exceeded")
        groups[role].append((key, name, raw, fact))
    for role, items in groups.items():
        if not items: continue
        repo = ROOT if role == "game" else pending.CONTENT
        request = "".join(pins[role] + ":" + name + "\n" for _, name, _, _ in items).encode()
        done = subprocess.run(["git", "--no-replace-objects", "-c", "safe.directory=" + repo.as_posix(),
                               "-C", str(repo), "cat-file", "--batch"], input=request,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, check=False)
        need(done.returncode == 0 and len(done.stdout) <= MAX_GIT_BYTES + 1024 * 1024,
             "bounded_dual_git_source_read_failed")
        offset = 0
        for key, _, raw, fact in items:
            end = done.stdout.find(b"\n", offset)
            need(end >= offset and end - offset <= 256, "git_source_batch_header_invalid")
            header = done.stdout[offset:end].split()
            need(len(header) == 3 and header[1] == b"blob" and header[0].decode() == fact.get("git_oid"),
                 "actual_immutable_git_object_mismatch:" + key)
            size = int(header[2]); need(0 <= size <= MAX_GIT_BLOB, "git_source_blob_size_invalid")
            expected = done.stdout[end+1:end+1+size];offset = end+2+size
            need(len(expected) == size and done.stdout[offset-1:offset] == b"\n", "git_source_batch_truncated")
            pointer = pending.parse_lfs_pointer(expected)
            if pointer:
                oid, count = pointer
                need(fact.get("lfs") is True and fact.get("lfs_content_verified") is True
                     and count == len(raw) and ledger.sha(raw) == oid, "resolved_lfs_source_proof_required")
            need((pointer is not None or expected == raw) and fact.get("sha256") == ledger.sha(raw),
                 "actual_immutable_source_bytes_mismatch:" + key)
        need(offset == len(done.stdout), "git_source_batch_contains_unrequested_data")
    return {key: ledger.sha(raw) for key, raw in sorted(source_raw.items())}


def semantic_readset(evidence, pins, source_raw, source_facts):
    """Include original producer readsets, not only pending source paths."""
    raw, facts = dict(source_raw), dict(source_facts)
    def add(key, value):
        role, _ = ledger.source_id(key).split(":", 1)
        git_raw = value["git_blob"] if isinstance(value, dict) else value
        content = value["content"] if isinstance(value, dict) else value
        need(type(git_raw) is bytes and type(content) is bytes, "original_source_bytes_required")
        oid = hashlib.sha1(b"blob " + str(len(git_raw)).encode() + b"\0" + git_raw).hexdigest()
        pointer = pending.parse_lfs_pointer(git_raw)
        fact = {"commit": pins[role], "git_oid": oid, **ledger.byte_fingerprint(content)}
        if pointer: fact.update(lfs=True, lfs_content_verified=True)
        if key in raw:
            need(raw[key] == content and all(facts[key].get(k) == fact[k] for k in ("commit", "git_oid", "sha256")),
                 "producer_source_readsets_disagree:" + key)
        else: raw[key], facts[key] = content, fact
    for compiler in compiler_entries(evidence["compiler"]):
        for key, value in compiler["source_bytes"].items(): add(key, value)
    for name, value in evidence["protection"]["source_bytes"].items(): add("game:" + name, value)
    for key, value in evidence["item_generator"]["input_bytes"].items(): add(key, value)
    for name, value in evidence["item_generator"]["output_bytes"].items(): add("game:" + name, value)
    for name, value in evidence["item_generator"]["content_mirrors"].items(): add("content:" + name, value)
    return raw, facts


def verify_producer_operators(evidence):
    records = []; counts = Counter()
    producers = [(f"compiler[{i}]", value) for i, value in enumerate(compiler_entries(evidence["compiler"]))]
    producers += [(name, evidence[name]) for name in ("protection", "item_generator")]
    for kind, kwargs in producers:
        revision = kwargs["source_revisions"]["operator"]
        tools = kwargs["operator_bytes" if kind == "item_generator" else "operator_tools"]
        for name, supplied in tools.items():
            ledger.path(name)
            actual = pending._git(ROOT, "show", revision + ":" + name, counts=counts)
            need(_lf(actual) == _lf(supplied), "original_producer_operator_bytes_not_git_commit:" + name)
            records.append({"producer": kind, "revision": revision, "path": name,
                            "git_sha256": ledger.sha(actual), "provided_sha256": ledger.sha(supplied)})
    return records


def _approved_ids(raw):
    ids = re.findall(rb'"([0-9]{17})"', raw)
    need(len(ids) == len(set(ids)) == 5 and re.search(rb"enabled\s*=\s*true", raw),
         "authenticated_five_account_roster_required")
    return sorted(value.decode("ascii") for value in ids)


@contextmanager
def admission_adapter(review_root, approved, expected_info, expected_client, expected_main, scene_maps, *, pack_api=None):
    """Keep canonical signature/hash/gate checks; adapt only evolved lobby code.

    Trusted files are separately constructed from immutable reviewed sources,
    never copied from an unverified candidate to manufacture self-trust.
    """
    api = pack if pack_api is None else pack_api
    h = api.handoff
    saved = {name: getattr(h, name) for name in ("ROOT", "POLICY", "steamids", "NATIVE_CLOUD_TESTERS",
             "NATIVE_CLOUD_ENTRY_LAYOUT", "NATIVE_CLOUD_INERT_CLIENT", "require_native_cloud_entry")}
    old_scenes = api.runtime.SCENE_MAPS
    def exact_ids(values):
        need(isinstance(values, list) and len(values) == len(set(values)) == 5
             and sorted(values) == approved, "candidate_changed_original_five_accounts")
        return sorted(values)
    def native(candidate, data):
        need(data == expected_info and data["addoninfo"].get("maps") == "ws4_entry"
             and data["addoninfo"].get("ws4_entry", {}).get("maxplayers") == "4"
             and data["addoninfo"].get("template_map", {}).get("maxplayers") == "4",
             "reviewed_entry4_template4_lobby_layout_required")
        for path, raw in (("scripts/vscripts/addon_game_mode_client.lua", expected_client),
                          ("scripts/vscripts/addon_game_mode.lua", expected_main)):
            need(api.protect_data.source_path(candidate, path).read_bytes() == raw,
                 "native_or_lobby_source_not_reviewed:" + path)
        need(h.configured_ids(candidate) == approved, "candidate_five_account_roster_changed")
        need(h.literal_flat_config(candidate, api.runtime.RELEASE_PROFILE) ==
             {"channel": "production", "native_cloud_roster_required": True}, "native_production_roster_required")
        need(h.literal_flat_config(candidate, "scripts/vscripts/config/player_web_auth.lua") ==
             {"enabled": True, "base_url": h.NATIVE_CLOUD_BASE}, "fixed_https_auth_origin_required")
        need(h.literal_flat_config(candidate, "scripts/vscripts/config/session_multiplayer_test.lua") ==
             {"enabled": False, "expected_map": "template_map"}, "session_only_storage_forbidden")
        cash = h.literal_flat_config(candidate, "scripts/vscripts/config/commerce_payment_access.lua")
        need(cash == {"enabled": True, "connection_helper": False, "expected_map": "template_map",
                      "base_url": h.NATIVE_CLOUD_BASE}, "original_authenticated_payment_boundary_required")
        actual_maps = {p.relative_to(candidate).as_posix() for p in (candidate / "maps").rglob("*.vpk")}
        need(actual_maps == set(scene_maps) | {"maps/ws4_entry.vpk", "maps/template_map.vpk"},
             "exact_reviewed_runtime_map_set_required")
        for path in actual_maps: api.protect_data.source_path(candidate, path)
        api.runtime.require_production(candidate)
    try:
        h.ROOT = review_root; h.POLICY = ROOT / "tools/release_security/protection_policy.json"
        h.steamids = exact_ids; h.NATIVE_CLOUD_TESTERS = approved
        h.NATIVE_CLOUD_ENTRY_LAYOUT = expected_info; h.NATIVE_CLOUD_INERT_CLIENT = expected_client
        h.require_native_cloud_entry = native
        api.runtime.SCENE_MAPS = set(scene_maps)
        yield
    finally:
        for name, value in saved.items(): setattr(h, name, value)
        api.runtime.SCENE_MAPS = old_scenes


def _full_tree(root, manifest, extras):
    expected = {row["path"] for row in manifest["files"]} | set(extras)
    need(inc.all_files(root) == expected, "complete_tree_has_extra_or_missing_files")
    for row in manifest["files"]:
        path = build_release._plain(root / row["path"], directory=False)
        need(build_release._file_hash(path) == ledger.fingerprint(row), "complete_tree_hash_mismatch:" + row["path"])


def verify_unsigned(*, inputs, reviewed_projection_raw, reviewed_projection_sha256,
                    unsigned_root, unsigned_review_raw, unsigned_review_sha256):
    reviewed = ledger.document(reviewed_projection_raw, reviewed_projection_sha256)
    actual = build_release.project(**inputs)
    need(ledger.canonical(reviewed) == ledger.canonical(actual), "reviewed_complete_projection_changed")
    report = ledger.document(unsigned_review_raw, unsigned_review_sha256)
    parent = ledger.document(inputs["parent_raw"], inputs["parent_sha256"])
    manifest = build_release.projected_manifest(parent, actual)
    root = build_release._plain(unsigned_root, directory=True)
    need(report.get("status") == "UNSIGNED_COMPLETE_TREE_NOT_AUTHENTICATED_OR_PUBLISHABLE"
         and report.get("source_revisions") == actual["source_revisions"]
         and report.get("projection_sha256") == actual["projection_sha256"]
         and report.get("candidate") == str(root) and report.get("content_sha256") == manifest["content_sha256"]
         and report.get("parent_manifest_sha256") == inputs["parent_sha256"]
         and report.get("all_target_files_rehashed") is True and report.get("hardlinks_created") == 0
         and report.get("signature_valid") is False and report.get("publication_ready") is False,
         "exact_unsigned_review_receipt_required")
    raw = (root / build_release.MANIFEST).read_bytes()
    need(raw == ledger.canonical(manifest) and ledger.sha(raw) == report.get("manifest_sha256"),
         "unsigned_manifest_not_exact_projection")
    marker = json.loads((root / build_release.MARKER).read_bytes())
    need(marker.get("projection_sha256") == actual["projection_sha256"]
         and marker.get("content_sha256") == manifest["content_sha256"]
         and marker.get("source_revisions") == actual["source_revisions"], "unsigned_marker_identity_mismatch")
    _full_tree(root, manifest, (build_release.MANIFEST, build_release.MARKER))
    return actual, parent, manifest, root


def verify_original_evidence(evidence, pins, manifest, bindings):
    """Consume original compiler/protection/generator receipts and real bytes."""
    need(isinstance(evidence, dict) and set(evidence) == {"compiler", "protection", "item_generator"},
         "complete_original_semantic_evidence_required")
    answers = {}; compiler_results = []
    for kwargs in compiler_entries(evidence["compiler"]):
        producers = kwargs.get("source_revisions", {})
        need(set(producers) == {"game", "content", "operator"}
             and all(producers.get(role) == pins[role] for role in ("game", "content")),
             "semantic_evidence_runtime_source_mismatch")
        ledger.revision(producers["operator"])
        compiler_results.append(ledger.verify_compiler_receipt(**kwargs))
    if isinstance(evidence["compiler"], list):
        merged = {}
        for result in compiler_results:
            for name, value in result["outputs"].items():
                need(name not in merged or merged[name] == value,
                     "independent_compiler_receipts_conflict:" + name)
                merged[name] = value
        answers["compiler"] = {"outputs": merged, "original_receipts": compiler_results}
    else:
        answers["compiler"] = compiler_results[0]
    for name, verify in (("protection", ledger.verify_protection_receipt),
                         ("item_generator", ledger.verify_item_generator_receipt)):
        kwargs = evidence[name]
        producers = kwargs.get("source_revisions", {})
        need(set(producers) == {"game", "content", "operator"}
             and all(producers.get(role) == pins[role] for role in ("game", "content")),
             "semantic_evidence_runtime_source_mismatch")
        ledger.revision(producers["operator"])
        answers[name] = verify(**kwargs)
    rows = {row["path"]: ledger.fingerprint(row) for row in manifest["files"]}
    compiled = answers["compiler"]["outputs"]
    protected = answers["protection"]["protected_outputs"]
    overrides = answers["protection"]["production_overrides"]
    generated = answers["item_generator"]["outputs"]
    for name, output in {**compiled, **protected, **overrides}.items():
        need(rows.get(name) == output, "original_semantic_output_not_in_complete_manifest:" + name)
    for binding in bindings:
        name, kind = binding["resource"], binding["kind"]
        expected = (compiled if kind == "compiled" else protected if kind == "protected"
                    else overrides if kind == "production_override" else generated if kind == "generated" else None)
        if expected is not None:
            need(name in expected and expected[name] == binding["output"],
                 "typed_scope_binding_missing_original_semantic_receipt:" + name)
    return answers


def compiler_entries(value):
    result = value if isinstance(value, list) else [value]
    need(1 <= len(result) <= 32 and all(isinstance(row, dict) for row in result),
         "bounded_original_compiler_receipt_list_required")
    return result


def sign_package(*, inputs, reviewed_projection_raw, reviewed_projection_sha256,
                 unsigned_root, unsigned_review_raw, unsigned_review_sha256,
                 source_raw, source_facts, parent_root, parent_vpk, baseline_package_raw,
                 baseline_package_sha256, overlay, trusted, view, output, key=None, build=False,
                 semantic_evidence, package_operator_revision,
                 empty_volume_policy="reject", reuse="copy"):
    """Explicit signing primitive. This function is never called by default.

    Default performs the full read-only preflight and rejects a key argument.
    Explicit build=True supplies a pre-existing external Ed25519 key. The
    returned signed package is NOT upload/native admission.
    No SDK, install, game process, formal journal or key generation exists here.
    """
    actual, parent, target, unsigned = verify_unsigned(
        inputs=inputs, reviewed_projection_raw=reviewed_projection_raw,
        reviewed_projection_sha256=reviewed_projection_sha256, unsigned_root=unsigned_root,
        unsigned_review_raw=unsigned_review_raw, unsigned_review_sha256=unsigned_review_sha256)
    pins = actual["source_revisions"]
    need(type(build) is bool, "explicit_build_boolean_required")
    need(build or key is None, "private_key_only_with_explicit_build")
    tools = verify_operator(package_operator_revision)
    need(ledger.sha(Path(sys.executable).read_bytes()) == SIGNING_PYTHON_SHA256,
         "loaded_signing_python_changed")
    facts = ledger.document(inputs["facts_raw"], inputs["facts_sha256"])["sources"]
    need(set(facts) <= set(source_facts)
         and all(source_facts[name] == value for name, value in facts.items()), "all_complete_scope_source_facts_required")
    original_evidence = verify_original_evidence(semantic_evidence, pins, target,
                                                actual["coverage_ledger"]["resource_bindings"])
    source_raw, source_facts = semantic_readset(semantic_evidence, pins, source_raw, source_facts)
    source_hashes = _git_sources(pins, source_raw, source_facts)
    producer_operators = verify_producer_operators(semantic_evidence)
    baseline_raw = pending.BASELINE.read_bytes()
    need(ledger.sha(baseline_raw) == pending.BASELINE_SHA256, "fixed_0104_source_baseline_changed")
    baseline = json.loads(baseline_raw)
    need(inputs["parent_sha256"] == baseline["parent_manifest_sha256"]
         and parent["content_sha256"] == baseline["parent_content_sha256"]
         and baseline["parent_sequence"] == 2026110104, "authenticated0104_parent_required")
    base = build_release._plain(parent_root, directory=True)
    base_vpk = build_release._plain(parent_vpk, directory=False)
    need((base / build_release.MANIFEST).read_bytes() == inputs["parent_raw"], "parent_manifest_bytes_changed")
    old, old_doc, old_meta = inc.metadata(base)
    need(old == parent, "parent_metadata_differs_from_reviewed_scope")
    h = pack.handoff
    policy, public = h.trusted_policy(h.POLICY)
    authenticated = pack.verify_signed_snapshot(old, old_doc, public, policy["integrity"]["minimum_release_sequence"],
                                                policy["integrity"]["trusted_key_id"])
    need(authenticated["release_sequence"] == 2026110104, "wrong_signed_baseline_sequence")
    _full_tree(base, parent, (build_release.MANIFEST, build_release.SIGNATURE))
    expected_package = ledger.document(baseline_package_raw, baseline_package_sha256)
    need(expected_package.get("parent_manifest_sha256") == inputs["parent_sha256"]
         and expected_package.get("release_sequence") == 2026110104
         and expected_package.get("steam_manifest") == baseline["official_parent_manifest"], "explicit_published_baseline_package_pin_required")
    need(pack.package_inventory(base_vpk) == expected_package.get("files"), "published_baseline_vpk_hash_set_changed")
    pack.verify_vpk(base_vpk, old)
    destinations = [build_release._plain(path, exists=False) for path in (overlay, trusted, view, output)]
    overlay, trusted, view, output = destinations
    for path in destinations:
        need(not path.is_relative_to(ROOT.parents[2]), "package_outputs_must_be_outside_game_content_trees")
    inc.disjoint([base, base_vpk.parent, unsigned, *destinations])
    need(reuse in ("copy", "hardlink"), "explicit_archive_reuse_policy_required")
    if build:
        key = build_release._plain(key, directory=False)
        need(not key.is_relative_to(ROOT.parents[2]) and not key.is_relative_to(base)
             and not key.is_relative_to(unsigned), "existing_external_private_key_required")
        need(all(not key.is_relative_to(path) and not path.is_relative_to(key.parent) for path in destinations),
             "signing_key_and_outputs_overlap")
    if reuse == "hardlink":
        need(inc.ancestor(output).stat().st_dev == base_vpk.stat().st_dev, "archive_hardlink_requires_same_volume")
    need(inc.ancestor(view).stat().st_dev == base.stat().st_dev, "unchanged_view_links_require_parent_volume")
    required = set(h.GATE_FILES) | set(h.NATIVE_CLOUD_ENTRY_GATE_FILES) | {h.ACCESS_FILE,
                "scripts/vscripts/systems/hosted_lobby.lua", "scripts/vscripts/systems/hosted_lobby_client.lua"}
    needs_source = required | set(production.OVERRIDES) | {production.ACCESS}
    need({"game:" + name for name in needs_source} <= set(source_raw), "immutable_admission_and_lobby_sources_required")
    selected_sources = {name: source_raw["game:" + name] for name in needs_source}
    parent_policy = {name: pack.protect_data.source_path(base, name).read_bytes()
                     for name in (*production.OVERRIDES, production.ACCESS)}
    production_targets, policy_reviews = production.transform_overrides(selected_sources, parent_policy)
    approved = _approved_ids(parent_policy[production.ACCESS])
    expected_files = {name: production_targets.get(name, selected_sources[name]) for name in required}
    expected_files.update({name: production_targets[name] for name in production.OVERRIDES})
    for name, raw in expected_files.items():
        need((unsigned / name).read_bytes() == raw, "unsigned_admission_or_production_policy_source_mismatch:" + name)
    info = h.kv(production_targets["addoninfo.txt"].decode("utf8"))
    scenes = {row["path"] for row in target["files"] if row["path"].startswith("maps/") and row["path"].endswith(".vpk")}
    scenes -= {"maps/ws4_entry.vpk", "maps/template_map.vpk"}
    rotation = rotation_plan(inc.read_entries(base_vpk), old, target, set(actual["changed_runtime_paths"]),
                             set(actual["removed_runtime_paths"]), empty_volume_policy=empty_volume_policy)
    active = set(range(len(rotation["groups"])))
    rewritten_active = active & rotation["rewritten"]
    space = inc.capacity(view, output, 2 * sum(actual["changed_resources"][name]["bytes"] for name in actual["changed_resources"]),
                         sum(rotation["sizes"][index] for index in rewritten_active),
                         pack.HEADER.size + len(rotation["tree"]) + 48,
                         sum(rotation["sizes"][index] for index in active - rewritten_active) if reuse == "copy" else 0)
    if not build:
        return {"kind": "READ_ONLY_COMPLETE_SIGNED_PACKAGE_PREFLIGHT_NOT_SIGNED", "dry_run": True,
                "source_revisions": pins, "package_operator_revision": package_operator_revision,
                "original_evidence": original_evidence, "producer_operator_bindings": producer_operators,
                "projection_sha256": actual["projection_sha256"], "full_manifest": target,
                "archive_plan": {**{key: value for key, value in rotation.items() if key not in ("tree", "groups", "rewritten")},
                                 "rewritten": sorted(rotation["rewritten"])}, "disk_preflight": space,
                "executed_operator_inputs": tools, "source_sha256s": source_hashes,
                "signing_key_read": False, "signature_valid": False, "files_written": 0,
                "sdk_calls": 0, "journal_writes": 0, "publication_ready": False}
    need(verify_operator(package_operator_revision) == tools, "operator_changed_before_new_stage_writes")
    # All authority/source/fullhash/capacity checks above precede any key read.
    # Preserve failed new stages and transcript; no old package is ever removed.
    overlay.mkdir(parents=True, exist_ok=False); trusted.mkdir(parents=True, exist_ok=False)
    transcript_path = trusted / "package_transcript.json"
    transcript = {"status": "PREFLIGHT_PASSED_KEY_NOT_YET_READ", "source_revisions": pins,
                  "package_operator_revision": package_operator_revision,
                  "projection_sha256": actual["projection_sha256"], "unsigned_review_sha256": unsigned_review_sha256,
                  "parent_manifest_sha256": inputs["parent_sha256"], "content_sha256": target["content_sha256"],
                  "full_manifest": target, "original_evidence": original_evidence,
                  "changed_runtime_paths": actual["changed_runtime_paths"], "removed_runtime_paths": actual["removed_runtime_paths"],
                  "sdk_calls": 0, "journal_writes": 0, "publication_ready": False}
    pack.runtime.atomic_write_json(transcript_path, transcript)
    for name in actual["changed_runtime_paths"]:
        inc.copy_new(unsigned / name, overlay / name, {"path": name, **actual["changed_resources"][name]})
    inc.write_new(overlay / build_release.MANIFEST, ledger.canonical(target))
    for name in required:
        inc.write_new(trusted / name, expected_files[name])
    for name in ("tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem"):
        inc.write_new(trusted / name, (ROOT / name).read_bytes())
    need(verify_operator(package_operator_revision) == tools, "operator_changed_before_key_use")
    signature = pack.protect_data.sign_manifest(overlay / build_release.MANIFEST, key,
                                               overlay / build_release.SIGNATURE, build_release.SEQUENCE)
    new, document, signed_metadata = inc.metadata(overlay)
    checked_signature = pack.verify_signed_snapshot(new, document, public,
                            policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(new == target and checked_signature["release_sequence"] == build_release.SEQUENCE,
         "new_signed_manifest_or_sequence_mismatch")
    transcript["status"] = "SIGNED_MANIFEST_VERIFIED_FULL_VIEW_PENDING"
    pack.runtime.atomic_write_json(transcript_path, transcript)
    with admission_adapter(trusted, approved, info, production_targets["scripts/vscripts/addon_game_mode_client.lua"],
                           selected_sources["scripts/vscripts/addon_game_mode.lua"], scenes):
        sources, merged = inc.validate_merged(base, overlay, old, target, trusted)
        need(merged == set(actual["changed_runtime_paths"]), "merged_dynamic_scope_changed")
        inc.materialize(view, sources, merged, target, signed_metadata)
        _, verified, signed, view_meta = pack.authenticate(view)
        need(verified == target and signed == checked_signature, "full_signed_candidate_authentication_mismatch")
        transcript["status"] = "FULL_SIGNED_VIEW_AUTHENTICATED_VPK_PENDING"
        pack.runtime.atomic_write_json(transcript_path, transcript)
        verification, package_files = inc.build_volumes(view, output, base_vpk, rotation["tree"], rotation["groups"],
                                                       rewritten_active, target, reuse)
        pack.verify_vpk(output / (ITEM + ".vpk"), target)
        pack.inventory_unchanged(view, view_meta)
    need(inc.all_files(output) == {row["name"] for row in package_files}, "package_directory_contains_old_or_unknown_files")
    pack.inventory_unchanged(base, old_meta); pack.inventory_unchanged(overlay, signed_metadata)
    _full_tree(base, old, (build_release.MANIFEST, build_release.SIGNATURE))
    need(pack.package_inventory(base_vpk) == expected_package["files"], "parent_package_changed_during_signing")
    need(verify_operator(package_operator_revision) == tools, "operator_changed_during_package_build")
    need(_git_sources(pins, source_raw, source_facts) == source_hashes, "immutable_sources_changed_during_package_build")
    need(ledger.sha(Path(sys.executable).read_bytes()) == SIGNING_PYTHON_SHA256,
         "signing_python_changed_during_package_build")
    report = {"schema": 1, "kind": "SIGNED_COMPLETE_DYNAMIC_CANDIDATE_REQUIRES_NATIVE_AND_PUBLICATION_ADMISSION",
              "source_revisions": pins, "projection_sha256": actual["projection_sha256"],
              "package_operator_revision": package_operator_revision, "original_evidence": original_evidence,
              "producer_operator_bindings": producer_operators,
              "signing_execution": {"python_executable_sha256": SIGNING_PYTHON_SHA256,
                                    "python_version": sys.version, "cryptography_version": cryptography.__version__},
              "scope_sha256": inputs["scope_sha256"], "facts_sha256": inputs["facts_sha256"],
              "unsigned_review_sha256": unsigned_review_sha256, "baseline_package_sha256": baseline_package_sha256,
              "parent_manifest_sha256": inputs["parent_sha256"], "content_sha256": target["content_sha256"],
              "manifest_sha256": ledger.sha(ledger.canonical(target)), "release_sequence": build_release.SEQUENCE,
              "files": target["file_count"], "payload_bytes": target["bytes"], "full_manifest": target,
              "changed_runtime_paths": actual["changed_runtime_paths"], "removed_runtime_paths": actual["removed_runtime_paths"],
              "archive_plan": {key: value for key, value in rotation.items() if key not in ("tree", "groups")},
              "package_files": package_files, "verification": verification, "disk_preflight": space,
              "executed_operator_inputs": tools, "source_sha256s": source_hashes,
              "production_policy_reviews": policy_reviews, "signature": signature, "signature_valid": True,
              "full_candidate_authenticated": True, "all_vpk_resources_crc_and_dual_hash_verified": True,
              "five_accounts_and_four_players_preserved": True, "hosted_lobby_source_preserved": True,
              "native_admission_verified": False, "sdk_calls": 0, "journal_writes": 0, "installed": False,
              "key_copied": False, "publication_ready": False}
    report["archive_plan"]["rewritten"] = sorted(report["archive_plan"]["rewritten"])
    pack.runtime.atomic_write_json(transcript_path, {**report, "status": "SIGNED_FULL_VPK_VERIFIED_NATIVE_ADMISSION_PENDING"})
    return report
