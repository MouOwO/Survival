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
    _spec=importlib.util.spec_from_file_location('lottery0202_own_builder',_builder)
    b=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(b)


def validated_package(expected_report_sha256,*,full=False):
    path=b.REPORT/'package.json'
    b.need(re.fullmatch(r'[a-f0-9]{64}',expected_report_sha256 or '') is not None
        and b.pack.runtime.digest(path)==expected_report_sha256,'Explicit completed-package SHA required')
    report=b.load(path)
    b.need(report.get('status')=='BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE'
        and report.get('release_sequence')==b.SEQUENCE and report.get('signature_valid') is True
        and report.get('full_runtime_validator_passed') is True and report.get('dry_run') is False
        and report.get('payload_changed') is False and report.get('workshop_upload_performed') is False,
        'A completed signed package is required; unsigned reviews are never admitted')
    b.need(report.get('workshop_id')==b.ITEM and report.get('files')==6917
        and report.get('protected_modules_preserved')==184
        and report.get('all_difficulties_unlocked') is False
        and report.get('archive_bundle_hash')==b.EXPECTED_BUNDLE
        and report.get('changed_runtime_paths')==sorted(b.PAYLOADS)
        and report.get('added_runtime_paths')==list(b.ADDED_RUNTIME_PATHS) and report.get('removed_runtime_paths')==[],
        'Completed report scope/counts or preserved production policy differs')
    b.need(set(report['auxiliary_input_pins'])==set(b.AUXILIARY_INPUTS)
        and all(b.checks((b.ROOT/name).read_bytes())==pin for name,pin in report['auxiliary_input_pins'].items()),
        'Frozen build/validator/policy inputs changed')
    operator_revision,operator_pins,operator_bindings=b.operator_inputs(report.get('operator_revision'))
    b.need(report['auxiliary_input_pins']==operator_pins
        and report.get('operator_source_bindings')==operator_bindings,
        'Every operator recipe input must match the declared immutable operator commit')
    base_report,old=b.baseline(full=full,require_current_journal=False)
    source_bindings={}
    _,values=b.payloads(report['source_revision'],source_bindings=source_bindings)
    lineage=b.source_lineage(report['source_revision'],report.get('source_revisions',{}).get('content'),
        old,values,source_bindings)
    b.need(report.get('git_runtime_lineage')==lineage
        and report.get('source_revisions')==lineage['source_revisions']
        and report.get('authenticated_parent_manifest_sha256')==lineage['actual_parent_manifest_sha256']
        and report.get('parent_resource_origins_sha256')==lineage['parent_resource_origins_sha256']
        and report.get('resource_origins_sha256')==lineage['resource_origins_sha256'],
        'Exact scoped source/complete resource-origin lineage required')
    b.need(len(source_bindings)==2 and report.get('source_artifact_pins')==source_bindings,
        'Both JS/CSS Git/compiler/artifact source bindings must match')
    b.need(report['trusted_review_pins']==b.trusted_review(base_report,values),
        'Exact17 unchanged parent reviews, replacement router and new production review required')
    b.need(report.get('training_ui_source_review')==b.training_review(report['source_revision'],values),
        'Both immutable training presentation source reviews required')
    expected,changed=b.projected(old,values)
    b.need(set(changed)==set(b.PAYLOADS) and expected['file_count']==6917
        and report['target_pins']=={name:b.checks(raw) for name,raw in sorted(changed.items())},'Exact four scoped replacements required')
    admission=b.preserved_admission(old,expected)
    b.need(report.get('preserved_admission_rows')==admission and report.get('max_players')==4
        and report.get('approved_steamids64')==list(b.APPROVED),'Exact five-account admission preservation proof required')
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
    with b.scene_maps():b.need(b.pack.handoff.configured_ids(b.VIEW)==sorted(b.APPROVED),'Candidate roster must remain exact five accounts')
    for name,pin in report['trusted_review_pins'].items():
        reviewed=values[name] if name in b.ADDITIONAL_SOURCE_REVIEWS else (b.BASE_TRUSTED/name).read_bytes()
        b.need(b.checks((b.TRUSTED/name).read_bytes())==pin==b.checks(reviewed),
            'Preserved17 parent reviews or either reviewed training source changed')
    b.need({row['path'] for row in b.parent.parent.previous.base.protection.selected_files(
        [row['path'] for row in manifest['files']],b.load(b.ROOT/'tools/lua_protection_policy.json'))}.isdisjoint(b.PAYLOADS),
        'No protected module may be replaced by scoped raw Lua')
    if full:
        b.need(b.pack.package_inventory(b.OUTPUT/(b.ITEM+'.vpk'))==report['package_files'],'Final five VPKs changed')
        with b.scene_maps():b.pack.verify_vpk(b.OUTPUT/(b.ITEM+'.vpk'),manifest)
    return report,manifest,signed
