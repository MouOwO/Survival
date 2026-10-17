"""Tie the shipped VIP overlay to its native, database and UI evidence."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/vip_recharge_20261016'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(name):
    return json.loads((OUT / name).read_bytes())


def main():
    candidate = read('game/candidate_validation.json')
    ui = read('ui/validation.json')
    deployed = read('deployment/vip_activate.json')
    independent = read('deployment/independent_verify.json')
    plan = read('release/release_plan.json')
    assert candidate['status'] == ui['status'] == 'PASS'
    assert deployed['status'] == 'VERIFIED'
    assert independent['status'] == 'PASS' and independent['archive_release'] == deployed['archive_release']
    assert candidate['bundle_hash'] == deployed['archive_bundle'] == plan['bundle']
    for name, digest in candidate['source_sha256'].items():
        assert sha(OUT / 'release/payload/backend/archive_backend' / name) == digest
        assert plan['files']['backend/archive_backend/' + name] == digest
    for record in ui['files']:
        assert sha(ROOT / record['file']) == record['sha256'], 'ui_source_drift'
    files = ['server/archive_backend/vip_progression.py', 'server/archive_backend/service.py',
             'server/archive_backend/endless_leaderboard.py',
             'server/migrations/202610160002_leaderboard_vip_badges.sql',
             'scripts/vscripts/systems/endless_leaderboard_service.lua']
    files += [record['file'] for record in ui['files']]
    completion = {'status': 'DEPLOYED_WITH_NATIVE_GAME_LIMITATION',
        'rules': {'source': 'archive_vip_levels.csv + archive_vip_rewards.csv',
            'real_paid_fen_only': True, 'inclusive_thresholds': True,
            'automatic_free_privileges': 12, 'paid_packages_remain_purchase_gated': True,
            'medals_require_actual_package_ownership': True, 'badge_levels': 'VIP1..VIP12'},
        'validation': {'candidate_native_lua_groups': candidate['groups'],
            'threshold_subcases': candidate['threshold_subcases'], 'http_and_ranking_groups': 18,
            'native_transport_groups': 14, 'ui_suites': len(ui['tests']), 'compiled_sources': len(ui['files']),
            'independent_online_checks': independent['check_count'],
            'actual_payment_gateway_used': False, 'native_game_ui_verified': False},
        'deployment': deployed,
        'source_files': {name: sha(ROOT / name) for name in files},
        'git_commit_or_push_performed': False,
        'preexisting_local_changes_preserved': True,
        'scope_isolation': 'Published service.py uses fresh production baseline plus exactly two install lines; unrelated local cooperative code was preserved locally.',
        'remaining': ['Start a new game to load the updated VScript ranking bridge and compiled UI; screenshots are isolated production-component previews.']}
    (OUT / 'completion.json').write_text(json.dumps(completion, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': completion['status'], 'archive_release': deployed['archive_release'],
                      'production_sources': len(files), 'vip_levels': 12, 'compiled_sources': 7}))


if __name__ == '__main__':
    main()
