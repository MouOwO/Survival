"""Exact-source, opt-in business changes for new isolated labs only.

Preparation uses one bounded Git read and O(B) source transformations. The
metadata view touches two fixed digests without I/O; full startup validation
reads one operator and two sources once, restores, replays and compiles them.
There is no request-time work, authorization cache, SQL call or retry here.
The profile variant removes one discarded read, retaining both initialization
passes, drains, final read and every remaining RPC's guards/reset. Its changed
error ordering is an explicit experiment boundary, not general equivalence.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess


OPERATOR_SOURCE = 'server/fishing_api_overrides/profile_initialization_patch.py'
OPERATOR_TARGET = 'operator/business_experiments/profile_initialization_patch.py'
OPERATOR_SHA256 = 'a478be66d1ca9bb6ac7291676e37fee158e98572a0f58da572a5ab575107761a'
TARGETS = ('runtime/fishing_api/application.py', 'runtime/archive_backend/service.py')
PARENTS = {
    TARGETS[0]: '5bcc930a034aa72096098c2e8446d2321cff33f2ee75168d77d9b1c46a812b92',
    TARGETS[1]: 'c059165933c6398dc9e02309116ac9d5717874aacaaf1b267fd4f54347ec9a42',
}
OUTPUTS = {
    TARGETS[0]: '9c4ca317f35073c4c873216c829ab25432efa317842c3c3696ee2b22b715c608',
    TARGETS[1]: '672a1e845ec17093c755d7a724fcc4978f8cc008d935e763e7105f300b73e2f8',
}
SCHEMA_TARGET = 'database/10_schema.sql'
SCHEMAS = frozenset((
    '56467cf615c01615adf1f8dbe885a8135f236ef820e1beb2551895245fa3475b',
    '600eb5d3fa430e57a369e0ed4724e29f279fd268d47b36dcd938f4ecec007f57',
))
ROW_KEYS = frozenset(('id', 'source_revision', 'operator_sources',
                      'parent_runtime_sha256', 'runtime_sha256'))
SOURCE_BUDGET = 4 * 1024 * 1024


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _isolated(cfg):
    _need(cfg.get('schema') == 1 and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'business_experiment_requires_isolated_bounded_v2')
    _need(cfg['sources'].get(SCHEMA_TARGET) in SCHEMAS,
          'business_experiment_schema_not_reviewed')


def _metadata(cfg):
    _need(type(cfg) is dict, 'business_experiment_manifest_invalid')
    sources = cfg.get('sources', {})
    _need(type(sources) is dict, 'business_experiment_sources_invalid')
    if 'business_experiment' not in cfg:
        _need(OPERATOR_TARGET not in sources
              and not any(sources.get(name) == digest for name, digest in OUTPUTS.items()),
              'business_experiment_binding_missing')
        return None
    _isolated(cfg)
    row = cfg['business_experiment']
    _need(type(row) is dict and set(row) == ROW_KEYS
          and row['id'] == 'init-only-v1', 'business_experiment_binding_invalid')
    revision = row['source_revision']
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'business_experiment_revision_mismatch')
    _need(type(row['operator_sources']) is dict
          and row['operator_sources'] == {OPERATOR_TARGET: OPERATOR_SHA256}
          and type(row['parent_runtime_sha256']) is dict
          and row['parent_runtime_sha256'] == PARENTS
          and type(row['runtime_sha256']) is dict
          and row['runtime_sha256'] == OUTPUTS,
          'business_experiment_exact_binding_required')
    _need(sources.get(OPERATOR_TARGET) == OPERATOR_SHA256
          and all(sources.get(name) == digest for name, digest in OUTPUTS.items()),
          'business_experiment_source_map_mismatch')
    return row


def metadata_parent_sources(cfg):
    """Return a virtual parent view for the preceding runtime chain, no I/O.

    This does not authenticate physical files. The server's full source guard
    must verify all declared paths/hashes and call validate_business_experiment
    before starting. The real manifest and source mapping are never mutated.
    """
    return {} if _metadata(cfg) is None else dict(PARENTS)


def _namespace(raw):
    _need(type(raw) is bytes and len(raw) <= 65536 and _sha(raw) == OPERATOR_SHA256,
          'business_experiment_operator_changed')
    namespace = {'__name__': 'isolated_reviewed_profile_initialization_experiment'}
    exec(compile(raw, OPERATOR_TARGET, 'exec'), namespace)
    return namespace


def _restore_replay(operator_raw, raw_sources):
    _need(type(raw_sources) is dict and set(raw_sources) == set(TARGETS),
          'business_experiment_source_set_invalid')
    for name in TARGETS:
        raw = raw_sources[name]
        _need(type(raw) is bytes and len(raw) <= SOURCE_BUDGET
              and _sha(raw) == OUTPUTS[name], 'business_experiment_output_changed')
    namespace = _namespace(operator_raw)
    texts = {name.removeprefix('runtime/'): raw_sources[name].decode('utf8')
             for name in TARGETS}
    restored = namespace['restore_sources'](texts)
    expected_keys = {name.removeprefix('runtime/') for name in TARGETS}
    _need(type(restored) is dict and set(restored) == expected_keys
          and all(type(restored[name.removeprefix('runtime/')]) is str
                  and _sha(restored[name.removeprefix('runtime/')].encode('utf8')) == PARENTS[name]
                  for name in TARGETS), 'business_experiment_parent_changed')
    _need(namespace['patch_sources'](restored) == texts,
          'business_experiment_restore_replay_failed')
    for name, text in texts.items():
        compile(text, 'runtime/' + name, 'exec')
    return dict(PARENTS)


def validate_business_experiment(cfg, read_source):
    """Full startup proof after generic source/path checks; exactly three reads."""
    if _metadata(cfg) is None:
        return {}
    _need(callable(read_source), 'business_experiment_source_reader_required')
    operator_raw = read_source(OPERATOR_TARGET)
    raw_sources = {name: read_source(name) for name in TARGETS}
    return _restore_replay(operator_raw, raw_sources)


def apply_business_experiment(root, cfg, revision, mode, repository):
    """Transform only new, unbound source files; never executes business code."""
    _need(type(mode) is str and mode in ('baseline', 'init-only-v1'),
          'business_experiment_mode_invalid')
    _need('business_experiment' not in cfg, 'business_experiment_already_bound')
    _metadata(cfg)
    if mode == 'baseline':
        return
    _isolated(cfg)
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'business_experiment_revision_mismatch')
    root, repository = Path(root), Path(repository)
    _need(root.is_dir() and not root.is_symlink()
          and not (root / 'lab.json').exists(), 'business_experiment_new_lab_required')
    resolved = root.resolve()
    operator_path = root / OPERATOR_TARGET
    _need(not operator_path.exists() and not operator_path.is_symlink()
          and operator_path.resolve().is_relative_to(resolved),
          'business_experiment_operator_path_invalid')
    parents = {}
    for name in TARGETS:
        path = root / name
        _need(path.is_file() and not path.is_symlink()
              and path.resolve().is_relative_to(resolved)
              and path.stat().st_size <= SOURCE_BUDGET,
              'business_experiment_parent_path_invalid')
        raw = path.read_bytes()
        _need(cfg['sources'].get(name) == PARENTS[name] and _sha(raw) == PARENTS[name],
              'business_experiment_parent_changed')
        parents[name.removeprefix('runtime/')] = raw.decode('utf8')
    raw = subprocess.run(['git', '-C', str(repository), 'show',
                          revision + ':' + OPERATOR_SOURCE],
                         capture_output=True, check=True, timeout=20).stdout
    namespace = _namespace(raw)
    _need(raw.replace(b'\r\n', b'\n') == (repository / OPERATOR_SOURCE).read_bytes().replace(b'\r\n', b'\n'),
          'business_experiment_must_match_committed_source')
    patched = namespace['patch_sources'](parents)
    _need(type(patched) is dict and set(patched) == set(parents)
          and all(type(value) is str for value in patched.values()),
          'business_experiment_patch_output_invalid')
    outputs = {'runtime/' + name: text.encode('utf8') for name, text in patched.items()}
    _restore_replay(raw, outputs)
    operator_path.parent.mkdir(parents=True, exist_ok=True)
    with operator_path.open('xb') as stream:
        stream.write(raw)
    for name in TARGETS:
        (root / name).write_bytes(outputs[name])
        cfg['sources'][name] = OUTPUTS[name]
    cfg['sources'][OPERATOR_TARGET] = OPERATOR_SHA256
    cfg['business_experiment'] = {
        'id': 'init-only-v1', 'source_revision': revision,
        'operator_sources': {OPERATOR_TARGET: OPERATOR_SHA256},
        'parent_runtime_sha256': dict(PARENTS), 'runtime_sha256': dict(OUTPUTS)}
    _metadata(cfg)
