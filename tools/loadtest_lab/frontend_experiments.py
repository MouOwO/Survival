"""Exact isolated frontend experiments; no import-time SQLite/filesystem work.

Baseline: no added I/O. Hot: same two-read proof. WAL: hot+guarded WAL exact
source proof plus public build-result bytes, four fixed reads at startup only.
The private library is selected by the operator's child env, never installed here.
"""
import hashlib,json,math,re,subprocess
from pathlib import Path
OPERATOR_SOURCE='server/player_web_auth_overrides/sqlite_hot_rate_patch.py'
OPERATOR_TARGET='operator/frontend_experiments/sqlite_hot_rate_patch.py'
OPERATOR_SHA256='6f3397906e3dfe1a217876a443b88f005bf62b1f004efc2f55e4616fba0e1e31'
WAL_SOURCE='server/player_web_auth_overrides/sqlite_wal_full_patch.py'
WAL_TARGET='operator/frontend_experiments/sqlite_wal_full_patch.py'
WAL_OPERATOR_SHA256='071aea50b990c352f5ac7cb1af93174d6849973dc8a5bc7567c10f59c75b2b38'
BUILD_PROOF='operator/frontend_experiments/private_sqlite_build_result.json'
TARGETS=('runtime/player_web_auth/service.py',)
PARENTS={TARGETS[0]:'a62b2355e84fb56bbc0e9613c2c00354f4e385599b483ea0cd4132d5d514b4b5'}
OUTPUTS={TARGETS[0]:'e2dfb18dd6396d314d6364821c48c029e284aabed1890b4b2bea0265ae329e92'}
WAL_OUTPUTS={TARGETS[0]:'a13dbf9082b0517490ab051c92469d3b06c955489d9cfbec1bddd151de32d35e'}
WAL_ONLY='8dcff1a5203faf4e7e7d2de5409d93d30d3a0f43c3c93904b27f8d296a43bea8'
ROW_KEYS=frozenset(('id','source_revision','operator_sources','parent_runtime_sha256','runtime_sha256'))
SOURCE_BUDGET=256*1024
BUILD_RUN='23984d04ba877f790a1a051462b252e7'
BUILD_ROOT='/srv/survival-loadtest/'+BUILD_RUN+'/sqlite_private_3513_build_02'
LIB_PATH=BUILD_ROOT+'/work/lib/libsqlite3.so.0'
BUILD_SOURCE_SHA='755f182fa15e450138c1fbbceb4c8f209a64991fba850f395dd5b1542e634bfa'
ARCHIVE_SHA='81f5be397049b0cae1b167f2225af7646fc0f82e4a9b3c48c9ea3a533e21d77a'
C_SHA3='32d5424f97e0a7fc5ed2f6335afbb58be4e0298bd7117a34e39d345ff13d859e'
SOURCE_ID='2026-03-13 10:38:09 737ae4a34738ffa0c3ff7f9bb18df914dd1cad163f28fd6b6e114a344fe6d618'
COMPILER_PATH='/usr/bin/x86_64-linux-gnu-gcc-13'
COMPILER_SHA='1b99826121ae6682a634e5efe09bd3e3df58ce58e0b28f849114ab5b89139c26'
EXTENSION_PATH='/usr/lib/python3.12/lib-dynload/_sqlite3.cpython-312-x86_64-linux-gnu.so'
EXTENSION_SHA='ecf54958b24c533f5c8dc67ca82cdce236aeb322864140bfe93eb8a69b729f4d'
ENV_FIXED={'schema':1,'kind':'ISOLATED_PRIVATE_SQLITE_3513','build_run_id':BUILD_RUN,
 'build_source_sha256':BUILD_SOURCE_SHA,'source_archive_sha256':ARCHIVE_SHA,
 'source_c_sha3_256':C_SHA3,'compiler_path':COMPILER_PATH,'compiler_sha256':COMPILER_SHA,
 'library_path':LIB_PATH,'sqlite_version':'3.51.3','sqlite_source_id':SOURCE_ID,
 'python_executable':'/usr/bin/python3.12','sqlite3_extension_path':EXTENSION_PATH,
 'sqlite3_extension_sha256':EXTENSION_SHA}
ENV_DYNAMIC=frozenset(('library_sha256','build_receipt_sha256','build_result_sha256'))
OP_SPECS={OPERATOR_TARGET:(OPERATOR_SOURCE,OPERATOR_SHA256),WAL_TARGET:(WAL_SOURCE,WAL_OPERATOR_SHA256)}
def _need(v,c):
 if not v:raise ValueError(c)
