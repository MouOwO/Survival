"""Bounded mature-v1 seed for a new attested synthetic lab, never production.

Preparation imports no runtime/DB modules. Metadata uses fixed100-element
periods, not an account scan. Seed once: bounded chunks with per-account PK probes;
real Lua archetypes supply stats/inventory, real startup sync and native grant
functions supply definitions/effects/complete reward receipts. No request hook.
"""
from __future__ import annotations
import hashlib,hmac,importlib,json,math,re,shutil,time
from contextlib import contextmanager
from pathlib import Path
from .guard import canonical,marker_guard,account,database_account
SEED=13112026;MAX_ROWS=1000000;MAX_BYTES=3000000000;CHUNK=1000
SCHEMA_SHA='600eb5d3fa430e57a369e0ed4724e29f279fd268d47b36dcd938f4ecec007f57'
ARCHETYPE_TARGET='operator/fixtures/mature_v1_archetypes.json'
ARCHETYPE_SHA='ce03ad209b7c5c20b4de05752c329a0691ff35734544153b22bae7d4b001e8bc'
BUNDLE_SHA='d38866d1be2dec7b3b8c27ddd1315bab9cb27a1c7e0a136b670e5e9df12e3ed1'
PROTECTED=('payments.orders','payments.cleared_reward_grants','payments.vip_recharge_credits','payments.test_resets','public.redemption_claims','public.redemption_attempts')
NEW_EMPTY=('public.player_gameplay_stats','public.player_effect_totals','public.reward_grants','public.out_of_match_reward_idempotency','public.fishing_daily_limit_receipts','public.online_time_sessions','public.online_time_idempotency','public.archive_online_outbox','public.archive_operations','public.match_profile_sessions')
def need(ok,code):
 if not ok:raise ValueError(code)
def _sha(raw):return hashlib.sha256(raw).hexdigest()
def cohort(account_ordinal):
 v=(account_ordinal*37+SEED)%100
 return 0 if v<28 else 1 if v<78 else 2 if v<98 else 3
def _period(n,values):
 q,r=divmod(n,len(values));return q*sum(values)+sum(values[:r])
def counts(accounts,active):
 need(type(accounts)is int and type(active)is int and 1<=active<=min(accounts,4000)and accounts<=100000,'mature_account_budget_invalid')
 pattern=tuple(cohort(i)for i in range(100));hist=tuple((0,0,1,8)[v]for v in pattern);positive=tuple(int(v>0)for v in hist)
 dense=(accounts-1)//997+1;dense_hist=tuple(hist[(997*i)%100]for i in range(100));dense_pos=tuple(positive[(997*i)%100]for i in range(100));history=_period(accounts,hist)-_period(dense,dense_hist)+512*dense;history_accounts=_period(accounts,positive)-_period(dense,dense_pos)+dense
 persistent=5*accounts+10*active+3*history+1000;peak=persistent+accounts+history_accounts+17
 need(peak<=MAX_ROWS,'mature_total_row_admission_exceeded')
 return {'accounts':accounts,'active':active,'cohort_counts':[_period(accounts,tuple(int(v==c)for v in pattern))for c in range(4)],'dense_accounts':dense,'completed_history_each_table':history,'temporary_online_session_accounts':history_accounts,'base_existing_five_tables_rows':4*accounts+active,'new_gameplay_stats_rows':accounts,'new_reward_grants':4*active,'new_reward_idempotency':4*active,'new_effect_totals':active,'persistent_row_ceiling':persistent,'peak_including_temporary_rows_ceiling':peak,'temporary_mapping_rows':accounts,'temporary_template_context_rows':17}
def _reviewed_schema(cfg):
 from .database_experiments import metadata_schema_parent_sources
 parent=metadata_schema_parent_sources(cfg)
 return parent.get('database/10_schema.sql',cfg.get('sources',{}).get('database/10_schema.sql'))

