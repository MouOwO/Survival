"""Read-only authentication of the future completed package, before/after upload."""
from pathlib import Path
import importlib.util
import re
import sys

_builder=Path(__file__).with_name('build_release.py').resolve()
b=sys.modules.get('build_release')
if not getattr(b,'__file__',None) or Path(b.__file__).resolve()!=_builder:
    # A later release may import this validator by file path. Never silently
    # resolve its bare build_release name to that later release's builder.
    _spec=importlib.util.spec_from_file_location('arcade_portrait_1102_frozen_builder',_builder)
    b=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(b)


def validated_package(expected_report_sha256,*,full=False):
    path=b.REPORT/'package.json'
    b.need(re.fullmatch(r'[a-f0-9]{64}',expected_report_sha256 or '') is not None
        and b.pack.runtime.digest(path)==expected_report_sha256,'Explicit completed-package SHA required')
    report=b.load(path)
    b.need(report.get('status')=='BUILT_SIGNED_PENDING_NATIVE_PERF_ACCEPTANCE'
        and report.get('release_sequence')==b.SEQUENCE and report.get('signature_valid') is True
        and report.get('full_runtime_validator_passed') is True and report.get('dry_run') is False
        and report.get('payload_changed') is False and report.get('workshop_upload_performed') is False,
        'A completed signed package is required; unsigned reviews are never admitted')
    b.need(report.get('workshop_id')==b.ITEM and report.get('files')==6918
        and report.get('protected_modules_preserved')==184
        and report.get('all_difficulties_unlocked') is False
        and report.get('archive_bundle_hash')==b.EXPECTED_BUNDLE
        and report.get('changed_runtime_paths')==sorted(b.PAYLOADS)
        and report.get('added_runtime_paths')==[b.PAYLOADS[1]] and report.get('removed_runtime_paths')==[],
        'Completed report scope/counts or preserved production policy differs')
    b.need(set(report['auxiliary_input_pins'])==set(b.AUXILIARY_INPUTS)
        and all(b.checks((b.ROOT/name).read_bytes())==pin for name,pin in report['auxiliary_input_pins'].items()),
        'Frozen build/validator/policy inputs changed')
    base_report,old=b.baseline(full=full,require_current_journal=False)
    b.need(report['trusted_review_pins']==base_report['trusted_review_pins'],'Exact16 original admission pins required')
    source_bindings={}
    _,values=b.payloads(report['source_revision'],source_bindings=source_bindings)
    b.need(len(source_bindings)==3 and report.get('source_artifact_pins')==source_bindings,
        'All three Git/compiler/artifact source bindings must match')
    expected,changed=b.projected(old,values)
    b.need(set(changed)==set(b.PAYLOADS) and expected['file_count']==6918
        and report['target_pins']=={name:b.checks(raw) for name,raw in sorted(changed.items())},'Exact13 scoped payloads required')
    manifest,document,_=b.inc.metadata(b.VIEW)
    b.need(manifest==expected and manifest['content_sha256']==report['content_sha256']
        and b.pack.runtime.digest(b.VIEW/b.pack.handoff.SIGNATURE)==report['signature_sha256'],
        'Complete manifest/signature metadata changed')
    with b.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        policy,public=b.pack.handoff.trusted_policy()
        signed=b.pack.verify_signed_snapshot(manifest,document,public,
            policy['integrity']['minimum_release_sequence'],policy['integrity']['trusted_key_id'])
        if full:
            _,verified,actual,_=b.pack.authenticate(b.VIEW)
            b.need(verified==manifest and actual==signed,'Full signed candidate differs')
    b.need(signed['release_sequence']==b.SEQUENCE,'Wrong release sequence')
    for name,pin in report['trusted_review_pins'].items():
        b.need(b.checks((b.TRUSTED/name).read_bytes())==pin==b.checks((b.BASE_TRUSTED/name).read_bytes()),'Original16 admission reviews changed')
    if full:
        b.need(b.pack.package_inventory(b.OUTPUT/(b.ITEM+'.vpk'))==report['package_files'],'Final five VPKs changed')
        with b.scene_maps():b.pack.verify_vpk(b.OUTPUT/(b.ITEM+'.vpk'),manifest)
    return report,manifest,signed
