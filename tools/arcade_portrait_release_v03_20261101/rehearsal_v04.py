"""v04 local operation adapter: mounted native log and exact exited-handle proof.

Default plan only. This never signs, publishes or installs on import. The same
signed14 candidate and frozen v03 runtime/validator remain the sole authority.
"""
from pathlib import Path
import ctypes as C
import hashlib
import importlib.util
import json
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
PARENT=HERE/'rehearsal_v03.py'
PARENT_SHA='e5ca41d01d3967b6a340c962c3655831d7b330581552b48017edb1e26dee0f54'
if hashlib.sha256(PARENT.read_bytes()).hexdigest()!=PARENT_SHA:
    raise ValueError('Frozen v03 operation source changed')
_spec=importlib.util.spec_from_file_location('ordinary_rehearsal_v04_private_v03',PARENT)
r=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(r)
p,need=r.p,r.need
RUNTIME_SOURCE_REVISION=r.RUNTIME_SOURCE_REVISION
LOG_ROOT=p.b.ROOT/'output/arcade_portrait_rehearsal_v04_20261101'
STORE=Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v04')
p.STORE=STORE;p.PORT=29048;p.SNAPSHOT_PS=p.SNAPSHOT_PS.replace('29038','29048')
_original_pins=r.own_code_pins
_OriginalLifetime=p.OwnedLifetime


def require_source_revision():
    r.require_source_revision()
    need(RUNTIME_SOURCE_REVISION==r.RUNTIME_SOURCE_REVISION,
        'PENDING_IMMUTABLE_V03_RUNTIME_SOURCE: exact frozen candidate source required')


def own_code_pins():
    need(hashlib.sha256(PARENT.read_bytes()).hexdigest()==PARENT_SHA,'Frozen v03 operation source changed')
    return {**_original_pins(),str(Path(__file__).resolve()):p.digest(Path(__file__))}


def expected_log_path(folder):
    folder=Path(folder).absolute()
    need(folder.parent==STORE and folder.name==p.safe_id(folder.name),'Exact v04 transaction log route required')
    return LOG_ROOT/folder.name/'engine.log'


def fixed_paths():
    need(p.INSTALLED==p.b.ROOT.parents[4]/'workshop/content/570/3824360109' and p.STORE==STORE,
        'Fixed v04 installation/store changed')
    need(LOG_ROOT==p.b.ROOT/'output/arcade_portrait_rehearsal_v04_20261101','Fixed mounted output log root changed')
    p.regular(p.INSTALLED);p.regular(STORE,exists=False);p.regular(LOG_ROOT,exists=False)
    need(p.INSTALLED.anchor.casefold()==STORE.anchor.casefold(),'Same-volume replacement required')
    p.b.inc.disjoint([p.INSTALLED,STORE,LOG_ROOT,p.b.VIEW,p.b.OUTPUT,p.b.BASE,
        *p.b.FROZEN_V01_OUTPUTS,*p.b.FROZEN_V02_OUTPUTS,
        Path('D:/Survival_本地排演/20261101_ws4_portrait_perf_teleport_snapshot_v03')])


