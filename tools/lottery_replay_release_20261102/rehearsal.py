"""Private0202 lifecycle reuse for ordinary0203; defaults to a zero-effect plan."""
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
_s=importlib.util.spec_from_file_location('snapshot0203_ops_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_s);_s.loader.exec_module(a)
impl=a.frozen('rehearsal','dda926955aae3ea7cb591130a9b5df2392a4184acf38591691aecd384c049d57')
checks=a.local('release_checks');impl.c=checks;impl.b=checks.b;impl.need=checks.b.need
impl.p.c=checks;impl.p.b=checks.b;impl.p.need=checks.b.need
impl.STORE=Path('D:/Survival_本地排演/20261102_ws4_lottery_replay_v11')
impl.LOG_ROOT=impl.b.ROOT/'output/lottery_replay_rehearsal_20261102'
impl.PORT=29066
impl.p.STORE=impl.STORE;impl.p.PORT=impl.PORT
a.need('29062' in impl.p.SNAPSHOT_PS,'Frozen0202 snapshot port guard changed')
impl.p.SNAPSHOT_PS=impl.p.SNAPSHOT_PS.replace('29062','29066')
a.function(impl,'fixed_paths',[
    ('output/lottery_hotfix_rehearsal_20261102','output/lottery_replay_rehearsal_20261102'),
    ('*b.FROZEN_V08_OUTPUTS,','*b.FROZEN_V08_OUTPUTS,*b.FROZEN_V09_OUTPUTS,')])
a.function(impl,'package_auth',[
    ('==2026110202','==2026110204')])
_old_pins=impl.own_code_pins
_old_plan=impl.static_plan


def own_code_pins():
    pins=_old_pins()
    for name in ('adapt.py','build_release.py','ledger.py','release_checks.py',
                 'rehearsal.py','native_admission.py'):
        path=HERE/name;pins[str(path.resolve())]=impl.p.digest(path)
    return pins


def static_plan():
    result=_old_plan();result.update(status='STATIC_ORDINARY_LOTTERY_SNAPSHOT_PLAN_NO_EFFECTS',
        operation_tool_version=10,external_store=str(impl.STORE),port=impl.PORT,
        mounted_log_root=str(impl.LOG_ROOT),scoped_runtime_paths=7,release_sequence=2026110204)
    return result


impl.own_code_pins=own_code_pins;impl.static_plan=static_plan
impl.v4.STORE=impl.STORE;impl.v4.LOG_ROOT=impl.LOG_ROOT
impl.v4.own_code_pins=own_code_pins;impl.v4.fixed_paths=impl.fixed_paths
impl.v4.expected_log_path=impl.expected_log_path;impl.v4.r.own_code_pins=own_code_pins
impl.p.own_code_pins=own_code_pins;impl.p.fixed_paths=impl.fixed_paths
impl.p.package_auth=impl.package_auth;impl.p.static_plan=static_plan
def __getattr__(name):return getattr(impl,name)
if __name__=='__main__':raise SystemExit(impl.main())
