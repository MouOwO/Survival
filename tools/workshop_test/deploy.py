"""Apply one explicit isolated-host step over the project's pinned SSH transport."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ws4_pinned_transport',ROOT/'tools/archive_caps_20261020/remote_driver.py')
transport=importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('prepare','finish_prepare','initialize_database','finish_database','harden_database','restore_ownership','start','verify','https_enable','pending','approve','update_overlay','audit'))
    parser.add_argument('--fingerprint',help='Only the fingerprint explicitly confirmed by the owner in their actual Workshop game')
    args=parser.parse_args()
    overlay={}
    if args.mode in ('prepare','finish_prepare','update_overlay'):
        for name in ('auth.py','run_api.py'):
            overlay['backend/workshop_test/'+name]=base64.b64encode((ROOT/'server/workshop_test'/name).read_bytes()).decode()
        overlay['backend/workshop_test/__init__.py']=''
        overlay['backend/archive_backend/test_access.py']=base64.b64encode((ROOT/'server/archive_backend/test_access.py').read_bytes()).decode()
    source='MODE='+repr(args.mode)+'\nOVERLAY='+repr(overlay)+'\nFINGERPRINT='+repr(args.fingerprint)+'\n'+Path(__file__).with_name('remote_operator.py').read_text(encoding='utf8')
    output=transport.remote(source,timeout=240)
    directory=ROOT/'output/workshop_auth_20261023'
    directory.mkdir(parents=True,exist_ok=True)
    (directory/('deploy_'+args.mode+'.json')).write_text(output,encoding='utf8')
    print(output)


if __name__=='__main__':main()