def build_fixture_profile(cfg):
 need(type(cfg)is dict and cfg.get('schema')==1 and cfg.get('kind')=='SURVIVAL_ISOLATED_LOADTEST'and cfg.get('purpose')in('capacity','functional-smoke')and cfg.get('backend_db_pool')=='bounded-v2'and _reviewed_schema(cfg)==SCHEMA_SHA,'mature_isolated_reviewed_schema_required')
 return {'id':'mature-v1','seed':SEED,'archetype_source':ARCHETYPE_TARGET,'archetype_sha256':ARCHETYPE_SHA,'schema_sha256':SCHEMA_SHA,'chunk_rows':CHUNK,'max_rows':MAX_ROWS,'max_database_bytes':MAX_BYTES,'counts':counts(cfg.get('accounts'),cfg.get('active'))}
def validate_fixture_profile(cfg,read_source=None):
 if 'mature_fixture'not in cfg:return None
 need(type(cfg['mature_fixture'])is dict and canonical(cfg['mature_fixture'])==canonical(build_fixture_profile(cfg)),'mature_fixture_metadata_changed');need(cfg['sources'].get(ARCHETYPE_TARGET)==ARCHETYPE_SHA,'mature_archetype_binding_missing')
 if read_source is None:return dict(cfg['mature_fixture'])
 raw=read_source(ARCHETYPE_TARGET);need(type(raw)is bytes and len(raw)<=256*1024 and _sha(raw)==ARCHETYPE_SHA,'mature_archetypes_source_changed');v=json.loads(raw)
 need(v.get('id')=='mature-v1'and v.get('cohort_seed')==SEED and v.get('schema_sha256')==SCHEMA_SHA and v.get('bundle_sha256')==BUNDLE_SHA and type(v.get('rows'))is list and len(v['rows'])==16,'mature_archetypes_shape_invalid')
 need({(r['cohort'],r['active'],r['dense'])for r in v['rows']}=={(c,a,d)for c in range(4)for a in(False,True)for d in(False,True)},'mature_archetypes_keys_invalid')
 source_map=v['source_sha256'];need(type(source_map)is dict and len(source_map)==66 and sum(name.startswith('runtime/')for name in source_map)==30 and sum(name.startswith('addon/server/bundles/')for name in source_map)==36,'mature_archetype_sources_shape_invalid')
 for name,digest in source_map.items():
  need(type(name)is str and (name.startswith('runtime/')or name.startswith('addon/server/bundles/'))and cfg['sources'].get(name)==digest,'mature_archetype_source_binding_changed')
  actual=read_source(name);need(type(actual)is bytes and len(actual)<=4*1024*1024 and _sha(actual)==digest,'mature_archetype_source_bytes_changed')
 return v

def actual_row_admission(before,budget):
 need(type(before)is dict and len(before)<=100 and all(type(v)is int and v>=0 for v in before.values()),'mature_initial_table_counts_invalid')
 existing=sum(before.values());new=budget['accounts']+3*budget['completed_history_each_table']+9*budget['active']+128
 temporary=budget['accounts']+17+budget['temporary_online_session_accounts'];persistent=existing+new;peak=persistent+temporary
 need(peak<=MAX_ROWS,'mature_rows_pre_admission_failed')
 return {'actual_initial_rows':existing,'new_persistent_row_reserve':new,'temporary_row_reserve':temporary,'persistent_row_ceiling':persistent,'peak_row_ceiling':peak}

class _SeedBudget:
 """One finite admin seed only; no request path. Each SQL has remaining budget."""
 def __init__(self,raw,deadline):self.raw=raw;self.deadline=deadline
 def remaining(self):
  milliseconds=math.floor((self.deadline-time.monotonic())*1000);need(milliseconds>=1,'mature_seed_deadline');return min(milliseconds,30000)
 def arm(self):
  ms=self.remaining();self.raw.execute("SELECT pg_catalog.set_config('statement_timeout',%s,true)",(str(ms),));self.remaining()
 def execute(self,*args,**kwargs):
  self.arm();value=self.raw.execute(*args,**kwargs);self.remaining();return value
 def commit(self):
  self.arm();self.raw.commit();self.remaining()
 def rollback(self):self.raw.rollback()
 @contextmanager
 def transaction(self):
  self.remaining()
  with self.raw.transaction():
   self.arm();yield self;self.arm()
  self.remaining()
 def cursor(self):return _SeedCopyCursor(self)

