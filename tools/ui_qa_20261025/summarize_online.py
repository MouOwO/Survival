"""Summarize fixed native test-entry logs without exporting identities or tokens.

This observes client success receipts. It does not independently inspect a cloud
database or claim an entire payment transaction completed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "output/test_entry_runtime"
OUT = ROOT / "output/ui_qa_20261025/online"


def summarize(label: str) -> dict:
    if not re.fullmatch(r"[a-z0-9_]{1,40}", label):
        raise ValueError("invalid_summary_label")
    receipt = json.loads((ENTRY / "online_latest.json").read_text(encoding="utf-8"))
    if receipt.get("mode") != "online" or receipt.get("addon") != "svt_w24":
        raise ValueError("fixed_online_entry_required")
    log = Path(receipt["log_file"])
    if (log.parent.resolve() != ENTRY.resolve() or log.is_symlink()
            or not re.fullmatch(r"online_[0-9_]+\.log", log.name)
            or receipt.get("started_utc", "") < "2026-10-24T16:06:39"):
        raise ValueError("current_task_online_log_required")
    raw = log.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    profiles = []
    # Export only these fixed fields, never whole matching lines.
    for match in re.finditer(
            r"public_profile_published provider_id=([a-z_]+) [^\r\n]*?revision=(\d+) [^\r\n]*?reason=([a-z_]+)", text):
        profiles.append(dict(provider=match[1], revision=int(match[2]), reason=match[3]))
    result = dict(schema=1, captured_utc=datetime.now(timezone.utc).isoformat(),
                  scope="native_online_client_receipts_not_independent_cloud_DB_verification",
                  mode="online", addon="svt_w24", pid=receipt["pid"],
                  started_utc=receipt["started_utc"], log_file=log.relative_to(ROOT).as_posix(),
                  log_bytes=len(raw), log_sha256=hashlib.sha256(raw).hexdigest(),
                  profile_publications=profiles,
                  checkpoint_responses=text.count("[OnlineTime] checkpoint_response "),
                  checkpoint_failures=text.count("[OnlineTime] checkpoint_failed "),
                  admission_api_diagnostic_count=text.count("[WS4-WEB-04]"),
                  offline_qa_probe_present="[UI_QA_REVIEW_" in text,
                  defeat_count=text.count("[PLAYER_DEFEAT]"),
                  independent_cloud_database_verification=False,
                  real_payments_attempted=False, native_visual_review="SEPARATELY_REQUIRED")
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / (label + "_client_summary.json")
    with target.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=True, indent=2)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("label")
    args = parser.parse_args()
    try:
        result = summarize(args.label)
        print(json.dumps(dict(scope=result["scope"], pid=result["pid"],
                              profile_publications=len(result["profile_publications"]),
                              latest_profile=result["profile_publications"][-1:] or None,
                              checkpoint_responses=result["checkpoint_responses"],
                              checkpoint_failures=result["checkpoint_failures"],
                              defeat_count=result["defeat_count"],
                              log_sha256=result["log_sha256"],
                              report="output/ui_qa_20261025/online/"+args.label+"_client_summary.json"),
                         ensure_ascii=True))
    except Exception:
        print(json.dumps({"ok": False, "error": "native_online_summary_failed"}))
        raise SystemExit(1)
