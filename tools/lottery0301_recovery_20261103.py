"""Run only pinned0301 close/restore while preserving in-progress pipeline work.

The completed0301 report pins the old common entry bytes. Temporarily restoring
those exact Git bytes lets its original validators run without weakening them.
No validator/policy mutation, SDK publication, force-stop or install bypass.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,sys

ROOT=Path(__file__).resolve().parents[1]
SHA='ad68a1cc205c4df3a99f8a298e8213d92508c308270e15932321e65fcbe6312d'
OPERATOR='e26c11f651b02f4987a60aebd6a37d444bc8d9ca'
digest=lambda raw:hashlib.sha256(raw).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('close','restore'))
    args=parser.parse_args()
    report_path=ROOT/'output/lottery_redemption_release_20261103/package.json'
    raw=report_path.read_bytes()
    if digest(raw)!=SHA:raise ValueError('completed0301_report_changed')
    report=json.loads(raw)
    path=ROOT/'tools/release_pipeline.py';edited=path.read_bytes()
    frozen=subprocess.check_output(['git','show',OPERATOR+':tools/release_pipeline.py'],cwd=ROOT)
    pin=report['auxiliary_input_pins']['tools/release_pipeline.py']['sha256']
    if digest(frozen)!=pin:raise ValueError('original_pinned_pipeline_bytes_required')
    folder=ROOT/'output/release_workflow_20261103';folder.mkdir(exist_ok=True)
    backup=folder/('pipeline_working_'+digest(edited)+'.py')
    if backup.exists() and backup.read_bytes()!=edited:raise ValueError('backup_conflict')
    if not backup.exists():backup.write_bytes(edited)
    try:
        path.write_bytes(frozen)
        result=subprocess.run([sys.executable,'-X','utf8','-B',str(path),'rehearsal',args.action,
            '--transaction','run02','--report-sha256',SHA],cwd=ROOT,env=os.environ)
        return result.returncode
    finally:
        if path.read_bytes()!=frozen:raise ValueError('pipeline_changed_during_pinned_operation_preserve_backup')
        path.write_bytes(edited)
        if digest(path.read_bytes())!=digest(edited):raise ValueError('working_pipeline_restore_failed')

if __name__=='__main__':raise SystemExit(main())
