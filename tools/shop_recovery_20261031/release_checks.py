"""Exact signed3102 admission, independent of the current Workshop journal head."""
from pathlib import Path
import re
import build_release as build


def validated_package(report_sha256, *, full=False):
    path=build.REPORT/'package.json'
    build.need(re.fullmatch(r'[a-f0-9]{64}',report_sha256 or '') and build.pack.runtime.digest(path)==report_sha256,'Explicit completed report hash required')
    report=build.load(path)
    build.need(report['status']=='BUILT_SIGNED_PENDING_NATIVE_AND_REDEMPTION_BACKEND' and report['signature_valid']
        and report['full_runtime_validator_passed'] and report['dry_run'] is False
        and report['release_sequence']==build.SEQUENCE and not report['workshop_upload_performed'],'Completed exact3102 required')
    for name,pin in report['auxiliary_input_pins'].items():build.need(build.checks((build.ROOT/name).read_bytes())==pin,'Frozen build dependency changed: '+name)
    _,old,_=build.parent.validated_package(build.BASE_REPORT_SHA,full=full)
    _,values=build.payloads(report['source_revision']);after,changed=build.parent.projected(old,values)
    build.need(set(changed)==set(build.PAYLOADS) and report['target_pins']=={name:build.checks(raw) for name,raw in sorted(changed.items())},'Exact six payloads required')
    manifest,document,_=build.inc.metadata(build.VIEW)
    build.need(manifest==after and manifest['content_sha256']==report['content_sha256'] and manifest['file_count']==6917,'Signed manifest differs')
    with build.parent.scene_maps(),build.inc.trusted_source(build.TRUSTED):
        policy,public=build.pack.handoff.trusted_policy()
        signature=build.pack.verify_signed_snapshot(manifest,document,public,policy['integrity']['minimum_release_sequence'],policy['integrity']['trusted_key_id'])
        if full:
            _,verified,signed,_=build.pack.authenticate(build.VIEW)
            build.need(verified==manifest and signed==signature,'Full candidate authentication failed')
    build.need(signature['release_sequence']==build.SEQUENCE,'Wrong signature release sequence')
    for name,pin in report['trusted_review_pins'].items():
        build.need(build.checks((build.TRUSTED/name).read_bytes())==pin==build.checks((build.BASE_TRUSTED/name).read_bytes()),'Admission review changed')
    if full:
        build.need(build.pack.package_inventory(build.OUTPUT/(build.ITEM+'.vpk'))==report['package_files'],'Final VPK inventory changed')
        with build.parent.scene_maps():build.pack.verify_vpk(build.OUTPUT/(build.ITEM+'.vpk'),manifest)
    return report,manifest,signature
