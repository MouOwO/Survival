"""Verify the real 3004 download with the unchanged official Steam protocol.

The completed package report is pinned, the ancestor's 184 protected modules
and account reviews must match, and only the explicit portrait/map scope may
differ. --download requires a successful same-release original-item journal.
"""
from pathlib import Path
import hashlib, importlib.util, json, sys
sys.dont_write_bytecode = True
import build_release as build

PROTOCOL = build.ROOT / 'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA = '1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
REPORT_SHA = '41727267f775e7fb9cd42826c9361b503322bc7f55042b62e6d351b73dcd260f'
build.need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == PROTOCOL_SHA,
           'Frozen official download protocol changed')
spec = importlib.util.spec_from_file_location('portrait3004_official_download', PROTOCOL)
protocol = importlib.util.module_from_spec(spec); spec.loader.exec_module(protocol)
api, need = protocol.api, protocol.need
REPORT = build.REPORT / build.PACKAGE_REPORT


def local_inputs(require_success=False, *, full=False):
    snapshots = {}
    read = lambda p: protocol.read_snapshot(p, api.pack.MAX_MANIFEST, snapshots)
    report_raw = read(REPORT)
    need(hashlib.sha256(report_raw).hexdigest() == REPORT_SHA, 'Completed 3004 package report changed')
    report = api.pack.handoff.decode_json(report_raw)
    need(report['release_sequence'] == build.SEQUENCE == 2026103004
         and report['dry_run'] is False and report['signature_valid'] is True
         and report['full_runtime_validator_passed'] is True, 'Completed signed portrait package required')
    build.SOURCE = report['portrait_source_revision']
    manifest = api.pack.handoff.decode_json(read(build.VIEW / api.pack.handoff.MANIFEST))
    document = api.pack.handoff.decode_json(read(build.VIEW / api.pack.handoff.SIGNATURE))
    api.pack.runtime.validate_manifest(manifest)
    policy, public = api.pack.handoff.trusted_policy(api.pack.handoff.POLICY)
    signature = api.pack.verify_signed_snapshot(manifest, document, public,
        policy['integrity']['minimum_release_sequence'], policy['integrity']['trusted_key_id'])
    need(signature['release_sequence'] == build.SEQUENCE
         and manifest['content_sha256'] == report['content_sha256']
         and manifest['file_count'] == report['files'] == 6913, 'Portrait signature/report identity differs')
    before = api.pack.handoff.decode_json(read(build.base.BASE / api.pack.handoff.MANIFEST))
    need(hashlib.sha256(read(build.base.BASE_REPORT)).hexdigest() == build.base.BASE_REPORT_SHA
         and before['content_sha256'] == build.base.BASE_CONTENT, '2901 ancestor identity differs')
    lua_policy = api.pack.handoff.decode_json(read(build.ROOT / 'tools/lua_protection_policy.json'))
    old = {r['path']: r for r in before['files']}; rows = {r['path']: r for r in manifest['files']}
    selected = build.base.protection.selected_files(list(rows), lua_policy)
    need(len(selected) == 184 and all(old[r['path']] == rows[r['path']] for r in selected),
         'Protected ancestor modules differ')
    catalog = json.loads(build.saved('art/portraits/monsters/manifest.json'))
    scenes = {'maps/' + s['map'] + '.vpk' for s in catalog['assets'].values()}
    need(len(catalog['assets']) == 197 and len(scenes) == 188, 'Exact portrait scene inventory required')
    allowed = scenes | {s['texture'].removeprefix('s2r://') + '_c' for s in catalog['backgrounds'].values()}
    allowed |= {'panorama/layout/custom_game/survival_hud.vxml_c',
        *('panorama/scripts/custom_game/' + n + '.vjs_c' for n in
          ('combat_stats', 'portrait_presentation', 'monster_portrait_scenes',
           'monster_portrait_renderer', 'topnav_remaining_5d5c1152eb'))}
    allowed |= {'panorama/styles/custom_game/survival_hud.vcss_c', 'resource/addon_schinese.txt', 'resource/localization/addon_schinese.txt'}
    allowed |= {build.base.MAP, 'resource/overviews/template_map.txt',
        'materials/overviews/template_map.vmat_c', 'materials/overviews/template_map_tga_d9088edf.vtex_c',
        *('scripts/vscripts/' + n for n in build.base.LUA_NAMES)}
    changed = {n for n in rows if rows[n] != old.get(n)}
    need(changed == set(report['changed_runtime_paths']) == set(report['target_pins'])
         and changed <= allowed and scenes <= changed, 'Portrait/map replacement scope differs')
    need(all({k: rows[n][k] for k in ('bytes', 'md5', 'sha256')} == pin
             for n, pin in report['target_pins'].items()), 'Signed target pins differ from completed report')
    for name in build.inc.all_files(build.TRUSTED):
        need(read(build.TRUSTED / name) == read(build.base.BASE_TRUSTED / name), 'Original account gate changed')
    state_raw = read(build.base.JOURNAL); state = api.pack.handoff.decode_json(state_raw)
    success = (state.get('uploaded') is True and state.get('owner') == api.OWNER
        and state.get('app_id') == api.APP and state.get('workshop_id') == build.ITEM
        and state.get('visibility_requested') == 3 and state.get('release_sequence') == build.SEQUENCE
        and state.get('content_sha256') == manifest['content_sha256']
        and state.get('package_files') == report['package_files']
        and state.get('vpk_sha256') == report['vpk_sha256'] and state.get('legal_agreement_required') is False)
    if require_success: need(success, 'Successful same-release original-item upload required')
    if full:
        with build.inc.trusted_source(build.TRUSTED):
            _, checked, signed, _ = api.pack.authenticate(build.VIEW)
        need(checked == manifest and signed == signature, 'Full signed portrait candidate changed')
        vpk = build.OUTPUT / (build.ITEM + '.vpk')
        need(api.pack.package_inventory(vpk) == report['package_files'], 'Portrait archive inventory changed')
        api.pack.verify_vpk(vpk, manifest)
    protocol.unchanged(snapshots)
    return dict(report=report, manifest=manifest, signature=signature, state=state, snapshots=snapshots,
        success=success, expected_manifest=protocol.journal_manifest(state) if success else None,
        total=sum(r['bytes'] for r in report['package_files']), report_sha256=REPORT_SHA,
        state_sha256=hashlib.sha256(state_raw).hexdigest(), protected_modules=184)


def main():
    report = build.base.load(REPORT); build.SOURCE = report['portrait_source_revision']
    values = dict(ITEM=build.ITEM, SEQUENCE=build.SEQUENCE, FILE_COUNT=report['files'],
        CONTENT=report['content_sha256'], CANDIDATE=build.VIEW, TRUSTED=build.TRUSTED,
        VPK=build.OUTPUT / (build.ITEM + '.vpk'), REPORT=REPORT, STATE=build.base.JOURNAL,
        OUTPUT=build.REPORT / 'download_evidence', MINIMUM_REMOTE_UPDATED=1793246958,
        local_inputs=local_inputs)
    for name, value in values.items(): setattr(protocol, name, value)
    # Full resource authentication and downloaded-install verification both use
    # the same exact 188 reviewed background-map exceptions as the builder.
    with build.portrait_scene_maps(report['target_pins']), build.inc.trusted_source(build.TRUSTED):
        return protocol.main()


if __name__ == '__main__': raise SystemExit(main())
