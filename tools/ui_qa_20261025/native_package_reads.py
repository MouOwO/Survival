"""Read eight pinned v07 VPK resources using Valve's read-only resourceinfo.

Only the reviewed local package or its Steam-managed downloaded copy can be
selected. No Dota launch, Steam operation, alias, listing or key mutation.
Every invocation creates a new ignored report directory and never overwrites.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import stream_workshop_vpk as pack

CONTENT_SHA = "811170a2c77396faee948bf7a77021fe8ac07c2117a919a6c3eb7163e4525e7e"
SEQUENCE = 2026102502
CANDIDATE = Path("D:/Survival_发布候选/20261025_ws4_ui_font_wallet_v07")
TARGETS = {
    "package": Path("D:/Survival_工坊输出/20261025_ws4_ui_font_wallet_v07/3824360109.vpk"),
    "download": Path("D:/SteamLibrary/steamapps/workshop/content/570/3824360109/3824360109.vpk"),
}
MEMBERS = [
    dict(name="3824360109.vpk", bytes=273250,
         sha256="84ebe1a22f2fc1892a94557bf73a59e593b36a60d094f9ef98deea8d9ff20870"),
    dict(name="3824360109_000.vpk", bytes=1073512900,
         sha256="ccfe41356cafef31a3b4a836f66fb4b4059afb36e400f1cbcda8d19fdae5d290"),
    dict(name="3824360109_001.vpk", bytes=1068730788,
         sha256="68cfc41f2c46f91ade8396ebe3f3597da03ab2d1f5bb06577feee49182cddff0"),
    dict(name="3824360109_002.vpk", bytes=1072379183,
         sha256="94a2a3b26731ea2a15fe0fad8116eb9043cb8bf960139a26c95e810192d56141"),
    dict(name="3824360109_003.vpk", bytes=552122253,
         sha256="b029127130dc54a0c98a9bb62beae30312c9b30f065ae19fa30e63949a53c3d5"),
]
TEAL = "panorama/images/ui/shared/texture/teal_png.vtex_c"
CHANGED_JS = (
    "panorama/scripts/custom_game/common/archive_font_v36.vjs_c",
    "panorama/scripts/custom_game/daily_remaining_5d5c1152eb.vjs_c",
    "panorama/scripts/custom_game/commerce_wallet.vjs_c",
)
TOOL = ROOT.parents[1] / "bin/win64/resourceinfo.exe"
GAME = ROOT.parents[1] / "dota"
REPORT_ROOT = ROOT / "output/ui_qa_20261025/native_package_reads"


def need(value, code):
    if not value:
        raise ValueError(code)


def select_rows(rows):
    by_name = {row["path"]: row for row in rows}
    need(len(by_name) == len(rows), "native_v07_duplicate_resource")
    archives = sorted({row["archive"] for row in rows})
    need(archives == [0, 1, 2, 3], "native_v07_expected_four_archives")
    chosen = []
    for archive in archives:
        textures = [row for row in rows if row["archive"] == archive
                    and row["path"].endswith(".vtex_c") and row["path"] != TEAL]
        need(textures, "native_v07_archive_texture_missing")
        chosen.append(min(textures, key=lambda row: row["path"]))
    for name in (TEAL, *CHANGED_JS):
        need(name in by_name, "native_v07_required_resource_missing:" + name)
        chosen.append(by_name[name])
    need(len(chosen) == len({row["path"] for row in chosen}) == 8,
         "native_v07_eight_distinct_resources_required")
    return chosen


def signed_manifest():
    raw = pack.read_metadata(pack.protect_data.source_path(CANDIDATE, pack.handoff.MANIFEST), pack.MAX_MANIFEST)
    sigraw = pack.read_metadata(pack.protect_data.source_path(CANDIDATE, pack.handoff.SIGNATURE), pack.MAX_SIGNATURE)
    manifest, document = pack.handoff.decode_json(raw), pack.handoff.decode_json(sigraw)
    pack.runtime.validate_manifest(manifest)
    policy, public = pack.handoff.trusted_policy(pack.handoff.POLICY)
    signature = pack.verify_signed_snapshot(manifest, document, public,
        policy["integrity"]["minimum_release_sequence"], policy["integrity"]["trusted_key_id"])
    need(manifest["content_sha256"] == CONTENT_SHA and manifest["file_count"] == 6630
         and signature["release_sequence"] == SEQUENCE, "native_v07_signed_identity_mismatch")
    return manifest, signature, {pack.handoff.MANIFEST: raw, pack.handoff.SIGNATURE: sigraw}


def read_rows(vpk):
    with vpk.open("rb") as source:
        raw = source.read(pack.HEADER.size)
        need(len(raw) == pack.HEADER.size, "native_v07_truncated_header")
        header = pack.HEADER.unpack(raw)
        need(header[0] == pack.MAGIC and header[1] == 2 and 1 <= header[2] <= pack.MAX_TREE,
             "native_v07_invalid_header")
        return pack.read_tree(source.read(header[2]))


def verify_package(vpk, manifest):
    vpk = pack.handoff.regular_path(vpk)
    members = pack.package_paths(vpk)
    need(set(vpk.parent.iterdir()) == set(members), "native_v07_unexpected_package_member")
    need(pack.runtime.digest(vpk) == MEMBERS[0]["sha256"], "native_v07_index_hash_mismatch")
    inventory = pack.package_inventory(vpk)
    need(inventory == MEMBERS, "native_v07_archive_hash_or_size_mismatch")
    verification = pack.verify_vpk(vpk, manifest)
    return verification, inventory, {p: (p.stat().st_size, p.stat().st_mtime_ns) for p in members}


def parse_native_result(raw, returncode, path):
    text = raw.decode("utf-8", errors="replace").replace("\\", "/")
    failed16 = "failed to read 16 bytes" in text.lower()
    ok = returncode == 0 and "Info for resource file" in text and path in text and not failed16
    return dict(ok=ok, exit_code=returncode, info_header_seen="Info for resource file" in text,
                resource_path_seen=path in text, failed_to_read_16_bytes=failed16)


def run(target):
    need(target in TARGETS, "native_v07_target_not_allowed")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report_dir = REPORT_ROOT / (target + "_" + stamp + "_" + uuid.uuid4().hex[:8])
    report_dir.mkdir(parents=True, exist_ok=False)
    report = dict(schema=1, target=target, started_utc=stamp, content_sha256=CONTENT_SHA,
                  release_sequence=SEQUENCE, index_sha256=MEMBERS[0]["sha256"],
                  scope="native_resourceinfo_parse_samples_not_gameplay_or_UI_acceptance",
                  resource_reads=[], Dota_launched=False, alias_changed=False,
                  Steam_API_called=False, workshop_upload_performed=False, private_key_read=False)
    try:
        vpk = pack.handoff.regular_path(TARGETS[target])
        manifest, signature, snapshots = signed_manifest()
        verification, inventory, stats = verify_package(vpk, manifest)
        report.update(vpk=str(vpk), signature_valid=signature["signature_valid"],
                      files=manifest["file_count"], package_files=inventory,
                      full_vpk_verification=verification)
        tool = pack.handoff.regular_path(TOOL)
        report.update(resourceinfo=str(tool), resourceinfo_sha256=pack.runtime.digest(tool))
        rows = select_rows(read_rows(vpk))
        for index, row in enumerate(rows, 1):
            command = [str(tool), "-game", str(GAME), "-i", vpk.name + "/" + row["path"]]
            try:
                completed = subprocess.run(command, cwd=vpk.parent, capture_output=True, timeout=30)
                raw = completed.stdout + completed.stderr
                result = parse_native_result(raw, completed.returncode, row["path"])
            except subprocess.TimeoutExpired as error:
                raw = (error.stdout or b"") + (error.stderr or b"")
                result = dict(ok=False, error="resourceinfo_timeout", timeout_seconds=30)
            log = report_dir / ("%02d_native.log" % index)
            with log.open("xb") as stream:
                stream.write(raw)
            result.update(path=row["path"], archive=row["archive"], log=log.name,
                          log_bytes=len(raw), log_sha256=hashlib.sha256(raw).hexdigest())
            report["resource_reads"].append(result)
            need(result["ok"], "native_v07_resource_parse_failed:" + row["path"])
        pack.inventory_unchanged(CANDIDATE, snapshots)
        need(all((p.stat().st_size, p.stat().st_mtime_ns) == value for p, value in stats.items()),
             "native_v07_package_changed_during_reads")
        report.update(ok=True, native_resource_reads=8, archives_verified=[0, 1, 2, 3],
                      all_exit_zero=True, failed_to_read_16_bytes=False,
                      native_gameplay_verified=False, native_UI_behavior_verified=False)
    except Exception as error:
        report.update(ok=False, error=type(error).__name__ + ": " + str(error))
    report["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    path = report_dir / "report.json"
    with path.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    return report, path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=tuple(TARGETS))
    args = parser.parse_args()
    report, path = run(args.target)
    print(json.dumps(dict(ok=report["ok"], report=str(path), target=args.target,
                         native_resource_reads=len(report["resource_reads"]), error=report.get("error")), ensure_ascii=True))
    return 0 if report["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
