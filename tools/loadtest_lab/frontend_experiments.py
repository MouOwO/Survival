"""Exact-source, opt-in SQLite rate housekeeping for new isolated labs.

Only one observed PWA source is transformed. Metadata checks use O(1) fixed
maps without I/O; full startup proof reads exactly operator+service once and
restores/replays/compiles. PostgreSQL source, authorization, counter commits and request
behavior are unchanged; expired-bucket housekeeping may lag after wall rollback.
No request-time source work, new timer, authorization cache or network call.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess


OPERATOR_SOURCE = 'server/player_web_auth_overrides/sqlite_hot_rate_patch.py'
OPERATOR_TARGET = 'operator/frontend_experiments/sqlite_hot_rate_patch.py'
OPERATOR_SHA256 = '6f3397906e3dfe1a217876a443b88f005bf62b1f004efc2f55e4616fba0e1e31'
TARGETS = ('runtime/player_web_auth/service.py',)
PARENTS = {TARGETS[0]: 'a62b2355e84fb56bbc0e9613c2c00354f4e385599b483ea0cd4132d5d514b4b5'}
OUTPUTS = {TARGETS[0]: 'e2dfb18dd6396d314d6364821c48c029e284aabed1890b4b2bea0265ae329e92'}
ROW_KEYS = frozenset(('id', 'source_revision', 'operator_sources',
                      'parent_runtime_sha256', 'runtime_sha256'))
SOURCE_BUDGET = 256 * 1024


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _isolated(cfg):
    _need(cfg.get('schema') == 1 and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'frontend_experiment_requires_isolated_bounded_v2')


def _metadata(cfg):
    _need(type(cfg) is dict, 'frontend_experiment_manifest_invalid')
    sources = cfg.get('sources', {})
    _need(type(sources) is dict, 'frontend_experiment_sources_invalid')
    if 'frontend_experiment' not in cfg:
        _need(OPERATOR_TARGET not in sources
              and not any(sources.get(name) == digest for name, digest in OUTPUTS.items()),
              'frontend_experiment_binding_missing')
        return None
    _isolated(cfg)
    row = cfg['frontend_experiment']
    _need(type(row) is dict and set(row) == ROW_KEYS
          and row['id'] == 'hot-rate-v1', 'frontend_experiment_binding_invalid')
    revision = row['source_revision']
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'frontend_experiment_revision_mismatch')
    _need(type(row['operator_sources']) is dict
          and row['operator_sources'] == {OPERATOR_TARGET: OPERATOR_SHA256}
          and type(row['parent_runtime_sha256']) is dict
          and row['parent_runtime_sha256'] == PARENTS
          and type(row['runtime_sha256']) is dict
          and row['runtime_sha256'] == OUTPUTS,
          'frontend_experiment_exact_binding_required')
    _need(sources.get(OPERATOR_TARGET) == OPERATOR_SHA256
          and all(sources.get(name) == digest for name, digest in OUTPUTS.items()),
          'frontend_experiment_source_map_mismatch')
    return row


def metadata_parent_sources(cfg):
    """Return a virtual parent view for the preceding runtime chain, no I/O.

    This does not authenticate physical files. The server's full source guard
    must verify all declared paths/hashes and call validate_frontend_experiment
    before starting. The real manifest and source mapping are never mutated.
    """
    return {} if _metadata(cfg) is None else dict(PARENTS)


def _namespace(raw):
    _need(type(raw) is bytes and len(raw) <= 65536 and _sha(raw) == OPERATOR_SHA256,
          'frontend_experiment_operator_changed')
    namespace = {'__name__': 'isolated_reviewed_sqlite_hot_rate_experiment'}
    exec(compile(raw, OPERATOR_TARGET, 'exec'), namespace)
    return namespace


def _restore_replay(operator_raw, raw_sources):
    _need(type(raw_sources) is dict and set(raw_sources) == set(TARGETS),
          'frontend_experiment_source_set_invalid')
    for name in TARGETS:
        raw = raw_sources[name]
        _need(type(raw) is bytes and len(raw) <= SOURCE_BUDGET
              and _sha(raw) == OUTPUTS[name], 'frontend_experiment_output_changed')
    namespace = _namespace(operator_raw)
    texts = {name: raw_sources[name].decode('utf8')
             for name in TARGETS}
    restored = namespace['restore_sources'](texts)
    expected_keys = {name for name in TARGETS}
    _need(type(restored) is dict and set(restored) == expected_keys
          and all(type(restored[name]) is str
                  and _sha(restored[name].encode('utf8')) == PARENTS[name]
                  for name in TARGETS), 'frontend_experiment_parent_changed')
    _need(namespace['patch_sources'](restored) == texts,
          'frontend_experiment_restore_replay_failed')
    for name, text in texts.items():
        compile(text, name, 'exec')
    return dict(PARENTS)


def validate_frontend_experiment(cfg, read_source):
    """Full startup proof after generic source/path checks; exactly two reads."""
    if _metadata(cfg) is None:
        return {}
    _need(callable(read_source), 'frontend_experiment_source_reader_required')
    operator_raw = read_source(OPERATOR_TARGET)
    raw_sources = {name: read_source(name) for name in TARGETS}
    return _restore_replay(operator_raw, raw_sources)


def apply_frontend_experiment(root, cfg, revision, mode, repository):
    """Transform only new, unbound source files; never executes business code."""
    _need(type(mode) is str and mode in ('baseline', 'hot-rate-v1'),
          'frontend_experiment_mode_invalid')
    _need('frontend_experiment' not in cfg, 'frontend_experiment_already_bound')
    _metadata(cfg)
    if mode == 'baseline':
        return
    _isolated(cfg)
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'frontend_experiment_revision_mismatch')
    root, repository = Path(root), Path(repository)
    _need(root.is_dir() and not root.is_symlink()
          and not (root / 'lab.json').exists(), 'frontend_experiment_new_lab_required')
    resolved = root.resolve()
    operator_path = root / OPERATOR_TARGET
    _need(not operator_path.exists() and not operator_path.is_symlink()
          and operator_path.resolve().is_relative_to(resolved),
          'frontend_experiment_operator_path_invalid')
    parents = {}
    for name in TARGETS:
        path = root / name
        _need(path.is_file() and not path.is_symlink()
              and path.resolve().is_relative_to(resolved)
              and path.stat().st_size <= SOURCE_BUDGET,
              'frontend_experiment_parent_path_invalid')
        raw = path.read_bytes()
        _need(cfg['sources'].get(name) == PARENTS[name] and _sha(raw) == PARENTS[name],
              'frontend_experiment_parent_changed')
        parents[name] = raw.decode('utf8')
    raw = subprocess.run(['git', '-C', str(repository), 'show',
                          revision + ':' + OPERATOR_SOURCE],
                         capture_output=True, check=True, timeout=20).stdout
    namespace = _namespace(raw)
    _need(raw.replace(b'\r\n', b'\n') == (repository / OPERATOR_SOURCE).read_bytes().replace(b'\r\n', b'\n'),
          'frontend_experiment_must_match_committed_source')
    patched = namespace['patch_sources'](parents)
    _need(type(patched) is dict and set(patched) == set(parents)
          and all(type(value) is str for value in patched.values()),
          'frontend_experiment_patch_output_invalid')
    outputs = {name: text.encode('utf8') for name, text in patched.items()}
    _restore_replay(raw, outputs)
    operator_path.parent.mkdir(parents=True, exist_ok=True)
    with operator_path.open('xb') as stream:
        stream.write(raw)
    for name in TARGETS:
        (root / name).write_bytes(outputs[name])
        cfg['sources'][name] = OUTPUTS[name]
    cfg['sources'][OPERATOR_TARGET] = OPERATOR_SHA256
    cfg['frontend_experiment'] = {
        'id': 'hot-rate-v1', 'source_revision': revision,
        'operator_sources': {OPERATOR_TARGET: OPERATOR_SHA256},
        'parent_runtime_sha256': dict(PARENTS), 'runtime_sha256': dict(OUTPUTS)}
    _metadata(cfg)