class OwnedLifetime(_OriginalLifetime):
    """Strict alive binding, then the SAME retained kernel object after signal.

    The completed object can no longer reliably expose its image path. Its
    creation and exit FILETIMEs remain queryable while this handle is retained.
    No new PID adoption, image fallback, new process handle or CIM query occurs.
    """
    def __init__(self,*args,**kwargs):
        super().__init__(*args,**kwargs)
        self._bound=None;self._exit_signaled=False

    def verify(self):
        if not self._exit_signaled:
            need(self.api.WaitForSingleObject(self.handle,0)==258,'Alive process required for initial executable binding')
            proof=super().verify()
            self._bound=dict(proof)
            return proof
        need(self._bound is not None and self.handle is not None,'No previously bound owned process object')
        need(self.api.WaitForSingleObject(self.handle,0)==0,'Retained process object is not signaled')
        times=[p.FILETIME() for unused in range(4)]
        need(self.api.GetProcessTimes(self.handle,*(C.byref(value) for value in times))!=0,
            'Retained exited-process FILETIME query failed')
        created=(times[0].high<<32)|times[0].low
        exited=(times[1].high<<32)|times[1].low
        need(created==self._bound['created_filetime']==self.native_created_filetime
            and created==self.record.get('native_created_filetime',created)
            and created//10==p.utc_ticks(self.record['created_utc'])//10,
            'Exited kernel object creation pin changed')
        need(exited>=created and exited>0,'Exited process must have an actual nonzero exit FILETIME')
        return dict(self._bound,exit_observed=True,exit_filetime=exited,
            executable_verified_while_alive=True,exit_identity_method='SAME_RETAINED_HANDLE_GETPROCESSTIMES')

    def wait_exited(self):
        result=self.api.WaitForSingleObject(self.handle,2000)
        need(result in (0,258),'Owned process wait failed; no PID replacement adopted')
        if result==0:
            self._exit_signaled=True;self.verify();return True
        return False


def live_record(folder,transaction):
    live=p.json_read(folder/'process.json')
    need(live.get('package_report_sha256')==transaction['package_report_sha256']
        and live.get('content_sha256')==transaction['content_sha256']
        and live.get('source_revision')==transaction['source_revision']
        and live.get('log_file')==str(expected_log_path(folder))
        and live.get('log_origin')=='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT'
        and live.get('code_pins')==transaction['code_pins'],'v04 process transaction/log binding changed')
    need(type(live.get('native_created_filetime')) is int
        and type(live.get('keeper',{}).get('native_created_filetime')) is int,'Exact native process creation pins required')
    return live


