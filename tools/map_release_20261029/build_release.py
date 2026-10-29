"""Signed map/placement update over the immutable uploaded 2901 release.

Only the main map and an explicit set of committed placement modules may
change. Existing protected Lua, account gates, UI, payments and backend bundle
remain byte-for-byte intact. Default is a read-only plan; --build writes NEW
external artifacts. No upload, game restart, database or Git mutation.
"""
from pathlib import Path
import argparse, copy, hashlib, importlib.util, json, subprocess, sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('map2902_parent', ROOT / 'tools/map_resources_20261028/build_map_resources.py')
parent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parent)
inc, pack, need = parent.incremental, parent.pack, parent.need
import protect_runtime_lua as protection

ITEM, SEQUENCE, REVISION = '3824360109', 2026102902, 'WS4-MAP-UPDATE-02'
BASE = Path('D:/Survival_发布候选/20261029_ws4_archive_all_v01_view')
BASE_TRUSTED = Path('D:/Survival_发布候选/20261029_ws4_archive_all_v01_trusted_source')
BASE_VPK = Path('D:/Survival_工坊输出/20261029_ws4_archive_all_v01/3824360109.vpk')
BASE_REPORT = ROOT / 'output/release_archive_20261029/workshop_build/package.json'
BASE_REPORT_SHA = '39a6877ce20132efcf96cdfb3f435ab6f759d5ba6ab5bd2258fefe2fd0501cd7'
BASE_CONTENT = '7eee7d5b975573da3e26b2f8fcf079cbc346e33e4a06dc7f7c1c7280691e46ba'
JOURNAL = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
OVERLAY = Path('D:/Survival_发布候选/20261029_ws4_map_v02_overlay')
TRUSTED = Path('D:/Survival_发布候选/20261029_ws4_map_v02_trusted_source')
VIEW = Path('D:/Survival_发布候选/20261029_ws4_map_v02_view')
OUTPUT = Path('D:/Survival_工坊输出/20261029_ws4_map_v02')
REPORT_DIR = ROOT / 'output/map_publish_20261029'
MAP = 'maps/template_map.vpk'
SOURCE = ROOT.parents[2] / 'content/dota_addons/Survival/maps/template_map.vmap'
PROOF = REPORT_DIR / 'compile/verification.json'
LUA_NAMES = (
    'config/mode_release_config.lua', 'config/mode_spawn_config.lua', 'config/tree_config.lua',
    'systems/builder_service.lua', 'systems/builder_work_position_service.lua',
    'systems/destination_validation_service.lua', 'systems/grid_placement_system.lua',
    'systems/match_setup_service.lua', 'systems/mode_spawn_service.lua',
    'systems/player_context_service.lua', 'systems/rich_region_service.lua',
    'systems/tree_system.lua', 'systems/valley_environment_service.lua',
    'systems/wall_target_service.lua', 'systems/wave_spawn_routing.lua',
    'systems/wave_system.lua', 'ui/grid_placement_router.lua',
)


def load(path):
    return pack.handoff.load_json(path)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def checks(raw):
    return dict(bytes=len(raw), md5=hashlib.md5(raw).hexdigest(), sha256=sha(raw))


def project(before, values, policy):
    allowed = {MAP, *('scripts/vscripts/' + n for n in LUA_NAMES)}
    old = {r['path']: r for r in before['files']}
    need(MAP in values and set(values) <= allowed and set(values) <= old.keys(),
         'Only the main map and explicit existing placement modules may change')
    protected = {r['path'] for r in protection.selected_files(list(old), policy)}
    need(len(protected) == 184 and not protected.intersection(values), 'Protected Lua must remain unchanged')
    after = copy.deepcopy(before)
    rows = copy.deepcopy(old)
    for name, raw in values.items():
        rows[name] = dict(path=name, **checks(raw))
    after['files'] = [rows[name] for name in sorted(rows)]
    after['bytes'] = sum(r['bytes'] for r in after['files'])
    after['content_sha256'] = sha(pack.runtime.manifest_payload(after))
    pack.runtime.validate_manifest(after)
    return after


def payloads():
    proof = load(PROOF)
    need(proof.get('status') == 'PASS', 'Actual matching map-source verification required')
    source, package = proof['source'], proof['package']
    raw = (ROOT / MAP).read_bytes()
    need(checks(raw)['sha256'] == package['sha256'] and len(raw) == package['bytes'], 'Compiled map changed')
    need(pack.runtime.digest(SOURCE) == source['sha256'], 'Hammer source changed after compilation')
    need(proof['source_match']['matches'] is True, 'Map source CRC mismatch')
    need(all(row['crc_matches'] for row in package['entries']), 'Map resource CRC mismatch')
    values = {MAP: raw}
    for name in LUA_NAMES:
        relative = 'scripts/vscripts/' + name
        values[relative] = subprocess.check_output(['git', 'show', 'HEAD:' + relative], cwd=ROOT)
    return values


