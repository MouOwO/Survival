# Exact opt-in fixed-stripe binding for new isolated labs only.
# Metadata has zero source reads; startup reads one operator and one target.
# Prepare is one bounded Git read plus O(bytes), with no SQL or hot-path work.
from __future__ import annotations
import hashlib
from pathlib import Path
import re
import subprocess

KEY = 'leaderboard_binding'
TARGET = 'runtime/archive_backend/endless_leaderboard.py'
OPERATOR_SOURCE = 'server/fishing_api_overrides/leaderboard_bind_patch.py'
OPERATOR_TARGET = 'operator/leaderboard_experiments/leaderboard_bind_patch.py'
OPERATOR_SHA256 = '3835dd854486c768647f789fb145f6050e0208aa7fb860f4f04cdf3f685f0c46'
PARENT_SHA256 = '9de91c7e489dd114e6c32a522894434873e80448049380e1aafc224777bd10fc'
OUTPUT_SHA256 = 'af4e0245ccf578de708a1e79b5f7d6ddae209ea003c57d78c46a4c5a2d16c12a'
SOURCE_BUDGET = 1024 * 1024
ROW_KEYS = frozenset(('id', 'stripes', 'source_revision', 'operator_sources',
                      'parent_runtime_sha256', 'runtime_sha256'))

def _need(value, code):
    if not value:
        raise ValueError(code)

def _sha(raw):
    return hashlib.sha256(raw).hexdigest()

def metadata(cfg):
    _need(type(cfg) is dict and type(cfg.get('sources')) is dict,
          'leaderboard_binding_manifest_invalid')
    sources = cfg['sources']
    if KEY not in cfg:
        _need(OPERATOR_TARGET not in sources and sources.get(TARGET) != OUTPUT_SHA256,
              'leaderboard_binding_missing')
        return None
    _need(type(cfg.get('schema')) is int and cfg['schema'] == 1
          and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'leaderboard_binding_requires_isolated_bounded_v2')
    row = cfg[KEY]
    _need(type(row) is dict and set(row) == ROW_KEYS and row['id'] == 'striped-v1'
          and type(row['stripes']) is int and row['stripes'] == 128,
          'leaderboard_binding_row_invalid')
    revision = row['source_revision']
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'leaderboard_binding_revision_mismatch')
    _need(type(row['operator_sources']) is dict
          and row['operator_sources'] == {OPERATOR_TARGET: OPERATOR_SHA256}
          and type(row['parent_runtime_sha256']) is dict
          and row['parent_runtime_sha256'] == {TARGET: PARENT_SHA256}
          and type(row['runtime_sha256']) is dict
          and row['runtime_sha256'] == {TARGET: OUTPUT_SHA256},
          'leaderboard_binding_exact_sources_required')
    _need(sources.get(OPERATOR_TARGET) == OPERATOR_SHA256
          and sources.get(TARGET) == OUTPUT_SHA256,
          'leaderboard_binding_source_map_mismatch')
    return row

def _namespace(raw):
    _need(type(raw) is bytes and len(raw) <= 65536 and _sha(raw) == OPERATOR_SHA256,
          'leaderboard_binding_operator_changed')
    scope = {'__name__': 'isolated_reviewed_leaderboard_stripes'}
    exec(compile(raw, OPERATOR_TARGET, 'exec'), scope)
    return scope

def _proof(operator_raw, output_raw):
    _need(type(output_raw) is bytes and len(output_raw) <= SOURCE_BUDGET
          and _sha(output_raw) == OUTPUT_SHA256, 'leaderboard_binding_output_changed')
    scope = _namespace(operator_raw)
    output = output_raw.decode('utf8')
    parent = scope['restore_source'](output)
    _need(type(parent) is str and _sha(parent.encode('utf8')) == PARENT_SHA256,
          'leaderboard_binding_parent_changed')
    _need(scope['patch_source'](parent) == output,
          'leaderboard_binding_restore_replay_failed')
    compile(output, TARGET, 'exec')
    return {TARGET: PARENT_SHA256}

def validate_leaderboard_binding(cfg, read_source):
    if metadata(cfg) is None:
        return {}
    _need(callable(read_source), 'leaderboard_binding_reader_required')
    return _proof(read_source(OPERATOR_TARGET), read_source(TARGET))

def apply_leaderboard_binding(root, cfg, revision, mode, repository):
    _need(type(mode) is str and mode in ('baseline', 'striped-v1'),
          'leaderboard_binding_mode_invalid')
    _need(KEY not in cfg, 'leaderboard_binding_already_bound')
    metadata(cfg)
    if mode == 'baseline':
        return
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'),
          'leaderboard_binding_revision_mismatch')
    _need(type(cfg.get('schema')) is int and cfg['schema'] == 1
          and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'leaderboard_binding_requires_isolated_bounded_v2')
    root, repository = Path(root), Path(repository)
    _need(root.is_dir() and not root.is_symlink() and not (root / 'lab.json').exists(),
          'leaderboard_binding_new_lab_required')
    resolved = root.resolve()
    target, operator = root / TARGET, root / OPERATOR_TARGET
    _need(target.is_file() and not target.is_symlink()
          and target.resolve().is_relative_to(resolved)
          and target.stat().st_size <= SOURCE_BUDGET,
          'leaderboard_binding_parent_path_invalid')
    parent_raw = target.read_bytes()
    _need(cfg['sources'].get(TARGET) == PARENT_SHA256 and _sha(parent_raw) == PARENT_SHA256,
          'leaderboard_binding_parent_changed')
    _need(not operator.exists() and not operator.is_symlink()
          and operator.resolve().is_relative_to(resolved),
          'leaderboard_binding_operator_path_invalid')
    git_raw = subprocess.run(['git', '-C', str(repository), 'show',
                              revision + ':' + OPERATOR_SOURCE],
                             capture_output=True, check=True, timeout=20).stdout
    scope = _namespace(git_raw)
    local = repository / OPERATOR_SOURCE
    _need(local.is_file() and not local.is_symlink() and local.stat().st_size <= 65536
          and git_raw.replace(b'\r\n', b'\n') == local.read_bytes().replace(b'\r\n', b'\n'),
          'leaderboard_binding_must_match_committed_operator')
    output = scope['patch_source'](parent_raw.decode('utf8'))
    _need(type(output) is str, 'leaderboard_binding_patch_output_invalid')
    output_raw = output.encode('utf8')
    _proof(git_raw, output_raw)
    operator.parent.mkdir(parents=True, exist_ok=True)
    with operator.open('xb') as stream:
        stream.write(git_raw)
    target.write_bytes(output_raw)
    cfg['sources'][OPERATOR_TARGET] = OPERATOR_SHA256
    cfg['sources'][TARGET] = OUTPUT_SHA256
    cfg[KEY] = {'id': 'striped-v1', 'stripes': 128, 'source_revision': revision,
                'operator_sources': {OPERATOR_TARGET: OPERATOR_SHA256},
                'parent_runtime_sha256': {TARGET: PARENT_SHA256},
                'runtime_sha256': {TARGET: OUTPUT_SHA256}}
    metadata(cfg)
