"""Bind the unchanged official download protocol to the reviewed3102 package.

Without --download: local read-only verification plan. Download additionally
requires a successful same-release upload and real fresh query/1313/3406 ACKs.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import sys

sys.dont_write_bytecode = True
from release_checks import build, validated_package

PROTOCOL = build.ROOT / "tools/arcade_cleanup_20261027/verify_download.py"
PROTOCOL_SHA = "1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f"
build.need(hashlib.sha256(PROTOCOL.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == PROTOCOL_SHA, "Frozen official protocol changed")
spec = importlib.util.spec_from_file_location("wall3102_official_download", PROTOCOL)
protocol = importlib.util.module_from_spec(spec); spec.loader.exec_module(protocol)
api = protocol.api
REPORT_SHA = None


def local_inputs(require_success=False, *, full=False):
    snapshots = {}
    read = lambda path: protocol.read_snapshot(path, api.pack.MAX_MANIFEST, snapshots)
    report_path = build.REPORT / "package.json"
    read(report_path); read(build.VIEW / api.pack.handoff.MANIFEST); read(build.VIEW / api.pack.handoff.SIGNATURE)
    state = api.pack.handoff.decode_json(read(build.parent.JOURNAL))
    report, manifest, signature = validated_package(REPORT_SHA, full=full)
    success = (state.get("uploaded") is True and state.get("owner") == api.OWNER and state.get("app_id") == api.APP
               and state.get("workshop_id") == build.ITEM and state.get("visibility_requested") == 3
               and state.get("release_sequence") == build.SEQUENCE and state.get("content_sha256") == manifest["content_sha256"]
               and state.get("package_files") == report["package_files"] and state.get("vpk_sha256") == report["vpk_sha256"]
               and state.get("legal_agreement_required") is False)
    if require_success: build.need(success, "Successful same-release3102 original-item upload required")
    protocol.unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signature, state=state, snapshots=snapshots,
                success=success, expected_manifest=protocol.journal_manifest(state) if success else None,
                total=sum(row["bytes"] for row in report["package_files"]), report_sha256=REPORT_SHA,
                state_sha256=hashlib.sha256(snapshots[build.parent.JOURNAL]).hexdigest(), protected_modules=184)


def main():
    global REPORT_SHA
    own = argparse.ArgumentParser(add_help=False)
    own.add_argument("--report-sha256", required=True)
    args, remaining = own.parse_known_args()
    REPORT_SHA = args.report_sha256
    report, _, _ = validated_package(REPORT_SHA)
    values = dict(ITEM=build.ITEM, SEQUENCE=build.SEQUENCE, FILE_COUNT=report["files"],
                  CONTENT=report["content_sha256"], CANDIDATE=build.VIEW, TRUSTED=build.TRUSTED,
                  VPK=build.OUTPUT / (build.ITEM + ".vpk"), REPORT=build.REPORT / "package.json", STATE=build.parent.JOURNAL,
                  OUTPUT=build.REPORT / "download_evidence", MINIMUM_REMOTE_UPDATED=1793440000, local_inputs=local_inputs)
    for name, value in values.items(): setattr(protocol, name, value)
    old = sys.argv
    try:
        sys.argv = [old[0], *remaining]
        with build.parent.scene_maps(), build.inc.trusted_source(build.TRUSTED): return protocol.main()
    finally:
        sys.argv = old


if __name__ == "__main__": raise SystemExit(main())
