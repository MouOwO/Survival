"""Explicit, immutable SQL lifecycle candidate for new synthetic labs only.

One Git read/one bounded SQL hash at preparation, two fixed files at startup;
metadata validation is O(1). No per-request source I/O, polling or account scan.
The historical10_schema.sql stays byte-for-byte unchanged. The image executes
the separately declared20 migration before the existing90 marker.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess

KEY = 'checkpoint_lifecycle'
SOURCE = 'server/fishing_api_overrides/checkpoint_lifecycle.sql'
TARGET = 'database/20_checkpoint_lifecycle.sql'
SQL_SHA256 = '4e5fa9f37473c0b576df5d942239cd460a5ab1f182591cde12b3bbaef5c376c5'
PARENT_SCHEMA_SHA256 = '1f30d656ffa7d70b31d3fca59d90b92326ee48c25502de825902c93856d5cca7'
ROW_KEYS = frozenset(('id', 'source_revision', 'parent_schema_sha256', 'sql_sha256'))


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def metadata(cfg):
    sources = cfg.get('sources')
    _need(type(sources) is dict, 'checkpoint_sources_invalid')
    if KEY not in cfg:
        _need(TARGET not in sources, 'checkpoint_lifecycle_binding_missing')
        return None
    row = cfg[KEY]
    _need(type(row) is dict and set(row) == ROW_KEYS and row['id'] == 'lifecycle-v1',
          'checkpoint_lifecycle_binding_invalid')
    _need(cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2', 'checkpoint_isolation_required')
    revision = row['source_revision']
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'), 'checkpoint_source_revision_invalid')
    _need(row['parent_schema_sha256'] == PARENT_SCHEMA_SHA256
          and row['sql_sha256'] == SQL_SHA256
          and sources.get('database/10_schema.sql') == PARENT_SCHEMA_SHA256
          and sources.get(TARGET) == SQL_SHA256, 'checkpoint_exact_sources_required')
    return row


def validate(cfg, read_source):
    if metadata(cfg) is None:
        return
    for name, expected in (('database/10_schema.sql', PARENT_SCHEMA_SHA256),
                           (TARGET, SQL_SHA256)):
        raw = read_source(name)
        _need(type(raw) is bytes and len(raw) <= 1024 * 1024 and _sha(raw) == expected,
              'checkpoint_physical_source_changed')


def prepare(root, cfg, revision, mode, repository):
    _need(mode in ('baseline', 'lifecycle-v1') and KEY not in cfg,
          'checkpoint_lifecycle_mode_invalid')
    metadata(cfg)
    if mode == 'baseline':
        return
    root, repository = Path(root), Path(repository)
    _need(not (root / 'lab.json').exists() and not (root / TARGET).exists(),
          'checkpoint_new_lab_required')
    raw = subprocess.run(['git', '-C', str(repository), 'show', revision + ':' + SOURCE],
                         capture_output=True, check=True, timeout=20).stdout
    _need(_sha(raw) == SQL_SHA256 and raw == (repository / SOURCE).read_bytes(),
          'checkpoint_committed_SQL_required')
    path = root / TARGET
    _need(path.resolve().is_relative_to(root.resolve()), 'checkpoint_path_escape')
    with path.open('xb') as stream:
        stream.write(raw)
    cfg['sources'][TARGET] = SQL_SHA256
    cfg[KEY] = {'id': mode, 'source_revision': revision,
                'parent_schema_sha256': PARENT_SCHEMA_SHA256, 'sql_sha256': SQL_SHA256}
    validate(cfg, lambda name: (root / name).read_bytes())
