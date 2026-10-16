"""Package the title-only release using fresh, exact PostgreSQL evidence.

Local files only. Never reads credentials, connects, or activates a pointer.
"""
from __future__ import annotations
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tarfile

sys.dont_write_bytecode = True
from prepare_publication import BASE, CANDIDATE, BASELINE_PINS, RELEASE, ROOT, check, canonical

SYNC = "public.archive_sync_config(text,jsonb)"
APPLY = "payments.apply_effects(text,jsonb,boolean)"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def need(value, reason):
    if not value:
        raise ValueError(reason)


def immutable(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    need(not path.is_symlink(), "publication_symlink_refused")
    need(not path.exists() or path.read_bytes() == raw, "publication_artifact_changed:" + str(path))
    if not path.exists():
        with path.open("xb") as stream:
            stream.write(raw)


def main():
    checked = check(RELEASE, ROOT / "server/bundles" / BASE)
    evidence_path = ROOT / "output/endless_titles_80_20261016/deployment/preflight_live.json"
    evidence = json.loads(evidence_path.read_bytes())
    need(evidence["status"] == "READ_ONLY_PREFLIGHT" and evidence["candidate"] == CANDIDATE,
         "fresh_candidate_evidence_missing")
    need(evidence["configuration_input_sha256"] == checked["configuration_input_sha256"],
         "postgres_fingerprint_input_changed")
    need(re.fullmatch("[0-9a-f]{64}", evidence["cfg_pg_sha256"]), "postgres_fingerprint_missing")
    need(evidence["metadata"]["bundle"] == BASE and not evidence["candidate_config_registered"], "running_baseline_changed")
    for field in ("archive_release", "payment_release"):
        need(evidence["metadata"][field] == BASELINE_PINS[field], "baseline_changed:" + field)
    for field in ("archive_manifest_sha256", "archive_service_sha256", "payment_manifest_sha256"):
        need(evidence[field] == BASELINE_PINS[field], "baseline_changed:" + field)
    need(evidence["metadata"]["catalog_hash"] == BASELINE_PINS["payment_catalog_hash"]
         and evidence["cash_enabled"] == 44 and len(evidence["table_names"]) == 28, "business_baseline_changed")
    states = evidence["function_states"]
    need(states[SYNC]["definition_sha256"] == BASELINE_PINS["old_sync_function_sha256"]
         and states[APPLY]["definition_sha256"] == BASELINE_PINS["payment_function_sha256"], "function_baseline_changed")
    old = evidence["function_definitions"][SYNC]
    need(sha(old.encode()) == states[SYNC]["definition_sha256"], "function_capture_changed")
    marker = " -- Reviewed shop catalog:"
    need(old.count(marker) == 1, "exact_function_marker_missing")
    branch = """ -- Reviewed endless titles: one exact immutable configuration, cosmetics only.
 if p_hash='%s' then
  if encode(sha256(convert_to(p_config::text,'UTF8')),'hex')<>'%s' then
   raise exception 'archive_titles_configuration_mismatch';
  end if;
  insert into archive_config_sets(config_hash,config) values(p_hash,p_config) on conflict do nothing;
  select config into v from archive_config_sets where config_hash=p_hash;
  if v is distinct from p_config then raise exception 'archive_config_immutable'; end if;
  return jsonb_build_object('ok',true);
 end if;
""" % (CANDIDATE, evidence["cfg_pg_sha256"])
    updated = old.replace(marker, branch + marker, 1)
    need(updated.replace(branch, "", 1) == old, "unrelated_function_logic_changed")
    new_sha = sha(updated.encode())
    guard = """-- Exact reviewed function only. CREATE OR REPLACE preserves ownership and ACL.
DO $titles_guard$
BEGIN
 IF encode(sha256(convert_to(pg_get_functiondef('public.archive_sync_config(text,jsonb)'::regprocedure),'UTF8')),'hex')
    NOT IN ('%s','%s') THEN
  RAISE EXCEPTION 'archive_titles_function_baseline_changed';
 END IF;
END;
$titles_guard$;
""" % (sha(old.encode()), new_sha)
    payload = RELEASE / "payload"
    source = RELEASE / "candidate/addon/server/bundles" / CANDIDATE
    for path in source.rglob("*"):
        if path.is_file():
            immutable(payload / "bundle" / CANDIDATE / path.relative_to(source), path.read_bytes())
    immutable(payload / "configuration.json", (RELEASE / "configuration.json").read_bytes())
    immutable(payload / "upgrade_archive_titles_compat.sql", (guard + updated.rstrip() + ";\n").encode())
    for name in ("smoke.py", "test_archive_titles_compat.py"):
        immutable(payload / name, Path(__file__).with_name(name).read_bytes())
    files = {p.relative_to(payload).as_posix(): sha(p.read_bytes()) for p in sorted(payload.rglob("*")) if p.is_file()}
    tar_bytes = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=tar_bytes, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for name, digest in sorted(files.items()):
                raw = (payload / name).read_bytes()
                need(sha(raw) == digest, "payload_changed_during_packaging")
                member = tarfile.TarInfo(name)
                member.size, member.mode, member.mtime = len(raw), 0o600, 0
                archive.addfile(member, io.BytesIO(raw))
    archive_raw = tar_bytes.getvalue()
    immutable(RELEASE / "overlay.tar.gz", archive_raw)
    plan = {"version": 1, "kind": "endless_titles_80_only", "base": BASE, "candidate": CANDIDATE,
            "old_release": BASELINE_PINS["archive_release"],
            "target_release": "/opt/goufayu/releases/20261016-endless-titles-v1",
            "rollback_release": "/opt/goufayu/releases/20261016-endless-titles-rollback-v1",
            "old_manifest": BASELINE_PINS["archive_manifest_sha256"],
            "old_service": BASELINE_PINS["archive_service_sha256"],
            "payment_release": BASELINE_PINS["payment_release"], "payment_manifest": BASELINE_PINS["payment_manifest_sha256"],
            "payment_catalog_hash": BASELINE_PINS["payment_catalog_hash"], "payment_enabled_products": 44,
            "old_sync_function": sha(old.encode()), "new_sync_function": new_sha,
            "cfg_pg_sha256": evidence["cfg_pg_sha256"], "configuration_input_sha256": checked["configuration_input_sha256"],
            "preflight_sha256": sha(evidence_path.read_bytes()), "tar_sha256": sha(archive_raw), "files": files,
            "input_hashes": {name: sha((ROOT / name).read_bytes()) for name in (
                "data/csv/存档系统/archive_titles.csv", "scripts/vscripts/systems/archive_titles.lua")}}
    immutable(RELEASE / "release_plan.json", canonical(plan))
    immutable(RELEASE / "archive_sync_config_before.sql", old.encode())
    immutable(RELEASE / "archive_sync_config_after.sql", updated.encode())
    print(json.dumps({"status": "READY_FOR_BACKUP_AND_ROLLBACK_VALIDATION", "candidate": CANDIDATE,
                      "files": len(files), "plan_sha256": sha(canonical(plan)), "new_sync_function": new_sha,
                      "network_requests": 0, "activated": False}))


if __name__ == "__main__":
    main()
