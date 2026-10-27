"""Plan by default; explicit audit is read-only, prepare writes a new private stage."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path

from deploy_plan import ROOT, TRANSPORT_PIN, build, canonical, encoded_files


def remote(mode, plan, files=None):
    driver = ROOT / "tools/archive_caps_20261020/remote_driver.py"
    if hashlib.sha256(driver.read_bytes()).hexdigest() != TRANSPORT_PIN:
        raise ValueError("pinned_ssh_transport_changed")
    spec = importlib.util.spec_from_file_location("reviewed_ws4_payment_transport", driver)
    transport = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    source = Path(__file__).with_name("remote_review.py").read_text(encoding="utf-8")
    if hashlib.sha256(source.encode()).hexdigest() != plan["source_hashes"]["review_tools/remote_review.py"]:
        raise ValueError("reviewed_operator_changed")
    source += "\nmain(" + repr(mode) + "," + repr(plan) + "," + repr(encoded_files(files) if files is not None else None) + ")\n"
    value = json.loads(transport.remote(source, timeout=55))
    if value.get("ok") is not True or value.get("plan_sha256") != plan["plan_sha256"]:
        raise RuntimeError("reviewed_ws4_payment_remote_check_failed")
    return value


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", nargs="?", choices=("plan", "audit", "prepare"), default="plan")
    parser.add_argument("--review-hash", help="Required exact plan hash for new-directory preparation")
    parser.add_argument("--save-plan", action="store_true", help="Write public plan into ignored output for review")
    parser.add_argument("--cloud-snapshot", type=Path, help="Reviewed fixed WS4 configuration snapshot under ignored output")
    args = parser.parse_args(argv)
    if args.mode == "prepare" and not args.review_hash:
        parser.error("prepare requires the concrete reviewed --review-hash")
    if args.mode != "prepare" and args.review_hash is not None:
        parser.error("--review-hash applies only to prepare")
    return args


def main(argv=None):
    args = arguments(argv)
    plan, files = build(cloud_snapshot=args.cloud_snapshot) if args.cloud_snapshot else build()
    if args.mode == "prepare" and args.review_hash != plan["plan_sha256"]:
        raise ValueError("reviewed_candidate_changed")
    value = plan if args.mode == "plan" else remote(args.mode, plan, files if args.mode == "prepare" else None)
    record = None
    if args.save_plan or args.mode != "plan":
        directory = ROOT / "output/arcade_payment_link_20261027"
        directory.mkdir(parents=True, exist_ok=True)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        record = directory / (args.mode + "_" + stamp + ".json")
        with record.open("xb") as stream:
            stream.write(canonical(value))
    summary = {"mode": args.mode, "plan_sha256": plan["plan_sha256"], "catalog": plan["catalog"],
               "staged_files": len(files), "payments_enabled": False, "activation_implemented": False,
               "record": str(record) if record else None}
    if args.mode == "audit":
        summary.update(bundle_all_sources_match=value["bundle"]["all_sources_match"],
                       missing_capability_functions=value["ws4_schema"]["missing_capability_functions"],
                       payment_tables=len(value["ws4_schema"]["tables"]),
                       payment_functions=len(value["ws4_schema"]["functions"]),
                       legacy_processes_unchanged=value["unchanged"])
    if args.mode == "prepare":
        summary.update(remote_stage=value["stage"], existing_services_unchanged=value["existing_services_unchanged"])
    print(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