class _SeedCopyCursor:
 def __init__(self,budget):self.budget=budget
 @contextmanager
 def copy(self,query):
  self.budget.arm()
  with self.budget.raw.cursor()as cur:
   with cur.copy(query)as copy:
    owner=self.budget
    class Copy:
     def write_row(self,row):owner.remaining();copy.write_row(row);owner.remaining()
    yield Copy();owner.remaining()
  self.budget.remaining()

STATS_SQL=r"""DO $mature$
DECLARE c record;m record;t record;
BEGIN
 SELECT * INTO c FROM pg_temp.mature_context;
 FOR m IN SELECT * FROM pg_temp.mature_accounts WHERE account_ordinal>=c.first_index AND account_ordinal<c.last_index ORDER BY account_ordinal LOOP
  SELECT * INTO STRICT t FROM pg_temp.mature_templates WHERE cohort=m.cohort AND active=m.active AND dense=m.dense;
  INSERT INTO public.player_gameplay_stats(player_id,__COLUMNS__) SELECT m.account_id,__VALUES__ FROM jsonb_populate_record(NULL::public.player_gameplay_stats,t.stats)r;
  UPDATE public.player_archive_state a SET archive=t.archive,content_inventory=t.inventory||(CASE WHEN m.active THEN jsonb_build_object('lottery_ticket',greatest(coalesce((a.content_inventory->>'lottery_ticket')::bigint,0),coalesce((t.inventory->>'lottery_ticket')::bigint,0))) ELSE '{}'::jsonb END) WHERE a.account_id=m.account_id;
  UPDATE public.survival_players p SET profile_revision=t.revision,created_at=least(p.created_at,to_timestamp(c.anchor)-make_interval(days=>CASE m.cohort WHEN 0 THEN 0 WHEN 1 THEN 7 WHEN 2 THEN 30 ELSE 90 END)) WHERE p.account_id=m.account_id;
  UPDATE public.archive_entitlements e SET starts_at=least(e.starts_at,to_timestamp(c.anchor)-interval '1 day') WHERE e.account_id=m.account_id AND m.active;
 END LOOP;
END $mature$"""

def _runtime(root,cfg,name):
 key='runtime/'+name.replace('.','/')+'.py';path=root/key
 need(path.is_file()and not path.is_symlink()and _sha(path.read_bytes())==cfg['sources'].get(key),'mature_runtime_source_changed');m=importlib.import_module(name)
 need(Path(m.__file__).resolve()==path.resolve(),'mature_runtime_import_mismatch');return m

def _tables(conn):
 names=conn.execute("SELECT schemaname,tablename FROM pg_catalog.pg_tables WHERE schemaname IN ('public','payments','loadtest_lab') ORDER BY schemaname,tablename").fetchall();need(len(names)<=100,'mature_table_budget_exceeded');result={}
 for schema,name in names:
  need(schema in('public','payments','loadtest_lab')and re.fullmatch('[a-z_][a-z0-9_]{0,62}',name),'mature_table_name_invalid');result[schema+'.'+name]=conn.execute('SELECT count(*) FROM "'+schema+'"."'+name+'"').fetchone()[0]
 return result

def _check_resources(root,conn,deadline):
 need(time.monotonic()<deadline,'mature_seed_deadline');size=conn.execute('SELECT pg_database_size(current_database())').fetchone()[0]
 need(type(size)is int and size<=MAX_BYTES,'mature_database_byte_admission_exceeded');need(shutil.disk_usage(root).free>=12000000000,'mature_host_free_space_insufficient');return size

