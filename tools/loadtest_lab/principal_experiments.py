"""Two fixed, opt-in post-G experiments for isolated labs only.

Metadata restores a constant-size parent view without I/O. Startup reads at most
six fixed files, proves each child by replay and returns original parent bytes
for the earlier business validator. Preparation does bounded local Git reads;
there is no database execution, request-time source I/O or authorization cache.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess


PREFIX = 'operator/principal_experiments/'
PG = 'runtime/fishing_api/postgres.py'
APP = 'runtime/fishing_api/application.py'
SERVER = 'runtime/fishing_api/server.py'
SERVICE = 'runtime/archive_backend/service.py'
G_SOURCES = {
    PG: '15efa09cc9297ff065d56067570ba001ae3c4700db62df6e4cd159e5f1e0a966',
    APP: '9c4ca317f35073c4c873216c829ab25432efa317842c3c3696ee2b22b715c608',
    SERVER: 'b5a0e44b3c1d5d66a4410f393da07025842d949c42d8a7ac329d640eed3523f1',
    SERVICE: '672a1e845ec17093c755d7a724fcc4978f8cc008d935e763e7105f300b73e2f8',
}
SCHEMAS = frozenset((
    '56467cf615c01615adf1f8dbe885a8135f236ef820e1beb2551895245fa3475b',
    '600eb5d3fa430e57a369e0ed4724e29f279fd268d47b36dcd938f4ecec007f57'))
SPECS = {
    'transport-principal-v1': {
        'operators': {
            PREFIX + 'principal_transport_patch.py':
                '7d151834d617147915b60823989e628f2307423b7803c8285d55ae62b67c367e',
            PREFIX + 'principal_transport_parent.py': G_SOURCES[PG]},
        'parents': {PG: G_SOURCES[PG]},
        'outputs': {PG: '4fe369498b9ee3d624747fbcfed2cde8f7b8ba465c9b2a46120fa2991ca8c4ce'}},
    'ensure-scope-v1': {
        'operators': {
            PREFIX + 'checkpoint_initialization_scope_patch.py':
                '15b913ff1056f7dfc19c6ab1f359c6c906f32f831be3e8b051726fe8a36a08ff'},
        'parents': {APP: G_SOURCES[APP], SERVER: G_SOURCES[SERVER]},
        'outputs': {
            APP: '8d69cdde0a8f864c4319d7af97f91de8ce639ba3012074a60a1f98fac9f54919',
            SERVER: '20b17c5ebfd0aeca5aff7d529d90ae7d5da2960ea2223524335918582135e443'}},
}
SPECS['transport-reset-v1'] = {
    'operators': dict(SPECS['transport-principal-v1']['operators']),
    'parents': {PG: G_SOURCES[PG]},
    'outputs': {PG: 'fde92f0b97b31769d6e42e0f76fc81db6a30db68c4f5536ab4c89bb8008fa7a8'}}
ORDER = ('transport-principal-v1', 'transport-reset-v1', 'ensure-scope-v1')
TRANSPORT_MODES = {'principal-v1': ORDER[0], 'reset-v1': ORDER[1]}
TRANSPORT_IDS = frozenset(TRANSPORT_MODES.values())
ROW_KEYS = frozenset(('id', 'source_revision', 'operator_sources',
                      'parent_runtime_sha256', 'runtime_sha256'))
SOURCE_BUDGET = 4 * 1024 * 1024


def _need(value, code):
    if not value:
        raise ValueError(code)


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _gated(cfg, sources):
    _need(cfg.get('schema') == 1 and cfg.get('kind') == 'SURVIVAL_ISOLATED_LOADTEST'
          and cfg.get('purpose') in ('capacity', 'functional-smoke')
          and cfg.get('backend_db_pool') == 'bounded-v2',
          'principal_experiment_requires_isolated_bounded_v2')
    _need(sources.get('database/10_schema.sql') in SCHEMAS
          and all(sources.get(name) == digest for name, digest in G_SOURCES.items()),
          'principal_experiment_reviewed_g_sources_required')
    from .business_experiments import metadata_parent_sources as business_parents
    _need(bool(business_parents({**cfg, 'sources': sources})),
          'principal_experiment_g_business_binding_required')


def _metadata(cfg):
    _need(type(cfg) is dict and type(cfg.get('sources')) is dict,
          'principal_experiment_manifest_invalid')
    rows = cfg.get('principal_experiments', [])
    _need(type(rows) is list and len(rows) <= 2, 'principal_experiment_list_invalid')
    selected = []
    for row in rows:
        _need(type(row) is dict and set(row) == ROW_KEYS,
              'principal_experiment_binding_invalid')
        identity = row['id']
        _need(type(identity) is str and identity in SPECS,
              'principal_experiment_id_invalid')
        selected.append(identity)
        spec = SPECS[identity]
        revision = row['source_revision']
        _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
              and revision == cfg.get('csv_source_revision'),
              'principal_experiment_revision_mismatch')
        for key, expected in (('operator_sources', spec['operators']),
                              ('parent_runtime_sha256', spec['parents']),
                              ('runtime_sha256', spec['outputs'])):
            _need(type(row[key]) is dict and row[key] == expected,
                  'principal_experiment_exact_binding_required')
        _need(all(cfg['sources'].get(name) == digest
                  for name, digest in spec['operators'].items()),
              'principal_experiment_operator_map_mismatch')
    _need(selected == [identity for identity in ORDER if identity in selected],
          'principal_experiment_order_or_duplicate_invalid')
    _need(sum(identity in TRANSPORT_IDS for identity in selected) <= 1,
          'principal_transport_modes_are_exclusive')
    restored = {}
    for row in reversed(rows):
        for name, digest in row['runtime_sha256'].items():
            _need(restored.get(name, cfg['sources'].get(name)) == digest,
                  'principal_experiment_output_map_mismatch')
        restored.update(row['parent_runtime_sha256'])
    covered_operators = {name for identity in selected for name in SPECS[identity]['operators']}
    for identity, spec in SPECS.items():
        if identity not in selected:
            _need(not any(name in cfg['sources'] and name not in covered_operators
                          for name in spec['operators'])
                  and not any(cfg['sources'].get(name) == digest
                              for name, digest in spec['outputs'].items()),
                  'principal_experiment_binding_missing')
    if rows:
        _gated(cfg, {**cfg['sources'], **restored})
    return rows, restored


def metadata_parent_sources(cfg):
    """Constant-size virtual view only; full proof is mandatory before startup."""
    return dict(_metadata(cfg)[1])


def _namespace(raw, identity):
    target = next(iter(SPECS[identity]['operators']))
    _need(type(raw) is bytes and len(raw) <= 65536
          and _sha(raw) == SPECS[identity]['operators'][target],
          'principal_experiment_operator_changed')
    namespace = {'__name__': 'isolated_reviewed_principal_experiment'}
    exec(compile(raw, target, 'exec'), namespace)
    return namespace


def _full_proof(identity, operators, outputs):
    spec = SPECS[identity]
    _need(set(operators) == set(spec['operators']) and set(outputs) == set(spec['outputs']),
          'principal_experiment_source_set_invalid')
    for name, raw in {**operators, **outputs}.items():
        expected = spec['operators'].get(name, spec['outputs'].get(name))
        _need(type(raw) is bytes and len(raw) <= (65536 if name in operators else SOURCE_BUDGET)
              and _sha(raw) == expected, 'principal_experiment_source_changed')
    namespace = _namespace(operators[next(iter(spec['operators']))], identity)
    if identity in TRANSPORT_IDS:
        raw = operators[PREFIX + 'principal_transport_parent.py']
        restored = {PG: raw}
        arm = 'reset-v1' if identity == 'transport-reset-v1' else 'principal-v1'
        _need(namespace['patch_postgres'](raw.decode('utf8'), arm).encode('utf8') == outputs[PG],
              'principal_experiment_transport_replay_failed')
    else:
        texts = {name.removeprefix('runtime/'): raw.decode('utf8') for name, raw in outputs.items()}
        original = namespace['restore_sources'](texts)
        _need(type(original) is dict and set(original) == set(texts)
              and all(type(text) is str for text in original.values()),
              'principal_experiment_restore_set_invalid')
        restored = {'runtime/' + name: text.encode('utf8') for name, text in original.items()}
        _need(namespace['patch_sources'](original) == texts,
              'principal_experiment_scope_replay_failed')
    _need({name: _sha(raw) for name, raw in restored.items()} == spec['parents'],
          'principal_experiment_parent_changed')
    for name, raw in outputs.items():
        compile(raw, name, 'exec')
    return restored


def validate_principal_experiments(cfg, read_source):
    """Full startup proof after generic path/hash checks; at most six reads."""
    rows, unused = _metadata(cfg)
    if not rows:
        return {}
    _need(callable(read_source), 'principal_experiment_source_reader_required')
    restored = {}
    for row in reversed(rows):
        spec = SPECS[row['id']]
        operators = {name: read_source(name) for name in spec['operators']}
        outputs = {name: (restored[name] if name in restored else read_source(name))
                   for name in spec['outputs']}
        restored.update(_full_proof(row['id'], operators, outputs))
    return restored


def apply_principal_experiments(root, cfg, revision, *, transport='baseline',
                                ensure_scope=False, repository):
    """Transform new, unbound files only; no SQL or service operations."""
    _need(type(transport) is str and transport in ('baseline', *TRANSPORT_MODES)
          and type(ensure_scope) is bool, 'principal_experiment_mode_invalid')
    _need('principal_experiments' not in cfg, 'principal_experiment_already_bound')
    _metadata(cfg)
    selected = ([TRANSPORT_MODES[transport]] if transport != 'baseline' else []) + (
        ['ensure-scope-v1'] if ensure_scope else [])
    if not selected:
        return
    _gated(cfg, cfg['sources'])
    _need(type(revision) is str and re.fullmatch('[a-f0-9]{40}', revision)
          and revision == cfg.get('csv_source_revision'), 'principal_experiment_revision_mismatch')
    root, repository = Path(root), Path(repository)
    resolved = root.resolve()
    _need(root.is_dir() and not root.is_symlink() and not (root / 'lab.json').exists(),
          'principal_experiment_new_lab_required')
    rows = []
    for identity in selected:
        spec = SPECS[identity]
        operators, parents = {}, {}
        for name, expected in spec['operators'].items():
            target = root / name
            _need(not target.exists() and not target.is_symlink()
                  and target.resolve().is_relative_to(resolved), 'principal_experiment_operator_path_invalid')
            source = 'server/fishing_api_overrides/' + Path(name).name
            raw = subprocess.run(['git', '-C', str(repository), 'show', revision + ':' + source],
                                 capture_output=True, check=True, timeout=20).stdout
            _need(_sha(raw) == expected and len(raw) <= 65536
                  and raw.replace(b'\r\n', b'\n') == (repository / source).read_bytes().replace(b'\r\n', b'\n'),
                  'principal_experiment_committed_source_changed')
            operators[name] = raw
        for name, expected in spec['parents'].items():
            path = root / name
            _need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(resolved)
                  and path.stat().st_size <= SOURCE_BUDGET, 'principal_experiment_parent_path_invalid')
            raw = path.read_bytes()
            _need(cfg['sources'].get(name) == expected and _sha(raw) == expected,
                  'principal_experiment_parent_changed')
            parents[name] = raw
        namespace = _namespace(operators[next(iter(spec['operators']))], identity)
        if identity in TRANSPORT_IDS:
            arm = 'reset-v1' if identity == 'transport-reset-v1' else 'principal-v1'
            outputs = {PG: namespace['patch_postgres'](parents[PG].decode('utf8'), arm).encode('utf8')}
        else:
            patched = namespace['patch_sources']({name.removeprefix('runtime/'): raw.decode('utf8')
                                                  for name, raw in parents.items()})
            _need(type(patched) is dict and set(patched) == {name.removeprefix('runtime/') for name in parents}
                  and all(type(text) is str for text in patched.values()),
                  'principal_experiment_patch_output_invalid')
            outputs = {'runtime/' + name: text.encode('utf8') for name, text in patched.items()}
        _need(_full_proof(identity, operators, outputs) == parents,
              'principal_experiment_replay_parent_mismatch')
        for name, raw in {**operators, **outputs}.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if name in operators:
                with path.open('xb') as stream:
                    stream.write(raw)
            else:
                path.write_bytes(raw)
            cfg['sources'][name] = _sha(raw)
        rows.append({'id': identity, 'source_revision': revision,
                     'operator_sources': dict(spec['operators']),
                     'parent_runtime_sha256': dict(spec['parents']), 'runtime_sha256': dict(spec['outputs'])})
    cfg['principal_experiments'] = rows
    _metadata(cfg)
