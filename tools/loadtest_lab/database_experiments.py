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


def _metadata(cfg):
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