def _startup_sync(root,cfg,conn):
 from psycopg.types.json import Jsonb
 definitions=_runtime(root,cfg,'fishing_api.definitions');gameplay=_runtime(root,cfg,'fishing_api.gameplay_stats');application=_runtime(root,cfg,'fishing_api.application');bundle_mod=_runtime(root,cfg,'archive_backend.bundle');service=_runtime(root,cfg,'archive_backend.service')
 defs=definitions.load_definitions(root/'addon/data/csv/玩家档案系统/star_blessing_reward_definitions.csv',allow_decimal_values=True);defaults=gameplay.load_gameplay_stats(root/'addon/data/csv/玩家档案系统/player_gameplay_stats.csv');bundle=bundle_mod.Bundle(root/'addon/server/bundles'/BUNDLE_SHA)
 gift=next((x for x in defs.rows if x['reward_id']=='star_blessing_005'),None);need(gift is not None and gift['effect_scope']=='permanent'and gift['effect_key']=='hero_all_attributes_flat'and gift['stacking_rule']=='add'and gift['cap_value']==0 and gift['value_min']==gift['value_max']==500,'mature_fixed_reward_definition_changed')
 class FixedSeedRPC:
  def __init__(self):self.calls=[]
  def rpc(self,name,p):
   self.calls.append(name)
   if name=='sync_star_blessing_reward_definitions':
    need(set(p)=={'p_definition_version','p_definition_hash','p_definitions'},'mature_definition_sync_contract_changed');return conn.execute('SELECT public.sync_star_blessing_reward_definitions(%s,%s,%s)',(p['p_definition_version'],p['p_definition_hash'],Jsonb(p['p_definitions']))).fetchone()[0]
   if name=='archive_sync_config':
    need(set(p)=={'p_hash','p_config'}and p['p_hash']==BUNDLE_SHA,'mature_archive_sync_contract_changed');return conn.execute('SELECT public.archive_sync_config(%s,%s)',(p['p_hash'],Jsonb(p['p_config']))).fetchone()[0]
   raise ValueError('mature_unreviewed_seed_RPC')
 rpc=FixedSeedRPC();app=type('SeedStartup',(),{'definitions':defs,'rpc_client':rpc})();application.FishingApplication.sync_definitions(app);service.ArchiveService(app,bundle,'not_used_for_SQL_seed').sync();need(rpc.calls==['sync_star_blessing_reward_definitions','archive_sync_config'],'mature_startup_sync_calls_changed');return defaults,defs

HISTORY_SQL=r"""DO $mature$
DECLARE c record;m record;j integer;stamp timestamptz;req text;day bigint;
BEGIN
 SELECT * INTO c FROM pg_temp.mature_context;
 FOR m IN SELECT * FROM pg_temp.mature_accounts WHERE account_ordinal>=c.first_index AND account_ordinal<c.last_index AND history>0 ORDER BY account_ordinal LOOP
  INSERT INTO public.online_time_sessions(account_id,session_id,last_checkpoint_at)
   VALUES(m.account_id,'mature_history:'||c.run_prefix||':'||m.account_ordinal,to_timestamp(c.anchor-m.history));
  FOR j IN 1..m.history LOOP
   stamp:=to_timestamp(c.anchor-m.history+j);day:=floor((extract(epoch from stamp)+10800)/86400)::bigint;
   UPDATE public.online_time_sessions SET last_checkpoint_at=stamp WHERE account_id=m.account_id;
   req:='lt_mature_'||c.run_prefix||'_'||m.account_ordinal||'_'||j;
   INSERT INTO public.online_time_idempotency(request_id,account_id,response,created_at)
   VALUES(req,m.account_id,jsonb_build_object('ok',true,'elapsed_seconds',1,
    'online_seconds_total',(CASE WHEN m.active THEN 2400 ELSE 0 END)+j,'grants','[]'::jsonb,
    'daily_limits',jsonb_build_object('day_key',day::text,'by_key',jsonb_build_object('fishing',
     jsonb_build_object('key','fishing','name','每日钓鱼','earned',0,'limit',80,'remaining',80,'capped',0,'implemented',1)))),stamp);
  END LOOP;
 INSERT INTO public.archive_operations(account_id,operation_id,config_hash,fingerprint,command,event_at,has_pass,done,error,response)
 SELECT x.account_id,'online:'||x.request_id,c.bundle_hash,'online:'||x.request_id,
  jsonb_build_object('id','online:'||x.request_id,'kind','online_checkpoint','session','online:'||x.request_id,
   'actual_seconds',x.elapsed,'map_seconds',x.weighted,'day_key',floor((extract(epoch from x.created_at)+10800)/86400)::bigint::text,
   'today',floor((extract(epoch from x.created_at)+10800)/86400)::bigint),x.created_at,false,true,NULL,NULL
 FROM public.archive_online_outbox x WHERE x.account_id=m.account_id;
 DELETE FROM public.online_time_sessions s WHERE s.account_id=m.account_id;
 END LOOP;
END $mature$"""
GIFT_SQL=r"""DO $mature$
DECLARE c record;m record;j integer;
BEGIN
 SELECT * INTO c FROM pg_temp.mature_context;
 FOR m IN SELECT * FROM pg_temp.mature_accounts WHERE account_ordinal>=c.first_index AND account_ordinal<c.last_index AND active ORDER BY account_ordinal LOOP
  FOR j IN 1..4 LOOP
   PERFORM public.grant_out_of_match_reward(m.account_id,md5(m.account_id||':star:v'||c.definition_version||':'||j)::uuid,
    'star_blessing_005',c.definition_version,500);
  END LOOP;
 END LOOP;
END $mature$"""

