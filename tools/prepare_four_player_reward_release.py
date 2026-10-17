"""Prepare and verify an archive-only overlay; never deploy or change live pointers."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tarfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/four_player_stress_20261012"
sys.path.insert(0, str(ROOT / "server"))
from archive_backend.bundle import Bundle, read_csv
from archive_backend.service import ArchiveService


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


stress = load("four_player_reward_stress_fixture", ROOT / "tools/test_four_player_reward_stress.py")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def immutable(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != raw:
        raise ValueError("existing staged file differs: " + str(path))
    path.write_bytes(raw)


def verify_candidate(bundle, previous):
    db = stress.LocalDatabase(bundle)
    app = stress.fixture_module.App(db)
    service = ArchiveService(app, bundle, stress.LUA)
    checks, evidence = [], {}

    def check(value, label):
        if not value:
            raise AssertionError(label)
        checks.append(label)

    command = {"id": "readycandidate20261012:challenge_kind:shadow_4", "kind": "challenge",
               "challenge_id": "shadow_4", "kill_sequence": 41, "difficulty_id": "n6"}
    counts = []
    for index, account in enumerate(("880001", "880002", "880003", "880004")):
        profile = db.profile(app._database_account_id(account))
        if index == 0: profile["entitlements"] = {"archive_pass": {"active": True, "expires_at": stress.NOW + 1000}}
        if index == 2: profile["entitlements"] = {"vip": {"active": True}}
        if index == 3: profile["entitlements"] = {"archive_pass": {"active": True, "expires_at": stress.NOW - 1}}
        payload = {"account_id": account, "config_hash": bundle.hash, "command": copy.deepcopy(command)}
        check(service.command(payload)["ok"], "candidate_command_account_" + str(index))
        before = copy.deepcopy(profile)
        check(service.command(payload)["ok"] and profile == before, "candidate_replay_no_increment_account_" + str(index))
        counts.append(copy.deepcopy(profile["save"]["archive"]["shadow_counts"]))
    check(counts[1] == counts[2] == counts[3], "base_same_for_plain_VIP_expired_pass")
    check(sum(counts[0].values()) == 3, "own_valid_monthly_pass_three_items")
    check(all(sum(row.values()) == 2 for row in counts[1:]), "each_non_pass_account_gets_unsplit_two_items")
    check(all(counts[0].get(item, 0) >= number for item, number in counts[1].items()), "monthly_receives_shared_base_plus_own_extra")
    evidence["new_event_counts"] = counts

    # A prepared current-deployment receipt must use its own immutable worker
    # and per-account seed. It cannot acquire the new shared seed on retry.
    legacy_payload = {"account_id": "880005", "config_hash": previous.hash, "command": {
        "id": "oldprepared20261012:challenge_kind:shadow_4", "kind": "challenge",
        "challenge_id": "shadow_4", "kill_sequence": 42, "difficulty_id": "n6"}}
    old_service = ArchiveService(app, previous, stress.LUA)
    old_service.settle = lambda *args: (_ for _ in ()).throw(TimeoutError("offline_stop_before_worker"))
    try:
        old_service.command(copy.deepcopy(legacy_payload))
    except TimeoutError:
        pass
    account = app._database_account_id("880005")
    operation = db.ops[(account, legacy_payload["command"]["id"])]
    check(not operation["done"] and operation["hash"] == previous.hash, "legacy_prepare_retains_original_hash")
    calls = []
    original = stress.subprocess.run

    def capture(*args, **kwargs):
        calls.append({"cwd": str(kwargs["cwd"]), "input": json.loads(kwargs["input"])})
        return original(*args, **kwargs)

    with patch("archive_backend.service.subprocess.run", side_effect=capture):
        check(service.command(copy.deepcopy(legacy_payload))["ok"], "current_deployment_hash_accepted_by_candidate")
    check(len(calls) == 1 and Path(calls[0]["cwd"]).name == previous.hash, "old_prepared_uses_original_worker_bundle")
    check(operation["hash"] == previous.hash, "retry_never_rewrites_receipt_hash")
    profile = db.profile(account)
    saved = copy.deepcopy(profile)
    check(service.command(copy.deepcopy(legacy_payload))["ok"] and profile == saved, "old_committed_receipt_replay_once")
    check(not service.shared_challenge_roll(previous), "old_recorded_policy_keeps_personal_seed")
    evidence["legacy_worker_bundle"] = Path(calls[0]["cwd"]).name
    evidence["legacy_seed"] = calls[0]["input"]["seed"]
    evidence["legacy_counts"] = copy.deepcopy(profile["save"]["archive"]["shadow_counts"])
    unknown = copy.deepcopy(legacy_payload); unknown["config_hash"] = "a" * 64
    check(service.command(unknown).get("error") == "archive_config_mismatch", "unknown_hash_rejected")
    return {"passed": True, "checks": len(checks), "check_labels": checks, "evidence": evidence,
            "real_lua_worker": True, "database": "local fixture", "live_requests": 0}


def main():
    pointers = [ROOT / "server/bundles/current.json", ROOT / "scripts/vscripts/config/generated/archive_http_bundle.lua"]
    before = [path.read_bytes() for path in pointers]
    previous_hash = json.loads(before[0])["hash"]
    previous = Bundle(ROOT / "server/bundles" / previous_hash)
    original = json.loads((previous.directory / "bundle.json").read_bytes())
    data = copy.deepcopy(original)
    rule_path = ROOT / "data/csv/存档系统/archive_cooperative_reward_rules.csv"
    data["configs"][rule_path.stem] = read_csv(rule_path)
    data["csv_hashes"][rule_path.relative_to(ROOT).as_posix()] = hashlib.sha256(rule_path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
    source_paths = {
        "systems/archive_settlement.lua": "scripts/vscripts/systems/archive_settlement.lua",
        "systems/archive_challenge_rewards.lua": "scripts/vscripts/systems/archive_challenge_rewards.lua",
        "systems/archive_cooperative_reward_policy.lua": "scripts/vscripts/systems/archive_cooperative_reward_policy.lua",
        "worker.lua": "server/archive_backend/worker.lua",
    }
    for bundled, source in source_paths.items():
        data["sources"][bundled] = (ROOT / source).read_text(encoding="utf-8-sig")
    aliases = data["compatible_config_hashes"]
    legacy_commands = sorted({kind for rule in aliases.values() for kind in rule["commands"]})
    aliases[previous_hash] = {"commands": legacy_commands, "upgrade_commands": []}
    raw = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    candidate_hash = hashlib.sha256(raw).hexdigest()
    # Lua 5.1's Windows file API cannot open >MAX_PATH worker paths.
    release_id = "r-" + candidate_hash[:8]
    release = OUT / "pkg" / release_id
    bundles = release / "addon/server/bundles"
    preserved = []
    for directory in sorted((ROOT / "server/bundles").iterdir()):
        if directory.is_dir() and len(directory.name) == 64 and all(c in "0123456789abcdef" for c in directory.name):
            old = Bundle(directory)
            target = bundles / old.hash
            for path in old.directory.rglob("*"):
                if path.is_symlink(): raise ValueError("historical bundle symlink")
                if path.is_file() and "__pycache__" not in path.parts:
                    immutable(target / path.relative_to(old.directory), path.read_bytes())
            preserved.append(old.hash)
    for path, text in data["sources"].items():
        immutable(bundles / candidate_hash / path, text.encode("utf-8"))
    immutable(bundles / candidate_hash / "bundle.json", raw)
    immutable(bundles / "current.json", json.dumps({"hash": candidate_hash, "protocol": 1}).encode())
    immutable(release / "game-config/archive_http_bundle.lua",
        ('-- Candidate; apply only after backend deployment and acceptance.\nreturn { protocol = 1, hash = "' + candidate_hash + '" }\n').encode())
    for name in ("service.py", "bundle.py", "config_compatibility.py"):
        immutable(release / "backend/archive_backend" / name, (ROOT / "server/archive_backend" / name).read_bytes())
    # Existing deployment RPC allowlist contains two old hashes only. This
    # reviewed candidate changes that one list; it changes no player values.
    sql = (ROOT / "server/migrations/202610090001_archive_sync_compatibility.sql").read_text(encoding="utf-8-sig")
    start = sql.index("create or replace function public.archive_sync_config(")
    finish = sql.index("end; $$;", start) + len("end; $$;")
    function = sql[start:finish]
    marker = "'288f724bcfd79880c4fbd7d4ac77040a8636e2f8f3ef96836632001340d3b2a7'];"
    if function.count(marker) != 1: raise ValueError("compatibility SQL baseline changed")
    function = function.replace(marker, marker[:-2] + ",\n  '" + previous_hash + "'];")
    migration = "-- Candidate only: retain existing RPC/immutable records; append the currently selected hash.\nbegin;\n" + function + "\ncommit;\n"
    immutable(release / "database/archive_cooperative_rewards_20261012.sql", migration.encode())
    candidate = Bundle(bundles / candidate_hash)
    changed_configs = sorted(key for key in data["configs"] if data["configs"][key] != original["configs"].get(key))
    if changed_configs != ["archive_cooperative_reward_rules"]: raise ValueError("unrelated configuration changed")
    changed_sources = sorted(key for key in data["sources"] if data["sources"][key] != original["sources"].get(key))
    if changed_sources != sorted(source_paths): raise ValueError("unreviewed source changes")
    validation = verify_candidate(candidate, Bundle(bundles / previous_hash))
    immutable(release / "validation/reward_candidate.json", json.dumps(validation, ensure_ascii=False, indent=2).encode())
    files = {path.relative_to(release).as_posix(): digest(path) for path in sorted(release.rglob("*"))
             if path.is_file() and path.name != "release_manifest.json"}
    manifest = {"format": 1, "release": release_id, "files": files, "archive_bundle": candidate_hash,
                "kind": "archive-only-overlay", "previous_bundle": previous_hash,
                "includes_secrets": False, "game_configuration_changed": False, "deployed": False}
    immutable(release / "release_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2).encode())
    manage = load("reward_release_manifest_verifier", ROOT / "server/aliyun/deploy/manage.py")
    manage.verify_release_manifest(release)
    archive = release.with_suffix(".tar.gz")
    if not archive.exists():
        with tarfile.open(archive, "x:gz") as tar:
            def normalize(info):
                info.uid = info.gid = 0; info.uname = info.gname = "root"
                info.mode = 0o755 if info.isdir() else 0o644
                return info
            tar.add(release, arcname=release_id, filter=normalize)
    immutable(Path(str(archive) + ".sha256"), (digest(archive) + "  " + archive.name + "\n").encode())
    report = {"status": "LOCAL_CANDIDATE_PREPARED_NOT_DEPLOYED", "candidate_hash": candidate_hash,
              "current_selected_hash": previous_hash, "release_directory": str(release), "archive_path": str(archive),
              "archive_sha256": digest(archive), "release_manifest": str(release / "release_manifest.json"),
              "manifest_sha256": digest(release / "release_manifest.json"), "manifest_verified": True,
              "source_sha256": {source: digest(ROOT / source) for source in source_paths.values()},
              "backend_source_sha256": {"server/archive_backend/" + name: digest(ROOT / "server/archive_backend" / name)
                                        for name in ("service.py", "bundle.py", "config_compatibility.py")},
              "changed_configs": changed_configs, "changed_sources": changed_sources,
              "all_other_configs_preserved": True, "commerce_lottery_player_stat_schema_preserved": True,
              "legacy_bundle_hashes_preserved": preserved, "legacy_compatibility": candidate.compatible_config_hashes,
              "candidate_validation": validation, "production_pointers_unchanged": before == [path.read_bytes() for path in pointers],
              "deployment_execution": False, "online_access": False,
              "integration_requirements": ["Review candidate archive_sync_config allowlist-only SQL, validate against PostgreSQL rollback fixture before execution.",
                  "Merge this archive-only overlay into a newly copied, verified current backend release; regenerate its complete manifest before manage.py prepare/activate.",
                  "Preserve current fishing API/payment/login sources, credentials, DB records, all old bundles and receipt fingerprints.",
                  "Switch game hash only after backend activation/config verification, then start a new match."]}
    # Frozen sets are serialized as reviewed arrays, matching bundle metadata.
    report["legacy_compatibility"] = {key: {name: sorted(values) for name, values in rule.items()}
                                      for key, rule in report["legacy_compatibility"].items()}
    (OUT / "reward_release_ready.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("REWARD_RELEASE_READY", candidate_hash, "checks=" + str(validation["checks"]), "manifest=PASS", "deployed=false")


if __name__ == "__main__":
    main()
