"""Explicit phases for the authorized host, using existing pinned SSH identity."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'design_refs/vip_recharge_20261016/release'
STAGE = '/tmp/survival-vip-recharge-20261016-v1'
spec = importlib.util.spec_from_file_location('vip_transport', ROOT / 'tools/shop_catalog_20261016/deploy_driver.py')
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
transport.REPORT = ROOT / 'design_refs/vip_recharge_20261016/deployment'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['check', 'upload', 'prepare', 'validate', 'activate', 'verify'])
    args = parser.parse_args()
    plan_raw = (OUT / 'release_plan.json').read_bytes()
    plan = json.loads(plan_raw)
    paths = {name: OUT / 'payload' / name for name in plan['files']}
    for name, path in paths.items():
        assert sha(path.read_bytes()) == plan['files'][name], 'overlay_changed:' + name
    operator = Path(__file__).with_name('deploy_remote.py')
    pin, operator_pin = sha(plan_raw), sha(operator.read_bytes())
    if args.action == 'check':
        print(json.dumps({'status': 'LOCAL_ARTIFACTS_VERIFIED', 'plan_sha': pin, 'operator_sha': operator_pin,
                          'target_release': plan['target_release'], 'payment_service_unchanged': True}))
        return
    if args.action == 'upload':
        paths.update({'release_plan.json': OUT / 'release_plan.json', 'deploy_remote.py': operator})
        entries = {name: {'sha256': sha(path.read_bytes()), 'base64': base64.b64encode(path.read_bytes()).decode()}
                   for name, path in paths.items()}
        code = 'STAGE=' + repr(STAGE) + '\nENTRIES=' + repr(entries) + '\n' + '''
from pathlib import Path,PurePosixPath
import base64,hashlib,json,os
os.umask(0o077);stage=Path(STAGE)
if stage.is_symlink():raise RuntimeError('stage_symlink')
stage.mkdir(mode=0o700,exist_ok=True)
if stage.stat().st_uid!=0 or stage.stat().st_mode&0o077:raise RuntimeError('private_stage_required')
for name,item in ENTRIES.items():
 relative=PurePosixPath(name)
 if relative.is_absolute() or '..' in relative.parts or ':' in name or '\\\\' in name:raise RuntimeError('unsafe_upload')
 raw=base64.b64decode(item['base64'],validate=True)
 if hashlib.sha256(raw).hexdigest()!=item['sha256']:raise RuntimeError('upload_hash')
 target=stage/name;target.parent.mkdir(parents=True,exist_ok=True)
 if target.is_symlink():raise RuntimeError('upload_symlink')
 if target.exists():
  if target.read_bytes()!=raw:raise RuntimeError('immutable_upload_changed')
 else:
  with target.open('xb') as f:f.write(raw)
  target.chmod(0o600)
print(json.dumps({'status':'UPLOADED_NOT_ACTIVE','files':len(ENTRIES)}))
'''
    else:
        if args.action == 'activate':
            candidate = json.loads((ROOT / 'design_refs/vip_recharge_20261016/game/candidate_validation.json').read_bytes())
            assert candidate['status'] == 'PASS', 'candidate_native_tests_required'
            assert candidate['bundle_hash'] == plan['bundle'], 'tested_bundle_changed'
            for name, digest in candidate['source_sha256'].items():
                assert plan['files']['backend/archive_backend/' + name] == digest, 'tested_candidate_changed:' + name
        code = 'import runpy,sys\nsys.dont_write_bytecode=True\nsys.argv=' + repr([
            'deploy_remote.py', args.action, '--plan-sha', pin, '--operator-sha', operator_pin])
        code += '\nrunpy.run_path(' + repr(STAGE + '/deploy_remote.py') + ",run_name='__main__')\n"
    print(json.dumps(transport.remote('vip_' + args.action, code, timeout=180), ensure_ascii=False))


if __name__ == '__main__':
    main()
