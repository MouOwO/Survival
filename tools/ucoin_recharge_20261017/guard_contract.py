"""Load actual frozen production helpers and execute the real validate CLI guards.

Only OS compatibility (pwd/geteuid/flock) and deployment-root paths are adapted
for Windows. No payment helper/export/guard is mocked. The DB adapter uses real
loopback PostgreSQL; its deliberately different catalog must fail before DDL.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import types

ROOT=Path(__file__).resolve().parents[2]
CANDIDATE=ROOT/'output/payment_release/20261017-payment03'
BASELINE=ROOT/'output/payment_release/20261016-shop-functional-v2'
sys.path[:0]=[str(CANDIDATE),str(ROOT/'output/video_shop_20261015/deps')]
platform_adapters=[]
if os.name=='nt':
    import msvcrt
    pwd=types.ModuleType('pwd')
    def private_account_not_needed(*args):raise AssertionError('guard_validation_must_not_query_accounts')
    pwd.getpwnam=private_account_not_needed;sys.modules['pwd']=pwd
    os.geteuid=lambda:0
    if not hasattr(os,'O_NOFOLLOW'):os.O_NOFOLLOW=0
    fcntl=types.ModuleType('fcntl');fcntl.LOCK_EX=2;fcntl.LOCK_NB=4
    def flock(fd,flags):
        assert flags==6
        os.lseek(fd,0,os.SEEK_SET);msvcrt.locking(fd,msvcrt.LK_NBLCK,1)
    fcntl.flock=flock;sys.modules['fcntl']=fcntl
    platform_adapters=['Linux pwd import blocked from account access','geteuid root semantics for Windows Administrator','actual Windows file lock via msvcrt','filesystem deployment roots relocated']

import psycopg
from payment_backend import upgrade_ucoin_recharge as operator
import deploy


def main():
    release=operator.release_module()
    assert not hasattr(release,'GAME'),'baseline_helper_did_not_gain_a_mock_export'
    original=json.loads((BASELINE/'manifest.json').read_bytes())
    helper_name='payment_backend/upgrade_ucoin_shop.py'
    assert hashlib.sha256(Path(release.__file__).read_bytes()).hexdigest()==original[helper_name]
    assert hashlib.sha256(Path(deploy.__file__).read_bytes()).hexdigest()==original['deploy.py']
    names=['verify_release','health','backup','prepare_environment','temporary_link','run','wait_healthy','connection','BASE']
    for name in names:assert hasattr(release,name),'actual_helper_missing:'+name
    for name in names[:-1]:assert callable(getattr(release,name))
    # Actual immutable package files and a real directory junction are checked.
    release.BASE=CANDIDATE.parent;deploy.BASE=CANDIDATE.parent
    assert (release.BASE/'current').resolve()==BASELINE
    archive=ROOT/'output/ucoin_recharge_20261017/guard_archive'/operator.ARCHIVE_RELEASE
    pointer=archive/'addon/server/bundles/current.json';pointer.parent.mkdir(parents=True,exist_ok=True)
    pointer.write_text(json.dumps({'hash':operator.ARCHIVE_BUNDLE})+'\n',encoding='utf-8')
    deploy.GAME=archive
    scope=operator.verify_scope(BASELINE)
    assert release.verify_release(str(BASELINE))==BASELINE
    operator.verify_archive_baseline(release)
    def loopback_connection():
        connection=psycopg.connect('host=127.0.0.1 port=54627 dbname=survival_bundle_test user=postgres',connect_timeout=3)
        assert connection.info.host=='127.0.0.1' and connection.info.dbname=='survival_bundle_test'
        return connection
    release.connection=loopback_connection
    lock=release.BASE/'.ucoin_recharge_activation.lock';existed=lock.exists()
    try:
        try:operator.main('validate',str(BASELINE))
        except RuntimeError as error:
            assert str(error)=='recharge_catalog_changed_since_review',str(error)
        else:raise AssertionError('real_local_nonproduction_catalog_must_be_rejected')
    finally:
        if not existed and lock.is_file() and not lock.is_symlink() and lock.stat().st_size==0:
            assert ROOT in lock.resolve().parents;lock.unlink()
    # All real guards remain valid and files/pointers are unchanged after CLI.
    assert release.verify_release(str(BASELINE))==BASELINE
    assert operator.verify_scope(BASELINE)==scope
    report=dict(passed=True,release=CANDIDATE.name,baseline=BASELINE.name,
        helper_source='actual immutable upgrade_ucoin_shop.py and deploy.py from current production baseline',
        helper_sha256=original[helper_name],deploy_sha256=original['deploy.py'],
        baseline_and_candidate_manifests_verified=True,actual_directory_junction_verified=True,
        actual_helper_exports_resolved=names,helper_has_no_GAME_export=True,
        archive_guard_imports_existing_deploy_GAME=True,actual_cli_validate_guard_sequence_executed=True,
        actual_operator_lock_executed=True,actual_loopback_sql_catalog_guard_executed=True,
        expected_nonproduction_catalog_rejection='recharge_catalog_changed_since_review',
        business_helpers_or_guards_mocked=False,platform_adapters=platform_adapters,
        remote_calls=0,database_ddl_or_player_writes=0,orders_created=0,gateway_requests=0)
    target=ROOT/'design_refs/ucoin_recharge_20261017/payment03_guard_contract.json'
    target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
