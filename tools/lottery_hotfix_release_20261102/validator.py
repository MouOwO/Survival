"""Read-only authority adapter for the four-resource lottery/training hotfix.

This new policy does not change any previous candidate's acceptance rules.
Actual signatures/source projection and the reviewed native UI evidence policy
remain mandatory; an input READY flag never grants publication authority.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import re

HERE = Path(__file__).resolve().parent
RELEASE_SEQUENCE = 2026110202
OWNER, APP = "76561198845461206", 570
PAYLOADS = frozenset((
    "panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c",
    "panorama/styles/custom_game/lottery_cinematic_v1.vcss_c",
    "scripts/vscripts/ui/production_ui_service.lua",
    "scripts/vscripts/ui/ui_request_router.lua",
))
NATIVE_ADMISSION_MODULE = HERE / "native_admission.py"
NATIVE_ADMISSION_SHA256 = "935f0958a188dce736baa08282b3b4cd2cd30794767ddb9e8060527600c7a8ab"
b = c = None


def need(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def digest(value):
    need(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value), "Explicit evidence SHA256 required")
    return value


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def context():
    # Authority registration/default import does not load a recipe, SDK or VPK.
    global b, c
    if b is None:
        b = module("canonical_lottery_hotfix_0202_builder", HERE / "build_release.py")
    if c is None:
        c = module("canonical_lottery_hotfix_0202_checks", HERE / "release_checks.py")
    need(b.SEQUENCE == RELEASE_SEQUENCE and set(b.PAYLOADS) == PAYLOADS,
         "Exact four-resource hotfix recipe required")
    return b, c


def same_plan(left, right):
    # Strict JSON comparison distinguishes bool/int and preserves every field.
    def encoded(value):
        return json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=True, allow_nan=False)
    return encoded(left) == encoded(right)


def parent_state(builder, report):
    raw = builder.JOURNAL.read_bytes()
    state = json.loads(raw)
    builder.require_parent_journal(state, report)
    return raw, state


def validate_bootstrap(request):
    need(isinstance(request, dict), "Structured bootstrap request required")
    builder, _ = context()
    report, parent = builder.baseline(full=True)
    raw, _ = parent_state(builder, report)
    snapshot = builder.ledger.load_baseline(
        parent, builder.pack.runtime.digest(builder.BASE / builder.pack.handoff.MANIFEST))
    need(request.get("canonical_journal_sha256") == sha(raw)
         and request.get("parent_manifest_sha256") == snapshot["parent_manifest_sha256"]
         and request.get("source_revisions") == snapshot["source_anchors"],
         "Bootstrap must bind authenticated parent and reviewed ancestry cursors")
    return dict(workshop_id=builder.ITEM, app_id=APP, owner=OWNER,
        canonical_journal_sha256=sha(raw), release_sequence=builder.BASE_SEQUENCE,
        content_sha256=builder.BASE_CONTENT, source_revisions=dict(snapshot["source_anchors"]),
        parent_manifest_sha256=snapshot["parent_manifest_sha256"],
        resource_origins_sha256=snapshot["resource_origins_sha256"],
        source_anchor_is_full_published_tree=False)


def validate_release(request):
    need(isinstance(request, dict) and type(request.get("release_sequence")) is int
         and request["release_sequence"] == RELEASE_SEQUENCE,
         "Only this exact four-resource candidate sequence is registered")
    need(type(request.get("generation")) is int and request["generation"] > 0,
         "Explicit lineage generation required")
    need(re.fullmatch(r"[a-f0-9]{64}", NATIVE_ADMISSION_SHA256 or ""),
         "PENDING_REVIEWED_NATIVE_LOTTERY_UI_ADMISSION_POLICY")
    path = Path(NATIVE_ADMISSION_MODULE).resolve()
    need(path.parent == HERE and path.is_file() and sha(path.read_bytes()) == NATIVE_ADMISSION_SHA256,
         "Reviewed native lottery UI admission policy changed")
    builder, checks = context()
    report, manifest, signed = checks.validated_package(digest(request.get("report_sha256")), full=True)
    # Parent18 already contains ui_request_router: replace that review and add
    # production_ui_service, preserving the other17. Two updates yield19 keys.
    need(report.get("status") == "BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE"
         and report.get("release_sequence") == RELEASE_SEQUENCE
         and report.get("files") == 6917 and report.get("protected_modules_preserved") == 184
         and set(report.get("changed_runtime_paths", [])) == PAYLOADS
         and report.get("added_runtime_paths") == [] and report.get("removed_runtime_paths") == []
         and len(report.get("trusted_review_pins", {})) == 19
         and len(report.get("source_artifact_pins", {})) == 2,
         "Exact four-resource, two-compiled, nineteen-review signed hotfix required")
    need(request.get("source_revisions") == report["source_revisions"]
         and request.get("signed_manifest_sha256") == builder.pack.runtime.digest(builder.VIEW / builder.pack.handoff.MANIFEST)
         and request.get("content_sha256", report["content_sha256"]) == report["content_sha256"],
         "Request source/package binding differs")
    plan_path = Path(request.get("plan_path") or "").resolve()
    need(builder.pack.runtime.within(plan_path, builder.REPORT.resolve()) and plan_path.is_file(),
         "Explicit construction plan beneath this candidate report directory required")
    plan = builder.reviewed_plan(plan_path, digest(request.get("plan_sha256")))
    recomputed, *_ = builder.plan(report["source_revisions"]["game"], report["source_revisions"]["content"], report["operator_revision"])
    need(same_plan(plan, recomputed), "Exact reviewed construction plan changed")
    projected = {key: report.get(key) for key in plan}
    for key in ("status", "dry_run", "signing_key_read", "signature_valid"):
        projected[key] = plan[key]
    need(same_plan(plan, projected), "Signed report differs from reviewed construction inputs")
    raw, _ = parent_state(builder, builder.load(builder.BASE_REPORT))
    need(sha(raw) == request.get("parent_journal_sha256"), "Publication journal changed")
    acceptance = module("lottery_hotfix_0202_native_admission", path).validate_native_release(
        request, report, manifest, signed)
    need(acceptance.get("ordinary_production_acceptance") is True
         and acceptance.get("content_sha256") == manifest["content_sha256"],
         "Same signed normal-client four-pool, fallback, result and no-transaction acceptance required")
    return dict(workshop_id=builder.ITEM, app_id=APP, owner=OWNER, release_sequence=RELEASE_SEQUENCE,
        generation=request["generation"], parent_journal_sha256=sha(raw),
        source_revisions=dict(report["source_revisions"]), signed_manifest_sha256=request["signed_manifest_sha256"],
        report_sha256=request["report_sha256"], plan_sha256=request["plan_sha256"], content_sha256=manifest["content_sha256"],
        authenticated_parent_content_sha256=builder.BASE_CONTENT,
        authenticated_parent_manifest_sha256=report["authenticated_parent_manifest_sha256"],
        parent_resource_origins_sha256=report["parent_resource_origins_sha256"],
        resource_origins_sha256=report["resource_origins_sha256"], package_dir=str(builder.OUTPUT.resolve()))
