"""Complete-candidate authority consumed only by the canonical lineage lease.

A report, copied READY JSON, Git push or build result cannot grant UGC access.
The actual immutable projection, signatures, precise full VPK, original source
receipts and ordinary-client evidence are rechecked before the guard receives
identity facts. No signing, SDK, install or journal writes occur here.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
from types import ModuleType

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))
from complete_delivery_release_20261103 import pipeline_recipe as recipe

OWNER, APP, RELEASE_SEQUENCE = recipe.OWNER, recipe.APP, recipe.SEQUENCE
TOOL = "tools/complete_delivery_release_20261103/publication_validator.py"
NATIVE_TOOL = "tools/complete_delivery_release_20261103/native_admission.py"
LOADED_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def need(value, reason):
    if not value:
        raise ValueError(reason)


def same_plan(left, right):
    return recipe.canonical(left) == recipe.canonical(right)


def _operator_file(name, raw, revision):
    d = recipe.dependencies()
    declared = d.package.pending._git(ROOT, "show", revision + ":" + name, counts=Counter())
    need(declared.replace(b"\r\n", b"\n") == raw.replace(b"\r\n", b"\n"),
         "publication_tool_not_in_declared_operator:" + name)
    return hashlib.sha256(declared).hexdigest()


def _native_policy(config, operator_revision):
    """Execute only the fixed new policy's exact verified bytes."""
    spec = config.get("native_admission_module")
    need(isinstance(spec, dict) and set(spec) == {"path", "sha256"}, "fixed_native_admission_policy_pin_required")
    path = recipe.dependencies().build._plain(spec["path"], directory=False)
    need(path == (ROOT / NATIVE_TOOL).resolve() and path.stat().st_size <= 1024*1024,
         "only_registered_complete_native_admission_policy_allowed")
    raw = path.read_bytes()
    need(recipe.sha(raw) == spec["sha256"], "native_admission_policy_changed")
    _operator_file(NATIVE_TOOL, raw, operator_revision)
    name = "_complete_native_admission_" + recipe.sha(raw)[:20]
    module = ModuleType(name)
    module.__file__ = str(path)
    module.__package__ = "complete_delivery_release_20261103"
    sys.modules[name] = module
    try:
        exec(compile(raw, str(path), "exec"), module.__dict__)
    except BaseException:
        sys.modules.pop(name, None)
        raise
    need(callable(getattr(module, "validate_native_release", None)), "native_admission_entry_required")
    return module


def validate_bootstrap(request):
    """Authenticate the historical published source cursors; never reset state."""
    need(isinstance(request, dict), "structured_bootstrap_request_required")
    report, parent = recipe.baseline(full=True, require_current_journal=True)
    d = recipe.dependencies()
    snap = d.package.pending._read_json(d.package.pending.BASELINE, d.package.pending.BASELINE_SHA256)
    journal_raw = recipe.JOURNAL.read_bytes()
    recipe.require_parent_journal(json.loads(journal_raw), report)
    need(request.get("canonical_journal_sha256") == recipe.sha(journal_raw)
         and request.get("parent_manifest_sha256") == snap["parent_manifest_sha256"]
         and request.get("source_revisions") == snap["source_anchors"], "bootstrap_original_parent_binding_mismatch")
    return dict(workshop_id=recipe.ITEM, app_id=APP, owner=OWNER,
        canonical_journal_sha256=recipe.sha(journal_raw), release_sequence=recipe.BASE_SEQUENCE,
        content_sha256=parent["content_sha256"], source_revisions=dict(snap["source_anchors"]),
        parent_manifest_sha256=snap["parent_manifest_sha256"],
        resource_origins_sha256=snap["resource_origins_sha256"], source_anchor_is_full_published_tree=False)


def validate_release(request):
    need(isinstance(request, dict) and type(request.get("release_sequence")) is int
         and request["release_sequence"] == RELEASE_SEQUENCE,
         "registered_complete_candidate_sequence_required")
    need(type(request.get("generation")) is int and request["generation"] > 0,
         "explicit_positive_lineage_generation_required")
    d = recipe.dependencies()
    for key in ("parent_journal_sha256", "signed_manifest_sha256", "report_sha256", "plan_sha256"):
        d.ledger.digest(request.get(key))
    report, manifest, signed = recipe.load_package(request["report_sha256"], full=True)
    cfg, config_raw = recipe.config()
    raw = Path(__file__).read_bytes()
    need(recipe.sha(raw.replace(b"\r\n", b"\n")) == LOADED_LF_SHA256, "validator_changed_after_import")
    _operator_file(TOOL, raw, report["operator_revision"])
    need(report.get("pipeline_inputs_sha256") == recipe.sha(config_raw)
         and request.get("source_revisions") == report["source_revisions"]
         and set(request["source_revisions"]) == {"game", "content"}
         and request["signed_manifest_sha256"] == report["signed_manifest_sha256"]
         and request["plan_sha256"] == report["plan_sha256"]
         and request.get("content_sha256", report["content_sha256"]) == manifest["content_sha256"]
         and report["release_sequence"] == signed["release_sequence"] == RELEASE_SEQUENCE,
         "publication_request_full_source_and_package_binding_mismatch")
    if "plan_path" in request:
        need(Path(request["plan_path"]).resolve() == Path(report["plan_path"]).resolve(), "publication_plan_path_changed")
    parent_report, _ = recipe.baseline(full=False, require_current_journal=True)
    journal_raw = recipe.JOURNAL.read_bytes()
    recipe.require_parent_journal(json.loads(journal_raw), parent_report)
    need(recipe.sha(journal_raw) == request["parent_journal_sha256"], "publication_parent_journal_changed")
    admission = _native_policy(cfg, report["operator_revision"])
    evidence = admission.validate_native_release(request, report, manifest, signed)
    need(evidence.get("ordinary_production_acceptance") is True
         and evidence.get("content_sha256") == manifest["content_sha256"]
         and evidence.get("release_sequence", RELEASE_SEQUENCE) == RELEASE_SEQUENCE,
         "same_signed_ordinary_client_complete_acceptance_required")
    need(recipe.JOURNAL.read_bytes() == journal_raw and recipe.INPUT_FILE.read_bytes() == config_raw,
         "parent_or_controls_changed_during_publication_validation")
    return dict(workshop_id=recipe.ITEM, app_id=APP, owner=OWNER,
        release_sequence=RELEASE_SEQUENCE, generation=request["generation"],
        parent_journal_sha256=recipe.sha(journal_raw), source_revisions=dict(report["source_revisions"]),
        signed_manifest_sha256=request["signed_manifest_sha256"],
        report_sha256=request["report_sha256"], plan_sha256=request["plan_sha256"],
        content_sha256=manifest["content_sha256"],
        authenticated_parent_content_sha256=report["authenticated_parent_content_sha256"],
        authenticated_parent_manifest_sha256=report["authenticated_parent_manifest_sha256"],
        parent_resource_origins_sha256=report["parent_resource_origins_sha256"],
        resource_origins_sha256=report["resource_origins_sha256"],
        package_dir=str(Path(cfg["candidate"]["output"]).resolve()),
        operator_revision=report["operator_revision"], ordinary_production_acceptance=True)