def _sha(raw):return hashlib.sha256(raw).hexdigest()
def _digest(v):return type(v)is str and re.fullmatch('[a-f0-9]{64}',v)is not None
def _isolated(cfg):
 _need(cfg.get('schema')==1 and cfg.get('kind')=='SURVIVAL_ISOLATED_LOADTEST'and cfg.get('purpose')in('capacity','functional-smoke')and cfg.get('backend_db_pool')=='bounded-v2','frontend_experiment_requires_isolated_bounded_v2')
def _operators(mode):return {p:OP_SPECS[p][1]for p in ((OPERATOR_TARGET,WAL_TARGET)if mode=='hot-wal-full-v1'else(OPERATOR_TARGET,))}
def _outputs(mode):return WAL_OUTPUTS if mode=='hot-wal-full-v1'else OUTPUTS
def _environment_metadata(cfg,mode):
 if mode!='hot-wal-full-v1':
  _need('sqlite_environment'not in cfg and BUILD_PROOF not in cfg.get('sources',{}),'sqlite_environment_requires_wal_mode');return None
 env=cfg.get('sqlite_environment');_need(type(env)is dict and set(env)==set(ENV_FIXED)|ENV_DYNAMIC,'sqlite_environment_shape_invalid')
 _need(type(env.get('schema'))is int and all(env.get(k)==v for k,v in ENV_FIXED.items())and all(_digest(env.get(k))for k in ENV_DYNAMIC),'sqlite_environment_exact_values_required')
 _need(cfg['sources'].get(BUILD_PROOF)==env['build_result_sha256'],'sqlite_environment_build_proof_missing');return env

def _metadata(cfg):
 _need(type(cfg)is dict and type(cfg.get('sources',{}))is dict,'frontend_experiment_manifest_invalid');sources=cfg.get('sources',{})
 if 'frontend_experiment'not in cfg:
  known=set(OUTPUTS.values())|set(WAL_OUTPUTS.values())|{WAL_ONLY}
  _need(not any(p in sources for p in(OPERATOR_TARGET,WAL_TARGET,BUILD_PROOF))and not any(sources.get(p)in known for p in TARGETS),'frontend_experiment_binding_missing');_environment_metadata(cfg,None);return None
 _isolated(cfg);row=cfg['frontend_experiment'];_need(type(row)is dict and set(row)==ROW_KEYS and row.get('id')in('hot-rate-v1','hot-wal-full-v1'),'frontend_experiment_binding_invalid');mode=row['id'];rev=row['source_revision']
 _need(type(rev)is str and re.fullmatch('[a-f0-9]{40}',rev)and rev==cfg.get('csv_source_revision'),'frontend_experiment_revision_mismatch')
 _need(row['operator_sources']==_operators(mode)and row['parent_runtime_sha256']==PARENTS and row['runtime_sha256']==_outputs(mode),'frontend_experiment_exact_binding_required')
 _need(all(sources.get(p)==d for p,d in {**_operators(mode),**_outputs(mode)}.items()),'frontend_experiment_source_map_mismatch')
 _need(mode=='hot-wal-full-v1'or WAL_TARGET not in sources,'frontend_experiment_orphan_wal_operator');_environment_metadata(cfg,mode);return row

def metadata_parent_sources(cfg):return {}if _metadata(cfg)is None else dict(PARENTS)

