"""Complete immutable-source recipe for the canonical release pipeline.

Cold planning indexes the dual Git trees once through the strict collector.
Integrity stages stream the precise signed tree/VPK; no game timer, SDK call,
background watcher, journal mutation or install occurs during import/plan.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager, ExitStack
import hashlib
import importlib
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
sys.dont_write_bytecode = True

REPORT = ROOT / "output/complete_delivery_release_20261103"
INPUT_FILE = REPORT / "pipeline_inputs.json"
JOURNAL = ROOT / "output/four_accounts_20261022/steam_upload_state.json"
ITEM, APP, OWNER, SEQUENCE = "3824360109", 570, "76561198845461206", 2026110302
BASE_SEQUENCE = 2026110104
BASE_CONTENT = "6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f"
BASE_REPORT = ROOT / "output/admission_five_20261101/package.json"
BASE_REPORT_SHA = "70306be7a42962172fddce88bc8c4ac12dc5e73db1119d97839b871115aa01b6"
BASELINE_RECORD = ROOT / "publishing/workshop/account_admission_20261101_v01.json"
BASELINE_RECORD_SHA = "663ae83f0cb138fdde2baf4af05b48af14edc496aab0308a51c3f8abfd3b88a4"
TOOL = "tools/complete_delivery_release_20261103/pipeline_recipe.py"
LOADED_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
MAX_CONTROL = 2 * 1024 * 1024
_MAX_ORDINARY = 30


def dependencies():
    """Load only the fixed reviewed tool family; no caller-selectable code."""
    from complete_delivery_release_20261103 import collect_inputs, build_release, ledger, package, production
    return SimpleNamespace(collect=collect_inputs, build=build_release, ledger=ledger,
                           package=package, production=production)


def need(value, reason):
    if not value:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False) + "\n").encode("ascii")


def checked_json(spec, *, limit=MAX_CONTROL):
    need(isinstance(spec, dict) and set(spec) == {"path", "sha256"}, "explicit_exact_document_pin_required")
    d = dependencies()
    d.ledger.digest(spec["sha256"])
    path = Path(spec["path"])
    if not path.is_absolute():
        need(not path.drive and ".." not in path.parts, "canonical_relative_document_path_required")
        path = ROOT / path
    path = d.build._plain(path, directory=False)
    need(path.stat().st_size <= limit, "pipeline_control_byte_budget_exceeded")
    raw = path.read_bytes()
    need(len(raw) <= limit and sha(raw) == spec["sha256"], "pipeline_control_pin_changed:" + path.name)
    value = json.loads(raw)
    need(isinstance(value, dict), "structured_pipeline_control_required")
    return value, raw


def config():
    d = dependencies()
    path = d.build._plain(INPUT_FILE, directory=False)
    need(path.stat().st_size <= MAX_CONTROL, "pipeline_inputs_byte_budget_exceeded")
    raw = path.read_bytes()
    value = json.loads(raw)
    required = {"schema", "source_revisions", "package_operator_revision", "collection_request",
                "projection", "unsigned_review", "baseline_package", "parent_root", "parent_vpk",
                "parent_trusted", "unsigned_root", "artifact_root", "allowed_artifact_root",
                "allowed_unsigned_root", "candidate"}
    need(isinstance(value, dict) and set(value) >= required and value["schema"] == 1,
         "complete_fixed_pipeline_inputs_required")
    need(set(value["source_revisions"]) == {"game", "content"}, "pipeline_dual_source_revisions_required")
    for revision in (*value["source_revisions"].values(), value["package_operator_revision"]):
        d.ledger.revision(revision)
    need(set(value["candidate"]) == {"overlay", "trusted", "view", "output"}, "four_exact_candidate_directories_required")
    destinations = []
    for key, rawpath in value["candidate"].items():
        p = Path(rawpath)
        d.build._plain(p, exists=os.path.lexists(p), directory=True if os.path.lexists(p) else None)
        need(not p.is_relative_to(ROOT.parents[2]), "candidate_outputs_must_be_outside_addon_mounts")
        destinations.append(p)
    need(len(set(destinations)) == 4, "candidate_directories_must_be_distinct")
    return value, raw


def __getattr__(name):
    table = {"VIEW": "view", "OUTPUT": "output", "TRUSTED": "trusted", "OVERLAY": "overlay"}
    if name in table:
        return Path(config()[0]["candidate"][table[name]])
    if name in {"BASE", "PARENT_VPK", "BASE_VPK", "BASE_TRUSTED", "UNSIGNED"}:
        return Path(config()[0][{"BASE": "parent_root", "PARENT_VPK": "parent_vpk", "BASE_VPK": "parent_vpk",
                                "BASE_TRUSTED": "parent_trusted", "UNSIGNED": "unsigned_root"}[name]])
    if name in {"pack", "inc", "ledger"}:
        return getattr(dependencies().package, name) if name != "ledger" else dependencies().ledger
    raise AttributeError(name)


def verify_facade_operator(revision):
    d = dependencies()
    d.ledger.revision(revision)
    raw = Path(__file__).read_bytes()
    need(sha(raw.replace(b"\r\n", b"\n")) == LOADED_LF_SHA256, "recipe_changed_after_import")
    declared = d.package.pending._git(ROOT, "show", revision + ":" + TOOL)
    need(declared.replace(b"\r\n", b"\n") == raw.replace(b"\r\n", b"\n"),
         "recipe_not_in_immutable_package_operator")
    return {"path": TOOL, "revision": revision, "git_sha256": sha(declared),
            "executed_lf_sha256": LOADED_LF_SHA256}


def verify_operator_paths(paths, package_operator_revision):
    """Bind a bounded actual executed Python closure to one immutable operator.

    Callers supply import-time LF digests, never post-hoc trust flags. One Git
    batch call reads all exact revision:path objects; no module code is executed.
    """
    d = dependencies()
    d.ledger.revision(package_operator_revision)
    need(isinstance(paths, dict) and 0 < len(paths) <= 256, "bounded_executed_operator_map_required")
    physical, names = {}, sorted(paths)
    total = 0
    for name in names:
        d.ledger.path(name); d.ledger.digest(paths[name])
        need(name.startswith("tools/") and name.endswith(".py"), "project_python_operator_paths_only")
        path = d.build._plain(ROOT / name, directory=False)
        need(path.stat().st_size <= MAX_CONTROL, "operator_file_byte_budget_exceeded")
        raw = path.read_bytes()
        total += len(raw); need(total <= 64*1024*1024, "operator_closure_byte_budget_exceeded")
        need(sha(raw.replace(b"\r\n", b"\n")) == paths[name], "operator_changed_after_execution:" + name)
        physical[name] = raw
    import subprocess
    query = "".join(package_operator_revision + ":" + name + "\n" for name in names).encode("utf8")
    done = subprocess.run(["git", "--no-replace-objects", "-c", "safe.directory=" + ROOT.as_posix(),
        "-C", str(ROOT), "cat-file", "--batch"], input=query, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=120, check=False)
    need(done.returncode == 0 and len(done.stdout) <= 64*1024*1024 + len(names)*256,
         "immutable_operator_batch_read_failed")
    position, git_bytes, bindings = 0, 0, {}
    for name in names:
        end = done.stdout.find(b"\n", position)
        need(position <= end <= position+256, "invalid_operator_batch_header")
        head = done.stdout[position:end].split()
        need(len(head) == 3 and head[1] == b"blob", "operator_path_is_not_git_blob")
        size = int(head[2]); need(0 <= size <= MAX_CONTROL, "git_operator_blob_too_large")
        git_bytes += size
        need(git_bytes <= 64*1024*1024, "git_operator_closure_byte_budget_exceeded")
        raw = done.stdout[end+1:end+1+size]
        position = end+2+size
        need(len(raw) == size and done.stdout[position-1:position] == b"\n", "truncated_operator_git_blob")
        need(raw.replace(b"\r\n", b"\n") == physical[name].replace(b"\r\n", b"\n"),
             "executed_operator_is_not_declared_commit:" + name)
        bindings[name] = {"revision": package_operator_revision, "git_oid": head[0].decode("ascii"),
            "git_sha256": sha(raw), "executed_lf_sha256": paths[name]}
    need(position == len(done.stdout), "unrequested_operator_batch_bytes")
    return {"bindings": bindings, "git_batch_calls": 1, "files": len(bindings), "physical_bytes": total}


def context(operator_revision=None):
    """One fresh strict complete collection; no signature/SDK/install writes."""
    d = dependencies()
    cfg, cfgraw = config()
    operator = operator_revision or cfg["package_operator_revision"]
    need(operator == cfg["package_operator_revision"], "configured_package_operator_mismatch")
    operator_binding = verify_facade_operator(operator)
    package_operator_bindings = d.package.verify_operator(operator)
    request, request_raw = checked_json(cfg["collection_request"])
    need(request.get("allow_uncommitted_collector_diagnostic") is not True,
         "diagnostic_collection_never_admits_release")
    pins = request.get("source_revisions", {})
    need(set(pins) == {"game", "content", "operator"} and
         {k: pins[k] for k in ("game", "content")} == cfg["source_revisions"],
         "collection_runtime_source_mismatch")
    collection = d.collect.collect(request)
    need(collection.get("status") == "COMPLETE_IMMUTABLE_INPUTS_COLLECTED_NOT_SIGNED"
         and collection.get("diagnostic_only") is False and not collection.get("blockers"),
         "complete_strict_collection_required")
    reviewed, reviewed_raw = checked_json(cfg["projection"], limit=d.ledger.MAX_DOCUMENT)
    need(reviewed_raw == collection["projection_raw"], "reviewed_projection_differs_from_fresh_collection")
    baseline_package, baseline_raw = checked_json(cfg["baseline_package"], limit=d.ledger.MAX_DOCUMENT)
    unsigned_review, unsigned_raw = checked_json(cfg["unsigned_review"])
    return SimpleNamespace(config=cfg, config_raw=cfgraw, config_sha256=sha(cfgraw),
        collection_request=request, collection_request_raw=request_raw, collection=collection,
        inputs=collection["inputs"], projection=collection["projection"], projection_raw=reviewed_raw,
        source_raw=collection["source_raw"], source_facts=collection["source_facts"],
        semantic_evidence=collection["semantic_evidence"], parent_root=Path(cfg["parent_root"]),
        parent_vpk=Path(cfg["parent_vpk"]), baseline_package=baseline_package,
        baseline_package_raw=baseline_raw, unsigned_root=Path(cfg["unsigned_root"]),
        unsigned_review=unsigned_review, unsigned_review_raw=unsigned_raw,
        operator_revision=operator, operator_binding=operator_binding,
        package_operator_bindings=package_operator_bindings, **{
            key: Path(cfg["candidate"][key]) for key in ("overlay", "trusted", "view", "output")})


def controls_unchanged(ctx):
    need(INPUT_FILE.read_bytes() == ctx.config_raw, "pipeline_inputs_changed_during_operation")
    for key in ("collection_request", "projection", "unsigned_review", "baseline_package"):
        checked_json(ctx.config[key], limit=dependencies().ledger.MAX_DOCUMENT)
    verify_facade_operator(ctx.operator_revision)


def baseline_evidence():
    report, _ = checked_json({"path": str(BASE_REPORT), "sha256": BASE_REPORT_SHA}, limit=16*1024*1024)
    record, raw = checked_json({"path": str(BASELINE_RECORD), "sha256": BASELINE_RECORD_SHA})
    receipt, receipt_raw = checked_json(record["download_receipt"], limit=16*1024*1024)
    need(record.get("status") == "UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED"
         and record.get("release_sequence") == BASE_SEQUENCE and record.get("content_sha256") == BASE_CONTENT
         and record.get("steam_manifest") == "7025356658517360342"
         and record.get("approved_accounts") == 5 and record.get("max_players") == 4
         and record.get("package_files") == report.get("package_files")
         and receipt.get("status") == "OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED"
         and receipt.get("release_sequence") == BASE_SEQUENCE and receipt.get("content_sha256") == BASE_CONTENT
         and receipt.get("steam_manifest") == record["steam_manifest"]
         and receipt.get("verification", {}).get("signature_valid") is True
         and receipt.get("verification", {}).get("package_files") == report.get("package_files"),
         "original_official0104_delivery_evidence_required")
    return {"report": report, "record": record, "receipt": receipt,
            "record_sha256": sha(raw), "receipt_sha256": sha(receipt_raw), "report_sha256": BASE_REPORT_SHA}


def require_parent_journal(state, report):
    need(state.get("uploaded") is True and state.get("status") == "SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST"
         and state.get("workshop_id") == ITEM and state.get("owner") == OWNER and state.get("app_id") == APP
         and state.get("visibility_requested") == 3 and state.get("release_sequence") == BASE_SEQUENCE
         and state.get("content_sha256") == BASE_CONTENT and state.get("package_files") == report["package_files"]
         and state.get("vpk_sha256") == report["vpk_sha256"] and state.get("legal_agreement_required") is False,
         "canonical_journal_is_not_verified0104_parent")


def baseline(*, full=True, require_current_journal=False):
    d = dependencies()
    cfg, _ = config()
    evidence = baseline_evidence()
    report = evidence["report"]
    root, vpk = d.build._plain(cfg["parent_root"], directory=True), d.build._plain(cfg["parent_vpk"], directory=False)
    manifest, document, metadata = d.package.inc.metadata(root)
    policy, public = d.package.pack.handoff.trusted_policy(d.package.pack.handoff.POLICY)
    signed = d.package.pack.verify_signed_snapshot(manifest, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    snap = d.package.pending._read_json(d.package.pending.BASELINE, d.package.pending.BASELINE_SHA256)
    need(sha(metadata[d.build.MANIFEST]) == snap["parent_manifest_sha256"]
         and manifest["content_sha256"] == snap["parent_content_sha256"] == BASE_CONTENT
         and signed["release_sequence"] == BASE_SEQUENCE, "actual_signed0104_parent_required")
    need(d.package.pack.package_inventory(vpk) == report["package_files"], "published0104_package_bytes_changed")
    if full:
        d.package._full_tree(root, manifest, (d.build.MANIFEST, d.build.SIGNATURE))
        d.package.pack.verify_vpk(vpk, manifest)
    if require_current_journal:
        require_parent_journal(json.loads(JOURNAL.read_bytes()), report)
    d.package.pack.inventory_unchanged(root, metadata)
    return {**report, "source_anchors": snap["source_anchors"],
            "parent_manifest_sha256": snap["parent_manifest_sha256"],
            "resource_origins_sha256": snap["resource_origins_sha256"],
            "official_download_receipt_sha256": evidence["receipt_sha256"],
            "full_parent_bytes_verified": bool(full)}, manifest


def resource_origins(ctx):
    d = dependencies()
    parent = d.ledger.document(ctx.inputs["parent_raw"], ctx.inputs["parent_sha256"])
    snap = d.package.pending._read_json(d.package.pending.BASELINE, d.package.pending.BASELINE_SHA256)
    need(snap["parent_manifest_sha256"] == ctx.inputs["parent_sha256"]
         and snap["parent_content_sha256"] == parent["content_sha256"], "origin_parent_binding_changed")
    origins = dict(snap["resource_origins"])
    need(set(origins) == {row["path"] for row in parent["files"]}
         and sha(canonical(origins)) == snap["resource_origins_sha256"], "exact_original_parent_origins_required")
    bindings = {row["resource"]: row for row in ctx.projection["coverage_ledger"]["resource_bindings"]}
    for name in ctx.projection["removed_runtime_paths"]:
        del origins[name]
    for name in ctx.projection["changed_runtime_paths"]:
        binding = bindings[name]
        origins[name] = {"kind": "COMPLETE_IMMUTABLE_TYPED_RUNTIME_BINDING",
            "resource_sha256": binding["output"]["sha256"], "resource_bytes": binding["output"]["bytes"],
            "parent_content_sha256": parent["content_sha256"],
            "source_revisions": ctx.config["source_revisions"],
            "collection_operator_revision": ctx.projection["source_revisions"]["operator"],
            "projection_sha256": ctx.projection["projection_sha256"], "binding": binding}
    need(set(origins) == {row["path"] for row in ctx.projection["projected_rows"]},
         "complete_resource_origin_set_required")
    return origins, snap["resource_origins_sha256"], sha(canonical(origins))


def make_plan(ctx):
    origins, old_origins_sha, new_origins_sha = resource_origins(ctx)
    return {"schema": 1, "kind": "COMPLETE_CANONICAL_CONSTRUCTION_PLAN_NOT_SIGNED",
        "dry_run": True, "workshop_id": ITEM, "release_sequence": SEQUENCE,
        "source_revisions": ctx.config["source_revisions"],
        "collection_source_revisions": ctx.projection["source_revisions"],
        "operator_revision": ctx.operator_revision, "recipe_operator_binding": ctx.operator_binding,
        "package_operator_bindings": ctx.package_operator_bindings,
        "pipeline_inputs_sha256": ctx.config_sha256,
        "projection_sha256": ctx.projection["projection_sha256"],
        "projection_document_sha256": sha(ctx.projection_raw),
        "original_receipts": ctx.collection["original_receipts"],
        "parent_manifest_sha256": ctx.inputs["parent_sha256"],
        "parent_resource_origins_sha256": old_origins_sha, "resource_origins_sha256": new_origins_sha,
        "baseline_report_sha256": BASE_REPORT_SHA, "baseline_record_sha256": BASELINE_RECORD_SHA,
        "files": ctx.projection["files"], "bytes": ctx.projection["bytes"],
        "changed_runtime_paths": ctx.projection["changed_runtime_paths"],
        "removed_runtime_paths": ctx.projection["removed_runtime_paths"],
        "candidate": ctx.config["candidate"], "control_pins": {key: ctx.config[key] for key in
            ("collection_request", "projection", "unsigned_review", "baseline_package")},
        "signature_valid": False, "signing_key_read": False, "sdk_calls": 0, "journal_writes": 0}


def reviewed_plan(path, expected_sha256, ctx=None):
    path = Path(path)
    need(path.resolve().is_relative_to(REPORT.resolve()) and path.resolve() != REPORT.resolve(),
         "reviewed_plan_must_be_beneath_fixed_report_directory")
    value, raw = checked_json({"path": str(path), "sha256": expected_sha256}, limit=16*1024*1024)
    need(canonical(value) == canonical(make_plan(ctx or context())), "reviewed_plan_changed")
    return value


def _admission_values(ctx):
    d = dependencies()
    h = d.package.pack.handoff
    required = set(h.GATE_FILES) | set(h.NATIVE_CLOUD_ENTRY_GATE_FILES) | {h.ACCESS_FILE,
                "scripts/vscripts/systems/hosted_lobby.lua", "scripts/vscripts/systems/hosted_lobby_client.lua"}
    names = required | set(d.production.OVERRIDES) | {d.production.ACCESS}
    selected = {name: ctx.source_raw["game:" + name] for name in names}
    parent = {name: (ctx.parent_root / name).read_bytes() for name in (*d.production.OVERRIDES, d.production.ACCESS)}
    outputs, _ = d.production.transform_overrides(selected, parent)
    approved = d.package._approved_ids(parent[d.production.ACCESS])
    info = h.kv(outputs["addoninfo.txt"].decode("utf8"))
    scenes = {row["path"] for row in ctx.projection["projected_rows"]
              if row["path"].startswith("maps/") and row["path"].endswith(".vpk")}
    scenes -= {"maps/ws4_entry.vpk", "maps/template_map.vpk"}
    expected = {name: outputs.get(name, selected[name]) for name in required}
    return approved, info, outputs["scripts/vscripts/addon_game_mode_client.lua"], selected["scripts/vscripts/addon_game_mode.lua"], scenes, expected


def verify_trusted_sources(ctx, expected):
    """The external trusted copy must match reviewed sources, never the view."""
    d = dependencies()
    wanted = dict(expected)
    for name in ("tools/release_security/protection_policy.json", "tools/release_security/trusted_public_key.pem"):
        wanted[name] = (ROOT / name).read_bytes()
    need(d.package.inc.all_files(ctx.trusted) == set(wanted) | {"package_transcript.json"},
         "trusted_source_exact_file_set_changed")
    for name, raw in wanted.items():
        path = d.build._plain(ctx.trusted / name, directory=False)
        need(path.read_bytes() == raw, "trusted_source_not_exact_reviewed_operator_or_source:" + name)


@contextmanager
def scene_maps(ctx=None):
    """Apply the same strict admission to both private build and actual SDK pack."""
    ctx = ctx or context()
    d = dependencies()
    approved, info, client, main, scenes, expected = _admission_values(ctx)
    verify_trusted_sources(ctx, expected)
    actual = importlib.import_module("stream_workshop_vpk")
    with ExitStack() as stack:
        seen = set()
        for api in (d.package.pack, actual):
            if id(api) in seen:
                continue
            seen.add(id(api))
            stack.enter_context(d.package.admission_adapter(ctx.trusted, approved, info, client, main, scenes, pack_api=api))
        yield
    controls_unchanged(ctx)


def _sign_args(ctx):
    return dict(inputs=ctx.inputs, reviewed_projection_raw=ctx.projection_raw,
        reviewed_projection_sha256=ctx.config["projection"]["sha256"],
        unsigned_root=ctx.unsigned_root, unsigned_review_raw=ctx.unsigned_review_raw,
        unsigned_review_sha256=ctx.config["unsigned_review"]["sha256"],
        source_raw=ctx.source_raw, source_facts=ctx.source_facts, parent_root=ctx.parent_root,
        parent_vpk=ctx.parent_vpk, baseline_package_raw=ctx.baseline_package_raw,
        baseline_package_sha256=ctx.config["baseline_package"]["sha256"],
        overlay=ctx.overlay, trusted=ctx.trusted, view=ctx.view, output=ctx.output,
        semantic_evidence=ctx.semantic_evidence, package_operator_revision=ctx.operator_revision,
        reuse="copy", empty_volume_policy="reject")


def build_signed(ctx, plan_path, plan_sha256, key):
    d = dependencies()
    destination = REPORT / "package.json"
    need(not destination.exists(), "signed_package_report_already_exists_preserve_candidate")
    reviewed_plan(plan_path, plan_sha256, ctx)
    baseline(full=True, require_current_journal=True)
    result = d.package.sign_package(**_sign_args(ctx), key=key, build=True)
    origins, parent_origin_sha, new_origin_sha = resource_origins(ctx)
    result.update(dry_run=False, payload_changed=False, workshop_upload_performed=False,
        status="BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION",
        workshop_id=ITEM, app_id=APP, owner=OWNER, candidate=str(ctx.view), trusted_source=str(ctx.trusted),
        output=str(ctx.output / (ITEM + ".vpk")), full_runtime_validator_passed=True,
        collection_source_revisions=result["source_revisions"],
        source_revisions=ctx.config["source_revisions"], source_revision=ctx.config["source_revisions"]["game"],
        operator_revision=ctx.operator_revision, operator_source_is_runtime_source=False,
        plan_sha256=plan_sha256, plan_path=str(plan_path), pipeline_inputs_sha256=ctx.config_sha256,
        baseline_report_sha256=BASE_REPORT_SHA, baseline_record_sha256=BASELINE_RECORD_SHA,
        authenticated_parent_manifest_sha256=ctx.inputs["parent_sha256"],
        authenticated_parent_content_sha256=BASE_CONTENT,
        parent_resource_origins_sha256=parent_origin_sha, resource_origins_sha256=new_origin_sha,
        resource_origins=origins, signed_manifest_sha256=d.package.pack.runtime.digest(ctx.view / d.build.MANIFEST),
        vpk_sha256=d.package.pack.runtime.digest(ctx.output / (ITEM + ".vpk")),
        vpk_bytes=(ctx.output / (ITEM + ".vpk")).stat().st_size,
        protected_modules_verified=len(result["original_evidence"]["protection"]["protected_outputs"]))
    controls_unchanged(ctx)
    need(not destination.exists(), "signed_package_report_already_exists_preserve_candidate")
    d.build._write_new(destination, canonical(result))
    return result


def verify_report_projection(report, ctx, target):
    """Evidence scope/counters must derive from the same complete projection."""
    expected = {
        "workshop_id": ITEM, "app_id": APP, "owner": OWNER,
        "candidate": str(ctx.view), "trusted_source": str(ctx.trusted),
        "output": str(ctx.output / (ITEM + ".vpk")), "full_runtime_validator_passed": True,
        "changed_runtime_paths": ctx.projection["changed_runtime_paths"],
        "removed_runtime_paths": ctx.projection["removed_runtime_paths"],
        "files": target["file_count"], "payload_bytes": target["bytes"],
        "content_sha256": target["content_sha256"], "manifest_sha256": sha(canonical(target)),
        "source_revision": ctx.config["source_revisions"]["game"],
        "package_operator_revision": ctx.operator_revision,
        "scope_sha256": ctx.inputs["scope_sha256"], "facts_sha256": ctx.inputs["facts_sha256"],
        "unsigned_review_sha256": ctx.config["unsigned_review"]["sha256"],
        "baseline_package_sha256": ctx.config["baseline_package"]["sha256"],
        "authenticated_parent_manifest_sha256": ctx.inputs["parent_sha256"],
        "authenticated_parent_content_sha256": BASE_CONTENT,
    }
    for name, value in expected.items():
        need(canonical(report.get(name)) == canonical(value), "signed_report_projection_field_changed:" + name)


def load_package(report_sha256, *, full=True):
    """Independently admit the exact signed tree, complete VPK and original proof."""
    d = dependencies()
    report, raw = checked_json({"path": str(REPORT / "package.json"), "sha256": report_sha256},
                               limit=d.ledger.MAX_DOCUMENT)
    ctx = context(report.get("operator_revision"))
    plan = reviewed_plan(report.get("plan_path", ""), report.get("plan_sha256", ""), ctx)
    need(report.get("status") == "BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION"
         and report.get("release_sequence") == SEQUENCE and report.get("source_revisions") == ctx.config["source_revisions"]
         and report.get("collection_source_revisions") == ctx.projection["source_revisions"]
         and report.get("pipeline_inputs_sha256") == ctx.config_sha256
         and report.get("projection_sha256") == ctx.projection["projection_sha256"]
         and report.get("dry_run") is False and report.get("payload_changed") is False
         and report.get("signature_valid") is True and report.get("workshop_upload_performed") is False,
         "signed_complete_report_identity_mismatch")
    baseline(full=full, require_current_journal=False)
    parent = d.ledger.document(ctx.inputs["parent_raw"], ctx.inputs["parent_sha256"])
    target = d.build.projected_manifest(parent, ctx.projection)
    verify_report_projection(report, ctx, target)
    original = d.package.verify_original_evidence(ctx.semantic_evidence, ctx.projection["source_revisions"],
                   target, ctx.projection["coverage_ledger"]["resource_bindings"])
    need(canonical(original) == canonical(report.get("original_evidence")), "original_producer_evidence_changed")
    source_raw, source_facts = d.package.semantic_readset(ctx.semantic_evidence, ctx.projection["source_revisions"],
                                                        ctx.source_raw, ctx.source_facts)
    source_hashes = d.package._git_sources(ctx.projection["source_revisions"], source_raw, source_facts)
    need(canonical(source_hashes) == canonical(report.get("source_sha256s")), "signed_original_source_readset_changed")
    need(canonical(ctx.package_operator_bindings) == canonical(report.get("executed_operator_inputs")),
         "signed_executed_package_operator_bindings_changed")
    need(canonical(d.package.verify_producer_operators(ctx.semantic_evidence)) == canonical(report.get("producer_operator_bindings")),
         "signed_original_producer_operator_bindings_changed")
    origins, parent_origins, new_origins = resource_origins(ctx)
    need(report.get("resource_origins") == origins and report.get("resource_origins_sha256") == new_origins
         and report.get("parent_resource_origins_sha256") == parent_origins,
         "complete_resource_origin_projection_changed")
    with scene_maps(ctx), d.package.inc.trusted_source(ctx.trusted):
        if full:
            _, manifest, signed, snapshots = d.package.pack.authenticate(ctx.view)
            d.package._full_tree(ctx.view, target, (d.build.MANIFEST, d.build.SIGNATURE))
            d.package.pack.verify_vpk(ctx.output / (ITEM + ".vpk"), manifest)
        else:
            manifest, document, snapshots = d.package.inc.metadata(ctx.view)
            policy, public = d.package.pack.handoff.trusted_policy(d.package.pack.handoff.POLICY)
            signed = d.package.pack.verify_signed_snapshot(manifest, document, public,
                policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
        need(manifest == target == report.get("full_manifest") and signed["release_sequence"] == SEQUENCE,
             "candidate_signed_manifest_differs_from_complete_projection")
        members = d.package.pack.package_inventory(ctx.output / (ITEM + ".vpk"))
        need(members == report.get("package_files") and d.package.inc.all_files(ctx.output) ==
             {row["name"] for row in members}, "complete_package_exact_file_set_changed")
        need(d.package.pack.runtime.digest(ctx.output / (ITEM + ".vpk")) == report.get("vpk_sha256")
             and d.package.pack.runtime.digest(ctx.view / d.build.MANIFEST) == report.get("signed_manifest_sha256"),
             "signed_package_raw_identity_changed")
        d.package.pack.inventory_unchanged(ctx.view, snapshots)
    need(report.get("protected_modules_verified") == len(original["protection"]["protected_outputs"]),
         "actual_protected_module_count_changed")
    controls_unchanged(ctx)
    return report, manifest, signed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--prepare", action="store_true")
    action.add_argument("--build", action="store_true")
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--content-source-revision", required=True)
    parser.add_argument("--operator-revision", required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--reviewed-plan", type=Path)
    parser.add_argument("--reviewed-plan-sha256")
    parser.add_argument("--key", type=Path)
    args = parser.parse_args(argv)
    need(args.report.resolve() == REPORT.resolve(), "fixed_canonical_report_directory_required")
    ctx = context(args.operator_revision)
    need(ctx.config["source_revisions"] == {"game": args.source_revision, "content": args.content_source_revision},
         "explicit_cli_runtime_source_bindings_differ")
    if args.prepare or args.build:
        need(args.reviewed_plan is not None and args.reviewed_plan_sha256 is not None,
             "reviewed_plan_and_sha256_required_before_writes")
        reviewed_plan(args.reviewed_plan, args.reviewed_plan_sha256, ctx)
    if args.build:
        need(args.key is not None, "existing_external_key_required")
        result = build_signed(ctx, args.reviewed_plan, args.reviewed_plan_sha256, args.key)
    elif args.prepare:
        need(args.key is None, "key_for_explicit_signing_only")
        preflight = dependencies().package.sign_package(**_sign_args(ctx), build=False)
        result = {"status": "COMPLETE_UNSIGNED_AND_PACKAGE_PREFLIGHT_VERIFIED_NOT_SIGNED",
                  "projection_sha256": ctx.projection["projection_sha256"], "package_preflight": preflight,
                  "files_written": 0, "sdk_calls": 0, "signing_key_read": False}
    else:
        need(args.key is None and args.reviewed_plan is None, "plan_has_no_write_or_key_arguments")
        result = make_plan(ctx)
    controls_unchanged(ctx)
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, default=lambda x: sorted(x) if isinstance(x, set) else str(x)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
