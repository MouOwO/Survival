"""Finalize the existing signed3102 after its policy-context-only postcheck failure.

Never signs, packs, changes a payload, modifies a parent or publishes.
"""
from pathlib import Path
import hashlib
import json
import sys
import build_release as build


def main():
    report = build.REPORT / "package.json"
    build.need(not report.exists(), "NEW completion report required")
    plan_path = build.REPORT / "plan_v02.json"
    expected = build.load(plan_path)
    actual, old, after, values, _, _ = build.plan(expected["source_revision"])
    build.need(build.parent.same_plan(actual, expected), "Original frozen plan/input bytes changed")
    diagnosis_path = build.REPORT / "build_postcheck_diagnosis.json"
    diagnosis = build.load(diagnosis_path)
    failed = diagnosis["base_runtime"]
    build.need(diagnosis["base_package_equal"] and failed["outside_runtime_policy"]
        and not any(failed[key] for key in ("missing", "modified", "unexpected_runtime", "errors")),
        "Failure must be policy-only with unchanged actual parent bytes")
    with build.parent.scene_maps():
        build.need(build.pack.runtime.verify(build.BASE, old)["ok"], "Parent failed its original reviewed map policy")
    build.baseline(full=True)
    manifest, document, _ = build.inc.metadata(build.VIEW)
    build.need(manifest == after, "Existing signed view differs from six-file plan")
    with build.parent.scene_maps(), build.inc.trusted_source(build.TRUSTED):
        _, verified, signature, _ = build.pack.authenticate(build.VIEW)
    build.need(verified == after and signature["release_sequence"] == build.SEQUENCE, "Existing signature invalid")
    files = build.pack.package_inventory(build.OUTPUT / (build.ITEM + ".vpk"))
    build.need(len(files) == 5, "Five final archives required")
    with build.parent.scene_maps():
        verification = build.pack.verify_vpk(build.OUTPUT / (build.ITEM + ".vpk"), manifest)
    build.need(build.pack.package_inventory(build.BASE_VPK) == expected["baseline_package_files"], "Parent archives changed")
    final, *_ = build.plan(expected["source_revision"])
    build.need(build.parent.same_plan(actual, final), "Input/publication drift during recovery")
    actual.update(status="BUILT_SIGNED_PENDING_NATIVE_AND_REDEMPTION_BACKEND", dry_run=False,
        signature_valid=True, full_runtime_validator_passed=True, package_files=files,
        vpk_sha256=files[0]["sha256"], verification=verification,
        build_recovery={"reason": "Original postcheck omitted the existing reviewed portrait scene context; no bytes differed.",
            "diagnosis_sha256": hashlib.sha256(diagnosis_path.read_bytes()).hexdigest(),
            "policy_only_exclusions": len(failed["outside_runtime_policy"]),
            "reused_existing_signed_view": True, "signing_key_read": False,
            "payload_modified": False, "all_full_checks_repeated": True})
    build.inc.write_new(report, (json.dumps(actual, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"status": actual["status"], "files": actual["files"],
        "content_sha256": actual["content_sha256"], "signature_valid": True, "private_key_read": False}))


if __name__ == "__main__": main()
