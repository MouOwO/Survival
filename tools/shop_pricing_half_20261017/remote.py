"""Pinned SSH transport for the requested shop price/rate synchronization."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/shop_pricing_half_20261017/remote'
OPTIONS = ['-T', '-F', 'none', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
           '-o', 'UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts',
           '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=10',
           '-i', str(Path.home() / '.ssh/goufayu_ecs_ed25519_v2')]


def execute(source, label, timeout=120):
    wrapped = "import json,sys\ntry:\n" + ''.join(' ' + line + '\n' for line in source.splitlines()) + '''except Exception as error:
 import re
 reason=str(error)
 print(json.dumps(dict(status='FAIL',error_type=type(error).__name__,error_code=reason if re.fullmatch(r'[A-Za-z0-9_:.() /-]{1,180}',reason) else 'private_details_suppressed')))
 sys.exit(1)
'''
    result = subprocess.run(['ssh.exe', *OPTIONS, 'root@47.110.238.248',
                             '/opt/goufayu/payments/current/.venv/bin/python -B -'],
                            input=wrapped.encode(), capture_output=True, cwd=ROOT,
                            timeout=timeout, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        records = [json.loads(line) for line in result.stdout.decode().splitlines() if line.strip()]
    except Exception:
        raise RuntimeError('invalid_remote_response_private_output_suppressed')
    report = dict(ssh_exit=result.returncode, records=records)
    (OUT / (label + '.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for record in records:
        print(json.dumps({k: v for k, v in record.items() if k not in ('functions', 'export_files', 'products', 'payment_manifest', 'archive_manifest')}, ensure_ascii=False))
    if result.returncode:
        raise SystemExit(result.returncode)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--label', required=True)
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    execute(args.source.read_text(encoding='utf-8-sig'), args.label, args.timeout)