def launch(identifier,report_sha):
    folder,record,package,manifest=p.load_transaction(identifier,report_sha,full=True)
    log=expected_log_path(folder)
    with p.operation_lock():
        p.no_clients();p.steam_ready();p.no_clients()
        need(not (folder/'launch_intent.json').exists(),'Launch already attempted; no automatic replay')
        need(p.acf_item()['item']==record['acf']['item'],'Original item ACF changed')
        p.require_rows(folder/'backup',record['original_files'])
        need(not (folder/'restored.json').exists(),'Restored transaction cannot be relaunched')
        p.regular(LOG_ROOT,exists=False).mkdir(parents=True,exist_ok=True)
        p.regular(log.parent,exists=False);need(not log.parent.exists(),'Exclusive NEW mounted log run required')
        log.parent.mkdir(exist_ok=False)
        p.write_new(folder/'launch_intent.json',dict(status='REQUESTED_NOT_YET_STARTED',requested_utc=p.stamp(),
            code_pins=own_code_pins(),log_file=str(log),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT'))
    completed=False
    try:
        with p.FiveHolds(p.INSTALLED) as held:
            p.require_rows(p.INSTALLED,record['candidate_files']);p.full_vpk(p.INSTALLED,manifest)
            p.no_clients();started=p.stamp();need(not log.exists(),'Engine must create the NEW native log')
            keeper=p.identity(p.process_details(p.os.getpid()))
            with OwnedLifetime(keeper,expected_exe=Path(keeper['executable'])) as owner_lifetime:
                keeper['native_created_filetime']=owner_lifetime.native_created_filetime
            child=p.subprocess.Popen([str(p.EXE),*p.arguments(log)],cwd=p.GAME/'dota',creationflags=p.HIDDEN,
                env=dict(p.os.environ,SteamAppId='570',SteamGameId='570'))
            game=p.identity(p.process_details(child.pid))
            need(p.utc_ticks(game['created_utc'])>=p.utc_ticks(started),'Launched PID predates request')
            live=dict(schema=1,kind=p.KIND,**game,port=p.PORT,workshop_id=p.b.ITEM,argv=p.arguments(log),
                log_file=str(log),log_origin='DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT',tools=False,
                offline_logic_requested=False,cheats_requested=False,http_requested=True,
                source_revision=package['source_revision'],content_sha256=package['content_sha256'],
                package_report_sha256=report_sha,keeper=keeper,held_files=held.identities,started_utc=started,
                file_hold_mode='GENERIC_READ_FILE_SHARE_READ_ONLY',code_pins=own_code_pins(),official_download=False)
            p.owned(p.snapshot(),live,listener=False)
            with OwnedLifetime(live) as lifetime:
                live['native_created_filetime']=lifetime.native_created_filetime
                p.write_new(folder/'process.json',live)
                print(json.dumps(dict(status='OWNED_REHEARSAL_V04_RUNNING_KEEP_THIS_TERMINAL_ALIVE',pid=game['pid'],
                    created_utc=game['created_utc'],transaction_id=identifier,log_file=str(log),
                    normal_oauth_required=True,production_gameplay_verified=False,ready_for_upload=False)),flush=True)
                while not lifetime.wait_exited():pass
                # Exit proof is native and tied to this retained handle. Do not
                # misreport a late CIM failure as a failed process/file hold.
                # Restore independently requires no Dota clients before writes.
                proof=lifetime.verify()
                p.write_new(folder/'hold_end.json',dict(status='OWNED_DOTA_EXITED_HOLDS_COMPLETED',ended_utc=p.stamp(),
                    pid=game['pid'],created_utc=game['created_utc'],held_files=held.identities,
                    process_lifetime=proof,end_no_dota_verified=None,end_no_dota_check_deferred_to_restore=True,
                    stable_observer='READ_ONLY_PROCESS_HANDLE_WAIT_ONLY',gameplay_verified=False,
                    restoration_still_required=True))
        completed=True
    except BaseException as error:
        if not (folder/'keeper_exception.json').exists():
            # Local lifecycle diagnosis only: no session/profile/HTTP values.
            p.write_new(folder/'keeper_exception.json',dict(status='KEEPER_EXCEPTION_PRESERVE_EVIDENCE',
                error_type=type(error).__name__,error_code=str(error) if isinstance(error,ValueError) else 'NATIVE_OR_OS_OPERATION_FAILED',
                observed_utc=p.stamp(),automatic_retry=False))
        raise
    finally:
        if not completed and not (folder/'hold_failed.json').exists():
            p.write_new(folder/'hold_failed.json',dict(status='HOLD_OR_OWNERSHIP_FAILED_NO_FORCE_STOP',observed_utc=p.stamp(),
                evidence_complete=False,automatic_restore=False,automatic_retry=False))
    return dict(status='REHEARSAL_V04_CLIENT_EXITED_RESTORE_REQUIRED',ready_for_upload=False)


def static_plan():
    return dict(r.static_plan(),status='STATIC_ORDINARY_REHEARSAL_V04_PLAN_NO_EFFECTS',operation_tool_version=4,
        external_store=str(STORE),port=p.PORT,mounted_log_root=str(LOG_ROOT),log_copied=False,
        exit_proof='ALIVE_BOUND_EXE_THEN_SAME_HANDLE_SIGNAL_CREATION_EXIT_FILETIME',
        no_dota_exit_query='DEFERRED_TO_MANDATORY_RESTORE')


# Rebind only this private instance. All frozen parent bytes remain unchanged.
r.own_code_pins=own_code_pins;r.fixed_paths=fixed_paths
p.own_code_pins=own_code_pins;p.fixed_paths=fixed_paths;p.OwnedLifetime=OwnedLifetime
p.live_record=live_record;p.launch=launch;p.static_plan=static_plan

def main(argv=None):return p.main(argv)


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='REFUSED_V04_PRESERVE_BACKUPS',error_type=type(error).__name__,
            code=str(error) if isinstance(error,ValueError) else 'NATIVE_OR_OS_OPERATION_FAILED',
            force_stop=False,automatic_retry=False,publication_performed=False)),flush=True)
        raise SystemExit(2)
