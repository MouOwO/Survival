"""Admit the exact3102 native/backend receipts, then update the original item."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

sys.dont_write_bytecode = True
from release_checks import build as b, validated_package
import steam_workshop_upload as publisher

BUNDLE = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
CHECKS = {'all_prizes_atomic_and_once_without_vip', 'concurrent_same_account_single_grant',
    'concurrent_global_quota', 'expiry_bad_codes_and_database_rate_limit', 'lost_commit_reply_recovery',
    'monthly_renewal_and_permanent_pass_preservation'}


def validate_receipts(package, native, plan, clone, backup, protected, activated, verified):
    b.need(native.get('status') == 'PASS_NATIVE_SIGNED_PRODUCTION_STARTUP_ONLY'
        and native.get('release_sequence') == b.SEQUENCE and native.get('content_sha256') == package['content_sha256']
        and native.get('signed_resources_verified') == 6917 and native.get('protected_modules_verified') == 184
        and native.get('cheats') is False and native.get('normal_default_verified') is True
        and native.get('redemption_resources_verified') is True
        and set(native.get('markers', {})) == {'signed_addon','server_activated','initialized','layout_ready','no_script_error'}
        and all(native['markers'].values()), 'Exact signed normal startup proof required')
    checks = clone.get('checks', {})
    b.need(clone.get('ok') is True and checks.get('ok') is True and checks.get('clone_only') is True
        and checks.get('actual_app_transport_ready') is True and checks.get('real_lua_reducer') is True
        and set(checks.get('checks', [])) == CHECKS and checks.get('real_player_redemption') is False
        and clone.get('production_player_data_copied') is False
        and clone.get('real_code_definitions_copied_to_clone') is False and clone.get('codes_registered') == 0,
        'Real schema-only synthetic database acceptance required')
    b.need(plan.get('authorized_scope') == 'WS4_3_TABLES_2_RPCS_EXISTING_128_DEFINITIONS'
        and re.fullmatch(r'20261031-redemption-ws4-[a-f0-9]{12}', plan.get('release', ''))
        and plan.get('registry_count') == 128, 'Exact WS4 scope required')
    b.need(protected.get('encrypted_verified') is True and protected.get('sha256') == backup.get('sha256')
        and backup.get('bytes', 0) > 0, 'Verified full encrypted backup required')
    b.need(activated.get('ok') is True and activated.get('status') == 'WS4_REDEMPTION_ACTIVATED'
        and activated.get('release') == plan['release'] and activated.get('bundle') == BUNDLE
        and activated.get('payment_untouched') is True and activated.get('codes_registered') == 128
        and activated.get('old_business_tables_unchanged', 0) > 0
        and activated.get('existing_functions_and_acls_unchanged') is True, 'WS4 preservation acceptance required')
    b.need(verified.get('ok') is True and verified.get('status') == 'WS4_REDEMPTION_VERIFIED'
        and verified.get('bundle') == BUNDLE and verified.get('codes') == 128
        and verified.get('payment_untouched') is True and verified.get('synthetic_schema_validation') is True
        and verified.get('real_player_redemption') is False, 'Active WS4 verification required')


def acceptance(package):
    snapshots = {}
    def read(name):
        path = b.REPORT / name
        raw = b.pack.read_metadata(b.pack.handoff.regular_path(path), b.pack.MAX_MANIFEST)
        snapshots[path] = raw
        return json.loads(raw)
    native = read('native_smoke.json')
    data = [read('ws4/' + name + '.json') for name in
        ('plan','clone','quiesce','protected_backup','activate','verify')]
    validate_receipts(package, native, *data)
    for name, digest in [('native_smoke_engine_frozen.log',native['engine_log_sha256']),
                         ('native_cvar_query.json',native['native_query_sha256'])]:
        b.need(b.pack.runtime.digest(b.REPORT/name) == digest, 'Native evidence changed')
    protected = data[3]
    encrypted = b.REPORT/'ws4'/('ws4-redemption-'+protected['sha256'][:16]+'.dump.dpapi')
    b.need(encrypted.stat().st_size == protected['bytes']
        and b.pack.runtime.digest(encrypted) == protected['encrypted_sha256'], 'Encrypted backup changed')
    for path, raw in snapshots.items(): b.need(path.read_bytes() == raw, 'Admission receipt changed')
    return {str(path.relative_to(b.REPORT)): hashlib.sha256(raw).hexdigest() for path,raw in snapshots.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-sha256', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    package, _, _ = validated_package(args.report_sha256, full=True)
    evidence = acceptance(package)
    listing = b.load(b.parent.REPORT/'listing.json')
    b.need(listing['workshop_id'] == b.ITEM and listing['visibility_requested'] == 'unlisted', 'Original Unlisted item required')
    listing.update(runtime_content_sha256=package['content_sha256'], release_sequence=b.SEQUENCE,
        release_revision=b.REVISION, vpk_sha256=package['vpk_sha256'], runtime_files=6917,
        package_bytes=sum(row['bytes'] for row in package['package_files']), package_files=package['package_files'])
    target = b.REPORT/'listing.json'
    raw = (json.dumps(listing,ensure_ascii=False,indent=2)+'\n').encode()
    if target.exists(): b.need(target.read_bytes() == raw, 'Reviewed listing changed')
    else: b.inc.write_new(target,raw)
    # The immutable incremental report predates this SDK compatibility field.
    # Full authentication above proves the VPK still carries the signed payload;
    # create a derived receipt rather than rewriting the frozen build report.
    sdk = dict(package, payload_changed=False, admission_receipt_sha256=evidence,
        immutable_build_report_sha256=args.report_sha256,
        payload_changed_basis='Full signed VIEW authentication and exact VPK CRC/MD5/SHA inventory verified at admission')
    sdk_path = b.REPORT/'sdk_upload_report.json'
    sdk_raw = (json.dumps(sdk,ensure_ascii=False,indent=2)+'\n').encode()
    if sdk_path.exists(): b.need(sdk_path.read_bytes() == sdk_raw, 'Derived SDK receipt changed')
    else: b.inc.write_new(sdk_path,sdk_raw)
    argv = ['--candidate',str(b.VIEW),'--vpk',str(b.OUTPUT/(b.ITEM+'.vpk')),
        '--listing',str(target),'--build-report',str(sdk_path),'--state-file',str(b.parent.JOURNAL)]
    if args.apply: argv += ['--apply','--update-existing']
    previous = sys.argv
    try:
        sys.argv = [str(Path(__file__)),*argv]
        with b.parent.scene_maps(),b.inc.trusted_source(b.TRUSTED): return publisher.main()
    finally: sys.argv = previous


if __name__ == '__main__': raise SystemExit(main())
