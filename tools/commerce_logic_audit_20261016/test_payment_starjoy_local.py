"""Exact local-DB before/after rollback verification; never connects externally."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path[:0]=[str(ROOT),str(ROOT/'server'),str(ROOT/'output/video_shop_20261015/deps')]
import psycopg
from payment_backend.test_starjoy_progress_database import run_checks
from payment_backend.csv_catalog import build
catalog=build(ROOT)["catalog"]
out=ROOT/'design_refs/commerce_logic_audit_20261016';out.mkdir(parents=True,exist_ok=True)
dsn='host=127.0.0.1 port=54627 dbname=survival_bundle_test user=postgres'
def immutable_digest(c):
 result={}
 for table in c.execute("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN ('public','payments') ORDER BY schemaname,tablename"):
  name='.'.join(table);rows=[r[0] for r in c.execute('SELECT to_jsonb(t)::text FROM '+name+' t ORDER BY to_jsonb(t)::text')];result[name]=hashlib.sha256(json.dumps(rows).encode()).hexdigest()
 return result
with psycopg.connect(dsn) as c:
 assert c.info.host=='127.0.0.1' and c.info.port==54627 and c.info.dbname=='survival_bundle_test'
 initial=immutable_digest(c);definition=c.execute("SELECT pg_get_functiondef('payments.apply_effects(text,jsonb,boolean)'::regprocedure)").fetchone()[0]
 (out/'baseline/apply_effects.sql').write_text(definition,encoding='utf-8');c.rollback()
 try:
  c.execute('SELECT 1');run_checks(c,catalog)
 except AssertionError as error:before={'status':'EXPECTED_FAIL','message':str(error)}
 else:raise AssertionError('Baseline must reproduce earned-progress failure')
 finally:c.rollback()
 (out/'baseline/sql_starjoy_failure.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
 c.execute((ROOT/'server/payment_backend/upgrade_starjoy_progress.sql').read_text(encoding='utf-8'))
 after=run_checks(c,catalog)
 # Reapplying the exact migration leaves the helper and semantics unchanged.
 new_definition=c.execute("SELECT pg_get_functiondef('payments.apply_effects(text,jsonb,boolean)'::regprocedure)").fetchone()[0]
 c.execute((ROOT/'server/payment_backend/upgrade_starjoy_progress.sql').read_text(encoding='utf-8'))
 assert c.execute("SELECT pg_get_functiondef('payments.apply_effects(text,jsonb,boolean)'::regprocedure)").fetchone()[0]==new_definition
 from tools.compact_checkout_20261015.test_quantity_database import run_checks as quantity_checks
 quantity_result=quantity_checks(c);bundle_result={'status':'NOT_APPLICABLE','reason':'Legacy bundle SQL fixture asserts receipt.version=4; deployed quantity migration emits version5. Kept assertions unchanged; current quantity SQL suite validates bundle/VIP/component paths.'}
 # Guard both forward and rollback scripts against silently replacing newer work.
 hostile=new_definition.replace("END; $function$", "-- third-party revision fixture\nEND; $function$")
 if hostile==new_definition:
  hostile=new_definition.replace("RETURN applied;", "RETURN applied; -- third-party revision fixture")
 for script in [ROOT/'server/payment_backend/upgrade_starjoy_progress.sql',ROOT/'tools/commerce_logic_audit_20261016/rollback_starjoy_progress.sql']:
  try:
   with c.transaction():
    c.execute(hostile)
    c.execute(script.read_text(encoding='utf-8'))
  except psycopg.errors.RaiseException as error:
   assert 'definition_unexpected' in str(error)
  else:raise AssertionError('Third-party helper must not be overwritten')
 # Only the expected helper is replaced. Restoring its original function body
 # does not rewrite any receipts or attempt to take back legitimate rewards.
 c.execute((ROOT/'tools/commerce_logic_audit_20261016/rollback_starjoy_progress.sql').read_text(encoding='utf-8'))
 assert c.execute("SELECT pg_get_functiondef('payments.apply_effects(text,jsonb,boolean)'::regprocedure)").fetchone()[0]==definition
 c.rollback()
 assert immutable_digest(c)==initial,'All account/order/catalog/claims tables must be unchanged after rollback'
 assert c.execute("SELECT pg_get_functiondef('payments.apply_effects(text,jsonb,boolean)'::regprocedure)").fetchone()[0]==definition
 report={'before':before,'after':after,'legacy_quantity_checks':quantity_result,'legacy_bundle_checks':bundle_result,'third_party_definition_guard':True,'migration_idempotent':True,'code_rollback_exact':True,'all_table_digests_preserved':True,'table_count':len(initial),'original_function_restored':True,'scope':'Disposable localhost54627 transaction only, no gateways/orders outside local fixtures','migration_sha256':hashlib.sha256((ROOT/'server/payment_backend/upgrade_starjoy_progress.sql').read_bytes()).hexdigest()}
 (out/'payment_starjoy_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2))
