"""Resume code activation after the committed migration; never replay SQL.

The original immutable operator and plan remain pinned. Only its mistaken CWD
expectation is replaced; original authenticated health/ready/hash checks remain.
"""
from pathlib import Path
import argparse,hashlib,json
from deploy_driver import checked,remote
OPERATOR='eec5c1c1929821f9db24d0efd6182de3309c2ffb7d97975bda5024df12fa4832'
PLAN='3ee690274a82071ac0452bc1ed35dc04e8da10de46d9978e6f3b2ddf71a17d1f'
CODE=r'''from pathlib import Path
import contextlib,fcntl,hashlib,importlib.util,io,json,subprocess,time
stage=Path('/tmp/survival-endless-leaderboard-20261016-v2')
operator_path=stage/'deploy_remote.py'
if hashlib.sha256(operator_path.read_bytes()).hexdigest()!=OPERATOR_PIN:raise RuntimeError('operator_pin_changed')
if hashlib.sha256((stage/'release_plan.json').read_bytes()).hexdigest()!=PLAN_PIN:raise RuntimeError('plan_pin_changed')
spec=importlib.util.spec_from_file_location('reviewed_ranking_operator',operator_path)
op=importlib.util.module_from_spec(spec);spec.loader.exec_module(op)
op.EXPECTED_PLAN_SHA=PLAN_PIN;op.EXPECTED_OPERATOR_SHA=OPERATOR_PIN
def corrected_ready(directory):
 manage=op.load('ranking_corrected_health_'+directory.name,directory/'deploy/manage.py')
 for attempt in range(25):
  try:
   with contextlib.redirect_stdout(io.StringIO()):manage.health()
   pid=subprocess.run(['systemctl','show','goufayu-api.service','--property=MainPID','--value'],capture_output=True,text=True,check=True,timeout=5).stdout.strip()
   configured=subprocess.run(['systemctl','show','goufayu-api.service','--property=WorkingDirectory','--value'],capture_output=True,text=True,check=True,timeout=5).stdout.strip()
   op.need(pid.isdigit() and int(pid)>1,'corrected_archive_pid_invalid')
   op.need(Path(configured).resolve()==directory,'configured_working_directory_changed')
   op.need(Path('/proc/'+pid+'/cwd').resolve()==directory,'physical_working_directory_changed')
   return
  except Exception:
   if attempt==24:raise RuntimeError('corrected_full_readiness_failed') from None
   time.sleep(.5)
op.ready=corrected_ready
with open('/var/lock/goufayu-endless-leaderboard.lock','w') as guard:
 fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
 op.plan();op.prepared()
 op.need(op.record('database_committed.json')['status']=='COMMITTED','committed_migration_required')
 with op.payment_deploy().connection() as c:
  c.execute('SET TRANSACTION READ ONLY')
  functions=op.invariants(c);before=op.record('backup.json')['old_functions']
  op.need(set(functions)-set(before)==op.NEW_FUNCTIONS and all(functions.get(k)==v for k,v in before.items()),'committed_function_state_changed')
  op.need(len(op.table_names(c))==29,'committed_table_state_changed')
  op.runtime_probe(c);c.rollback()
 if ACTION=='activate':
  op.current(op.ROLLBACK);corrected_ready(op.ROLLBACK)
  try:
   op.systemctl('stop');op.current(op.ROLLBACK);op.switch(op.TARGET);op.systemctl('start');corrected_ready(op.TARGET)
   result=op.verify();result.update(status='DEPLOYED',code_only_resumption=True,migration_replayed=False,
    correction='Physical and configured CWD both equal the release root; original authenticated readiness retained',correction_sha256=CORRECTION_SHA)
   op.save('activation_resumed.json',result)
  except BaseException:
   errors=[]
   if (op.BASE/'current').resolve() in (op.ROLLBACK,op.TARGET):
    try:op.systemctl('stop')
    except Exception:errors.append('recovery_stop_failed')
    try:op.switch(op.ROLLBACK)
    except Exception:errors.append('recovery_pointer_switch_failed')
    try:op.systemctl('start')
    except Exception:errors.append('recovery_start_failed')
    try:corrected_ready(op.ROLLBACK)
    except Exception:errors.append('recovery_readiness_failed')
   else:errors.append('pointer_changed_by_external_actor')
   op.save('resume_failed.json',{'status':'RESUME_RECOVERY_REQUIRES_ATTENTION' if errors else 'RESUME_COMPAT_RESTORED',
    'current':str((op.BASE/'current').resolve()),'recovery_errors':errors,'migration_replayed':False,'correction_sha256':CORRECTION_SHA})
   raise
 else:
  op.current(op.TARGET);result=op.verify();result.update(migration_replayed=False,correction_sha256=CORRECTION_SHA)
  op.save('verified_after_cwd_correction.json',result)
 print(json.dumps(op.stamp(result),ensure_ascii=False))
'''
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['activate','verify']);args=parser.parse_args()
    pins=checked();assert pins['plan_sha256']==PLAN and pins['operator_sha256']==OPERATOR
    script=('OPERATOR_PIN='+repr(OPERATOR)+'\nPLAN_PIN='+repr(PLAN)+'\nACTION='+repr(args.action)
      +'\nCORRECTION_SHA='+repr(hashlib.sha256(Path(__file__).read_bytes()).hexdigest())+'\n'+CODE)
    result=remote('resume' if args.action=='activate' else 'verify',script)
    print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':main()
