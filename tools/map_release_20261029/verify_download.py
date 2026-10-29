"""Reuse the official query/callback/install protocol for the completed map build.

No SDK mutation occurs without --download. Metadata must match the actual new
build and its successful original-item journal. Protected rows are checked
against the authenticated 2901 ancestor, rather than falsely rebuilt evidence.
"""
from pathlib import Path
import hashlib, importlib.util, sys
sys.dont_write_bytecode = True
import build_release as build
PROTOCOL = build.ROOT / 'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA = '1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
build.need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == PROTOCOL_SHA,
           'Frozen official download protocol changed')
spec = importlib.util.spec_from_file_location('map2902_official_download', PROTOCOL)
protocol = importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
api, need = protocol.api, protocol.need
REPORT = build.REPORT_DIR / 'package.json'


def local_inputs(require_success=False, *, full=False):
    snapshots = {}
    read = lambda p: protocol.read_snapshot(p, api.pack.MAX_MANIFEST, snapshots)
    report_raw = read(REPORT)
    report = api.pack.handoff.decode_json(report_raw)
    need(report.get('release_sequence') == build.SEQUENCE and report.get('dry_run') is False
         and report.get('signature_valid') is True and report.get('full_runtime_validator_passed') is True,
         'Completed signed map package required')
    manifest = api.pack.handoff.decode_json(read(build.VIEW / api.pack.handoff.MANIFEST))
    document = api.pack.handoff.decode_json(read(build.VIEW / api.pack.handoff.SIGNATURE))
    api.pack.runtime.validate_manifest(manifest)
    policy, public = api.pack.handoff.trusted_policy(api.pack.handoff.POLICY)
    signature = api.pack.verify_signed_snapshot(manifest, document, public,
        policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
    need(signature['release_sequence'] == build.SEQUENCE and manifest['content_sha256'] == report['content_sha256'],
         'Map signature/report identity differs')
    before = api.pack.handoff.decode_json(read(build.BASE / api.pack.handoff.MANIFEST))
    ancestor_report = read(build.BASE_REPORT)
    need(hashlib.sha256(ancestor_report).hexdigest() == build.BASE_REPORT_SHA
         and before['content_sha256'] == build.BASE_CONTENT, '2901 ancestor identity differs')
    lua_policy = api.pack.handoff.decode_json(read(build.ROOT / 'tools/lua_protection_policy.json'))
    old = {r['path']: r for r in before['files']}
    rows = {r['path']: r for r in manifest['files']}
    selected = build.protection.selected_files(list(rows), lua_policy)
    need(len(selected) == 184 and all(old[r['path']] == rows[r['path']] for r in selected),
         'Protected ancestor modules differ')
    changed = {n for n in rows if rows[n] != old.get(n)}
    need(changed == set(report['changed_runtime_paths']) and build.MAP in changed
         and changed <= {build.MAP, *('scripts/vscripts/' + n for n in build.LUA_NAMES)},
         'Map replacement scope differs')
    for name in build.inc.all_files(build.TRUSTED):
        raw = read(build.TRUSTED / name)
        need(raw == read(build.BASE_TRUSTED / name), 'Original account gate changed')
    state_raw = read(build.JOURNAL)
    state = api.pack.handoff.decode_json(state_raw)
    success = (state.get('uploaded') is True and state.get('owner') == api.OWNER
        and state.get('app_id') == api.APP and state.get('workshop_id') == build.ITEM
        and state.get('visibility_requested') == 3 and state.get('release_sequence') == build.SEQUENCE
        and state.get('content_sha256') == manifest['content_sha256']
        and state.get('package_files') == report['package_files']
        and state.get('vpk_sha256') == report['vpk_sha256'] and state.get('legal_agreement_required') is False)
    if require_success:
        need(success, 'Successful same-release original-item upload required')
    if full:
        with build.inc.trusted_source(build.TRUSTED):
            _, checked, signed, _ = api.pack.authenticate(build.VIEW)
        need(checked == manifest and signed == signature, 'Full signed map candidate changed')
        vpk = build.OUTPUT / (build.ITEM + '.vpk')
        need(api.pack.package_inventory(vpk) == report['package_files'], 'Map archive inventory changed')
        api.pack.verify_vpk(vpk, manifest)
    protocol.unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signature, state=state, snapshots=snapshots,
        success=success, expected_manifest=protocol.journal_manifest(state) if success else None,
        total=sum(r['bytes'] for r in report['package_files']), report_sha256=hashlib.sha256(report_raw).hexdigest(),
        state_sha256=hashlib.sha256(state_raw).hexdigest(), protected_modules=184)


def main():
    report = build.load(REPORT)
    values = dict(ITEM=build.ITEM, SEQUENCE=build.SEQUENCE, FILE_COUNT=report['files'],
        CONTENT=report['content_sha256'], CANDIDATE=build.VIEW, TRUSTED=build.TRUSTED,
        VPK=build.OUTPUT / (build.ITEM + '.vpk'), REPORT=REPORT, STATE=build.JOURNAL,
        OUTPUT=build.REPORT_DIR / 'download_evidence', MINIMUM_REMOTE_UPDATED=1793246958,
        local_inputs=local_inputs)
    for name, value in values.items():
        setattr(protocol, name, value)
    return protocol.main()


if __name__ == '__main__':
    raise SystemExit(main())
