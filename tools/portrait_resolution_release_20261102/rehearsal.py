"""Ordinary signed0201 scoped seventeen-resource rehearsal, restoring only the official five-account0104.

No arguments is a zero-effect plan. Real actions first authenticate the exact
signed report and bind its immutable game/content cursors; no raw source override. Frozen v04 lifecycle/CAS code is private.
"""
from pathlib import Path
import hashlib
import importlib.util
import inspect as source_inspection
import json
import re
import sys
import argparse

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
_ROOT=next((p for p in HERE.parents if (p/'tools/shared_boss_portrait_release_20261101/source_baseline_0104.json').is_file()),None)
if _ROOT is None: raise ValueError('Fixed project root unavailable')
PARENT=_ROOT/'tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py'
PARENT_SHA='2adecf06ca42cd67d40cef29cd91f7f8935db5f1e428e9d01fb300e2081b4c13'
if hashlib.sha256(PARENT.read_bytes()).hexdigest()!=PARENT_SHA:
    raise ValueError('Frozen native-verified v04 operation source changed')
_spec=importlib.util.spec_from_file_location('ordinary0201_private_v04',PARENT)
v4=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(v4)
_spec=importlib.util.spec_from_file_location('ordinary0201_own_checks',HERE/'release_checks.py')
c=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(c)
p=v4.p;p.c=c;p.b=c.b;p.need=c.b.need
b,need=p.b,p.need
# Source identities are admitted only from the authenticated signed report.
# No caller source override or per-release commit constant is accepted.
_SOURCE_CONTEXT=None
_ROUTE_CONTEXT=None
LAUNCH_ROUTES=('direct','lobby')
STORE=Path('D:/Survival_本地排演/20261102_ws4_shared_boss_portrait_v08')
LOG_ROOT=b.ROOT/'output/portrait_resolution_rehearsal_20261102'
BASE_MANIFEST='7025356658517360342'
RESTORED_STATUS='ORIGINAL0104_FIVE_FILES_FULLY_RESTORED'
PORT=29060
_parent_pins=v4.own_code_pins
_parent_plan=v4.static_plan
p.STORE=STORE;p.PORT=PORT;p.SNAPSHOT_PS=p.SNAPSHOT_PS.replace('29048',str(PORT))


def require_source_revision():
    need(isinstance(_SOURCE_CONTEXT,dict), 'AUTHENTICATED_SIGNED_PACKAGE_SOURCE_REQUIRED')
    return dict(_SOURCE_CONTEXT['source_revisions'])


def arguments(log,route=None):
    route=_ROUTE_CONTEXT if route is None else route
    need(route in LAUNCH_ROUTES,'Explicit reviewed launch route required')
    base=['-steam','-novid','-console','-vconport',str(PORT),'-condebug','-con_logfile',str(log),
        '+sv_cheats','0','+survival_archive_http_enabled','1']
    # Lobby intentionally starts at the native main menu. Users create/join
    # the original item's Local Host ws4_entry lobby before starting together.
    return base+(['+dota_launch_custom_game',b.ITEM,'ws4_entry'] if route=='direct' else [])


def bind_route(route):
    global _ROUTE_CONTEXT
    need(route in LAUNCH_ROUTES,'Unknown launch route')
    need(_ROUTE_CONTEXT is None or _ROUTE_CONTEXT==route,'One fixed launch route per operation process')
    _ROUTE_CONTEXT=route
    return route


def source_binding(package,expected_sha):
    global _SOURCE_CONTEXT
    sources=package.get('source_revisions')
    need(isinstance(sources,dict) and set(sources)=={'game','content'}
        and all(isinstance(value,str) and re.fullmatch('[a-f0-9]{40}',value) for value in sources.values())
        and package.get('source_revision')==sources['game'], 'Exact signed game/content source cursors required')
    context=dict(report_sha256=expected_sha,source_revisions=dict(sources),
        content_sha256=package['content_sha256'])
    need(_SOURCE_CONTEXT is None or _SOURCE_CONTEXT==context,'One authenticated signed package per operation process')
    _SOURCE_CONTEXT=context
    return dict(sources)


def own_code_pins():
    need(hashlib.sha256(PARENT.read_bytes()).hexdigest()==PARENT_SHA,'Frozen native-verified v04 source changed')
    return {**_parent_pins(),**{str(path.resolve()):p.digest(path) for path in
        (Path(__file__),HERE/'release_checks.py',HERE/'build_release.py',
         b.ROOT/'tools/shared_boss_portrait_release_20261101/historical_parent.py',
         b.ROOT/'tools/shared_boss_portrait_release_20261101/ledger.py',
         b.ROOT/'tools/shared_boss_portrait_release_20261101/source_baseline_0104.json',HERE/'native_admission.py')}}


