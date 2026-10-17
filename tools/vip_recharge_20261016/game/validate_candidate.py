"""Exercise the minimal release backend, rather than dirty workspace modules."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend-dir', type=Path, required=True,
                        help='Candidate backend directory containing archive_backend')
    parser.add_argument('--baseline-backend-dir', type=Path,
                        default=ROOT / 'design_refs/vip_recharge_20261016/deployment/online_baseline/archive/backend',
                        help='Unmodified online backend used under the candidate overlay')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'design_refs/vip_recharge_20261016/game/candidate_validation.json')
    args = parser.parse_args()
    backend = args.backend_dir.resolve(strict=True)
    source = backend / 'archive_backend'
    baseline_backend = args.baseline_backend_dir.resolve(strict=True)
    baseline_source = baseline_backend / 'archive_backend'
    if not (baseline_source / 'bundle.py').is_file():
        raise FileNotFoundError(baseline_source / 'bundle.py')
    for name in ('service.py', 'vip_progression.py', 'endless_leaderboard.py'):
        if not (source / name).is_file():
            raise FileNotFoundError(source / name)
    sys.path.insert(0, str(ROOT))
    sys.path.insert(0, str(ROOT / 'server'))
    sys.path.insert(0, str(backend))
    # The deployment is a three-file overlay, deliberately without a second
    # __init__.py. Mirror that overlay without letting Python fall back to the
    # workspace's regular package and accidentally test unrelated local edits.
    package = types.ModuleType('archive_backend')
    package.__package__ = 'archive_backend'
    package.__path__ = [str(source), str(baseline_source)]
    sys.modules['archive_backend'] = package
    import archive_backend.service as candidate
    import archive_backend.vip_progression as progression
    import archive_backend.endless_leaderboard as ranking
    for module in (candidate, progression, ranking):
        if Path(module.__file__).resolve().parent != source:
            raise RuntimeError('candidate_import_not_isolated:' + str(module.__file__))
    from server.tests.test_vip_progression import VipProgressionTests
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(VipProgressionTests))
    report = {
        'ok': result.wasSuccessful(), 'status': 'PASS' if result.wasSuccessful() else 'FAIL',
        'groups': result.testsRun,
        'threshold_subcases': 36, 'native_lua_worker': VipProgressionTests.lua,
        'bundle_hash': VipProgressionTests.bundle.hash,
        'backend_directory': str(backend),
        'baseline_backend_directory': str(baseline_backend),
        'module_paths': {module.__name__: str(Path(module.__file__).resolve())
                         for module in (candidate, progression, ranking)},
        'seconds': round(time.monotonic() - started, 3),
        'source_sha256': {name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                          for name in ('service.py', 'vip_progression.py', 'endless_leaderboard.py')},
        'failures': [{'test': str(test), 'traceback': trace} for test, trace in result.failures],
        'errors': [{'test': str(test), 'traceback': trace} for test, trace in result.errors],
        'skipped': [str(test) for test, _ in result.skipped],
        'network_access': False, 'real_orders': False, 'real_player_save_writes': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
