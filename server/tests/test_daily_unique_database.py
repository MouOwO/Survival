"""Real PostgreSQL checks for the owner-controlled candidate transaction.

run_checks() never commits and always rolls its synthetic account, backups,
constraint changes and stat writes back to its own savepoint. Call only after
the candidate's real-data preview/repair and constraint validation have passed.
"""
import copy
import hashlib
import json
import uuid


def runtime_checks(conn,bundle,account,saved):
    """Use the real app session identity inside the uncommitted DDL trial.

    A second connection cannot see the candidate's uncommitted permission
    changes. The existing admin session temporarily assumes the app identity,
    runs the exact startup permission checks and real definer RPCs, then rolls
    every probe back and restores its original authorization and role.
    """
    from fishing_api.postgres import PostgresRpcClient
    session,role,is_superuser=conn.execute('''SELECT session_user,current_user,
        (SELECT rolsuper FROM pg_roles WHERE rolname=session_user)''').fetchone()
    assert is_superuser is True,'Candidate role checks require the existing admin session'
    available=[bundle.hash,*getattr(bundle,'compatible_config_hashes',{})]
    registered=conn.execute('''SELECT config_hash FROM public.archive_config_sets
        WHERE config_hash=ANY(%s::text[]) ORDER BY CASE WHEN config_hash=%s THEN 0 ELSE 1 END,config_hash LIMIT 1''',
        (available,bundle.hash)).fetchone()
    assert registered,'A previously registered compatible configuration is required'
    fingerprint=hashlib.sha256(('daily-unique-runtime:'+str(uuid.uuid4())).encode()).hexdigest()
    conn.execute('SAVEPOINT daily_unique_app_runtime')
    try:
        conn.execute('RESET ROLE')
        conn.execute('SET SESSION AUTHORIZATION goufayu_app')
        assert conn.execute('SELECT session_user,current_user').fetchone()==('goufayu_app','goufayu_app')
        assert conn.execute("SELECT has_function_privilege(current_user,'public.archive_unique_points_20261019_valid(jsonb,jsonb)','EXECUTE')").fetchone()==(False,)
        class TransactionLease:
            # Run the exact ready() path against this real PostgreSQL session,
            # while its normal per-request commit/close cannot escape the
            # caller's uncommitted candidate validation and fixture savepoint.
            def cursor(self):return conn.cursor()
            def commit(self):pass
            def rollback(self):pass
            def close(self):pass
        client=PostgresRpcClient('service=goufayu_app',connector=lambda *args,**kwargs:TransactionLease())
        assert client.ready() is True
        payload=copy.deepcopy(saved)
        for value in (1,0):
            identity='daily-runtime:'+fingerprint+':'+str(value)
            command={'id':identity,'kind':'daily_init'}
            prepared=conn.execute('SELECT public.archive_prepare(%s,%s,%s,%s,%s::jsonb)',
                (account,identity,registered[0],fingerprint,json.dumps(command))).fetchone()[0]
            assert prepared['ok'] is True and not prepared['done']
            payload['daily_rewards']['item_counts']['daily_growth_gem']=value
            payload['runtime_probe']='valid-'+str(value)
            committed=conn.execute('SELECT public.archive_commit(%s,%s,%s,%s::jsonb,%s::jsonb,NULL)',
                (account,identity,prepared['profile']['revision'],json.dumps(payload),'{}')).fetchone()[0]
            assert committed['ok'] is True and committed['done'] is True
            assert committed['profile']['save']['archive']['daily_rewards']['item_counts']['daily_growth_gem']==value
        conn.execute('SAVEPOINT daily_unique_app_invalid')
        try:
            identity='daily-runtime:'+fingerprint+':invalid'
            prepared=conn.execute('SELECT public.archive_prepare(%s,%s,%s,%s,%s::jsonb)',
                (account,identity,registered[0],fingerprint,json.dumps({'id':identity,'kind':'daily_init'}))).fetchone()[0]
            payload['daily_rewards']['item_counts']['daily_growth_gem']=2
            conn.execute('SELECT public.archive_commit(%s,%s,%s,%s::jsonb,%s::jsonb,NULL)',
                (account,identity,prepared['profile']['revision'],json.dumps(payload),'{}'))
        except Exception as error:
            assert getattr(error,'sqlstate',None)=='23514',str(error)
        else:raise AssertionError('An application definer RPC bypassed the unique CHECK')
        finally:
            conn.execute('ROLLBACK TO SAVEPOINT daily_unique_app_invalid')
            conn.execute('RELEASE SAVEPOINT daily_unique_app_invalid')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT daily_unique_app_runtime')
        conn.execute('RESET SESSION AUTHORIZATION')
        if role!=session:conn.execute('SET ROLE "'+role.replace('"','""')+'"')
        conn.execute('RELEASE SAVEPOINT daily_unique_app_runtime')
    assert conn.execute('SELECT session_user,current_user').fetchone()==(session,role)
    return ['actual_app_session_real_client_ready_passes_startup_runtime_and_rpc_permission_checks',
            'app_has_no_direct_internal_checker_execute_permission',
            'security_definer_archive_rpc_saves_zero_one_and_rejects_two']


