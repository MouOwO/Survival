"""Minimal VIP service overlay based on the freshly verified production files."""
from pathlib import Path
import hashlib
import io
import json
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/vip_recharge_20261016/release'
BASE = ROOT / 'design_refs/vip_recharge_20261016/deployment/online_baseline/archive'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((BASE / 'release_manifest.json').read_bytes())
    preflight = json.loads((ROOT / 'design_refs/vip_recharge_20261016/deployment/online_preflight.json').read_bytes())
    files = {}
    for name in ('service.py', 'endless_leaderboard.py'):
        original = (BASE / 'backend/archive_backend' / name).read_text(encoding='utf-8')
        backup = (ROOT / 'design_refs/vip_recharge_20261016/baseline/server/archive_backend' / name).read_text(encoding='utf-8-sig')
        current = (ROOT / 'server/archive_backend' / name).read_text(encoding='utf-8-sig')
        if name == 'service.py':
            hook = '    from .vip_progression import install as install_vip_progression\n    install_vip_progression(service)\n'
            assert current.replace(hook, '') == backup, 'unexpected_local_task_change'
            anchor = '    install_endless_leaderboard(service)\n    return service\n'
            assert original.count(anchor) == 1, 'online_install_anchor_changed'
            current = original.replace(anchor, '    install_endless_leaderboard(service)\n' + hook + '    return service\n')
        else:
            assert original == backup, 'local_baseline_diverged:' + name
        files['backend/archive_backend/' + name] = current.encode()
    files['backend/archive_backend/vip_progression.py'] = (ROOT / 'server/archive_backend/vip_progression.py').read_bytes()
    files['ranking.sql'] = (ROOT / 'server/migrations/202610160002_leaderboard_vip_badges.sql').read_bytes()
    files['rollback_ranking.sql'] = preflight['leaderboard_function']['definition'].encode()
    for name, raw in files.items():
        dest = OUT / 'payload' / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
    with tarfile.open(OUT / 'overlay.tar.gz', 'w:gz') as tar:
        for name, raw in sorted(files.items()):
            entry = tarfile.TarInfo(name)
            entry.size = len(raw)
            entry.mode = 0o644
            tar.addfile(entry, io.BytesIO(raw))
    plan = {'version': 1, 'kind': 'vip_recharge_progression',
        'old_release': preflight['archive_release'], 'old_payment': preflight['payment_release'],
        'target_release': '/opt/goufayu/releases/20261016-vip-recharge-v1',
        'bundle': preflight['bundle'], 'old_manifest_sha': sha((BASE / 'release_manifest.json').read_bytes()),
        'old_ranking_sha': sha(files['rollback_ranking.sql']),
        'cash_hash': '730784ed954ed3aba0fb000e7d3a6689ae9494a64d81063162bebde0a5e91a34',
        'apply_sha': '6bef548e25b839749ce042748aa3f79ad5ae43c6fa898bedd785c9b940f038f5',
        'sync_sha': '5dd027838dbce67e49da61ecb36c533e8904a9ad637fcb63b52f6b720993a4dd',
        'files': {name: sha(raw) for name, raw in files.items()},
        'old_backend': {name: metadata['files'][name] for name in files if name.startswith('backend/') and name in metadata['files']},
        'tar_sha256': sha((OUT / 'overlay.tar.gz').read_bytes()),
        'payment_source_changes': 0, 'product_price_changes': 0, 'new_tables': 0}
    (OUT / 'release_plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'BUILT', 'files': len(files), 'plan_sha256': sha((OUT / 'release_plan.json').read_bytes()),
                      'target_release': plan['target_release'], 'bundle_unchanged': plan['bundle']}))


if __name__ == '__main__':
    main()