def expected_log_path(folder):
    folder=Path(folder).absolute()
    need(folder.parent==STORE and folder.name==p.safe_id(folder.name),'Exact v08 transaction log route required')
    return LOG_ROOT/folder.name/'engine.log'


def fixed_paths():
    need(p.INSTALLED==b.ROOT.parents[4]/'workshop/content/570/3824360109'
        and p.STORE==STORE and p.PORT==PORT,'Fixed v08 installation/store/port changed')
    need(LOG_ROOT==b.ROOT/'output/portrait_resolution_rehearsal_20261102','Fixed mounted v08 log root changed')
    p.regular(p.INSTALLED);p.regular(STORE,exists=False);p.regular(LOG_ROOT,exists=False)
    need(p.INSTALLED.anchor.casefold()==STORE.anchor.casefold(),'Same-volume atomic replacement required')
    b.inc.disjoint([p.INSTALLED,STORE,LOG_ROOT,b.VIEW,b.OUTPUT,b.BASE,
        *b.FROZEN_V01_OUTPUTS,*b.FROZEN_V02_OUTPUTS,*b.FROZEN_V03_OUTPUTS,*b.FROZEN_V05_OUTPUTS,*b.FROZEN_V06_OUTPUTS,*b.FROZEN_V07_OUTPUTS,
        Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v03'),
        Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v04'),
        Path('D:/Survival_本地排演/20261101_ws4_five_account_portrait_v05'),
        Path('D:/Survival_本地排演/20261101_ws4_five_account_portrait_v06'),
        Path('D:/Survival_本地排演/20261101_ws4_shared_boss_portrait_v07')])


def acf_item():
    path=p.regular(p.ACF)
    need(path.stat().st_size<=4*1024*1024,'Bounded existing Workshop ACF required')
    raw=path.read_bytes();value=b.pack.handoff.kv(raw.decode('utf-8-sig'))['appworkshop']
    item=value['workshopitemsinstalled'][b.ITEM]
    need(value.get('appid')=='570' and item.get('manifest')==BASE_MANIFEST,
        'Official five-account0104 installed manifest required; never rewrite ACF')
    return dict(item=item,raw_sha256=hashlib.sha256(raw).hexdigest())


def package_auth(expected_sha,*,full=True):
    need(re.fullmatch(r'[a-f0-9]{64}',expected_sha or '') is not None,'Explicit completed signed report SHA required')
    # This validator authenticates signed metadata, immutable Git/compiler
    # lineage, all seventeen changes and five-account parent. Full operations
    # additionally authenticate actual VIEW/VPK bytes before installation.
    package,manifest,signed=c.validated_package(expected_sha,full=full)
    need(signed['signature_valid'] is True and signed['release_sequence']==b.SEQUENCE==2026110201,
        'Signed production0201 candidate required')
    need(package.get('changed_runtime_paths')==sorted(b.PAYLOADS) and package.get('files')==6919
        and [row['name'] for row in package['package_files']]==list(p.NAMES)
        and package['content_sha256']==manifest['content_sha256'],'Exact signed0201 identity required')
    need(b.BASE_SEQUENCE==2026110104 and b.BASE_CONTENT=='6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f',
        'Official five-account0104 restoration parent required')
    source_binding(package,expected_sha)
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
    return dict(_parent_plan(),status='STATIC_ORDINARY_REHEARSAL_V08_PLAN_NO_EFFECTS',operation_tool_version=8,
        external_store=str(STORE),port=PORT,mounted_log_root=str(LOG_ROOT),expected_runtime_source_revision=None,source_binding='AUTHENTICATED_REPORT_GAME_AND_CONTENT_CURSORS',
        original_release_sequence=b.BASE_SEQUENCE,original_content_sha256=b.BASE_CONTENT,
        original_steam_manifest=BASE_MANIFEST,restoration_status=RESTORED_STATUS,
        approved_accounts=5,launch_routes=list(LAUNCH_ROUTES),launch_requires_explicit_route=True,
        lobby_starts_native_main_menu=True,lobby_requires_actual_local_host_and_both_players_before_start=True,
        ready_for_upload=False)


_write_new=p.write_new
_load_transaction=p.load_transaction
_live_record=v4.live_record


