"""Current PostgreSQL ranking VIP projection checks, savepoint-rollback only."""
import hashlib, json, re, secrets

def run_checks(conn, migration_source, defaults):
    from psycopg.types.json import Jsonb
    assert not conn.autocommit and conn.info.transaction_status.name == 'INTRANS'
    checks=[]
    def need(value,name):
        assert value,name
        checks.append(name)
    signature='public.archive_endless_leaderboard()'
    original=conn.execute('SELECT pg_get_functiondef(%s::regprocedure)',(signature,)).fetchone()[0]
    owner=conn.execute("SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid=%s::regprocedure",(signature,)).fetchone()[0]
    need(owner=='goufayu_owner','ranking_owner_preserved')
    need(conn.execute("SELECT has_table_privilege(%s,'payments.vip_recharge_levels','SELECT')",(owner,)).fetchone()[0], 'ranking_definer_can_read_thresholds')
    nonce=secrets.token_hex(16)
    ids=[]
    conn.execute('SAVEPOINT vip_rank_projection_fixture')
    try:
        # 105 fresh synthetic saves fill the entire top 100; no real identities
        # need to leave PostgreSQL or appear in the fixture report.
        for index in range(105):
            account=hashlib.sha256(('vip_rank:'+nonce+':'+str(index)).encode()).hexdigest()
            need(not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone(),'fresh_rank_fixture_'+str(index))
            conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s)',(account,Jsonb(defaults)))
            saved={'endless_best_wave':9007199254740000-index,'endless_score':105-index}
            conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s)',(account,Jsonb(saved),Jsonb({})))
            entry=conn.execute('SELECT entry_id::text FROM public.archive_leaderboard_identities WHERE account_id=%s',(account,)).fetchone()[0]
            ids.append((account,entry,saved))
        old_rows=conn.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]['entries']
        need(len(old_rows)==100 and [r['entry_id'] for r in old_rows]==[v[1] for v in ids[:100]], 'old_projection_exact_top100_fixture_order')
        inner=re.sub(r'(?im)^BEGIN;\s*','',migration_source,count=1)
        inner=re.sub(r'(?im)^COMMIT;\s*$','',inner,count=1)
        need(not re.search(r'(?im)^\s*(BEGIN|COMMIT);',inner),'only_outer_migration_transaction_removed')
        conn.execute(inner)
        def rows():
            value=conn.execute('SELECT public.archive_endless_leaderboard()').fetchone()[0]
            need(value.get('ok') is True,'ranking_response_ok')
            return value['entries']
        new_rows=rows()
        need([{k:v for k,v in row.items() if k not in ('vip_level','vip_medal_level')} for row in new_rows]==old_rows,'all_original_rank_fields_and_order_unchanged')
        need(all(set(r)=={'entry_id','steam_id','best_floor','endless_score','vip_level','vip_medal_level'} for r in new_rows),'public_fields_only_no_recharge_amount_or_inventory')
        account,entry,saved=ids[0]
        thresholds=conn.execute('SELECT level,required_fen FROM payments.vip_recharge_levels ORDER BY level').fetchall()
        for level,fen in thresholds:
            conn.execute('UPDATE public.player_gameplay_stats SET vip_recharge_total_fen=%s,vip_level=12 WHERE player_id=%s',(fen-1,account))
            result=next(r for r in rows() if r['entry_id']==entry)
            need(result['vip_level']==level-1 and result['vip_medal_level']==0,'vip'+str(level)+'_before_threshold_cache_cannot_bypass')
            conn.execute('UPDATE public.player_gameplay_stats SET vip_recharge_total_fen=%s,vip_level=0 WHERE player_id=%s',(fen,account))
            result=next(r for r in rows() if r['entry_id']==entry)
            need(result['vip_level']==level and result['vip_medal_level']==0,'vip'+str(level)+'_exact_threshold_without_free_paid_medal')
        def medal(claims,inventory,expected,label):
            archive=dict(saved,vip_claimed=claims)
            conn.execute('UPDATE public.player_archive_state SET archive=%s,content_inventory=%s WHERE account_id=%s',(Jsonb(archive),Jsonb(inventory),account))
            result=next(r for r in rows() if r['entry_id']==entry)
            need(result['vip_level']==12 and result['vip_medal_level']==expected,label)
        medal({'vip_medal_03':True},{},3,'owned_claim_true_medal3')
        medal({'vip_medal_03':False},{},0,'false_claim_not_owned')
        medal({'vip_medal_09':'true'},{},0,'string_claim_not_true')
        medal({}, {'vip_medal_05':1},5,'inventory_owned_medal5')
        medal({'vip_medal_03':True},{'vip_medal_05':1,'vip_medal_10':0},5,'highest_actual_owned_medal')
        medal({}, {'vip_medal_05':0,'vip_medal_10':-1,'vip_medal_09':None},0,'zero_negative_null_inventory_not_owned')
        medal({}, {'vip_medal_08':'1'},0,'string_inventory_not_owned')
        medal({'vip_medal_11':True},{'vip_medal_12':1},0,'unsupported_medal_tiers_not_invented')
        final_rows=rows()
        need(len(final_rows)==100 and [r['entry_id'] for r in final_rows]==[v[1] for v in ids[:100]],'top100_order_unchanged_after_all_badge_updates')
        for role in ('anon','authenticated','service_role','goufayu_payment'):
            need(not conn.execute('SELECT has_function_privilege(%s,%s,%s)',(role,signature,'EXECUTE')).fetchone()[0],role+'_cannot_execute_ranking')
        need(conn.execute('SELECT has_function_privilege(%s,%s,%s)',('goufayu_app',signature,'EXECUTE')).fetchone()[0], 'application_can_execute_ranking')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT vip_rank_projection_fixture')
    need(conn.execute('SELECT pg_get_functiondef(%s::regprocedure)',(signature,)).fetchone()[0]==original,'ranking_function_rolled_back_to_original')
    need(conn.execute('SELECT count(*) FROM public.survival_players WHERE account_id=ANY(%s)',([v[0] for v in ids],)).fetchone()[0]==0,'all_105_rank_fixture_accounts_rolled_back')
    return {'status':'PASS','checks':checks,'check_count':len(checks),'synthetic_accounts':len(ids),
            'original_ranking_function_sha256':hashlib.sha256(original.encode()).hexdigest(),
            'fixture_writes_committed':0,'sql_function_patch_rolled_back':True,'gateway_requests':0}
