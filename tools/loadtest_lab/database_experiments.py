"""Exact-source SQL experiments for new isolated load-test labs only.

Preparation performs one local Git read and O(schema bytes) pure transformations.
Startup reads each of the two fixed files once and proves restore/replay; no
database connection or request-time work is introduced. For M default fields,
the set variant reduces SQL statement boundaries (107 to 5 for M=103), while
metadata work remains O(M log A) and sorting O(M log M). Empty input grows from
4 to 5 statements. This is an opt-in experiment, not a capacity guarantee.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess


SCHEMA_TARGET = 'database/10_schema.sql'
OPERATOR_SOURCE = 'server/fishing_api_overrides/gameplay_defaults_patch.py'
OPERATOR_TARGET = 'operator/database_experiments/gameplay_defaults_patch.py'
OPERATOR_SHA256 = '16fb2249123620be1817b72f0f6ac03e52c5d9715f411a700021186984c79026'
PARENT_SHA256 = '56467cf615c01615adf1f8dbe885a8135f236ef820e1beb2551895245fa3475b'
OUTPUT_SHA256 = '600eb5d3fa430e57a369e0ed4724e29f279fd268d47b36dcd938f4ecec007f57'
ROW_KEYS = frozenset(('id', 'source_revision', 'operator_sources',
                      'parent_schema_sha256', 'schema_sha256'))


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _isolated(cfg):
    _need(cfg.get('schema') == 1 and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'schema_experiment_requires_isolated_bounded_v2')


def _base_metadata(cfg):
    sources = cfg.get('sources', {})
    _need(type(sources) is dict, 'schema_experiment_sources_invalid')
    if 'schema_experiment' not in cfg:
        _need(sources.get(SCHEMA_TARGET) != OUTPUT_SHA256
              and OPERATOR_TARGET not in sources,
              'schema_experiment_binding_missing')
        return None
    _isolated(cfg)
    row = cfg['schema_experiment']
    _need(type(row) is dict and set(row) == ROW_KEYS
          and row['id'] == 'set-v1', 'schema_experiment_binding_invalid')
    revision = row['source_revision']
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'schema_experiment_revision_mismatch')
    _need(row['operator_sources'] == {OPERATOR_TARGET: OPERATOR_SHA256}
          and type(row['operator_sources']) is dict
          and row['parent_schema_sha256'] == PARENT_SHA256
          and row['schema_sha256'] == OUTPUT_SHA256,
          'schema_experiment_exact_binding_required')
    _need(sources.get(OPERATOR_TARGET) == OPERATOR_SHA256
          and sources.get(SCHEMA_TARGET) == OUTPUT_SHA256,
          'schema_experiment_source_map_mismatch')
    return row


def _namespace(raw):
    _need(type(raw) is bytes and len(raw) <= 65536
          and _sha(raw) == OPERATOR_SHA256, 'schema_experiment_operator_changed')
    namespace = {'__name__': 'isolated_reviewed_gameplay_defaults_experiment'}
    exec(compile(raw, OPERATOR_TARGET, 'exec'), namespace)
    return namespace


def _restore_replay(operator_raw, schema_raw):
    _need(type(schema_raw) is bytes and len(schema_raw) <= 1024 * 1024
          and _sha(schema_raw) == OUTPUT_SHA256, 'schema_experiment_output_changed')
    namespace = _namespace(operator_raw)
    text = schema_raw.decode('utf8')
    parent = namespace['restore_schema'](text)
    _need(type(parent) is str and _sha(parent.encode('utf8')) == PARENT_SHA256
          and namespace['patch_schema'](parent).encode('utf8') == schema_raw,
          'schema_experiment_restore_replay_failed')


def validate_schema_experiment(cfg, read_source):
    """Validate startup proof; return the one original snapshot schema digest.

    The existing source guard must first verify paths and declared hashes.
    read_source is invoked once per fixed target only for an explicit binding.
    Legacy manifests without this experiment require no extra source reads.
    """
    if _metadata(cfg) is None:
        return {}
    _need(callable(read_source), 'schema_experiment_source_reader_required')
    operator_raw = read_source(OPERATOR_TARGET)
    schema_raw = read_source(SCHEMA_TARGET)
    if 'archive_validation' in cfg:
        archive_raw = read_source(ARCHIVE_OPERATOR_TARGET)
        schema_raw = _archive_restore_replay(archive_raw, schema_raw)
    _restore_replay(operator_raw, schema_raw)
    return {SCHEMA_TARGET: PARENT_SHA256}


def apply_schema_experiment(root, cfg, revision, mode, repository):
    """Prepare new source bytes only; never executes SQL or mutates an old lab."""
    _need(type(mode) is str and mode in ('baseline', 'set-v1'),
          'schema_experiment_mode_invalid')
    _need('schema_experiment' not in cfg, 'schema_experiment_already_bound')
    _metadata(cfg)
    if mode == 'baseline':
        return
    _isolated(cfg)
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'schema_experiment_revision_mismatch')
    root, repository = Path(root), Path(repository)
    _need(root.is_dir() and not root.is_symlink()
          and not (root / 'lab.json').exists()
          and not (root / OPERATOR_TARGET).exists(),
          'schema_experiment_new_unbound_lab_required')
    parent_path = root / SCHEMA_TARGET
    _need(parent_path.is_file() and not parent_path.is_symlink()
          and parent_path.resolve().is_relative_to(root.resolve())
          and parent_path.stat().st_size <= 1024 * 1024,
          'schema_experiment_parent_path_invalid')
    parent = parent_path.read_bytes()
    _need(cfg['sources'].get(SCHEMA_TARGET) == PARENT_SHA256
          and _sha(parent) == PARENT_SHA256, 'schema_experiment_parent_changed')
    raw = subprocess.run(['git', '-C', str(repository), 'show',
                          revision + ':' + OPERATOR_SOURCE],
                         capture_output=True, check=True, timeout=20).stdout
    namespace = _namespace(raw)
    _need(raw.replace(b'\r\n', b'\n') == (repository / OPERATOR_SOURCE).read_bytes().replace(b'\r\n', b'\n'),
          'schema_experiment_must_match_committed_source')
    output = namespace['patch_schema'](parent.decode('utf8')).encode('utf8')
    _restore_replay(raw, output)
    operator_path = root / OPERATOR_TARGET
    _need(operator_path.resolve().is_relative_to(root.resolve()),
          'schema_experiment_operator_path_invalid')
    operator_path.parent.mkdir(parents=True, exist_ok=True)
    with operator_path.open('xb') as stream:
        stream.write(raw)
    parent_path.write_bytes(output)
    cfg['sources'][OPERATOR_TARGET] = OPERATOR_SHA256
    cfg['sources'][SCHEMA_TARGET] = OUTPUT_SHA256
    cfg['schema_experiment'] = {
        'id': 'set-v1', 'source_revision': revision,
        'operator_sources': {OPERATOR_TARGET: OPERATOR_SHA256},
        'parent_schema_sha256': PARENT_SHA256, 'schema_sha256': OUTPUT_SHA256}
    _metadata(cfg)


# One optional child of the already reviewed set-v1 schema. No SQL executes here.
ARCHIVE_OPERATOR_SOURCE = 'server/fishing_api_overrides/archive_unique_check_patch.py'
ARCHIVE_OPERATOR_TARGET = 'operator/database_experiments/archive_unique_check_patch.py'
ARCHIVE_OPERATOR_SHA256 = '93fc7fbff55fb67394dfa06ef50c1b63fe641c4ba73b7d4851a801cda8169df2'
ARCHIVE_OUTPUT_SHA256 = '1f30d656ffa7d70b31d3fca59d90b92326ee48c25502de825902c93856d5cca7'

def _archive_metadata(cfg):
    sources=cfg.get('sources',{})
    _need(type(sources)is dict,'archive_validation_sources_invalid')
    if 'archive_validation'not in cfg:
        _need(sources.get(SCHEMA_TARGET)!=ARCHIVE_OUTPUT_SHA256 and ARCHIVE_OPERATOR_TARGET not in sources,'archive_validation_binding_missing')
        return None
    _isolated(cfg)
    row=cfg['archive_validation']
    _need(type(row)is dict and set(row)==ROW_KEYS and row['id']=='indexed-v1','archive_validation_binding_invalid')
    revision=row['source_revision']
    _need(type(revision)is str and re.fullmatch('[a-f0-9]{40}',revision)and revision==cfg.get('csv_source_revision'),'archive_validation_revision_mismatch')
    _need(type(row['operator_sources'])is dict and row['operator_sources']=={ARCHIVE_OPERATOR_TARGET:ARCHIVE_OPERATOR_SHA256}
          and row['parent_schema_sha256']==OUTPUT_SHA256 and row['schema_sha256']==ARCHIVE_OUTPUT_SHA256,'archive_validation_exact_binding_required')
    _need(sources.get(ARCHIVE_OPERATOR_TARGET)==ARCHIVE_OPERATOR_SHA256 and sources.get(SCHEMA_TARGET)==ARCHIVE_OUTPUT_SHA256,'archive_validation_source_map_mismatch')
    return row

def metadata_schema_parent_sources(cfg):
    """Zero-IO exact certificate view for old600 business/archetype validators."""
    if _archive_metadata(cfg)is None:return {}
    view={**cfg,'sources':{**cfg['sources'],SCHEMA_TARGET:OUTPUT_SHA256}}
    _need(_base_metadata(view)is not None,'archive_validation_requires_set_v1')
    return {SCHEMA_TARGET:OUTPUT_SHA256}

def _metadata(cfg):
    parents=metadata_schema_parent_sources(cfg)
    view={**cfg,'sources':{**cfg['sources'],**parents}}if parents else cfg
    return _base_metadata(view)

def _archive_namespace(raw):
    _need(type(raw)is bytes and len(raw)<=65536 and _sha(raw)==ARCHIVE_OPERATOR_SHA256,'archive_validation_operator_changed')
    namespace={'__name__':'isolated_reviewed_archive_validation'}
    exec(compile(raw,ARCHIVE_OPERATOR_TARGET,'exec'),namespace)
    return namespace

def _archive_restore_replay(operator_raw,schema_raw):
    _need(type(schema_raw)is bytes and len(schema_raw)<=1024*1024 and _sha(schema_raw)==ARCHIVE_OUTPUT_SHA256,'archive_validation_output_changed')
    namespace=_archive_namespace(operator_raw)
    parent=namespace['restore_schema'](schema_raw.decode('utf8'))
    _need(type(parent)is str and _sha(parent.encode('utf8'))==OUTPUT_SHA256
          and namespace['patch_schema'](parent).encode('utf8')==schema_raw,'archive_validation_restore_replay_failed')
    return parent.encode('utf8')

def apply_archive_validation(root,cfg,revision,mode,repository):
    """One final preparation transform, after other overlays/archetype metadata.
    Fixed one Git read and O(schema bytes); no DB/HTTP/request-time work.
    """
    _need(type(mode)is str and mode in('baseline','indexed-v1'),'archive_validation_mode_invalid')
    _need('archive_validation'not in cfg,'archive_validation_already_bound')
    metadata_schema_parent_sources(cfg)
    if mode=='baseline':return
    _isolated(cfg)
    _need(_base_metadata(cfg)is not None,'archive_validation_requires_set_v1')
    _need(type(revision)is str and re.fullmatch('[a-f0-9]{40}',revision)and revision==cfg.get('csv_source_revision'),'archive_validation_revision_mismatch')
    root,repository=Path(root),Path(repository)
    _need(root.is_dir()and not root.is_symlink()and not(root/'lab.json').exists()and not(root/ARCHIVE_OPERATOR_TARGET).exists(),'archive_validation_new_unbound_lab_required')
    path=root/SCHEMA_TARGET
    _need(path.is_file()and not path.is_symlink()and path.resolve().is_relative_to(root.resolve())and path.stat().st_size<=1024*1024,'archive_validation_parent_path_invalid')
    parent=path.read_bytes()
    _need(cfg['sources'].get(SCHEMA_TARGET)==OUTPUT_SHA256 and _sha(parent)==OUTPUT_SHA256,'archive_validation_parent_changed')
    raw=subprocess.run(['git','-C',str(repository),'show',revision+':'+ARCHIVE_OPERATOR_SOURCE],capture_output=True,check=True,timeout=20).stdout
    namespace=_archive_namespace(raw)
    _need(raw.replace(b'\r\n',b'\n')==(repository/ARCHIVE_OPERATOR_SOURCE).read_bytes().replace(b'\r\n',b'\n'),'archive_validation_must_match_committed_source')
    output=namespace['patch_schema'](parent.decode('utf8')).encode('utf8')
    _need(_archive_restore_replay(raw,output)==parent,'archive_validation_parent_restore_changed')
    target=root/ARCHIVE_OPERATOR_TARGET
    _need(target.resolve().is_relative_to(root.resolve()),'archive_validation_operator_path_invalid')
    target.parent.mkdir(parents=True,exist_ok=True)
    with target.open('xb')as stream:stream.write(raw)
    path.write_bytes(output)
    cfg['sources'][ARCHIVE_OPERATOR_TARGET]=ARCHIVE_OPERATOR_SHA256
    cfg['sources'][SCHEMA_TARGET]=ARCHIVE_OUTPUT_SHA256
    cfg['archive_validation']={'id':'indexed-v1','source_revision':revision,'operator_sources':{ARCHIVE_OPERATOR_TARGET:ARCHIVE_OPERATOR_SHA256},'parent_schema_sha256':OUTPUT_SHA256,'schema_sha256':ARCHIVE_OUTPUT_SHA256}
    _metadata(cfg)
