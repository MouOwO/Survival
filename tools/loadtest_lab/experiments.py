"""Exact-source, opt-in runtime experiments for isolated labs only.

Preparation reads each reviewed operator source from the immutable Git binding
once and compiles the resulting files. Startup validates at most three overlays
and ten touched files: O(S) hashing belongs to the existing source guard, with
O(1) binding work and no extra request-time source reads or database calls.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import runpy
import subprocess


OBSERVATION_INPUTS = frozenset((
    'fishing_api/server.py', 'fishing_api/application.py',
    'archive_backend/http_request_timing.py', 'archive_backend/command_timing.py',
    'archive_backend/settlement_runner.py', 'player_web_auth/service.py',
    'player_web_auth/http_api.py'))
SPECS = {
    'checkpoint-observation-v1': (
        ('checkpoint_observation.py',), OBSERVATION_INPUTS,
        OBSERVATION_INPUTS | {'archive_backend/_checkpoint_observation.py'}),
    # The admission helper path is fixed by the reviewed overlay recipe.
    'http-admission-v1': (
        ('http_admission_patch.py', 'http_admission.py'),
        frozenset(('fishing_api/server.py', 'player_web_auth/http_api.py')),
        frozenset(('fishing_api/server.py', 'player_web_auth/http_api.py',
                   'survival_http_admission.py'))),
}
SPECS['http-admission-v2'] = SPECS['http-admission-v1']
SPECS['pool-notify-v1'] = (
    ('db_pool_notify_patch.py', 'bounded_pool_notify.py'),
    frozenset(('fishing_api/_bounded_pool.py',)),
    frozenset(('fishing_api/_bounded_pool.py',)))
ADMISSION_IDS = ('http-admission-v1', 'http-admission-v2')
ORDER = ('checkpoint-observation-v1', *ADMISSION_IDS, 'pool-notify-v1')
ROW_KEYS = frozenset(('id', 'source_revision', 'operator_sources',
                      'parent_runtime_sha256', 'runtime_sha256'))


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def has_experiment(cfg, name):
    return any(row['id'] == name for row in cfg.get('runtime_experiments', ()))


def has_http_admission(cfg):
    return any(row['id'] in ADMISSION_IDS for row in cfg.get('runtime_experiments', ()))


def apply_experiments(root, cfg, revision, *, observation=False, admission=False,
                      pool_notify=False, repository):
    """Apply reviewed transformations in order, before the lab manifest exists."""
    admission = ('bounded-v1' if admission is True else 'baseline' if admission is False else admission)
    _need(admission in ('baseline', 'bounded-v1', 'bounded-v2'), 'http_admission_mode_invalid')
    selected = ([ORDER[0]] if observation else []) + (
        [ADMISSION_IDS[0] if admission == 'bounded-v1' else ADMISSION_IDS[1]]
        if admission != 'baseline' else []) + (['pool-notify-v1'] if pool_notify else [])
    if not selected:
        return
    _need(cfg.get('backend_db_pool') == 'bounded-v2', 'runtime_experiment_requires_bounded_v2')
    _need('runtime_experiments' not in cfg, 'runtime_experiment_already_bound')
    root, repository = Path(root), Path(repository)
    rows = []
    for identity in selected:
        filenames, inputs, outputs = SPECS[identity]
        operator_sources = {}
        for filename in filenames:
            source = 'server/fishing_api_overrides/' + filename
            raw = subprocess.run(['git', '-C', str(repository), 'show', revision + ':' + source],
                                 capture_output=True, check=True).stdout
            _need(raw.replace(b'\r\n', b'\n') == (repository / source).read_bytes().replace(b'\r\n', b'\n'),
                  'runtime_experiment_must_match_committed_source')
            operator_target = 'operator/runtime_experiments/' + filename
            operator_path = root / operator_target
            _need(not operator_path.exists(), 'runtime_experiment_target_already_exists')
            operator_path.parent.mkdir(parents=True, exist_ok=True)
            operator_path.write_bytes(raw)
            cfg['sources'][operator_target] = operator_sources[operator_target] = _sha(raw)
        parents = {}
        source_texts = {}
        for name in sorted(inputs):
            target = 'runtime/' + name
            content = (root / target).read_bytes()
            _need(cfg['sources'][target] == _sha(content), 'runtime_experiment_parent_changed')
            parents[target] = _sha(content)
            source_texts[name] = content.decode('utf-8-sig')
        namespace = runpy.run_path(str(root / 'operator/runtime_experiments' / filenames[0]),
                                  run_name='isolated_reviewed_runtime_experiment')
        patched = namespace['patch_sources'](source_texts)
        _need(type(patched) is dict and set(patched) == outputs,
              'runtime_experiment_output_set_invalid')
        digests = {}
        for name, content in patched.items():
            _need(type(content) is str, 'runtime_experiment_output_invalid')
            compile(content, 'runtime/' + name, 'exec')
            target = 'runtime/' + name
            path = root / target
            _need(name in inputs or not path.exists(), 'runtime_experiment_helper_already_exists')
            path.parent.mkdir(parents=True, exist_ok=True)
            content = content.encode('utf-8')
            path.write_bytes(content)
            cfg['sources'][target] = digests[target] = _sha(content)
        _need(any(digests[name] != digest for name, digest in parents.items()),
              'runtime_experiment_did_not_change_parent')
        rows.append({'id': identity, 'source_revision': revision,
                     'operator_sources': operator_sources,
                     'parent_runtime_sha256': parents, 'runtime_sha256': digests})
    cfg['runtime_experiments'] = rows
    validate_experiments(cfg)


def validate_experiments(cfg):
    """Return restored parent digests; final bytes remain guarded by load()."""
    rows = cfg.get('runtime_experiments', [])
    _need(type(rows) is list and len(rows) <= 3, 'runtime_experiment_list_invalid')
    if not rows:
        return {}
    _need(cfg.get('backend_db_pool') == 'bounded-v2', 'runtime_experiment_requires_bounded_v2')
    identities = []
    for row in rows:
        _need(type(row) is dict and set(row) == ROW_KEYS, 'runtime_experiment_binding_invalid')
        identity = row['id']
        _need(type(identity) is str and identity in SPECS, 'runtime_experiment_id_invalid')
        identities.append(identity)
        filenames, inputs, outputs = SPECS[identity]
        expected_operators = {'operator/runtime_experiments/' + filename for filename in filenames}
        _need(row['source_revision'] == cfg.get('csv_source_revision')
              and type(row['source_revision']) is str
              and re.fullmatch('[a-f0-9]{40}', row['source_revision']),
              'runtime_experiment_revision_mismatch')
        _need(type(row['operator_sources']) is dict and set(row['operator_sources']) == expected_operators
              and all(type(digest) is str and re.fullmatch('[a-f0-9]{64}', digest)
                      and cfg['sources'].get(target) == digest
                      for target, digest in row['operator_sources'].items()),
              'runtime_experiment_operator_mismatch')
        for key, names in (('parent_runtime_sha256', inputs), ('runtime_sha256', outputs)):
            mapping = row[key]
            _need(type(mapping) is dict and set(mapping) == {'runtime/' + name for name in names},
                  'runtime_experiment_runtime_set_invalid')
            _need(all(type(digest) is str and re.fullmatch('[a-f0-9]{64}', digest)
                      for digest in mapping.values()), 'runtime_experiment_digest_invalid')
    _need(identities == [name for name in ORDER if name in identities],
          'runtime_experiment_order_or_duplicate_invalid')
    _need(not all(name in identities for name in ADMISSION_IDS), 'http_admission_modes_are_exclusive')
    _need('pool-notify-v1' not in identities or ADMISSION_IDS[1] in identities,
          'targeted_pool_notify_requires_http_v2_queue32')
    # Walk a fixed three-step chain backwards: each child's parent must equal
    # the immediately preceding output, even when both touch the same file.
    restored = {}
    for row in reversed(rows):
        for target, digest in row['runtime_sha256'].items():
            _need(restored.get(target, cfg['sources'].get(target)) == digest,
                  'runtime_experiment_output_hash_mismatch')
        for target in row['runtime_sha256']:
            restored[target] = row['parent_runtime_sha256'].get(target)
    if any(name in identities for name in ADMISSION_IDS):
        # A waiter remains counted until it gets the mutex after notify. Even
        # with idle connections, all HTTP workers can briefly be queued. V2
        # reserves one waiting place per HTTP worker; connection count stays 4.
        waiting = 32 if ADMISSION_IDS[1] in identities else 28
        _need((cfg.get('http_concurrency'), cfg.get('web_concurrency'),
               cfg.get('db_concurrency'), cfg.get('database_pool_limits')) ==
              (32, 48, 4, {'connections': 4, 'waiting': waiting, 'wait_seconds': 2}),
              'reviewed_http_admission_budgets_required')
    return restored
