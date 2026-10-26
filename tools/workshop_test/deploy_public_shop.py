"""Plan or explicitly install the independent read-only /ws4-shop/ static route.

Only --apply connects to the pinned host. It never reads payment credentials,
connects to a database, creates an order, changes an app service or edits auth.
The host's observed nginx file and all business service/code pins must match.
"""
from __future__ import annotations
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/payment_shop_20261026"
BASELINE = OUT / "static_nginx_baseline_20261025T233752Z.json"
BASELINE_SHA = "b11c63fd9a5b04d07357ed1a5f92e8fb3079e92db691e6ae35958ebe3a7ed9fb"
TRANSPORT_SHA = "b94b2fada7995561f3ed73d4b85fad81279fe90346208815a6f9c6713b15b1c4"
FILES = frozenset(("index.html", "shop.js", "shop.css", "catalog.js", "catalog.json"))
sha = lambda raw: hashlib.sha256(raw).hexdigest()

REMOTE = r'''
import base64, hashlib, json, os, re, secrets, stat, subprocess, time, urllib.request, urllib.error
from pathlib import Path
sha=lambda raw:hashlib.sha256(raw).hexdigest()
ROUTE_OBSERVATIONS=[]
def need(value,code):
 if not value:raise RuntimeError(code)
def raw(path):
 path=Path(path)
 need(path.is_file() and not path.is_symlink(),'regular_file_required')
 return path.read_bytes()
def command(args):
 result=subprocess.run(args,capture_output=True,timeout=30)
 need(result.returncode==0,'host_command_failed')
 return result.stdout.strip().decode()
def observe():
 for unit,pin in PINS['business_services'].items():
  need(command(['systemctl','is-active',unit])=='active','business_service_inactive')
  need(command(['systemctl','show',unit,'--property=MainPID','--value'])==str(pin['pid']),'business_service_pid_changed')
  need(sha(raw(pin['unit_path']))==pin['unit_sha256'],'business_unit_changed')
 for name,pin in PINS['release_pointers'].items():
  target=Path(name).resolve(strict=True)
  need(str(target)==pin['target'],'business_release_changed')
  if pin['release_manifest_sha256'] is not None:
   need(sha(raw(target/'release_manifest.json'))==pin['release_manifest_sha256'],'business_manifest_changed')
 for name,pin in PINS['fixed_releases'].items():
  for relative,digest in pin['code_sha256'].items():
   path=Path(name)/relative
   need(not path.exists() if digest is None else sha(raw(path))==digest,'isolated_code_changed')
 need(sha(raw('/etc/nginx/goufayu-ws4-web.locations'))==PINS['existing_ws4_web_include_sha256'],'auth_include_changed')
def health():
 for port in (8765,8766,18765,18767):
  with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=8) as response:
   need(response.status==200 and json.load(response).get('ok') is True,'existing_health_failed')
def newfile(path,data,mode):
 need(not path.exists() and not path.is_symlink(),'new_file_required')
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode)
 with os.fdopen(fd,'wb') as output:output.write(data);output.flush();os.fsync(output.fileno())
 path.chmod(mode)
def replace(path,data,info):
 need(not path.is_symlink(),'replace_symlink_refused')
 temporary=path.with_name(path.name+'.ws4-shop-'+secrets.token_hex(8))
 newfile(temporary,data,stat.S_IMODE(info.st_mode));os.chown(temporary,info.st_uid,info.st_gid)
 os.replace(temporary,path)
def root_response(timeout=3):
 class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self,request,fp,code,message,headers,newurl):return None
 try:
  with urllib.request.build_opener(NoRedirect).open('https://pay.xiaofengnet.com/ws4-shop/',timeout=timeout) as response:
   code,location=response.status,response.headers.get('Location')
 except urllib.error.HTTPError as error:code,location=error.code,error.headers.get('Location')
 return code,location
def wait_route():
 deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  try:
   code,location=root_response()
   ROUTE_OBSERVATIONS.append({'status':code,'expected_location':location in ('/ws4-shop/index.html','https://pay.xiaofengnet.com/ws4-shop/index.html')})
   if code==302 and location in ('/ws4-shop/index.html','https://pay.xiaofengnet.com/ws4-shop/index.html'):
    time.sleep(0.5);return
  except (OSError,urllib.error.URLError):pass
  time.sleep(0.25)
 raise RuntimeError('public_route_not_ready_after_reload')
def public():
 code,location=root_response()
 need(code==302 and location in ('/ws4-shop/index.html','https://pay.xiaofengnet.com/ws4-shop/index.html'),'public_root_redirect_mismatch')
 for name,digest in MANIFEST['files'].items():
  address='https://pay.xiaofengnet.com/ws4-shop/'+name
  with urllib.request.urlopen(address,timeout=15) as response:
   need(response.status==200 and sha(response.read(1024*1024))==digest,'public_static_bytes_mismatch')
   need(response.headers.get('Content-Security-Policy')==CSP,'public_csp_missing')
   content_type=response.headers.get('Content-Type','').lower().replace(' ','')
   need(content_type==types[name]+';charset=utf-8','public_static_content_type_mismatch')
   for header,expected in (('X-Content-Type-Options','nosniff'),('Referrer-Policy','no-referrer'),('Cache-Control','no-store')):
    need(response.headers.get(header)==expected,'public_static_header_mismatch')
 for suffix,method,expected in (('', 'POST',405),('checkout','GET',404),('../ws4-shop/not-a-file','GET',404)):
  request=urllib.request.Request('https://pay.xiaofengnet.com/ws4-shop/'+suffix,method=method,data=b'' if method=='POST' else None)
  try:
   with urllib.request.urlopen(request,timeout=10) as response:status=response.status
  except urllib.error.HTTPError as error:status=error.code
  need(status==expected,'public_static_route_scope_failed')

need(PINS['target']['path']=='/etc/nginx/nginx.conf','unexpected_nginx_target')
need(set(PAYLOAD)==set(MANIFEST['files'])=={'index.html','shop.js','shop.css','catalog.js','catalog.json'},'static_file_set_changed')
need(MANIFEST['checkout_enabled'] is False and MANIFEST['public_base']=='https://pay.xiaofengnet.com/ws4-shop/','readonly_shop_required')
need(isinstance(MANIFEST.get('catalog_sha256'),str) and re.fullmatch(r'[a-f0-9]{64}',MANIFEST['catalog_sha256']),'catalog_hash_invalid')
assets={name:base64.b64decode(data,validate=True) for name,data in PAYLOAD.items()}
need(all(len(data)<=1024*1024 and sha(data)==MANIFEST['files'][name] for name,data in assets.items()),'static_payload_changed')
catalog=json.loads(assets['catalog.json'])
need(catalog['checkout_enabled'] is False and catalog['availability']=='preview_only' and catalog['catalog_sha256']==MANIFEST['catalog_sha256'],'readonly_catalog_required')
unsigned=dict(catalog);unsigned.pop('catalog_sha256')
need(sha(json.dumps(unsigned,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode())==MANIFEST['catalog_sha256'],'catalog_hash_mismatch')
observe();health();command(['nginx','-t'])
config=Path('/etc/nginx/nginx.conf');before=raw(config);info=config.stat()
need(sha(before)==PINS['target']['sha256'],'nginx_changed_since_readonly_review')
needle=b'    include /etc/nginx/goufayu-ws4-web.locations;'
need(before.count(needle)==1 and b'/ws4-shop' not in before and b'goufayu-ws4-shop.locations' not in before,'nginx_insert_context_changed')
include=Path('/etc/nginx/goufayu-ws4-shop.locations')
need(not include.exists() and not include.is_symlink(),'shop_route_already_exists')
manifest_digest=sha(json.dumps(MANIFEST,sort_keys=True,separators=(',',':')).encode())
base=Path('/opt/goufayu-ws4-shop');release=base/'releases'/('20261026-'+manifest_digest[:16])
for path in (base,base/'releases'):
 need(not path.is_symlink(),'shop_parent_symlink_refused');path.mkdir(exist_ok=True,mode=0o755)
manifest_raw=(json.dumps(MANIFEST,sort_keys=True)+'\n').encode()
if release.exists():
 need(not release.is_symlink() and release.is_dir() and release.stat().st_uid==0,'inactive_release_directory_invalid')
 need({p.name for p in release.iterdir()}==set(assets)|{'manifest.json'},'inactive_release_files_changed')
 need(raw(release/'manifest.json')==manifest_raw and all(raw(release/name)==data for name,data in assets.items()),'inactive_release_bytes_changed')
else:
 need(not release.is_symlink(),'new_static_release_required');release.mkdir(mode=0o755)
 for name,data in assets.items():newfile(release/name,data,0o644)
 newfile(release/'manifest.json',manifest_raw,0o644)
CSP="default-src 'none'; script-src 'self'; style-src 'self'; img-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
headers='\n'.join('    '+line for line in (
 'add_header Content-Security-Policy "'+CSP+'" always;',
 'add_header Referrer-Policy "no-referrer" always;',
 'add_header X-Content-Type-Options "nosniff" always;',
 'add_header Cache-Control "no-store" always;'))
rules=['# Read-only WS4 shop. No proxy, auth, payment or player-data route.',
       'location = /ws4-shop { return 308 /ws4-shop/; }',
       'location = /ws4-shop/ {\n    if ($request_method !~ ^(GET|HEAD)$) { return 405; }\n    return 302 /ws4-shop/index.html;\n}',
       'location ^~ /ws4-shop/ { return 404; }']
types={'index.html':'text/html','shop.css':'text/css','shop.js':'application/javascript','catalog.js':'application/javascript','catalog.json':'application/json'}
for name in sorted(assets):
 uri='/ws4-shop/'+name
 rules.append('location = '+uri+' {\n    if ($request_method !~ ^(GET|HEAD)$) { return 405; }\n'
              +'    alias '+str(release/name)+';\n    types { }\n    default_type '+types[name]+';\n    charset utf-8;\n    charset_types text/css application/javascript application/json;\n'+headers+'\n}')
rules=('\n'.join(rules)+'\n').encode()
after=before.replace(needle,needle+b'\n    include /etc/nginx/goufayu-ws4-shop.locations;',1)
backup=Path('/var/backups/goufayu-ws4-shop');need(not backup.is_symlink(),'backup_parent_symlink_refused');backup.mkdir(mode=0o700,exist_ok=True)
backup=backup/('20261026-'+secrets.token_hex(8));backup.mkdir(mode=0o700)
newfile(backup/'nginx.before',before,0o600);newfile(backup/'locations.after',rules,0o600)
newfile(backup/'nginx.after',after,0o600)
stage='install_include';changed=False
try:
 observe();need(raw(config)==before,'nginx_changed_before_install')
 newfile(include,rules,0o644)
 stage='insert_include';replace(config,after,info);changed=True
 stage='validate_nginx';command(['nginx','-t'])
 stage='reload_nginx';command(['systemctl','reload','nginx'])
 stage='wait_new_route';wait_route()
 stage='verify_public';public();health();observe()
 need(raw(config)==after and raw(include)==rules,'nginx_changed_during_final_verification')
 result={'ok':True,'phase':'READ_ONLY_SHOP_DEPLOYED','public_base':MANIFEST['public_base'],
  'catalog_sha256':MANIFEST['catalog_sha256'],'static_files':len(assets),'checkout_enabled':False,
  'business_services_unchanged':True,'database_accessed':False,'orders_created':False,'rewards_granted':False,
  'nginx_sha256':sha(after),'backup':str(backup),'release':str(release)}
 result['route_readiness_observations']=ROUTE_OBSERVATIONS
 result['direct_file_bytes_and_headers_verified']=True
 newfile(backup/'verified.json',(json.dumps(result,sort_keys=True)+'\n').encode(),0o600)
 print(json.dumps(result,sort_keys=True))
except Exception as error:
 rollback=False
 try:
  need(raw(config)==(after if changed else before),'nginx_rollback_concurrent_edit')
  if changed:replace(config,before,info)
  if include.exists():need(raw(include)==rules,'include_rollback_concurrent_edit');include.unlink()
  command(['nginx','-t']);command(['systemctl','reload','nginx']);health();observe();rollback=True
 except Exception:pass
 code=str(error) if isinstance(error,RuntimeError) and re.fullmatch(r'[a-z_]{3,80}',str(error)) else 'static_deploy_verification_failed'
 print(json.dumps({'ok':False,'phase':'READ_ONLY_SHOP_DEPLOY_FAILED','stage':stage,'error':code,'rollback_ok':rollback,'route_readiness_observations':ROUTE_OBSERVATIONS}))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-release", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    baseline_raw = BASELINE.read_bytes()
    if sha(baseline_raw) != BASELINE_SHA:
        raise RuntimeError("readonly_host_baseline_changed")
    pins = json.loads(baseline_raw)["summary"]
    release = args.web_release.resolve(strict=True)
    if not release.is_relative_to(OUT.resolve()) or release.is_symlink():
        raise RuntimeError("web_release_must_be_new_task_output")
    manifest = json.loads((release / "manifest.json").read_bytes())
    import re
    if (manifest.get("checkout_enabled") is not False or manifest.get("public_base") != "https://pay.xiaofengnet.com/ws4-shop/"
            or not isinstance(manifest.get("catalog_sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", manifest["catalog_sha256"])):
        raise RuntimeError("readonly_public_shop_required")
    if set(manifest["files"]) != FILES or set(p.name for p in release.iterdir()) != FILES | {"manifest.json"}:
        raise RuntimeError("unexpected_static_files")
    payload = {}
    for name, digest in manifest["files"].items():
        path = release / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError("static_source_must_be_regular")
        raw = path.read_bytes()
        if len(raw) > 1024 * 1024 or sha(raw) != digest:
            raise RuntimeError("static_source_drift")
        payload[name] = base64.b64encode(raw).decode("ascii")
    # Only the reviewed local web sources and freshly compiled formal catalog
    # can be published; a caller-supplied manifest is not an authorization.
    catalog_spec = importlib.util.spec_from_file_location("shop_formal_builder", Path(__file__).with_name("build_public_shop_catalog.py"))
    catalog_builder = importlib.util.module_from_spec(catalog_spec); catalog_spec.loader.exec_module(catalog_builder)
    data = catalog_builder.catalog()
    expected = {name: (ROOT / "server/web_shop" / name).read_bytes() for name in ("index.html", "shop.js", "shop.css")}
    expected["catalog.js"] = catalog_builder.javascript(data, "browser")
    expected["catalog.json"] = catalog_builder.canonical(data) + b"\n"
    if manifest.get("catalog_sha256") != data["catalog_sha256"] or any(base64.b64decode(payload[name]) != raw for name, raw in expected.items()):
        raise RuntimeError("static_payload_is_not_reviewed_formal_build")
    transport_path = ROOT / "tools/archive_caps_20261020/remote_driver.py"
    if sha(transport_path.read_bytes()) != TRANSPORT_SHA:
        raise RuntimeError("pinned_transport_changed")
    if not args.apply:
        print(json.dumps(dict(ok=True, phase="LOCAL_READ_ONLY_SHOP_PLAN", public_base=manifest["public_base"],
            files=len(payload), catalog_sha256=manifest["catalog_sha256"], checkout_enabled=False,
            host_contacted=False, services_changed=False)))
        return
    receipt = OUT / "web_deployment.json"
    if receipt.exists():
        raise RuntimeError("web_deployment_receipt_already_exists")
    spec = importlib.util.spec_from_file_location("shop_pinned_transport", transport_path)
    transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)
    source = "PINS=" + repr(pins) + "\nMANIFEST=" + repr(manifest) + "\nPAYLOAD=" + repr(payload) + "\n" + REMOTE
    try:
        result = json.loads(transport.remote(source, timeout=120))
    except RuntimeError:
        # The fixed transport emits a bounded error summary, never stderr or
        # credentials. Preserve a local failure receipt even before activation.
        result = dict(ok=False, phase="READ_ONLY_SHOP_REMOTE_CHECK_FAILED", rollback_ok=None)
    with receipt.open("xb") as output:
        output.write((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps(result, ensure_ascii=False))
    if result.get("ok") is not True:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
