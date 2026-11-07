"""Local online testing of the currently approved complete signed candidate.

The fixed binding is written by the release operator AFTER signing/review. It
names immutable sources, not workspace HEAD (a later documentation commit is
not a new runtime candidate). Advancing the authority or expected_newest without
a matching signed package refuses launch; there is no legacy-addon fallback.

Check is read-only and calls canonical authentication, never Steam/login/SDK.
Run delegates installation, retained process/file handles and restoration to
the existing pinned rehearsal. One startup authentication is O(manifest/files);
stage/restore retain their existing O(package bytes) checks. No game polling,
account/profile copying, input, transaction automation or new game timer.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "output/test_entry_runtime"
# This selection record is local, written after signing. Keep it in the
# existing ignored output namespace: adding a tracked/untracked publication
# file then would change the canonical inventory/projection and refuse launch.
BINDING = RUNTIME / "online_signed_candidate.json"
WORKSHOP_ID = "3824360109"
KIND = "CANONICAL_SIGNED_ONLINE_TEST_BINDING"
LOCAL_STATUS = "LOCAL_ONLINE_TEST_NOT_PUBLISHED"
RESTORED = "ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED"
MAX_RECORD = 16 * 1024
sys.dont_write_bytecode = True


def need(value, code):
    if not value:
        raise RuntimeError(code)


def _sha(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def _revision(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{40}", value) is not None


def _expected(value):
    need(isinstance(value, dict) and set(value) == {
        "release_sequence", "source_revisions", "operator_revision"}, "online_expected_newest_invalid")
    need(type(value["release_sequence"]) is int and value["release_sequence"] > 0,
         "online_release_sequence_invalid")
    sources = value["source_revisions"]
    need(isinstance(sources, dict) and set(sources) == {"game", "content"}
         and all(_revision(revision) for revision in sources.values())
         and _revision(value["operator_revision"]), "online_immutable_sources_required")


def build_binding(report, report_sha256, *, expected_newest):
    """Pure operator helper; returns a record and NEVER writes/approves a file.

    The caller must review/sign the package first. prepare() independently
    authenticates it with the pinned canonical implementation on every launch.
    """
    _expected(expected_newest)
    need(isinstance(report, dict) and _sha(report_sha256), "online_package_binding_invalid")
    need(report.get("status") == "BUILT_SIGNED_COMPLETE_CANDIDATE_PENDING_NATIVE_ADMISSION"
         and report.get("signature_valid") is True and report.get("workshop_upload_performed") is False
         and str(report.get("workshop_id")) == WORKSHOP_ID, "online_signed_candidate_required")
    need(type(report.get("release_sequence")) is int, "online_release_sequence_invalid")
    for key in expected_newest:
        need(report.get(key) == expected_newest[key], "online_expected_newest_mismatch")
    candidate = {"package_report_sha256": report_sha256,
                 "content_sha256": report.get("content_sha256"),
                 "signed_manifest_sha256": report.get("signed_manifest_sha256")}
    need(all(_sha(pin) for pin in candidate.values()), "online_candidate_hash_invalid")
    return {"schema": 1, "kind": KIND, "workshop_id": WORKSHOP_ID,
            "expected_newest": json.loads(json.dumps(expected_newest)), "candidate": candidate,
            "route": "direct", "cloud_login_required": True, "cheats_allowed": False,
            "publication_status": LOCAL_STATUS}


def _facade():
    path = ROOT / "tools/release_pipeline.py"
    spec = importlib.util.spec_from_file_location("online_canonical_release_pipeline", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _regular_record(facade, path):
    value, raw = facade.guard.read_json(path, MAX_RECORD)
    return value, raw


def prepare():
    """Authenticate the fixed current binding/package; no install/process writes."""
    facade = _facade()
    authority = facade.authority()  # fixed tracked authority + existing SHA pin
    policy = authority.policy
    need(str(policy.get("workshop_id")) == WORKSHOP_ID, "online_workshop_mismatch")
    binding, binding_raw = _regular_record(facade, BINDING)
    need(set(binding) == {"schema", "kind", "workshop_id", "expected_newest", "candidate",
                          "route", "cloud_login_required", "cheats_allowed", "publication_status"}
         and type(binding["schema"]) is int and binding["schema"] == 1
         and binding["kind"] == KIND and binding["workshop_id"] == WORKSHOP_ID
         and binding["route"] == "direct" and binding["cloud_login_required"] is True
         and binding["cheats_allowed"] is False and binding["publication_status"] == LOCAL_STATUS,
         "online_binding_contract_invalid")
    _expected(binding["expected_newest"])
    candidate = binding["candidate"]
    need(isinstance(candidate, dict) and set(candidate) == {
        "package_report_sha256", "content_sha256", "signed_manifest_sha256"}
        and all(_sha(pin) for pin in candidate.values()), "online_candidate_hash_invalid")
    need(policy.get("release_sequence") == binding["expected_newest"]["release_sequence"],
         "online_authority_not_expected_newest")
    report_folder = facade.guard.regular(policy.get("report_directory", ""))
    need(Path(policy.get("report_directory", "")).is_absolute()
         and report_folder.resolve().is_relative_to((ROOT / "output").resolve()), "online_fixed_report_directory_required")
    # The canonical package_auth reads REPORT/package.json itself, verifies its
    # source/operator/producer closure, signature, manifest and production
    # projections. A user-controlled READY flag or a few policy-file hashes is
    # never a substitute. No comparison with mutable workspace HEAD is added.
    rehearsal = facade.pinned_module(authority, "rehearsal")
    report, _manifest = rehearsal.package_auth(candidate["package_report_sha256"], full=False)
    need(Path(rehearsal.recipe().REPORT).resolve() == report_folder.resolve(),
         "online_canonical_report_directory_mismatch")
    expected_record = build_binding(report, candidate["package_report_sha256"],
                                    expected_newest=binding["expected_newest"])
    need(binding == expected_record, "online_signed_package_not_current_binding")
    reviews = {row.get("path"): row for row in report.get("production_policy_reviews", [])}
    for path in ("scripts/vscripts/config/release_profile.lua", "scripts/vscripts/config/player_web_auth.lua"):
        row = reviews.get(path, {})
        need(row.get("kind") == "AUTHENTICATED0104_CONSTANT_BYTES"
             and row.get("constant_policy_probe_required") is True
             and _sha(row.get("production_sha256"))
             and row.get("production_sha256") == row.get("parent_sha256"),
             "online_production_auth_policy_unverified")
    summary = {"ok": True, "mode": "online", "addon": WORKSHOP_ID,
               "status": "SIGNED_ONLINE_ENTRY_CHECKED", "release_sequence": report["release_sequence"],
               "source_revisions": report["source_revisions"], "operator_revision": report["operator_revision"],
               "package_report_sha256": candidate["package_report_sha256"],
               "signed_manifest_sha256": report["signed_manifest_sha256"],
               "binding_sha256": hashlib.sha256(binding_raw).hexdigest(),
               "cloud_login_required": True, "cheats_allowed": False, "game_started": False,
               "offline_storage": None, "publication_status": LOCAL_STATUS,
               "workshop_synchronized": False}
    return {"facade": facade, "rehearsal": rehearsal, "binding": binding, "summary": summary,
            "authority_policy": json.loads(json.dumps(policy))}


def check():
    return prepare()["summary"]


def _write_status(value):
    # Only non-sensitive lifecycle facts. Never copy engine logs, login status,
    # account IDs, tokens, profile state or backend responses into this record.
    RUNTIME.mkdir(parents=True, exist_ok=True)
    path = RUNTIME / "online_latest.json"
    temporary = path.with_name(path.name + ".pending")
    temporary.write_text(json.dumps(value, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def _error_code(error):
    value = str(error) if isinstance(error, (RuntimeError, ValueError)) else "online_native_or_os_failure"
    return value if re.fullmatch(r"[a-zA-Z0-9_]{1,100}", value) else "online_canonical_action_failed"


def _normal_exit_ready(prepared, transaction):
    rehearsal, facade = prepared["rehearsal"], prepared["facade"]
    folder = rehearsal.STORE / transaction
    need(not (folder / "hold_failed.json").exists(), "online_keeper_failed_preserve_transaction")
    hold, _ = _regular_record(facade, folder / "hold_end.json")
    need(hold.get("status") == "OWNED_DOTA_EXITED_HOLDS_COMPLETED"
         and hold.get("package_report_sha256") == prepared["summary"]["package_report_sha256"]
         and hold.get("restoration_still_required") is True,
         "online_normal_exit_receipt_required")
    # restore() additionally verifies exact process FILETIME/keeper release,
    # absence of ALL Dota processes, old ACF and all original/candidate bytes.


def _assert_current(prepared):
    facade = prepared["facade"]
    _binding, raw = _regular_record(facade, BINDING)
    need(hashlib.sha256(raw).hexdigest() == prepared["summary"]["binding_sha256"],
         "online_binding_changed_before_launch")
    need(facade.authority().policy == prepared["authority_policy"], "online_authority_changed_before_launch")


def _launch_keeper(transaction, report_sha):
    # restore explicitly requires the keeper process to have exited. Therefore
    # run the EXISTING canonical launch CLI in a separate foreground child and
    # inherit its output. It owns Dota and its file/process handles; this parent
    # neither launches nor polls Dota. No shell, new timer, timeout or force stop.
    # subprocess.run() kills its child on KeyboardInterrupt. Retain an explicit
    # Popen and wait instead: interruption must preserve the live keeper/game.
    keeper = subprocess.Popen([sys.executable, "-B", "-X", "utf8", str(ROOT / "tools/release_pipeline.py"),
                               "rehearsal", "launch", "--transaction", transaction,
                               "--report-sha256", report_sha, "--route", "direct"], cwd=ROOT)
    need(keeper.wait() == 0, "online_keeper_exit_failed_preserve_transaction")


def run_prepared(prepared):
    """Block in the real canonical keeper; never launch Dota independently."""
    rehearsal = prepared["rehearsal"]
    summary = dict(prepared["summary"])
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    transaction = "online_" + str(summary["release_sequence"]) + "_" + stamp
    report_sha = summary["package_report_sha256"]
    summary.update(transaction=transaction, transaction_directory=str(rehearsal.STORE / transaction),
                   status="SIGNED_ONLINE_STAGING", started_utc=datetime.now(timezone.utc).isoformat())
    _write_status(summary)
    print(json.dumps(summary, ensure_ascii=True), flush=True)
    print("联网本地签名测试：请保留此窗口。游戏中正常完成 Steam 授权；退出游戏后将校验并恢复原安装。", flush=True)
    phase, mutation_started = "preflight", False
    try:
        _assert_current(prepared)
        phase, mutation_started = "stage", True
        staged = rehearsal.stage(transaction, report_sha)
        need(staged.get("status") == "COMPLETE_SIGNED_CANDIDATE_INSTALLED", "online_stage_not_complete")
        phase = "launch"
        summary.update(status="SIGNED_ONLINE_CLIENT_STARTING_KEEP_WINDOW_OPEN")
        _write_status(summary)
        _assert_current(prepared)
        summary["game_started"] = None  # keeper's process receipt will prove this
        _launch_keeper(transaction, report_sha)
        _normal_exit_ready(prepared, transaction)
        summary.update(game_started=True)
        phase = "restore"
        restored = rehearsal.restore(transaction, report_sha)
        need(restored.get("status") == RESTORED, "online_restore_not_complete")
        summary.update(status="SIGNED_ONLINE_EXITED_ORIGINAL_RESTORED", restore_status=RESTORED,
                       restoration_required=False, finished_utc=datetime.now(timezone.utc).isoformat())
        _write_status(summary)
        return summary
    except (Exception, KeyboardInterrupt) as error:
        # Never restore from an arbitrary failure/finally block: launch may be
        # live or ownership uncertain. Preserve evidence and explicit recovery.
        summary.update(ok=False, status="SIGNED_ONLINE_INTERRUPTED_PRESERVE_TRANSACTION" if mutation_started
                       else "SIGNED_ONLINE_REFUSED_BEFORE_INSTALL", failed_phase=phase,
                       error="online_interrupted" if isinstance(error, KeyboardInterrupt) else _error_code(error),
                       restoration_required=mutation_started, automatic_retry=False, game_force_stopped=False,
                       recovery_argv=[sys.executable, "-B", "-X", "utf8", str(ROOT / "tools/release_pipeline.py"),
                                      "rehearsal", "restore", "--transaction", transaction,
                                      "--report-sha256", report_sha] if mutation_started else None)
        try:
            _write_status(summary)
        except OSError:
            summary["status_receipt_write_failed"] = True
        return summary