def write_new(path,value):
    if Path(path).name in ('launch_intent.json','process.json'):
        need(isinstance(value,dict),'Structured launch receipt required')
        route=bind_route(_ROUTE_CONTEXT)
        value=dict(value,launch_route=route,owned_launch=True,
            direct_entry_requested=route=='direct',lobby_creation_by_tool=False)
    if isinstance(value,dict) and 'source_revision' in value and 'package_report_sha256' in value:
        sources=require_source_revision()
        need(value['package_report_sha256']==_SOURCE_CONTEXT['report_sha256']
            and value['source_revision']==sources['game']
            and value.get('content_sha256')==_SOURCE_CONTEXT['content_sha256'],
            'Operation receipt source/package differs from authenticated report')
        need('source_revisions' not in value or value['source_revisions']==sources,'Receipt source cursors changed')
        value=dict(value,source_revisions=sources)
    return _write_new(path,value)


def load_transaction(identifier,report_sha,*,full=False):
    folder,record,package,manifest=_load_transaction(identifier,report_sha,full=full)
    need(record.get('source_revisions')==require_source_revision(),'Transaction source cursors differ')
    return folder,record,package,manifest


def live_record(folder,transaction):
    candidate=p.json_read(folder/'process.json')
    route=bind_route(candidate.get('launch_route'))
    need(candidate.get('owned_launch') is True
        and candidate.get('direct_entry_requested') is (route=='direct')
        and candidate.get('argv')==arguments(Path(candidate['log_file']),route),
        'Exact controlled launch profile differs; manual adoption is unsupported')
    live=_live_record(folder,transaction)
    need(live.get('source_revisions')==transaction.get('source_revisions')==require_source_revision(),
        'Process source cursors differ')
    return live


# Freeze the existing five-file RM inspection behavior, adapting only its
# authenticated inventory count and export of an already verified native pin.
# Do not alter index/Dota/keeper booleans or reclassify INCOMPLETE observations.
_inspection_source=source_inspection.getsource(p.inspect)
_old_count='external_signed_resources_verified=6918'
_old_process="('pid','created_utc','command_line_sha256')"
need(_inspection_source.count(_old_count)==1 and _inspection_source.count(_old_process)==1,
    'Frozen native inspection metadata shape changed')
_inspection_source=_inspection_source.replace(_old_count,"external_signed_resources_verified=manifest['file_count']").replace(
    _old_process,"('pid','created_utc','command_line_sha256','native_created_filetime')")
exec(compile(_inspection_source,str(Path(__file__))+'[authenticated_inspection_count]','exec'),p.__dict__)


# Adapt only the privately imported chain. Frozen parent files stay untouched.
v4.STORE=STORE;v4.LOG_ROOT=LOG_ROOT
v4.own_code_pins=own_code_pins;v4.expected_log_path=expected_log_path;v4.fixed_paths=fixed_paths
v4.r.own_code_pins=own_code_pins  # Frozen v03 close resolves its own module globals.
p.own_code_pins=own_code_pins;p.fixed_paths=fixed_paths;p.acf_item=acf_item
p.package_auth=package_auth;p.restore=restore;p.static_plan=static_plan
p.write_new=write_new;p.load_transaction=load_transaction;p.live_record=live_record
p.arguments=arguments
OwnedLifetime=v4.OwnedLifetime


def launch(identifier,report_sha,*,route):
    bind_route(route)
    return v4.launch(identifier,report_sha)


p.launch=launch


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',nargs='?',default='plan',choices=['plan','stage','launch','inspect','close','restore'])
    parser.add_argument('--transaction');parser.add_argument('--report-sha256');parser.add_argument('--label')
    parser.add_argument('--route',choices=LAUNCH_ROUTES)
    args=parser.parse_args(argv)
    if args.action=='plan':
        need(not any((args.transaction,args.report_sha256,args.label,args.route)),'Static plan takes no action inputs')
        result=static_plan()
    else:
        p.safe_id(args.transaction)
        need(args.action=='inspect' or args.label is None,'Label is only for explicit inspection')
        need((args.action=='launch')==(args.route is not None),'Explicit route is required only for controlled launch')
        if args.action=='launch':
            result=launch(args.transaction,args.report_sha256,route=args.route)
        else:
            function=getattr(p,args.action)
            result=function(args.transaction,args.report_sha256,*([p.safe_id(args.label)] if args.action=='inspect' else []))
    print(json.dumps(result,ensure_ascii=True),flush=True)
    return 0


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='REFUSED_V08_PRESERVE_OFFICIAL0104_AND_BACKUPS',error_type=type(error).__name__,
            code=str(error) if isinstance(error,ValueError) else 'NATIVE_OR_OS_OPERATION_FAILED',
            force_stop=False,automatic_retry=False,publication_performed=False)),flush=True)
        raise SystemExit(2)
