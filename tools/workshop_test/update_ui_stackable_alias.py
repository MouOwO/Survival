"""Read-only plan or exact three-resource v07 -> v08 update of fixed svt_w24.

Load the reviewed transactional updater in an independent namespace. Historical
v06 code/globals, the immutable candidates and all non-allowlisted files stay
untouched. The shared alias lock/backup journal protects against concurrent
updates. A native Dota process blocks apply. No game launch or publication.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_ui_stackable_candidate as builder

ROOT, web = builder.ROOT, builder.web
ENGINE_FILE = Path(__file__).with_name("update_ui_qa_alias.py")
ENGINE_SHA = "f4df4b0754e75af84c004463cc819c870748ec332c49e3603187810a48bb2190"
CANDIDATE = Path("D:/Survival_发布候选/20261025_ws4_ui_stackable_v08")
TRUSTED = CANDIDATE.with_name(CANDIDATE.name + "_trusted_source")
OLD_RECEIPT_SHA = "7e274530752371e53e7c1af072526a0cefaf06fdc9fdc35362fbf14112146f7d"
ENGINE_ORIGINAL_RECEIPT_SHA = "530d86c05af6d35cd51016384d0dcae1e1372f6c09d0d3849ce8494c9ffed0bc"
# The owner pins this only after explicitly building/signing the exact v08.
# Unset is deliberately unusable, including read-only installation plans.
CANDIDATE_SHA = "88611d026e49c52b5bce7324818f36a11a60059a2844b8f646b884ba15debaa9"


def require_candidate_pin():
    if not isinstance(CANDIDATE_SHA, str) or not re.fullmatch(r"[0-9a-f]{64}", CANDIDATE_SHA):
        raise RuntimeError("stackable_alias_candidate_not_pinned")


def load_engine():
    """Never reassign globals on the normally imported historical updater."""
    raw = ENGINE_FILE.read_bytes()
    if web.sha(raw) != ENGINE_SHA:
        raise RuntimeError("stackable_alias_transaction_engine_changed")
    spec = importlib.util.spec_from_file_location("_ws4_archive_stackable_alias_engine", ENGINE_FILE)
    if spec is None or spec.loader is None:
        raise RuntimeError("stackable_alias_transaction_engine_unavailable")
    engine = importlib.util.module_from_spec(spec)
    # Execute the exact bytes just hashed, rather than letting the loader read
    # the file a second time between its identity check and execution.
    exec(compile(raw, str(ENGINE_FILE), "exec"), engine.__dict__)
    # Check the exact prior release receipt before replacing this private
    # instance's globals. The actual installed receipt is independently pinned
    # and checked by old_receipt plus complete old inventory verification.
    if web.sha(engine.updated_receipt()) != ENGINE_ORIGINAL_RECEIPT_SHA:
        raise RuntimeError("stackable_alias_prior_receipt_contract_changed")
    engine.builder = builder
    engine.web, engine.pack = builder.web, builder.pack
    engine.ROOT = ROOT
    engine.TARGET = ROOT.parent / "svt_w24"
    engine.CANDIDATE, engine.TRUSTED = CANDIDATE, TRUSTED
    engine.CANDIDATE_SHA = CANDIDATE_SHA
    engine.OLD_RECEIPT_SHA = OLD_RECEIPT_SHA
    engine.ALLOWLIST = builder.ALLOWLIST
    # Preserve the original fixed store and shared lock. Its legacy v06_ UUID
    # directory label is not a release identity; signed SHA/sequence and exact
    # receipt in the journal identify v07 -> v08 without changing the engine.
    engine.STORE = ROOT / "output/ui_qa_20261025/release/alias_updates"
    return engine


def run(*, apply=False):
    require_candidate_pin()
    builder.require_review_pins()
    engine = load_engine()
    result = engine.run(apply=apply)
    result.update(revision=builder.REVISION, previous_revision="WS4-UI-FONT-WALLET-07",
                  transaction_engine_sha256=ENGINE_SHA)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Only after fixed v07/v08 checks and Dota exit")
    args = parser.parse_args()
    try:
        result = run(apply=args.apply)
    except BaseException as error:
        if hasattr(error, "report") and isinstance(error.report, dict):
            result = dict(error.report, revision=builder.REVISION)
        else:
            value = str(error)
            code = value if re.fullmatch(r"[a-z][a-z0-9_]{0,79}", value) else "stackable_alias_update_failed"
            result = dict(ok=False, error=code, changed=False, game_started=False,
                          workshop_upload_performed=False, revision=builder.REVISION)
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result["ok"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
