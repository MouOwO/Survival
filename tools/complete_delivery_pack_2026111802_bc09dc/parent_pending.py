"""Pinned complete0804 parent; no source relabelling, SDK or filesystem mutation."""
from pathlib import Path
from collections import Counter
import json, hashlib
import release_pending_inventory as legacy
ROOT = Path(__file__).resolve().parents[2]
CONTENT = legacy.CONTENT
BASELINE = ROOT / 'output/release_baselines/complete/2026111609_9b1ca433dd0c64ea2b247d658da07858aad5f10cd14a08f8c129a61286a0243f.json'
BASELINE_SHA256 = '9b1ca433dd0c64ea2b247d658da07858aad5f10cd14a08f8c129a61286a0243f'
PARENT_MANIFEST = Path('D:\\Survival_发布候选\\pack_2026111609_9ade313c_view\\_release_manifest.json')
PARENT_AUTHORITY_SHA256 = '64849fbdabd9052f26636bb7428774cba3eb603d21c77a9f89506f319322b780'
JOURNAL_RECORD = ROOT / 'output/packager/pack_2026111802_ebbc09dc/parent_journal.json'
JOURNAL_RECORD_SHA256 = '5aaca399399bcf06b605434b724d185fe25b0427c8c5e999aaa41da2822e2956'
EXECUTED_SOURCE_LF_SHA256 = hashlib.sha256(Path(__file__).read_bytes().replace(b'\r\n', b'\n')).hexdigest()

def __getattr__(name):
    return getattr(legacy, name)

def read(path, pin):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError('bounded_regular_parent_evidence_required')
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != pin:
        raise ValueError('immutable1609_parent_evidence_changed')
    return json.loads(raw)

def evidence():
    base = read(BASELINE, BASELINE_SHA256)
    ev = base['complete_delivery']
    if base['parent_sequence'] != 2026111609 or base['deferred_sources'] != {} or ev['authority_sha256'] != PARENT_AUTHORITY_SHA256:
        raise ValueError('exact_complete0804_parent_required')
    manifest = read(PARENT_MANIFEST, base['parent_manifest_sha256'])
    report = read(ev['report_path'], ev['report_sha256'])
    receipt = read(ev['receipt_path'], ev['receipt_sha256'])
    journal = read(JOURNAL_RECORD, JOURNAL_RECORD_SHA256)
    if JOURNAL_RECORD_SHA256 != ev['canonical_journal_sha256']:
        raise ValueError('parent_journal_checkpoint_changed')
    from release_delivery_state import report as delivery
    status = delivery(dict(local_package=report, local_package_report_sha256=ev['report_sha256'], expected_source_revisions=base['source_anchors'], journal=journal, journal_sha256=JOURNAL_RECORD_SHA256, download_receipt=receipt, local_resources=manifest['files'], published_resources=manifest['files'], pending_source_changes=[]))
    if not status['workshop_synchronized'] or report['release_sequence'] != 2026111609 or report['content_sha256'] != base['parent_content_sha256'] or (receipt['steam_manifest'] != base['official_parent_manifest']):
        raise ValueError('actual1609_sdk_signature_and_official_receipt_required')
    if hashlib.sha256(__import__('complete_delivery_pack_2026111802_bc09dc.pipeline_recipe', fromlist=['canonical']).canonical(base['source_inventory'])).hexdigest() != base['source_inventory_sha256']:
        raise ValueError('parent_source_inventory_changed')
    if hashlib.sha256(__import__('complete_delivery_pack_2026111802_bc09dc.pipeline_recipe', fromlist=['canonical']).canonical(base['resource_origins'])).hexdigest() != base['resource_origins_sha256']:
        raise ValueError('parent_resource_origins_changed')
    return (base, manifest, report, receipt, journal)

def inventory():
    base, manifest, _, _, _ = evidence()
    counts = Counter()
    trees = {}
    commits = {}
    dirty = []
    for role, repo in [('game', ROOT), ('content', CONTENT)]:
        commits[role] = legacy._git(repo, 'rev-parse', 'HEAD', counts=counts).decode().strip()
        trees[role] = legacy.git_tree(repo, counts, commits[role])
        dirty.extend(legacy.git_dirty(repo, role, counts))
    keys = legacy.pending_source_keys(base['source_inventory'], trees, base['deferred_sources'])
    budget = legacy.HashBudget()
    facts = {}
    for role, repo in [('game', ROOT), ('content', CONTENT)]:
        paths = {p for r, p in keys if r == role}
        if paths:
            facts.update(((role + ':' + p, v) for p, v in legacy.read_git_facts(repo, trees[role], paths, budget, counts).items()))
    policy = json.loads((ROOT / 'tools/lua_protection_policy.json').read_bytes())
    production = set(policy['business_modules'])
    for name in set(base['source_inventory']['game']) | set(trees['game']):
        if name.startswith(policy['generated_prefix']) and Path(name).name not in policy['generated_exclusions']:
            production.add(name)
    result = legacy.classify_inventory(baseline_inventory=base['source_inventory'], head_inventory=trees, parent_manifest=manifest, deferred_sources=base['deferred_sources'], blob_facts=facts, dirty=dirty, production_resources=production)
    result.update(target_commits=commits, baseline_mode='AUTHENTICATED_COMPLETE0804_PARENT', recorded_parent_sequence=2026111609, recorded_parent_manifest_sha256=base['parent_manifest_sha256'], recorded_parent_content_sha256=base['parent_content_sha256'], recorded_parent_steam_manifest=base['official_parent_manifest'], call_counts=dict(counts), sdk_calls=0, network_calls=0)
    return result

def main(argv=None):
    print(json.dumps(inventory(), ensure_ascii=True))
    return 0