def _environment_from_build(raw):
 _need(type(raw)is bytes and len(raw)<=SOURCE_BUDGET,'private_sqlite_build_result_budget');outer=json.loads(raw)
 _need(type(outer)is dict and set(outer)=={'exit_code','receipt','receipt_sha256'}and type(outer['exit_code'])is int and outer['exit_code']==0,'private_sqlite_build_outer_not_verified')
 r=outer['receipt'];_need(type(r)is dict and _digest(outer['receipt_sha256'])and _sha(json.dumps(r,sort_keys=True,ensure_ascii=True,allow_nan=False).encode())==outer['receipt_sha256'],'private_sqlite_build_receipt_digest_changed')
 _need(r.get('kind')=='PRIVATE_SQLITE_3513_BUILD_AND_FRESH_ABI_VERIFICATION'and r.get('status')=='PRIVATE_SQLITE_BUILD_VERIFIED'and r.get('error')is None and r.get('last_stage')=='system_after'and r.get('run_id')==BUILD_RUN and r.get('artifact_root')==BUILD_ROOT and r.get('source_sha256')==BUILD_SOURCE_SHA,'private_sqlite_build_identity_changed')
 for name in ('install_or_OS_or_venv_edits','existing_DB_opened','source_archive_downloaded','automatic_retry','data_deleted'):_need(r.get(name)is False,'private_sqlite_build_safety_flag_changed')
 _need(r.get('uploaded_source_archive_verified')is True and r.get('not_HTTP_capacity_or_service_smoke')is True,'private_sqlite_build_source_not_verified')
 _need(all(type(r.get(k))is int and r[k]==0 for k in('Postgres_connections','HTTP_calls','SSH_calls')),'private_sqlite_build_external_calls_changed')
 _need(type(r.get('elapsed_seconds'))in(int,float)and math.isfinite(r['elapsed_seconds'])and 0<=r['elapsed_seconds']<=600,'private_sqlite_build_time_invalid')
 e=r.get('evidence');_need(type(e)is dict,'private_sqlite_build_evidence_invalid');archive=e.get('archive',{});c=e.get('source_files',{}).get('sqlite3.c',{});lib=e.get('library',{});p=e.get('private_probe',{});before=e.get('system_before',{});after=e.get('system_after',{})
 _need(archive=={'url':'https://www.sqlite.org/2026/sqlite-autoconf-3510300.tar.gz','sha256':ARCHIVE_SHA,'bytes':3208867,'input':'uploaded_fixed_hash_tar_only','network_calls':0}and c.get('sha3_256')==C_SHA3,'private_sqlite_build_official_source_changed')
 _need(e.get('compiler')=={'path':COMPILER_PATH,'sha256':COMPILER_SHA}and e.get('cc_target','').strip()=='x86_64-linux-gnu','private_sqlite_build_compiler_changed')
 _need(lib.get('path')==LIB_PATH and _digest(lib.get('sha256'))and type(lib.get('bytes'))is int and 0<lib['bytes']<=64*1024*1024 and lib.get('SONAME')=='libsqlite3.so.0'and lib.get('architecture')=='ELF64_x86_64','private_sqlite_build_library_invalid')
 _need(before==after and before.get('status')=='PASS'and before.get('mode')=='system'and before.get('mapped_library_sha256')=='85265a9d4afca6f4b325ceb078b669c754fb881abed4cafe91ccebe9d625d975','private_sqlite_build_system_changed')
 _need(p.get('status')=='PASS'and p.get('mode')=='private'and p.get('mapped_library')==LIB_PATH and p.get('mapped_library_sha256')==lib['sha256']and p.get('sqlite_version')=='3.51.3'and p.get('sqlite_source_id')==SOURCE_ID,'private_sqlite_build_ABI_not_verified')
 _need(p.get('python_executable')==before.get('python_executable')=='/usr/bin/python3.12'and p.get('extension')==before.get('extension')==EXTENSION_PATH and p.get('extension_sha256')==before.get('extension_sha256')==EXTENSION_SHA,'private_sqlite_build_python_extension_changed')
 _need(p.get('python_threadsafety')==3 and 'THREADSAFE=1'in p.get('compile_options',[])and p.get('journal_mode')=='wal'and type(p.get('synchronous'))is int and p['synchronous']==2 and p.get('wal_autocheckpoint_pages')==1000,'private_sqlite_build_WAL_FULL_not_verified')
 _need(p.get('counter_transactions')=={'begin':3,'commit':3}and p.get('overlimit_counter_committed_before_denial')is True and p.get('close_reopen_counter_and_quickcheck_passed')is True,'private_sqlite_build_counter_probe_not_verified')
 return {**ENV_FIXED,'library_sha256':lib['sha256'],'build_receipt_sha256':outer['receipt_sha256'],'build_result_sha256':_sha(raw)}

def _namespace(raw,path):
 _need(type(raw)is bytes and len(raw)<=65536 and _sha(raw)==OP_SPECS[path][1],'frontend_experiment_operator_changed');ns={'__name__':'reviewed_isolated_frontend_experiment'};exec(compile(raw,path,'exec'),ns);return ns

def _restore_replay(mode,operators,raw):
 _need(type(raw)is bytes and len(raw)<=SOURCE_BUDGET and _sha(raw)==_outputs(mode)[TARGETS[0]],'frontend_experiment_output_changed');text={TARGETS[0]:raw.decode('utf8')};hot=_namespace(operators[OPERATOR_TARGET],OPERATOR_TARGET);wal=_namespace(operators[WAL_TARGET],WAL_TARGET)if mode=='hot-wal-full-v1'else None
 mid=wal['restore_sources'](text)if wal else text;_need(type(mid)is dict and set(mid)==set(TARGETS)and _sha(mid[TARGETS[0]].encode())==OUTPUTS[TARGETS[0]],'frontend_experiment_hot_parent_changed')
 parent=hot['restore_sources'](mid);_need(type(parent)is dict and set(parent)==set(TARGETS)and _sha(parent[TARGETS[0]].encode())==PARENTS[TARGETS[0]],'frontend_experiment_parent_changed');replay=hot['patch_sources'](parent);replay=wal['patch_sources'](replay)if wal else replay;_need(replay==text,'frontend_experiment_restore_replay_failed');compile(text[TARGETS[0]],TARGETS[0],'exec');return dict(PARENTS)

