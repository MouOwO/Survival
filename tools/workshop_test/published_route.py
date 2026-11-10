"""Select an already published installation; never authorize candidate staging.

One startup reads bounded release records and five file sizes, O(package files).
No source gate, install, SDK call, process, polling or gameplay work is changed.
An unpublished authority always keeps the canonical signed-test route.
"""
from pathlib import Path
import json
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))


def select(current, policy):
    report, cursor = current['report'], current['cursor']
    evidence = current['baseline']['complete_delivery']
    if (report.get('release_sequence') != policy.get('release_sequence')
            or cursor.get('release_sequence') != policy.get('release_sequence')
            or Path(evidence['report_path']).parent.resolve() != Path(policy['report_directory']).resolve()):
        return {'ok': False, 'reason': 'unpublished_candidate_requires_signed_test'}
    if (str(policy.get('workshop_id')) != '3824360109'
            or evidence.get('signature_valid') is not True
            or evidence.get('official_full_installation_reverified') is not True
            or evidence.get('steam_manifest') != cursor.get('official_steam_manifest')):
        return {'ok': False, 'reason': 'published_delivery_not_verified'}
    return dict(ok=True, mode='published_workshop', workshop_id='3824360109',
                release_sequence=report['release_sequence'], steam_manifest=evidence['steam_manifest'],
                installation_changed=False, local_candidate_staged=False, publication_performed=False)


def inspect_current():
    from release_packager.core import baseline
    import release_pipeline
    current = baseline(ROOT)
    result = select(current, release_pipeline.authority().policy)
    if not result['ok']:
        return result
    installed = ROOT.parents[4] / 'workshop/content/570/3824360109'
    files = current['report']['package_files']
    if (len(files) > 16 or {p.name for p in installed.iterdir()} != {row['name'] for row in files}
            or any(not (installed / row['name']).is_file()
                   or (installed / row['name']).is_symlink()
                   or (installed / row['name']).stat().st_size != row['bytes'] for row in files)):
        return {'ok': False, 'reason': 'published_installation_not_ready'}
    return result


if __name__ == '__main__':
    try:
        value = inspect_current()
    except (OSError, ValueError, KeyError, RuntimeError):
        value = {'ok': False, 'reason': 'published_route_not_verified'}
    print(json.dumps(value, ensure_ascii=True))
