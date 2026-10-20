"""Hash and package an already validated local stage; never deploys anything."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "tmp/archive_caps_20261020/release_candidate"
METADATA = ("plan.json", "release_manifest.json", "configuration.json", "schema_before.json",
            "baseline_hashes.json", "input_hashes.json", "backend.patch", "overlay_manifest.json",
            "filelist.txt", "validation_report.json", "REVIEW.txt")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def seal(stage, output):
    stage, output = stage.resolve(), output.resolve()
    assert stage.is_relative_to(ROOT / "tmp") and output.is_relative_to(ROOT / "tmp")
    plan = json.loads((stage / "plan.json").read_bytes())
    report = json.loads((stage / "validation_report.json").read_bytes())
    candidate = plan["candidate"]
    assert plan["status"] == "LOCAL_CANDIDATE_NOT_DEPLOYED"
    assert plan["remote_writes"] == plan["database_writes"] == 0 and plan["production_deployed"] is False
    assert report["status"] == "PASS" and report["actual_subprocess_worker"] is True
    assert report["database_connections"] == report["remote_operations"] == 0
    assert report["bundle_hash"] == candidate["bundle_hash"] and report["overlay_hashes"] == candidate["overlay"]
    expected = set(METADATA) | {"overlay/" + name for name in candidate["overlay"]}
    actual = {path.relative_to(stage).as_posix() for path in stage.rglob("*") if path.is_file()}
    assert actual == expected, "unreviewed_stage_file"
    payload = {}
    for name in sorted(expected):
        path = stage / name
        assert not path.is_symlink() and ".." not in Path(name).parts
        payload[name] = path.read_bytes()
        if name.startswith("overlay/"):
            assert sha(payload[name]) == candidate["overlay"][name.removeprefix("overlay/")]
    assert sha(payload["release_manifest.json"]) == candidate["release_manifest_sha256"]
    assert sha(payload["configuration.json"]) == candidate["configuration_sha256"]
    assert sha(payload["schema_before.json"]) == plan["expected"]["schema_sha256"]
    file_hashes = {name: sha(raw) for name, raw in payload.items()}
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for name, raw in payload.items():
                info = tarfile.TarInfo("stage/" + name)
                info.size, info.mode, info.mtime = len(raw), 0o644, 0
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                archive.addfile(info, io.BytesIO(raw))
    packed = buffer.getvalue()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        assert output.read_bytes() == packed, "sealed_artifact_changed"
    else:
        output.write_bytes(packed)
    result = {"status": "SEALED_LOCAL_NOT_DEPLOYED", "archive": output.name, "archive_sha256": sha(packed),
              "archive_bytes": len(packed), "plan_sha256": sha(payload["plan.json"]),
              "bundle_hash": candidate["bundle_hash"], "file_count": len(payload),
              "files": file_hashes, "files_manifest_sha256": sha(canonical(file_hashes)),
              "validation_cases": len(report["cases"]), "database_connections": 0, "remote_operations": 0}
    output.with_suffix(output.suffix + ".sha256").write_text(sha(packed) + "  " + output.name + "\n", encoding="ascii")
    output.with_suffix(output.suffix + ".seal.json").write_bytes(canonical(result) + b"\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=PACKAGE / "stage")
    parser.add_argument("--output", type=Path, default=PACKAGE / "archive_caps_review_ecf55dd6.tar.gz")
    args = parser.parse_args()
    result = seal(args.stage, args.output)
    print(json.dumps({key: result[key] for key in ("status", "archive", "archive_sha256", "plan_sha256", "file_count", "validation_cases")}))


if __name__ == "__main__":
    main()