def validate_frontend_experiment(cfg,read_source):
 row=_metadata(cfg)
 if row is None:return {}
 _need(callable(read_source),'frontend_experiment_source_reader_required');mode=row['id'];operators={p:read_source(p)for p in _operators(mode)};raw=read_source(TARGETS[0]);parents=_restore_replay(mode,operators,raw)
 if mode=='hot-wal-full-v1':_need(_environment_from_build(read_source(BUILD_PROOF))==cfg['sqlite_environment'],'sqlite_environment_build_result_mismatch')
 return parents

def apply_frontend_experiment(root,cfg,revision,mode,repository,private_sqlite_build_receipt=None):
 _need(type(mode)is str and mode in('baseline','hot-rate-v1','hot-wal-full-v1'),'frontend_experiment_mode_invalid');_need(mode=='hot-wal-full-v1'or private_sqlite_build_receipt is None,'private_sqlite_receipt_requires_wal_mode');_need('frontend_experiment'not in cfg,'frontend_experiment_already_bound');_metadata(cfg)
 if mode=='baseline':return
 _isolated(cfg);_need(type(revision)is str and re.fullmatch('[a-f0-9]{40}',revision)and revision==cfg.get('csv_source_revision'),'frontend_experiment_revision_mismatch');root,repository=Path(root),Path(repository);_need(root.is_dir()and not root.is_symlink()and not(root/'lab.json').exists(),'frontend_experiment_new_lab_required');resolved=root.resolve()
 proof=None;environment=None
 if mode=='hot-wal-full-v1':
  _need(private_sqlite_build_receipt is not None,'private_sqlite_build_receipt_required');path=Path(private_sqlite_build_receipt);_need(path.is_file()and not path.is_symlink()and path.stat().st_size<=SOURCE_BUDGET,'private_sqlite_build_receipt_path_invalid');proof=path.read_bytes();environment=_environment_from_build(proof)
 path=root/TARGETS[0];_need(path.is_file()and not path.is_symlink()and path.resolve().is_relative_to(resolved)and path.stat().st_size<=SOURCE_BUDGET,'frontend_experiment_parent_path_invalid');parent=path.read_bytes();_need(cfg['sources'].get(TARGETS[0])==PARENTS[TARGETS[0]]and _sha(parent)==PARENTS[TARGETS[0]],'frontend_experiment_parent_changed');operators={}
 for target in _operators(mode):
  dest=root/target;_need(not dest.exists()and not dest.is_symlink()and dest.resolve().is_relative_to(resolved),'frontend_experiment_operator_path_invalid');source=OP_SPECS[target][0];raw=subprocess.run(['git','-C',str(repository),'show',revision+':'+source],capture_output=True,check=True,timeout=20).stdout;_namespace(raw,target);_need(raw.replace(b'\r\n',b'\n')==(repository/source).read_bytes().replace(b'\r\n',b'\n'),'frontend_experiment_must_match_committed_source');operators[target]=raw
 if proof is not None:_need(not(root/BUILD_PROOF).exists()and not(root/BUILD_PROOF).is_symlink()and(root/BUILD_PROOF).resolve().is_relative_to(resolved),'private_sqlite_proof_path_exists')
 texts=_namespace(operators[OPERATOR_TARGET],OPERATOR_TARGET)['patch_sources']({TARGETS[0]:parent.decode('utf8')})
 if mode=='hot-wal-full-v1':texts=_namespace(operators[WAL_TARGET],WAL_TARGET)['patch_sources'](texts)
 raw=texts[TARGETS[0]].encode();_restore_replay(mode,operators,raw)
 for name,data in operators.items():
  target=root/name;target.parent.mkdir(parents=True,exist_ok=True)
  with target.open('xb')as stream:stream.write(data)
  cfg['sources'][name]=_operators(mode)[name]
 if proof is not None:
  with(root/BUILD_PROOF).open('xb')as stream:stream.write(proof)
  cfg['sources'][BUILD_PROOF]=_sha(proof);cfg['sqlite_environment']=environment
 path.write_bytes(raw);cfg['sources'][TARGETS[0]]=_outputs(mode)[TARGETS[0]];cfg['frontend_experiment']={'id':mode,'source_revision':revision,'operator_sources':_operators(mode),'parent_runtime_sha256':dict(PARENTS),'runtime_sha256':dict(_outputs(mode))};_metadata(cfg)