def run(build=False, key=None, reviewed=None):
    for dest in (OVERLAY, TRUSTED, VIEW, OUTPUT):
        pack.handoff.regular_path(dest, must_exist=False)
        need(not dest.exists() and not pack.runtime.within(dest, pack.handoff.INSTALL), 'New external output required')
    need(pack.runtime.digest(BASE_REPORT) == BASE_REPORT_SHA, '2901 report drift')
    original = load(BASE_REPORT)
    state = load(JOURNAL)
    need(state.get('uploaded') is True and state.get('release_sequence') == 2026102901
         and state.get('workshop_id') == ITEM and state.get('content_sha256') == BASE_CONTENT,
         'Original successful 2901 upload journal required; preserve pending state')
    journal_sha = pack.runtime.digest(JOURNAL)
    with inc.trusted_source(BASE_TRUSTED):
        _, before, signed, baseline_metadata = pack.authenticate(BASE)
    need(before['content_sha256'] == BASE_CONTENT and signed['release_sequence'] == 2026102901,
         'Signed 2901 baseline mismatch')
    inventory = pack.package_inventory(BASE_VPK)
    need(inventory == original['package_files'] == state['package_files'], '2901 archive identity mismatch')
    pack.verify_vpk(BASE_VPK, before)
    values = payloads()
    old = {r['path']: r for r in before['files']}
    need(set(values) <= old.keys(), 'Map update cannot introduce unreviewed runtime paths')
    values = {name: raw for name, raw in values.items() if checks(raw)['sha256'] != old[name]['sha256']}
    need(MAP in values, 'The map must actually change')
    policy = load(ROOT / 'tools/lua_protection_policy.json')
    review = {name: (BASE_TRUSTED / name).read_bytes() for name in inc.all_files(BASE_TRUSTED)}
    need(len(review) == 16 and not set(review).intersection(values), 'Admission review files must remain unchanged')
    need('scripts/vscripts/config/generated/archive_http_bundle.lua' not in values, 'Backend bundle must remain unchanged')
    after = project(before, values, policy)
    tree, groups, rewritten, moves = parent.rotation_plan(inc.read_entries(BASE_VPK), before, after, set(values))
    sizes = [sum(i['row']['bytes'] for i in group) for group in groups]
    disk = inc.capacity(VIEW, OUTPUT, sum(len(v) for v in values.values()) * 2 + 2**22,
                        sum(sizes[i] for i in rewritten), pack.HEADER.size + len(tree) + 48, 0)
    plan = dict(schema=1, revision=REVISION, release_sequence=SEQUENCE, workshop_id=ITEM,
        source_git_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        baseline_release_sequence=2026102901, baseline_content_sha256=BASE_CONTENT,
        baseline_download_verified=False, canonical_journal_sha256=journal_sha,
        content_sha256=after['content_sha256'], files=after['file_count'],
        changed_runtime_paths=sorted(values), target_pins={n: checks(v) for n, v in values.items()},
        map_proof_sha256=pack.runtime.digest(PROOF), map_source_sha256=pack.runtime.digest(SOURCE),
        protected_modules_preserved=184, protected_modules_rebuilt=0,
        authentication_payment_ui_backend_preserved=True, trusted_review_files=16,
        rebuilt_archives=sorted(rewritten), archive_migrations=moves, disk_preflight=disk,
        candidate=str(VIEW), trusted_source=str(TRUSTED), output=str(OUTPUT / (ITEM + '.vpk')),
        container_bytes=after['bytes'] + pack.HEADER.size + len(tree) + 48)
    need(pack.runtime.digest(JOURNAL) == journal_sha, 'Publication journal changed during plan')
    if not build:
        return plan
    need(reviewed is not None and load(reviewed) == plan, 'Reviewed map plan changed')
    need(key is not None, 'Existing external signing key required')
    key = pack.handoff.regular_path(pack.protect_data.external(key, source=BASE))
    for dest in (OVERLAY, TRUSTED, VIEW, OUTPUT):
        need(not pack.runtime.within(key, dest) and not pack.runtime.within(dest, key.parent), 'Key/output overlap')
    OVERLAY.mkdir(parents=True)
    TRUSTED.mkdir(parents=True)
    for name, raw in values.items():
        inc.write_new(OVERLAY / name, raw)
    for name, raw in review.items():
        inc.write_new(TRUSTED / name, raw)
    inc.write_new(OVERLAY / pack.handoff.MANIFEST, pack.runtime.canonical_bytes(after) + b'\n')
    pack.protect_data.sign_manifest(OVERLAY / pack.handoff.MANIFEST, key, OVERLAY / pack.handoff.SIGNATURE, SEQUENCE)
    _, _, metadata = inc.metadata(OVERLAY)
    sources, changed = inc.validate_merged(BASE, OVERLAY, before, after, TRUSTED)
    need(changed == set(values), 'Unexpected overlay scope')
    inc.materialize(VIEW, sources, changed, after, metadata)
    with inc.trusted_source(TRUSTED):
        _, verified, signature, _ = pack.authenticate(VIEW)
    need(verified == after and signature['release_sequence'] == SEQUENCE, 'Signed candidate mismatch')
    verification, files = inc.build_volumes(VIEW, OUTPUT, BASE_VPK, tree, groups, rewritten, after, 'hardlink')
    need(pack.package_inventory(BASE_VPK) == inventory and pack.runtime.verify(BASE, before)['ok'], 'Immutable baseline changed')
    need(pack.runtime.digest(JOURNAL) == journal_sha, 'Publication journal changed during build')
    current = payloads()
    need(all(current[n] == raw for n, raw in values.items()), 'Reviewed map/source changed during build')
    plan.update(status='BUILT_SIGNED_MAP_UPDATE', dry_run=False, signature_valid=True,
        full_runtime_validator_passed=True, payload_changed=False, workshop_upload_performed=False,
        package_files=files, vpk_sha256=files[0]['sha256'], verification=verification,
        native_test='NOT_RUN', ready_for_upload=False)
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--key', type=Path)
    parser.add_argument('--reviewed-plan', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    need(not args.report.exists(), 'New report path required')
    result = run(args.build, args.key, args.reviewed_plan)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(json.dumps({k: result[k] for k in ('release_sequence', 'content_sha256', 'files', 'changed_runtime_paths')}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps(dict(status='MAP_RELEASE_REFUSED', error=str(error)), ensure_ascii=False))
        raise SystemExit(1)
