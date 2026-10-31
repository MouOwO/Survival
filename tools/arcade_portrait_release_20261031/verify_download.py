"""Bind the unchanged official1313/3406 download protocol to signed1101.

Default --preflight is local/read-only and never initializes Steam. --download
is an explicit later operation requiring a successful same-release publication;
the frozen protocol guards pending requests, real callbacks and all installed
signed bytes. Its historical terminal180 summary is not the authoritative
receipt: that unchanged protocol writes the actual184 from local_inputs().
"""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import importlib.util
import sys

sys.dont_write_bytecode=True
_checks_path=Path(__file__).with_name('release_checks.py').resolve()
_checks_name='portrait1101_adapter_release_checks'
_checks=sys.modules.get(_checks_name)
if not getattr(_checks,'__file__',None) or Path(_checks.__file__).resolve()!=_checks_path:
    _spec=importlib.util.spec_from_file_location(_checks_name,_checks_path)
    _checks=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_checks)
    sys.modules[_checks_name]=_checks
b,validated_package=_checks.b,_checks.validated_package

PROTOCOL=b.ROOT/'tools/arcade_cleanup_20261027/verify_download.py'
PROTOCOL_SHA='1f7afed91128c8601ccd9848b092300d0869067853422fe87cc5c5e511eb237f'
b.need(hashlib.sha256(PROTOCOL.read_bytes().replace(b'\r\n',b'\n')).hexdigest()==PROTOCOL_SHA,
    'Frozen official download protocol changed')
spec=importlib.util.spec_from_file_location('portrait1101_official_download',PROTOCOL)
protocol=importlib.util.module_from_spec(spec);spec.loader.exec_module(protocol)
api=protocol.api
REPORT_SHA=None
SUCCESS_STATUS='SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'


def successful_same_release(state,package,manifest):
    """Pure identity check; previous-release manifests never satisfy this."""
    return (state.get('uploaded') is True and state.get('status')==SUCCESS_STATUS
        and state.get('owner')==api.OWNER and state.get('app_id')==api.APP
        and state.get('workshop_id')==b.ITEM and state.get('visibility_requested')==3
        and state.get('release_sequence')==b.SEQUENCE
        and state.get('content_sha256')==manifest['content_sha256']
        and state.get('vpk_sha256')==package['vpk_sha256']
        and state.get('vpk_bytes')==package['package_files'][0]['bytes']
        and state.get('package_files')==package['package_files']
        and state.get('legal_agreement_required') is False)


def local_inputs(require_success=False,*,full=False):
    snapshots={}
    read=lambda path:protocol.read_snapshot(path,api.pack.MAX_MANIFEST,snapshots)
    report_path=b.REPORT/'package.json'
    read(report_path);read(b.VIEW/api.pack.handoff.MANIFEST);read(b.VIEW/api.pack.handoff.SIGNATURE)
    state=api.pack.handoff.decode_json(read(b.JOURNAL))
    package,manifest,signature=validated_package(REPORT_SHA,full=full)
    b.need(len(package['package_files'])==5,'Exactly five candidate VPK volumes required')
    # Do not convert an unknown/incomplete publication to a downloadable state,
    # even for a local plan. No reset, pending clear, automatic retry or SDK call.
    b.need(state.get('uploaded') is True and state.get('status')==SUCCESS_STATUS,
        'Unknown/pending publication must be reconciled separately; journal preserved')
    success=successful_same_release(state,package,manifest)
    if require_success:b.need(success,'Successful exact1101 original-item publication required')
    else:
        b.need(success or (state.get('release_sequence')==b.BASE_SEQUENCE
            and state.get('content_sha256')==b.BASE_CONTENT and state.get('owner')==api.OWNER
            and state.get('app_id')==api.APP and state.get('workshop_id')==b.ITEM
            and state.get('visibility_requested')==3 and state.get('legal_agreement_required') is False),
            'Only successful original3102 parent or exact1101 release may be planned')
        if not success:
            parent_raw=read(b.BASE_REPORT);parent=api.pack.handoff.decode_json(parent_raw)
            b.need(hashlib.sha256(parent_raw).hexdigest()==b.BASE_REPORT_SHA
                and state.get('vpk_sha256')==parent['vpk_sha256']
                and state.get('package_files')==parent['package_files']
                and state.get('vpk_bytes')==parent['package_files'][0]['bytes'],'Frozen parent journal package differs')
    protocol.unchanged(snapshots)
    return dict(report=package,manifest=manifest,signature=signature,state=state,snapshots=snapshots,
        success=success,expected_manifest=protocol.journal_manifest(state) if success else None,
        total=sum(row['bytes'] for row in package['package_files']),report_sha256=REPORT_SHA,
        state_sha256=hashlib.sha256(snapshots[b.JOURNAL]).hexdigest(),protected_modules=184)


def main(argv=None):
    global REPORT_SHA
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--preflight',action='store_true');mode.add_argument('--download',action='store_true')
    parser.add_argument('--report-sha256',required=True)
    args=parser.parse_args(argv);REPORT_SHA=args.report_sha256
    package,_,_=validated_package(REPORT_SHA)
    b.need(b.pack.runtime.digest(b.BASE_RECORD)==b.BASE_RECORD_SHA,'Frozen3102 delivery record changed')
    parent_observed=datetime.fromisoformat(b.load(b.BASE_RECORD)['observed_utc'])
    b.need(parent_observed.tzinfo is not None,'Parent delivery timestamp must include timezone')
    values=dict(ITEM=b.ITEM,SEQUENCE=b.SEQUENCE,FILE_COUNT=6918,CONTENT=package['content_sha256'],
        CANDIDATE=b.VIEW,TRUSTED=b.TRUSTED,VPK=b.OUTPUT/(b.ITEM+'.vpk'),REPORT=b.REPORT/'package.json',
        STATE=b.JOURNAL,OUTPUT=b.REPORT/'download_evidence',
        MINIMUM_REMOTE_UPDATED=int(parent_observed.timestamp()),local_inputs=local_inputs)
    for name,value in values.items():setattr(protocol,name,value)
    with b.scene_maps(),b.inc.trusted_source(b.TRUSTED):
        return protocol.main(['--download'] if args.download else [])


if __name__=='__main__':raise SystemExit(main())
