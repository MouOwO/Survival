"""Authenticate official0104 without demanding that today's SDK equals old tools.

Historical helper hashes are preserved evidence, not a requirement to roll back
the current central SDK guard. Actual trust is the pinned record/report/receipt,
the fixed public key, signed runtime inventory, and full native VPK checks.
"""
def validate(b, *, full=False):
    need=b.need
    need(b.pack.runtime.digest(b.BASE_REPORT)==b.BASE_REPORT_SHA,'Frozen0104 completed report changed')
    need(b.pack.runtime.digest(b.BASE_RECORD)==b.BASE_RECORD_SHA,'Frozen0104 delivery record changed')
    report,record=b.load(b.BASE_REPORT),b.load(b.BASE_RECORD)
    need(report.get('release_sequence')==2026110104 and report.get('signature_valid') is True
        and report.get('full_runtime_validator_passed') is True and report.get('dry_run') is False
        and report.get('payload_changed') is False and report.get('files')==6917,
        'Historical0104 completed signed package required')
    need(record.get('status')=='UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED'
        and record.get('release_sequence')==2026110104 and record.get('runtime_files')==6917
        and record.get('protected_modules')==184 and record.get('steam_manifest')=='7025356658517360342'
        and record.get('content_sha256')==b.BASE_CONTENT and record.get('package_files')==report.get('package_files'),
        'Pinned official0104 record/report identity differs')
    historical=report.get('auxiliary_input_pins')
    need(isinstance(historical,dict) and historical,'Historical helper provenance must remain recorded')
    # Deliberately do not compare historical pins to mutable current helper paths.
    # Their enclosing report SHA is fixed; the new builder pins its own toolchain.
    receipt_path=b.ROOT/record['download_receipt']['path']
    need(b.pack.runtime.digest(receipt_path)==record['download_receipt']['sha256'],'Official0104 receipt changed')
    receipt=b.load(receipt_path)
    need(receipt.get('status')=='OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
        and receipt.get('release_sequence')==2026110104 and receipt.get('content_sha256')==b.BASE_CONTENT
        and receipt.get('steam_manifest')==record['steam_manifest'] and receipt.get('signed_resources_verified')==6917
        and receipt.get('protected_modules_verified')==184 and receipt['verification']['signature_valid'] is True
        and receipt['verification']['package_files']==report['package_files'],'Complete official0104 download proof required')
    manifest,document,_=b.inc.metadata(b.BASE)
    need(manifest.get('content_sha256')==b.BASE_CONTENT and manifest.get('file_count')==6917
        and report.get('content_sha256')==b.BASE_CONTENT,'Parent signed inventory differs')
    with b.scene_maps(),b.inc.trusted_source(b.BASE_TRUSTED):
        policy,public=b.pack.handoff.trusted_policy(b.pack.handoff.POLICY)
        signed=b.pack.verify_signed_snapshot(manifest,document,public,
            policy['integrity']['minimum_release_sequence'],policy['integrity']['trusted_key_id'])
        need(signed['release_sequence']==2026110104,'Wrong historical signed sequence')
        b.pack.handoff.require_single_map(b.BASE)
        b.pack.handoff.require_reviewed_gate(b.BASE,manifest)
        need(b.pack.handoff.configured_ids(b.BASE)==sorted(b.APPROVED),'Signed official five-account roster differs')
        if full:
            _,checked,authenticated,_=b.pack.authenticate(b.BASE)
            need(checked==manifest and authenticated==signed,'Full immutable parent runtime authentication failed')
            need(b.pack.package_inventory(b.BASE_VPK)==report['package_files'],'Historical five VPK files changed')
            b.pack.verify_vpk(b.BASE_VPK,manifest)
    for name,pin in report['trusted_review_pins'].items():
        need(b.checks((b.BASE_TRUSTED/name).read_bytes())==pin,'Historical trusted review source changed: '+name)
    need(report.get('source_revision')==record.get('source_revision'),'Historical source anchor differs')
    return report,manifest,signed
