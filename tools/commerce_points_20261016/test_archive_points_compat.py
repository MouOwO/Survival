"""Rollback-only negative checks. Import never connects or registers config."""
import copy,hashlib,json,secrets

def run_checks(conn,cfg,caf_hash,dee_hash):
 from psycopg.types.json import Jsonb
 import psycopg
 assert not conn.autocommit and conn.info.transaction_status.name=='INTRANS'
 assert caf_hash=='caf4493bb7ad373a43ca81c19f961d4fd288a47112866ba93df62013852f7a59'
 assert dee_hash=='dee53fe2e9fb8d1bc97ba6b822a86896e97e94b6bad84501fad5791920c3ca26'
 assert cfg['compatible_config_hashes'][dee_hash]['upgrade_commands']==[]
 def current():
  return {r[0]['config_hash']:r[0] for r in conn.execute('SELECT to_jsonb(c) FROM public.archive_config_sets c')}
 before=current();results=[]
 assert caf_hash not in before, "run_checks must execute before legitimate CAF registration"
 nonce=secrets.token_hex(12)
 unknown=hashlib.sha256(('archive_points_compat:'+nonce).encode()).hexdigest()
 assert unknown not in cfg['compatible_config_hashes'] and unknown not in (caf_hash,dee_hash)
 def reject(label,target,mutated,expected):
  savepoint='points_negative_'+secrets.token_hex(8)
  conn.execute('SAVEPOINT '+savepoint);message=None;sqlstate=None
  try:
   try:conn.execute('SELECT public.archive_sync_config(%s,%s)',(target,Jsonb(mutated)))
   except psycopg.Error as error:
    message=error.diag.message_primary;sqlstate=error.sqlstate
  finally:
   conn.execute('ROLLBACK TO SAVEPOINT '+savepoint)
   conn.execute('RELEASE SAVEPOINT '+savepoint)
  assert sqlstate=="P0001",(label,sqlstate,message)
  assert message==expected,(label,message,expected)
  assert current()==before,label+':config_rows_changed'
  results.append({'case':label,'error':message,'sqlstate':sqlstate,'savepoint_rolled_back':True})
 # Unknown source remains blocked; only the exact DEE source is added.
 bad=copy.deepcopy(cfg);bad['compatible_config_hashes'][unknown]={'commands':['lottery_draw'],'upgrade_commands':[]}
 reject('unknown_source_hash',caf_hash,bad,'archive_compatibility_invalid')
 # The reviewed source may not be added to arbitrary targets.
 reject('DEE_for_unknown_target',unknown,copy.deepcopy(cfg),'archive_compatibility_invalid')
 bad=copy.deepcopy(cfg);r=bad['compatible_config_hashes'][dee_hash]
 if 'starjoy_reconcile' not in r['commands']:r['commands'].append('starjoy_reconcile')
 r['upgrade_commands']=['starjoy_reconcile']
 reject('DEE_nonempty_upgrade_commands',caf_hash,bad,'archive_compatibility_upgrade_invalid')
 bad=copy.deepcopy(cfg);bad['compatible_config_hashes'][dee_hash]['upgrade_commands']='not_an_array'
 reject('DEE_upgrade_bad_type',caf_hash,bad,'archive_compatibility_invalid')
 # Empty upgrades may not weaken even one existing default or bound.
 bad=copy.deepcopy(cfg);rows=bad['configs']['player_gameplay_stats']['rows'];assert rows
 rows[0]['default_value']=rows[0].get('default_value',0)+1
 reject('CAF_changed_stat_default',caf_hash,bad,'archive_compatibility_schema_invalid')
 bad=copy.deepcopy(cfg);bad['configs']['player_gameplay_stats']['rows'][0]['min_value']=-1
 reject('CAF_changed_stat_bounds',caf_hash,bad,'archive_compatibility_schema_invalid')
 bad=copy.deepcopy(cfg);bad['configs']['player_gameplay_stats']['rows'].pop()
 reject('CAF_missing_stat_field',caf_hash,bad,'archive_compatibility_schema_invalid')
 bad=copy.deepcopy(cfg);bad['configs']['player_gameplay_stats']['rows'].append({'field_id':'unexpected_'+nonce,'storage_type':'integer','default_value':0,'min_value':0,'enabled':True})
 reject('CAF_extra_stat_field',caf_hash,bad,'archive_compatibility_schema_invalid')
 assert current()==before
 return {'status':'PASS','cases':len(results),'checks':results,'all_config_rows_unchanged':True,'permanent_hashes_registered':0,'positive_registration':'root register() validates the actual CAF separately'}