def run_checks(conn,bundle,ddl=None):
    from archive_backend.daily_unique import backup_ddl,plans,repair,rollback,render_constraint_sql
    conn.execute('SAVEPOINT daily_unique_checks')
    checks=[]
    account=hashlib.sha256(('daily-unique-synthetic:'+str(uuid.uuid4())).encode()).hexdigest()
    try:
        conn.execute('ALTER TABLE public.player_archive_state DROP CONSTRAINT IF EXISTS archive_unique_points_20261019_check')
        conn.execute(backup_ddl())
        conn.execute('INSERT INTO public.survival_players(account_id) VALUES(%s)',(account,))
        conn.execute('INSERT INTO public.player_gameplay_stats(player_id,hero_attack_per_second,initial_wood) VALUES(%s,10,29)',(account,))
        before={'daily_rewards':{'first_day':20000,'claimed':{'20000':True},'count':1,
            'item_counts':{'daily_growth_gem':3,'daily_wood_gem':3}},
            'keep':{'unchanged':True},'commerce':{'balances':{'shop_points':100,'u_coin':7}}}
        inventory={'unrelated_stackable':999999,'material_synthesis_gem':123}
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s::jsonb,%s::jsonb)',
                     (account,json.dumps(before),json.dumps(inventory)))
        before_stats=conn.execute("SELECT to_jsonb(s)-'player_id'-'created_at'-'updated_at' FROM public.player_gameplay_stats s WHERE player_id=%s",(account,)).fetchone()[0]
        candidates,digest=plans(conn,bundle,[account])
        assert len(candidates)==1 and candidates[0]['converted_points']==100
        result=repair(conn,bundle,digest,[account]);run=result['run_id']
        assert result['converted_points']==100 and result['changed_accounts']==1
        saved=conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()
        assert saved[0]['daily_rewards']['item_counts']=={'daily_growth_gem':1,'daily_wood_gem':1}
        assert saved[0]['commerce']['balances']=={'shop_points':200,'u_coin':7}
        assert saved[0]['daily_rewards']['claimed']==before['daily_rewards']['claimed']
        assert saved[1]==inventory
        stats=conn.execute("SELECT to_jsonb(s)-'player_id'-'created_at'-'updated_at' FROM public.player_gameplay_stats s WHERE player_id=%s",(account,)).fetchone()[0]
        expected=dict(before_stats,hero_attack_per_second=8,initial_wood=23)
        assert stats==expected,'Only excess daily effects can be removed; other contributions remain'
        backup=conn.execute('SELECT before_archive,before_stats,inventory FROM public.archive_daily_unique_backups WHERE run_id=%s AND account_id=%s',(run,account)).fetchone()
        assert backup==(before,before_stats,inventory)
        checks.append('exact_deduction_compensation_and_atomic_complete_backup')
        second,digest=plans(conn,bundle,[account]);assert second==[]
        assert repair(conn,bundle,digest,[account])['changed_accounts']==0
        checks.append('repair_replay_never_subtracts_or_credits_again')
        conn.execute(ddl or render_constraint_sql(bundle))
        assert conn.execute("SELECT convalidated FROM pg_constraint WHERE conrelid='public.player_archive_state'::regclass AND conname='archive_unique_points_20261019_check'").fetchone()==(True,)
        checks.append('constraint_validated_after_repair')
        checks.extend(runtime_checks(conn,bundle,account,saved[0]))

        def rejected(archive=None,contents=None):
            conn.execute('SAVEPOINT daily_unique_rejected_write')
            try:
                conn.execute('UPDATE public.player_archive_state SET archive=%s::jsonb,content_inventory=%s::jsonb WHERE account_id=%s',
                             (json.dumps(saved[0] if archive is None else archive),json.dumps(inventory if contents is None else contents),account))
            except Exception as error:
                assert getattr(error,'sqlstate',None)=='23514',str(error)
            else:
                raise AssertionError('The database accepted non-unique ownership')
            finally:
                conn.execute('ROLLBACK TO SAVEPOINT daily_unique_rejected_write')
                conn.execute('RELEASE SAVEPOINT daily_unique_rejected_write')

        ids=[row['item_id'] for row in bundle.configs['archive_daily_items']['rows'] if row.get('enabled') is not False]
        for invalid in (2,'broken',True,None,[],{}):
            if invalid!={}:rejected({'daily_rewards':invalid})
        for invalid in (None,[],2,'broken',True):
            rejected({'daily_rewards':{'item_counts':invalid}})
        checks.append('malformed_daily_container_or_item_counts_cannot_bypass_check')
        for identity in ids:
            rejected(contents={**inventory,identity:1})
            for invalid in (2,-1,1.5,'1',True,None,{},[]):
                rejected({'daily_rewards':{'item_counts':{identity:invalid}}})
            for valid in (0,1):
                assert conn.execute('SELECT public.archive_unique_points_20261019_valid(%s::jsonb,%s::jsonb)',
                    (json.dumps({'daily_rewards':{'item_counts':{identity:valid}}}),json.dumps(inventory))).fetchone()==(True,)
                conn.execute('SAVEPOINT daily_unique_allowed_write')
                conn.execute('UPDATE public.player_archive_state SET archive=%s::jsonb WHERE account_id=%s',
                    (json.dumps({'daily_rewards':{'item_counts':{identity:valid}}}),account))
                conn.execute('ROLLBACK TO SAVEPOINT daily_unique_allowed_write')
                conn.execute('RELEASE SAVEPOINT daily_unique_allowed_write')
        checks.append('all_12_daily_ids_reject_two_malformed_values_and_second_inventory_allow_canonical_zero_one')
        for row in bundle.configs['lottery_item_definitions']['rows']:
            if (row.get('enabled') is False or row.get('item_type')!='积分道具'
                    or row.get('item_id')=='lottery_ember_of_legacy'):continue
            rejected(contents={**inventory,row['item_id']:2})
        rejected(contents={'lottery_nature_crystal':1,'lottery_flame_crystal':1})
        rejected(contents={'lottery_bombardment_crystal':1,'lottery_burst_crystal':1})
        for contents in ({},inventory,{'lottery_nature_crystal':0,'lottery_flame_crystal':1},
                         {'lottery_nature_crystal':1,'lottery_flame_crystal':0},
                         {'lottery_ember_of_legacy':1600,'welfare_zongzi':150}):
            assert conn.execute('SELECT public.archive_unique_points_20261019_valid(%s::jsonb,%s::jsonb)',
                                ('{}',json.dumps(contents))).fetchone()==(True,)
        checks.append('all_96_unique_lottery_ids_and_alias_aggregate_checked_ember_stacks_preserved')
        # An update that changes only the allowed inventory still passes the
        # actual table CHECK, not merely a direct call of the predicate.
        conn.execute('UPDATE public.player_archive_state SET content_inventory=%s::jsonb WHERE account_id=%s',(json.dumps(inventory),account))
        conn.execute('ALTER TABLE public.player_archive_state DROP CONSTRAINT archive_unique_points_20261019_check')
        assert rollback(conn,run)['rolled_back_accounts']==1
        restored=conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s',(account,)).fetchone()
        restored_stats=conn.execute("SELECT to_jsonb(s)-'player_id'-'created_at'-'updated_at' FROM public.player_gameplay_stats s WHERE player_id=%s",(account,)).fetchone()[0]
        assert restored==(before,inventory) and restored_stats==before_stats
        assert rollback(conn,run)['rolled_back_accounts']==0
        checks.append('guarded_rollback_restores_counts_wallet_and_exact_stats_once')
        _,digest=plans(conn,bundle,[account]);again=repair(conn,bundle,digest,[account])
        conn.execute('UPDATE public.player_gameplay_stats SET initial_gold=initial_gold+1 WHERE player_id=%s',(account,))
        try:rollback(conn,again['run_id'])
        except ValueError as error:assert str(error)=='daily_unique_rollback_refused_account_changed'
        else:raise AssertionError('Rollback overwrote a newer player change')
        checks.append('rollback_refuses_to_overwrite_later_stat_changes')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT daily_unique_checks')
        conn.execute('RELEASE SAVEPOINT daily_unique_checks')
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone()
    checks.append('all_synthetic_rows_backups_and_ddl_rolled_back')
    return {'ok':True,'checks':checks,'groups':len(checks),'synthetic_players':1,
            'durable_player_changes':0,'real_payments':0}