def seed_mature_fixture(root,cfg,private,conn):
 """Call inside ordinary seed, before its single ANALYZE and seeded=true.

 Baseline registration/archive/pass rows must already exist, all other account
 data must be empty. One own marker survives failure, so this is never resumed
 into the same lab. A/B use the same frozen archetype artifact and cohort seed.
 """
 deadline=time.monotonic()+900;raw_conn=conn;conn=_SeedBudget(raw_conn,deadline);root=Path(root).resolve();profile=validate_fixture_profile(cfg,lambda name:(root/name).read_bytes());need(profile is not None,'mature_mode_required');budget=build_fixture_profile(cfg)['counts']
 marker_guard(conn,cfg,private);need(conn.execute('SELECT seeded FROM loadtest_lab.marker WHERE singleton').fetchone()==(False,),'mature_seed_requires_unseeded_marker');need(conn.execute('SELECT session_user,current_user').fetchone()==('postgres','postgres'),'mature_seed_admin_only')
 need(conn.execute("SELECT to_regclass('loadtest_lab.mature_seed')").fetchone()==(None,),'mature_seed_once_required');before=_tables(conn)
 need(before.get('public.survival_players')==cfg['accounts'] and before.get('public.player_archive_state')==cfg['accounts']and before.get('public.archive_leaderboard_identities')==cfg['accounts']and before.get('public.player_onboarding_state')==cfg['accounts']and before.get('public.archive_entitlements')==cfg['active'],'mature_base_seed_counts_changed')
 need(all(before.get(name)==0 for name in (*NEW_EMPTY,*PROTECTED)),'mature_nonempty_or_transaction_data_present');need(conn.execute('SELECT coalesce(max(profile_revision),0) FROM public.survival_players').fetchone()==(0,),'mature_existing_player_progress')
 actual_admission=actual_row_admission(before,budget);additional=actual_admission['new_persistent_row_reserve'];initial_bytes=_check_resources(root,conn,deadline)
 max_row=max(len(canonical(row))for row in profile['rows']);snapshots=sum(budget['cohort_counts'][i]*max(len(canonical(r['archive']))+len(canonical(r['inventory']))for r in profile['rows']if r['cohort']==i)for i in range(4));conservative_growth=cfg['accounts']*(256*32+512)+3*snapshots+4*cfg['active']*(3*(max_row+4096)+2048)+budget['completed_history_each_table']*4096+additional*256
 need(initial_bytes+conservative_growth<=MAX_BYTES,'mature_bytes_pre_admission_failed');conn.commit();need(conn.execute('SELECT pg_try_advisory_lock(124710,1)').fetchone()==(True,),'mature_seed_lock_unavailable');conn.commit();created=False;result=None
 try:
  from psycopg.types.json import Jsonb
  conn.execute("CREATE TABLE loadtest_lab.mature_seed(singleton boolean PRIMARY KEY CHECK(singleton),run_id text NOT NULL,manifest_sha256 text NOT NULL,profile jsonb NOT NULL,status text NOT NULL,receipt jsonb,started_at timestamptz DEFAULT clock_timestamp(),completed_at timestamptz)")
  conn.execute('INSERT INTO loadtest_lab.mature_seed(singleton,run_id,manifest_sha256,profile,status)VALUES(true,%s,%s,%s,\'started\')',(cfg['run_id'],_sha(canonical(cfg)),Jsonb(cfg['mature_fixture'])));conn.commit();created=True
  defaults,defs=_startup_sync(root,cfg,conn);keys=sorted(defaults);need(len(keys)<=256 and all(re.fullmatch('[a-z][a-z0-9_]{0,62}',key)and key not in('player_id','created_at','updated_at')for key in keys),'mature_gameplay_identifiers_invalid');need(all(set(row['stats'])==set(keys)for row in profile['rows']),'mature_archetypes_defaults_mismatch');conn.commit()
  conn.execute('CREATE TEMP TABLE mature_accounts(account_ordinal bigint PRIMARY KEY,account_id text UNIQUE,cohort int,active boolean,dense boolean,history int) ON COMMIT PRESERVE ROWS');conn.execute('CREATE TEMP TABLE mature_templates(cohort int,active boolean,dense boolean,archive jsonb,inventory jsonb,stats jsonb,revision bigint,PRIMARY KEY(cohort,active,dense)) ON COMMIT PRESERVE ROWS');conn.execute('CREATE TEMP TABLE mature_context(first_index bigint,last_index bigint,anchor bigint,bundle_hash text,run_prefix text,definition_version int) ON COMMIT PRESERVE ROWS')
  conn.execute('INSERT INTO mature_context VALUES(0,0,%s,%s,%s,%s)',(profile['fixed_archetype_clock_seconds'],BUNDLE_SHA,cfg['run_id'][:16],defs.version))
  with conn.cursor().copy('COPY mature_templates(cohort,active,dense,archive,inventory,stats,revision) FROM STDIN')as copy:
   for row in profile['rows']:copy.write_row((row['cohort'],row['active'],row['dense'],json.dumps(row['archive']),json.dumps(row['inventory']),json.dumps(row['stats']),row['profile_revision_before_star']))
  conn.commit()
  for first in range(0,cfg['accounts'],CHUNK):
   with conn.transaction():
    with conn.cursor().copy('COPY mature_accounts(account_ordinal,account_id,cohort,active,dense,history) FROM STDIN')as copy:
     for i in range(first,min(first+CHUNK,cfg['accounts'])):
      c=cohort(i);dense=i%997==0;copy.write_row((i,database_account(private,account(cfg,i)),c,i<cfg['active'],dense,512 if dense else(0,0,1,8)[c]))
  conn.execute('ANALYZE pg_temp.mature_accounts,pg_temp.mature_templates');conn.commit()
  need(conn.execute('SELECT count(*) FROM mature_accounts').fetchone()==(cfg['accounts'],),'mature_mapping_count_invalid');need(conn.execute('SELECT count(*) FROM public.survival_players p LEFT JOIN mature_accounts m ON m.account_id=p.account_id WHERE m.account_id IS NULL').fetchone()==(0,),'mature_unmapped_players');need(conn.execute('SELECT count(*) FROM mature_accounts m LEFT JOIN public.survival_players p ON p.account_id=m.account_id WHERE p.account_id IS NULL').fetchone()==(0,),'mature_missing_players');need(conn.execute("SELECT count(*) FROM public.archive_entitlements e LEFT JOIN mature_accounts m ON m.account_id=e.account_id WHERE e.entitlement_id<>'archive_pass' OR NOT coalesce(m.active,false)").fetchone()==(0,),'mature_pass_scope_invalid');conn.commit()
  columns=','.join('"'+key+'"'for key in keys);values=','.join('r."'+key+'"'for key in keys);stats_sql=STATS_SQL.replace('__COLUMNS__',columns).replace('__VALUES__',values)
  for first in range(0,cfg['accounts'],CHUNK):
   with conn.transaction():
    conn.execute('UPDATE mature_context SET first_index=%s,last_index=%s',(first,min(first+CHUNK,cfg['accounts'])));conn.execute(stats_sql);_check_resources(root,conn,deadline)
  for first in range(0,cfg['accounts'],500):
   with conn.transaction():
    conn.execute('UPDATE mature_context SET first_index=%s,last_index=%s',(first,min(first+500,cfg['accounts'])));conn.execute(HISTORY_SQL);_check_resources(root,conn,deadline)
  for first in range(0,cfg['active'],100):
   with conn.transaction():
    conn.execute('UPDATE mature_context SET first_index=%s,last_index=%s',(first,min(first+100,cfg['active'])));conn.execute(GIFT_SQL);_check_resources(root,conn,deadline)
  expected={'public.player_gameplay_stats':cfg['accounts'],'public.reward_grants':4*cfg['active'],'public.out_of_match_reward_idempotency':4*cfg['active'],'public.player_effect_totals':cfg['active'],'public.online_time_idempotency':budget['completed_history_each_table'],'public.archive_online_outbox':budget['completed_history_each_table'],'public.archive_operations':budget['completed_history_each_table'],'public.online_time_sessions':0};after=_tables(conn);need(all(after.get(k)==v for k,v in expected.items()),'mature_final_counts_changed');need(sum(after.values())<=MAX_ROWS and all(after.get(name)==before[name]for name in PROTECTED),'mature_final_admission_or_protected_data_changed')
  need(conn.execute("SELECT count(*) FROM public.archive_online_outbox x LEFT JOIN public.archive_operations o ON o.account_id=x.account_id AND o.operation_id='online:'||x.request_id WHERE o.done IS DISTINCT FROM true OR o.error IS NOT NULL").fetchone()==(0,),'mature_unfinished_outbox');need(conn.execute('SELECT count(*) FROM public.reward_grants g LEFT JOIN mature_accounts m ON m.account_id=g.account_id WHERE m.active IS DISTINCT FROM true').fetchone()==(0,),'mature_reward_account_scope_invalid')
  samples=[]
  for c,a,d,identity in conn.execute('SELECT DISTINCT ON(cohort,active,dense)cohort,active,dense,account_id FROM mature_accounts ORDER BY cohort,active,dense,account_ordinal').fetchall():
   value=conn.execute('SELECT public.get_fishing_profile(%s)',(identity,)).fetchone()[0];need(type(value)is dict and value.get('account_id')==identity and value.get('schema_version')==1 and type(value.get('revision'))is int and type(value.get('save'))is dict and set(keys)<=set(value['save'].get('gameplay_stats',{})),'mature_profile_not_readable')
   need((value['save'].get('fishing_inventory',{}).get('star_blessing_005',0)==4)if a else not value['save'].get('fishing_inventory',{}),'mature_profile_grants_mismatch');samples.append({'cohort':c,'active':a,'dense':d,'bytes':len(canonical(value)),'sha256':_sha(canonical(value))})
  size=_check_resources(root,conn,deadline);result={'id':'mature-v1','status':'MATURE_SYNTHETIC_FIXTURE_READY','profile':cfg['mature_fixture'],'actual_table_counts':after,'actual_row_admission':actual_admission,'temporary_tables_analyzed_once':True,'SQL_remaining_deadline_seconds':900,'failure_cleanup_timeout_seconds':5,'actual_database_bytes':size,'conservative_growth_pre_admission_bytes':conservative_growth,'actual_profile_samples':samples,'real_star_grants':4*cfg['active'],'real_startup_sync':True,'outbox_trigger_used':True,'completed_history_rows':budget['completed_history_each_table'],'temporary_mapping_rows':cfg['accounts'],'protected_transaction_tables_unchanged':True,'ANALYZE_executed_here':False,'requires_caller_final_ANALYZE_before_seeded_true':True,'partial_history_semantics':'Controlled partial completed online history with validwriter/triggerformat; snapshotsfromactualLua. Notallpriorlotterydrawoperationsorhistoricmilestonerequestsarecopied; fixture is notproductionbackup/replayparity.','initial_seed_row_byte_admission_only':True,'real_accounts_used':0}
  conn.execute("UPDATE loadtest_lab.mature_seed SET status='complete',receipt=%s,completed_at=clock_timestamp() WHERE singleton",(Jsonb(result),));conn.execute('DROP TABLE mature_accounts,mature_templates,mature_context');conn.commit();return result
 except Exception:
  raw_conn.rollback()
  if created:
   try:
    raw_conn.execute("SET LOCAL statement_timeout='5000'");raw_conn.execute("UPDATE loadtest_lab.mature_seed SET status='failed',completed_at=clock_timestamp() WHERE singleton");raw_conn.commit()
   except Exception:raw_conn.rollback()
  raise
 finally:
  try:
   raw_conn.execute("SET LOCAL statement_timeout='5000'");raw_conn.execute('SELECT pg_advisory_unlock(124710,1)');raw_conn.commit()
  except Exception:
   raw_conn.rollback()
   if result is not None:raise ValueError('mature_seed_unlock_unconfirmed')from None
