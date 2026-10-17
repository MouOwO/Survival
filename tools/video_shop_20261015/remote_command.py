"""Run one explicitly reviewed remote command; never prints credential contents."""
from pathlib import Path
import subprocess,sys,shlex
ROOT=Path(__file__).resolve().parents[2]
name,command=sys.argv[1:]
if not name.replace('_','').isalnum():raise SystemExit('invalid_report_name')
opts=['-T','-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','UserKnownHostsFile=tools/deploy/goufayu_test_known_hosts','-o','IdentitiesOnly=yes','-o','ConnectTimeout=10','-i',str(Path.home()/'.ssh/goufayu_ecs_ed25519_v2')]
code='import subprocess,sys; sys.exit(subprocess.run('+repr(shlex.split(command))+').returncode)'
r=subprocess.run(['ssh.exe',*opts,'root@47.110.238.248','/opt/goufayu/payments/20261014-payment01/.venv/bin/python -B -'],input=code.encode('utf8'),stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=ROOT,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
p=ROOT/'output/video_shop_20261015/release'/(name+'.log');p.write_bytes(r.stdout+r.stderr)
print(r.stdout.decode('utf8',errors='replace'))
if r.returncode:
 print(r.stderr.decode('utf8',errors='replace')[:1500]);raise SystemExit(r.returncode)
