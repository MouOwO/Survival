"""Read-only WS4 inventory and aggregate ticket redemption audit."""
from pathlib import Path
import importlib.util
import json
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('ws4_transport',ROOT/'tools/ws4_catalog_sync_20261031/driver.py')
transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
source=(ROOT/'tools/redemption_ticket_codes_20261102/ws4_operator.py').read_text('utf8')
source+=r'''
result=inventory()
result.pop('schema_columns',None)
with connect() as conn:
 conn.execute('SET TRANSACTION READ ONLY')
 conn.execute("SET LOCAL statement_timeout='10s'")
 row=conn.execute("""SELECT o.done,o.error IS NULL,
 coalesce((o.command#>>'{rewards,products,0,grants,items,lottery_ticket}')::bigint,0),
 coalesce((s.content_inventory->>'lottery_ticket')::bigint,0),
 coalesce((o.response->>'granted')::integer,0)
 FROM public.redemption_claims c JOIN public.archive_operations o
 ON o.account_id=c.account_id AND o.operation_id=c.operation_id
 LEFT JOIN public.player_archive_state s ON s.account_id=c.account_id
 WHERE c.created_at>clock_timestamp()-interval '24 hours'
 AND o.command->>'kind'='redemption_redeem'
 AND coalesce(o.command#>>'{rewards,products,0,grants,items,lottery_ticket}','0') IN ('10','50','100','200')
 ORDER BY c.created_at DESC LIMIT 1""").fetchone()
 result['recent_ordinary_ticket_redemption']=None if row is None else dict(zip(('done','no_error','quantity','current_tickets','granted_products'),row))
 rows=conn.execute("""WITH latest AS (
 SELECT c.account_id,c.created_at FROM public.redemption_claims c
 JOIN public.archive_operations o ON o.account_id=c.account_id AND o.operation_id=c.operation_id
 WHERE c.created_at>clock_timestamp()-interval '24 hours'
 AND coalesce(o.command#>>'{rewards,products,0,grants,items,lottery_ticket}','0') IN ('10','50','100','200')
 ORDER BY c.created_at DESC LIMIT 1)
 SELECT o.command->>'pool_id',count(*),sum(coalesce((o.command->>'count')::integer,0))
 FROM public.archive_operations o JOIN latest c ON c.account_id=o.account_id
 WHERE o.event_at>c.created_at AND o.command->>'kind'='lottery_draw' AND o.done AND o.error IS NULL
 GROUP BY o.command->>'pool_id'""").fetchall()
 result['subsequent_completed_draws']=[dict(pool=r[0],operations=r[1],draws=r[2]) for r in rows]
 conn.rollback()
release=Path(result['active_release'])
result['backend_sources']={name:sha((release/'backend/archive_backend'/name).read_bytes()) for name in ('service.py',)}
result['receipt_helper_exists']=(release/'backend/archive_backend/lottery_receipt_snapshot.py').exists()
legacy=Path('/opt/goufayu/releases/current')
result['legacy_restored']=legacy.resolve().name=='20261029-redemption-2f918e4c0edd'
result['legacy_prepared_preserved']=Path('/opt/goufayu/releases/20261102-lottery-receipt-d2c7c2e85920').is_dir()
print(json.dumps(result,ensure_ascii=True))
'''
if __name__=='__main__':
    result=transport.remote(source,timeout=90)
    out=ROOT/'output/lottery_replay_release_20261102/backend/ws4_redemption_audit.json'
    out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result,ensure_ascii=True))
