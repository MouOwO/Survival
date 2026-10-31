"""Read-only WS4 compatibility audit and a concrete additive redemption plan.

Never uploads a registry, writes a remote file, clones data, migrates or deploys.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists(): raise ValueError("NEW report required")
    driver = module("ws4_readonly_transport", ROOT / "tools/ws4_catalog_sync_20261031/driver.py")
    patcher = ROOT / "tools/redemption_codes/patch_backend.py"
    sql_path = ROOT / "server/aliyun/database/target/202610290002_redemption_codes.sql"
    sql_raw = driver.ws4_sql(sql_path.read_bytes().replace(b"\r\n", b"\n"))
    source = "PATCHER=" + repr(base64.b64encode(patcher.read_bytes()).decode()) + "\n" + r'''
from pathlib import Path
import ast,base64,hashlib,json,subprocess,psycopg
root=Path('/opt/goufayu-ws4/releases/20261031-catalog-d573588b64d2')
pid=subprocess.check_output(['systemctl','show','goufayu-ws4.service','--property=MainPID','--value'],text=True).strip()
cwd=Path('/proc/'+pid+'/cwd').resolve();command=Path('/proc/'+pid+'/cmdline').read_bytes()
assert cwd in (root,root/'backend') or str(root).encode() in command
namespace={};exec(compile(base64.b64decode(PATCHER,validate=True),'public_redemption_patch','exec'),namespace)
sha=lambda raw:hashlib.sha256(raw).hexdigest()
pins={}
for name,kind in [('backend/archive_backend/service.py','service'),('backend/fishing_api/postgres.py','rpc')]:
 raw=(root/name).read_bytes();candidate=namespace['patch'](raw,kind);ast.parse(candidate)
 assert candidate!=raw and b'redemption_' in candidate
 pins[name]={'before':sha(raw),'after':sha(candidate),'bytes':len(candidate)}
result={'parent_release':root.name,'parent_manifest_sha256':sha((root/'release_manifest.json').read_bytes()),'patches':pins,'tables':{},'rpcs':{}}
with psycopg.connect(host='127.0.0.1',port=15432,dbname='goufayu_ws4',user='postgres',password=Path('/etc/goufayu-ws4/admin-password').read_text().strip()) as conn:
 conn.execute('SET TRANSACTION READ ONLY')
 for name in ['redemption_codes','redemption_claims','redemption_attempts']:
  result['tables'][name]=conn.execute('SELECT to_regclass(%s) IS NOT NULL',('public.'+name,)).fetchone()[0]
 for name in ['redemption_prepare','redemption_commit']:
  result['rpcs'][name]=conn.execute('SELECT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname=%s AND p.proname=%s)',('public',name)).fetchone()[0]
 conn.rollback()
print(json.dumps(result))
'''
    observed = driver.remote(source, timeout=35)
    modules = {}
    for name in ("redemption_codes.py", "redemption_worker.lua", "redemption_settlement.lua"):
        raw = (ROOT / "server/archive_backend" / name).read_bytes()
        modules["backend/archive_backend/" + name] = {"sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}
    registry = ROOT / "output/redemption_codes_20261029/private/server_codes_ready.json"
    registry_metadata = {"available": registry.is_file(), "uploaded": False, "registered": False}
    if registry.is_file():
        raw = registry.read_bytes(); document = json.loads(raw)
        registry_metadata.update(entries=len(document["codes"]), sha256=hashlib.sha256(raw).hexdigest(),
            cleartext_code_fields=any("code" in row or "raw_code" in row for row in document["codes"]))
    result = {"schema": 1, "status": "WS4_REDEMPTION_PLAN_NOT_APPLIED", "target": "goufayu_ws4@127.0.0.1:15432",
        "observed": observed, "new_modules": modules, "sql_source": sql_path.relative_to(ROOT).as_posix(),
        "effective_sql_sha256": hashlib.sha256(sql_raw).hexdigest(), "registry": registry_metadata,
        "backup_required": "server_full_plus_local_DPAPI_ciphertext_only", "synthetic_schema_only_validation_required": True,
        "existing_player_order_rows_must_remain_unchanged": True, "payment_service_restart_allowed": False,
        "current_deployment_authorization": "REQUIRED", "remote_files_written": False, "server_modified": False}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({"status": result["status"], "compatible_patches": len(observed["patches"]),
        "new_modules": len(modules), "tables_to_add": 3, "rpcs_to_add": 2,
        "existing_registry_available": registry_metadata["available"], "server_modified": False}))


if __name__ == "__main__": main()
