"""Optional fresh-lab SQL partner for the fixed read-context principal factor.

O(1) metadata; two bounded byte reads at startup/preparation. No runtime source
I/O, cached authorizations, scan, clock, network, database or deployment work.
Baseline performs no additional SQL/data reads.
"""
from pathlib import Path
import hashlib,re
KEY='profile_context'
FACTOR='profile-context-idle-v1'
OPERATOR_SQL='operator/principal_experiments/profile_context.sql'
TARGET='database/21_profile_context.sql'
SQL_SHA256='2f17cfd40e32c7477aeedd9c7a76474b0f916b46f7f07569a8a6843cfe7e69b7'
PARENT_SCHEMA_SHA256='1f30d656ffa7d70b31d3fca59d90b92326ee48c25502de825902c93856d5cca7'
LIFECYCLE_SHA256='4e5fa9f37473c0b576df5d942239cd460a5ab1f182591cde12b3bbaef5c376c5'
CHAIN=('transport-reset-filtered-combined-v1','ensure-scope-v1','checkpoint-profile-drain-v1',FACTOR)
ROWS=frozenset(('id','source_revision','parent_schema_sha256','sql_sha256'))
def need(value,code):
 if not value:raise ValueError(code)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def metadata(cfg):
 sources=cfg.get('sources');need(type(sources)is dict,'profile_context_sources_invalid');rows=cfg.get('principal_experiments',[]);need(type(rows)is list and all(type(row)is dict for row in rows),'profile_context_principal_rows_invalid')
 if KEY not in cfg:
  need(TARGET not in sources and OPERATOR_SQL not in sources and not any(row.get('id')==FACTOR for row in rows),'profile_context_SQL_binding_missing');return None
 row=cfg[KEY];need(type(row)is dict and set(row)==ROWS and row['id']=='idle-v1','profile_context_metadata_invalid')
 need(cfg.get('schema')==1 and cfg.get('kind')=='SURVIVAL_ISOLATED_LOADTEST'and cfg.get('purpose')=='capacity'and cfg.get('backend_db_pool')=='bounded-v2','profile_context_isolation_required')
 revision=row['source_revision'];need(type(revision)is str and re.fullmatch('[a-f0-9]{40}',revision)and revision==cfg.get('csv_source_revision'),'profile_context_revision_invalid')
 need(tuple(r.get('id')for r in rows)==CHAIN,'profile_context_reviewed_principal_chain_required')
 need(type(cfg.get('checkpoint_lifecycle'))is dict and cfg['checkpoint_lifecycle'].get('id')=='lifecycle-v1'and sources.get('database/20_checkpoint_lifecycle.sql')==LIFECYCLE_SHA256,'profile_context_lifecycle_binding_required')
 need(row['parent_schema_sha256']==PARENT_SCHEMA_SHA256 and sources.get('database/10_schema.sql')==PARENT_SCHEMA_SHA256 and row['sql_sha256']==SQL_SHA256 and sources.get(OPERATOR_SQL)==sources.get(TARGET)==SQL_SHA256 and rows[-1].get('operator_sources',{}).get(OPERATOR_SQL)==SQL_SHA256,'profile_context_exact_SQL_binding_required')
 return row
def validate(cfg,read_source):
 if metadata(cfg)is None:return
 need(callable(read_source),'profile_context_source_reader_required');first=None
 for name in(OPERATOR_SQL,TARGET):
  raw=read_source(name);need(type(raw)is bytes and len(raw)<=65536 and sha(raw)==SQL_SHA256,'profile_context_SQL_bytes_changed')
  if first is None:first=raw
  else:need(raw==first,'profile_context_SQL_copy_changed')
def prepare(root,cfg,revision,mode):
 need(mode in('baseline','idle-v1')and KEY not in cfg,'profile_context_mode_invalid')
 if mode=='baseline':metadata(cfg);return
 root=Path(root);need(root.is_dir()and not root.is_symlink()and not(root/'lab.json').exists()and not(root/TARGET).exists(),'profile_context_new_lab_required');need(revision==cfg.get('csv_source_revision'),'profile_context_revision_invalid')
 source=root/OPERATOR_SQL;need(source.is_file()and not source.is_symlink()and source.resolve().is_relative_to(root.resolve()),'profile_context_SQL_source_path_invalid');raw=source.read_bytes();need(len(raw)<=65536 and sha(raw)==SQL_SHA256 and cfg['sources'].get(OPERATOR_SQL)==SQL_SHA256,'profile_context_SQL_source_changed')
 row={'id':mode,'source_revision':revision,'parent_schema_sha256':PARENT_SCHEMA_SHA256,'sql_sha256':SQL_SHA256};candidate={**cfg,KEY:row,'sources':{**cfg['sources'],TARGET:SQL_SHA256}};metadata(candidate)
 path=root/TARGET;need(path.resolve().is_relative_to(root.resolve()),'profile_context_SQL_target_escape')
 with path.open('xb')as stream:stream.write(raw)
 cfg[KEY]=row;cfg['sources'][TARGET]=SQL_SHA256;validate(cfg,lambda name:(root/name).read_bytes())
