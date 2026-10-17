"""Run VIP integration checks without network or production database writes."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from server.tests.test_vip_progression import VipProgressionTests


if __name__ == '__main__':
    started = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(VipProgressionTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    source_files = ['server/archive_backend/vip_progression.py',
                    'server/archive_backend/service.py',
                    'server/tests/test_vip_progression.py']
    report = {
        'ok': result.wasSuccessful(), 'groups': result.testsRun,
        'threshold_subcases': 36, 'thresholds': 12,
        'native_lua_worker': VipProgressionTests.lua,
        'bundle_hash': VipProgressionTests.bundle.hash,
        'seconds': round(time.monotonic() - started, 3),
        'failures': [{'test': str(test), 'traceback': trace} for test, trace in result.failures],
        'errors': [{'test': str(test), 'traceback': trace} for test, trace in result.errors],
        'skipped': [str(test) for test, reason in result.skipped],
        'source_sha256': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                          for name in source_files},
        'network_access': False, 'real_orders': False, 'real_player_save_writes': False,
        'coverage': ['12 exact recharge thresholds and +/-1 fen', 'cumulative cross-tier effects',
                     'recharge rather than cached grade, wallet, or entitlement',
                     'wallet spending never downgrades VIP', 'stable automatic receipts',
                     'manual-claim interoperability', 'lost reply after commit',
                     'optimistic-lock conflict preserves concurrent stats',
                     'no automatic paid package purchases or medals',
                     'legacy inventory claims', 'four synthetic account isolation',
                     'actual marketplace eligibility refresh',
                     'actual marketplace purchase and medal grant',
                     'invalid progress and foreign identity rejected',
                     'full production install chain retains leaderboard hook'],
    }
    output = ROOT / 'design_refs/vip_recharge_20261016/game'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'native_validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                                                  encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
