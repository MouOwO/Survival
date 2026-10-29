"""Real PG17 RPC -> candidate Python -> Lua -> durable receipt; rollback only.

The caller supplies an owner-controlled isolated-clone connection. No new
connection, external HTTP call, commit, account data or credential output.
"""
from __future__ import annotations
import copy, hashlib, importlib, json, shutil, sys, uuid
from pathlib import Path
from types import SimpleNamespace

def run(conn,release):
    from psycopg import sql
    from psycopg.types.json import Jsonb
    release=Path(release)
    sys.path.insert(0,str(release/'backend'))
    for name in list(sys.modules):
        if name in ('archive_backend','fishing_api') or name.startswith(('archive_backend.','fishing_api.')):
            del sys.modules[name]
    from archive_backend.bundle import Bundle
    from archive_backend.service import ArchiveService
    from fishing_api.postgres import RPC_SIGNATURES
    for name in ('archive_backend.service','fishing_api.postgres'):
        if not Path(sys.modules[name].__file__).resolve().is_relative_to((release/'backend').resolve()):
            raise AssertionError('archive_runtime_candidate_import_mismatch')
    bundle=Bundle(release/'addon/server/bundles'/json.loads((release/'addon/server/bundles/current.json').read_bytes())['hash'])
    nonce=uuid.uuid4().hex
    account=hashlib.sha256(('archive-release-synthetic:'+nonce).encode()).hexdigest()
    session='survival_release_'+nonce
    checks=[]
    def need(value,label):
        if not value:raise AssertionError('archive_runtime_'+label)
        checks.append(label)
    class RPC:
        lose=False
        calls=[]
        def rpc(self,name,params):
            allowed=set(RPC_SIGNATURES)
            need(name in allowed,'rpc_allowlisted')
            self.calls.append(name)
            fields=list(params)
            statement=sql.SQL('SELECT public.{}({})').format(sql.Identifier(name),
                sql.SQL(',').join(sql.SQL('{}=>%s').format(sql.Identifier(field)) for field in fields))
            values=[Jsonb(params[field]) if isinstance(params[field],(dict,list)) else params[field] for field in fields]
            result=conn.execute(statement,values).fetchone()[0]
            if name=='archive_commit_challenge' and self.lose:
                self.lose=False
                raise TimeoutError('synthetic_lost_ack_after_atomic_statement')
            return result
    rpc=RPC()
    defaults={row['field_id']:row['default_value'] for row in bundle.configs['player_gameplay_stats']['rows']}
    conn.execute('SAVEPOINT archive_release_synthetic')
    try:
        rpc.rpc('ensure_player_gameplay_stats',dict(p_account_id=account,p_gameplay_stats=defaults))
        conn.execute('INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,%s,%s) ON CONFLICT(account_id) DO UPDATE SET archive=excluded.archive,content_inventory=excluded.content_inventory',
            (account,Jsonb({'standard_clear_counts':{'n3':1,'n5':1}}),Jsonb({'unrelated_material':37})))
        context=rpc.rpc('match_profile_login',dict(p_account=account,p_session=session,p_mode='cold',p_defaults=defaults))
        need(context.get('ok') is True and context['mode']=='cold','trusted_cold_session')
        denied=rpc.rpc('match_profile_login',dict(p_account=account,p_session=session+'_locked',p_mode='scourge',p_defaults=defaults))
        need(denied.get('error')=='mode_not_released','unreleased_mode_stays_closed')
        app=SimpleNamespace(rpc_client=rpc,account_id_pepper='isolated-probe-only',
            _database_account_id=lambda _:account,_ensure_gameplay_stats=lambda _:None,
            _public_response=lambda value,*_:copy.deepcopy(value))
        service=ArchiveService(app,bundle,shutil.which('lua5.1') or shutil.which('lua'))
        def request(identity,challenge):
            return dict(account_id='100',match_session_id=session,config_hash=bundle.hash,
                command=dict(id='archiveRuntimeA:challenge_kind:'+identity,kind='challenge',
                    challenge_id=challenge,difficulty_id='n30',kill_sequence=1))
        payload=request('football','football');rpc.lose=True
        try: service.command(payload)
        except TimeoutError: checks.append('lost_ack_exercised')
        else: raise AssertionError('archive_runtime_lost_ack_not_exercised')
        granted=conn.execute('SELECT to_jsonb(a),to_jsonb(g),p.profile_revision FROM public.player_archive_state a JOIN public.survival_players p USING(account_id) JOIN public.player_gameplay_stats g ON g.player_id=a.account_id WHERE a.account_id=%s',(account,)).fetchone()
        first=service.command(payload)
        need(first['ok'] and first['done'] and first['response']['awarded']==10,'lost_ack_exact_reward')
        need(sum(row['count'] for row in first['response']['rewards'])==10,'real_reward_detail_sum')
        repeated=service.command(payload)
        after=conn.execute('SELECT to_jsonb(a),to_jsonb(g),p.profile_revision FROM public.player_archive_state a JOIN public.survival_players p USING(account_id) JOIN public.player_gameplay_stats g ON g.player_id=a.account_id WHERE a.account_id=%s',(account,)).fetchone()
        need(after==granted and repeated['response']==first['response'],'replay_no_double_grant')
        need(granted[0]['content_inventory']=={'unrelated_material':37},'inventory_unchanged')
        skipped=service.command(request('social_wife','social_wife'))
        need(skipped['ok'] and skipped['response']['awarded']==0 and skipped['response'].get('skipped_reason'),'recipient_eligibility_preserved')
        tower=dict(account_id='100',match_session_id=session,config_hash=bundle.hash,
            command=dict(id='archiveRuntimeA:tower:15',kind='endless',wave=15,difficulty=30,variant='tower'))
        result=service.command(tower)
        need(result['ok'] and result['done'],'tower_high_n_real_worker')
        need(result['profile']['save']['archive']['tower_best_wave']==15,'tower_progress_saved')
        # A response-write exception after inner archive_commit must roll back
        # stats, archive, revision and done. Use a nested PostgreSQL savepoint.
        failure=request('hunt_01','hunt_01');operation=session+':challenge_kind:hunt_01'
        conn.execute("CREATE FUNCTION public.archive_release_probe_response_failure() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public,pg_temp AS $$ BEGIN IF NEW.operation_id=TG_ARGV[0] THEN RAISE EXCEPTION 'archive_release_injected_response_failure'; END IF; RETURN NEW; END $$")
        conn.execute(sql.SQL('CREATE TRIGGER archive_release_probe_response_failure BEFORE UPDATE OF response ON public.archive_operations FOR EACH ROW EXECUTE FUNCTION public.archive_release_probe_response_failure({})').format(sql.Literal(operation)))
        snapshot=conn.execute('SELECT to_jsonb(a),to_jsonb(g),p.profile_revision FROM public.player_archive_state a JOIN public.survival_players p USING(account_id) JOIN public.player_gameplay_stats g ON g.player_id=a.account_id WHERE a.account_id=%s',(account,)).fetchone()
        try:
            with conn.transaction(): service.command(failure)
        except Exception as error:
            need(getattr(error,'sqlstate',None)=='P0001','response_failure_injected')
        else: raise AssertionError('archive_runtime_response_failure_not_exercised')
        need(conn.execute('SELECT to_jsonb(a),to_jsonb(g),p.profile_revision FROM public.player_archive_state a JOIN public.survival_players p USING(account_id) JOIN public.player_gameplay_stats g ON g.player_id=a.account_id WHERE a.account_id=%s',(account,)).fetchone()==snapshot,'response_failure_whole_grant_rolled_back')
        conn.execute('DROP TRIGGER archive_release_probe_response_failure ON public.archive_operations')
        conn.execute('DROP FUNCTION public.archive_release_probe_response_failure()')
        # Explicit runtime metadata verifies the dedicated signature's grants.
        signature='public.archive_commit_challenge(text,text,bigint,jsonb,jsonb,text,jsonb)'
        need(conn.execute("SELECT has_function_privilege('goufayu_app',%s,'EXECUTE') AND NOT has_function_privilege('anon',%s,'EXECUTE') AND NOT has_table_privilege('goufayu_app','public.player_archive_state','SELECT,INSERT,UPDATE,DELETE')",(signature,signature)).fetchone()[0],'rpc_least_privilege')
    finally:
        conn.execute('ROLLBACK TO SAVEPOINT archive_release_synthetic')
        conn.execute('RELEASE SAVEPOINT archive_release_synthetic')
    need(not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id=%s',(account,)).fetchone(),'synthetic_account_rolled_back')
    return dict(ok=True,checks=sorted(set(checks)),synthetic_accounts_retained=0,original_player_updates=0)