def _runtime_file(path,maximum):
 path=Path(path);_need(path.is_file()and not path.is_symlink()and path.stat().st_size<=maximum,'private_sqlite_runtime_file_invalid');raw=path.read_bytes();_need(len(raw)<=maximum,'private_sqlite_runtime_file_budget');return raw

def _check_actual_environment(env,actual):
 expected={'library_path':env['library_path'],'library_sha256':env['library_sha256'],'sqlite_version':env['sqlite_version'],'sqlite_source_id':env['sqlite_source_id'],'python_executable':env['python_executable'],'sqlite3_extension_path':env['sqlite3_extension_path'],'sqlite3_extension_sha256':env['sqlite3_extension_sha256']}
 _need(type(actual)is dict and all(actual.get(k)==v for k,v in expected.items())and actual.get('mapped_libraries')==[env['library_path']]and actual.get('LD_LIBRARY_PATH')==env['library_path'].rsplit('/',1)[0]and actual.get('python_threadsafety')==3,'private_sqlite_runtime_dependency_mismatch')
 return {'kind':'VERIFIED_PRIVATE_SQLITE_STARTUP','checked_before_listener':True,'build_result_sha256':env['build_result_sha256'],'build_receipt_sha256':env['build_receipt_sha256'],'build_source_sha256':env['build_source_sha256'],'compiler_sha256':env['compiler_sha256'],'source_archive_sha256':env['source_archive_sha256'],'source_c_sha3_256':env['source_c_sha3_256'],**actual}

def checked_sqlite_environment(cfg):
 row=_metadata(cfg)
 if row is None or row['id']!='hot-wal-full-v1':return None
 import os,sys,sqlite3,_sqlite3
 env=cfg['sqlite_environment'];_need(sys.platform.startswith('linux'),'private_sqlite_runtime_linux_required');_need(os.environ.get('LD_LIBRARY_PATH')==env['library_path'].rsplit('/',1)[0],'private_sqlite_runtime_LD_PATH_required')
 maps=Path('/proc/self/maps').read_bytes();_need(len(maps)<=1024*1024,'private_sqlite_runtime_maps_budget');paths=set()
 for line in maps.decode().splitlines():
  f=line.split(None,5)
  if len(f)==6 and f[5].startswith('/')and Path(f[5]).name.startswith('libsqlite3.so'):paths.add(str(Path(f[5]).resolve(strict=True)))
 library=_runtime_file(env['library_path'],64*1024*1024);extension_path=str(Path(_sqlite3.__file__).resolve(strict=True));extension=_runtime_file(extension_path,16*1024*1024);conn=sqlite3.connect(':memory:',timeout=1)
 try:source_id=conn.execute('SELECT sqlite_source_id()').fetchone()[0]
 finally:conn.close()
 actual={'library_path':env['library_path'],'library_sha256':_sha(library),'mapped_libraries':sorted(paths),'sqlite_version':sqlite3.sqlite_version,'sqlite_source_id':source_id,'python_executable':str(Path(sys.executable).resolve(strict=True)),'sqlite3_extension_path':extension_path,'sqlite3_extension_sha256':_sha(extension),'LD_LIBRARY_PATH':os.environ.get('LD_LIBRARY_PATH'),'python_threadsafety':sqlite3.threadsafety}
 return _check_actual_environment(env,actual)

def checked_sqlite_connection(service,dependency):
 if dependency is None:return None
 _need(type(dependency)is dict and dependency.get('kind')=='VERIFIED_PRIVATE_SQLITE_STARTUP','private_sqlite_runtime_snapshot_invalid')
 with service.lock:
  journal=service.db.execute('PRAGMA journal_mode').fetchone()[0];sync=service.db.execute('PRAGMA synchronous').fetchone()[0];checkpoint=service.db.execute('PRAGMA wal_autocheckpoint').fetchone()[0]
 _need(journal=='wal'and type(sync)is int and sync==2 and type(checkpoint)is int and checkpoint==1000,'private_sqlite_runtime_WAL_FULL_required')
 return {**dependency,'journal_mode':journal,'synchronous':sync,'wal_autocheckpoint_pages':checkpoint,'same_service_connection_checked':True}
