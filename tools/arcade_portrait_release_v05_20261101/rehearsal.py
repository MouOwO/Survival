"""Ordinary signed1105 rehearsal, restoring only the official five-account0104.

No arguments is a zero-effect plan. Runtime source starts unset and blocks every
real action before native/API access. Frozen v04 lifecycle/CAS code is private.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
PARENT=HERE.parent/'arcade_portrait_release_v03_20261101/rehearsal_v04.py'
PARENT_SHA='2adecf06ca42cd67d40cef29cd91f7f8935db5f1e428e9d01fb300e2081b4c13'
if hashlib.sha256(PARENT.read_bytes()).hexdigest()!=PARENT_SHA:
    raise ValueError('Frozen native-verified v04 operation source changed')
_spec=importlib.util.spec_from_file_location('ordinary1105_private_v04',PARENT)
v4=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(v4)
_spec=importlib.util.spec_from_file_location('ordinary1105_own_checks',HERE/'release_checks.py')
c=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(c)
p=v4.p;p.c=c;p.b=c.b;p.need=c.b.need
b,need=p.b,p.need
RUNTIME_SOURCE_REVISION='79d7d10529435b399eb9b5f6bc6216cd823946e1'
STORE=Path('D:/Survival_本地排演/20261101_ws4_five_account_portrait_v05')
LOG_ROOT=b.ROOT/'output/arcade_portrait_rehearsal_v05_20261101'
BASE_MANIFEST='7025356658517360342'
RESTORED_STATUS='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED'
PORT=29058
_parent_pins=v4.own_code_pins
_parent_plan=v4.static_plan
p.STORE=STORE;p.PORT=PORT;p.SNAPSHOT_PS=p.SNAPSHOT_PS.replace('29048',str(PORT))


def require_source_revision():
    need(isinstance(RUNTIME_SOURCE_REVISION,str)
        and re.fullmatch(r'[a-f0-9]{40}',RUNTIME_SOURCE_REVISION) is not None,
        'PENDING_IMMUTABLE_V05_RUNTIME_SOURCE: final root source commit required')


def own_code_pins():
    need(hashlib.sha256(PARENT.read_bytes()).hexdigest()==PARENT_SHA,'Frozen native-verified v04 source changed')
    return {**_parent_pins(),**{str(path.resolve()):p.digest(path) for path in
        (Path(__file__),HERE/'release_checks.py',HERE/'build_release.py')}}


def expected_log_path(folder):
    folder=Path(folder).absolute()
    need(folder.parent==STORE and folder.name==p.safe_id(folder.name),'Exact v05 transaction log route required')
    return LOG_ROOT/folder.name/'engine.log'


def fixed_paths():
    need(p.INSTALLED==b.ROOT.parents[4]/'workshop/content/570/3824360109'
        and p.STORE==STORE and p.PORT==PORT,'Fixed v05 installation/store/port changed')
    need(LOG_ROOT==b.ROOT/'output/arcade_portrait_rehearsal_v05_20261101','Fixed mounted v05 log root changed')
    p.regular(p.INSTALLED);p.regular(STORE,exists=False);p.regular(LOG_ROOT,exists=False)
    need(p.INSTALLED.anchor.casefold()==STORE.anchor.casefold(),'Same-volume atomic replacement required')
    b.inc.disjoint([p.INSTALLED,STORE,LOG_ROOT,b.VIEW,b.OUTPUT,b.BASE,
        *b.FROZEN_V01_OUTPUTS,*b.FROZEN_V02_OUTPUTS,*b.FROZEN_V03_OUTPUTS,
        Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v03'),
        Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v04')])


def acf_item():
    path=p.regular(p.ACF)
    need(path.stat().st_size<=4*1024*1024,'Bounded existing Workshop ACF required')
    raw=path.read_bytes();value=b.pack.handoff.kv(raw.decode('utf-8-sig'))['appworkshop']
    item=value['workshopitemsinstalled'][b.ITEM]
    need(value.get('appid')=='570' and item.get('manifest')==BASE_MANIFEST,
        'Official five-account0104 installed manifest required; never rewrite ACF')
    return dict(item=item,raw_sha256=hashlib.sha256(raw).hexdigest())


def package_auth(expected_sha,*,full=True):
    # The unset source gate runs before package I/O and all native/SDK actions.
    require_source_revision()
    need(re.fullmatch(r'[a-f0-9]{64}',expected_sha or '') is not None,'Explicit completed signed report SHA required')
    package,manifest,signed=c.validated_package(expected_sha,full=full)
    need(signed['signature_valid'] is True and signed['release_sequence']==b.SEQUENCE,
        'Signed production1105 candidate required')
    need(package.get('source_revision')==RUNTIME_SOURCE_REVISION
        and [row['name'] for row in package['package_files']]==list(p.NAMES)
        and package['content_sha256']==manifest['content_sha256'],'Exact signed1105 identity required')
    need(b.BASE_SEQUENCE==2026110104 and b.BASE_CONTENT=='6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f',
        'Official five-account0104 restoration parent required')
    return package,manifest


def restore(identifier,report_sha):
    folder,record,package,manifest=p.load_transaction(identifier,report_sha,full=True)
    with p.operation_lock():
        p.no_clients();need(not (folder/'restored.json').exists(),'Already restored; never replay')
        need(acf_item()['item']==record['acf']['item'],'Official0104 ACF changed before restoration')
        if (folder/'process.json').exists():
            live=p.live_record(folder,record)
            need(not p.same_identity(p.process_details(live['keeper']['pid']),live['keeper']),
                'Wait for owned keeper exit and release of read holds')
        p.require_rows(folder/'backup',record['original_files'])
        original,old_manifest=b.baseline(full=True,require_current_journal=False)
        need(record['original_files']==original['package_files']
            and record.get('original_content_sha256')==b.BASE_CONTENT
            and record.get('original_release_sequence')==b.BASE_SEQUENCE,
            'Restoration must preserve the official five-account0104 parent')
        p.full_vpk(folder/'backup',old_manifest)
        p.known_images(record)
        try:
            p.transition(folder,record,to_original=True)
            p.no_clients();p.require_rows(p.INSTALLED,record['original_files']);p.full_vpk(p.INSTALLED,old_manifest)
            need(acf_item()['item']==record['acf']['item'],'Official0104 ACF changed; do not rewrite it')
            p.write_new(folder/'restored.json',dict(schema=1,status=RESTORED_STATUS,observed_utc=p.stamp(),
                original_files=record['original_files'],original_content_sha256=b.BASE_CONTENT,
                original_release_sequence=b.BASE_SEQUENCE,original_steam_manifest=BASE_MANIFEST,
                official_download_performed=False,canonical_journal_written=False,acf_written=False,
                backups_preserved=True,publication_performed=False))
            p.event(folder,RESTORED_STATUS)
            return dict(status=RESTORED_STATUS,publication_performed=False)
        except BaseException:
            p.event(folder,'RESTORE_INCOMPLETE_PRESERVE_ALL_BACKUPS',automatic_retry=False);raise


def static_plan():
    return dict(_parent_plan(),status='STATIC_ORDINARY_REHEARSAL_V05_PLAN_NO_EFFECTS',operation_tool_version=5,
        external_store=str(STORE),port=PORT,mounted_log_root=str(LOG_ROOT),expected_runtime_source_revision=RUNTIME_SOURCE_REVISION,
        original_release_sequence=b.BASE_SEQUENCE,original_content_sha256=b.BASE_CONTENT,
        original_steam_manifest=BASE_MANIFEST,restoration_status=RESTORED_STATUS,
        approved_accounts=5,ready_for_upload=False)


# Adapt only the privately imported chain. Frozen parent files stay untouched.
v4.STORE=STORE;v4.LOG_ROOT=LOG_ROOT
v4.own_code_pins=own_code_pins;v4.expected_log_path=expected_log_path;v4.fixed_paths=fixed_paths
v4.r.own_code_pins=own_code_pins  # Frozen v03 close resolves its own module globals.
p.own_code_pins=own_code_pins;p.fixed_paths=fixed_paths;p.acf_item=acf_item
p.package_auth=package_auth;p.restore=restore;p.static_plan=static_plan
OwnedLifetime=v4.OwnedLifetime
live_record=v4.live_record
launch=v4.launch


def main(argv=None):return p.main(argv)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='REFUSED_V05_PRESERVE_OFFICIAL0104_AND_BACKUPS',error_type=type(error).__name__,
            code=str(error) if isinstance(error,ValueError) else 'NATIVE_OR_OS_OPERATION_FAILED',
            force_stop=False,automatic_retry=False,publication_performed=False)),flush=True)
        raise SystemExit(2)
