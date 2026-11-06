"""Pure source-bound preparation for the one WS4 beta/profile-wire candidate.

No SSH, unit changes, reward calls or database access. All work is one-time
O(parent bytes + changed bytes), with no runtime periodic work introduced.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PARENT_RELEASE = '20261106-ws4-compact-receipt-d15b405cfb16'
PARENT_MANIFEST = '5ae22761341595aa94731e6f226f598ad6665dc8c18c8db03fe857e254d8ba1c'
PARENT_BUNDLE = 'd573588b64d2ea6d1431c856d52e0515b5ed471cfdf6af4456ff618d0f568488'
NEW_BUNDLE = 'f8ab7087c042cc82f43555500e134262211062e78c88190b6691dcce57ebff42'
PARENT_SERVICE = 'ec0748b94f3e7581b9271dc23c8ab0eb0f46a0901d796c6fcbca2b434b08c4b3'
RECIPE = 'public-beta-profile-wire-v1'


def need(ok, code):
    if not ok:
        raise RuntimeError(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf8')


def git_blob(revision, path):
    need(bool(re.fullmatch('[0-9a-f]{40}', revision or '')), 'immutable_revision_required')
    return subprocess.check_output(['git', '--no-replace-objects', '-C', str(ROOT),
                                    'show', revision + ':' + path]).replace(b'\r\n', b'\n')


def module_at(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    exec(compile(path.read_bytes(), str(path), 'exec'), module.__dict__)
    return module


def project_fragment(raw):
    text = raw.decode('utf8')
    need('\r' not in text, 'match_modes_lf_required')
    tree = ast.parse(text)
    installs = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'install']
    need(len(installs) == 1, 'match_modes_install_required')
    nodes = [node for node in installs[0].body if isinstance(node, ast.FunctionDef) and node.name == 'project']
    need(len(nodes) == 1, 'match_modes_project_required')
    node = nodes[0]
    lines = text.splitlines(keepends=True)
    return lines, node, ''.join(lines[node.lineno - 1:node.end_lineno])


def derive_match_modes(parent_raw, desired_raw, expected_parent_sha):
    need(bool(re.fullmatch('[a-f0-9]{64}', expected_parent_sha or ''))
         and sha(parent_raw) == expected_parent_sha, 'audited_match_modes_changed')
    lines, node, before = project_fragment(parent_raw)
    _, _, desired = project_fragment(desired_raw)
    signature = '    def project(application, payload, response, match_context, *, login=False):\n'
    old_return = 'return _daily_projection(application, response, result)'
    need(before.count(signature) == 1 and before.count(old_return) == 2,
         'match_modes_projection_anchors_changed')
    after = before.replace(signature, signature + '        from .http_profile_wire import pack\n', 1)
    after = after.replace(old_return, 'return pack(payload, _daily_projection(application, response, result))')
    need(after == desired, 'unreviewed_match_projection_change')
    lines[node.lineno - 1:node.end_lineno] = [after]
    result = ''.join(lines).encode('utf8')
    compile(result, '<derived-match-modes>', 'exec')
    return result, dict(parent_sha256=sha(parent_raw), source_sha256=sha(desired_raw),
                        derived_sha256=sha(result), parent_project_sha256=sha(before.encode()),
                        source_project_sha256=sha(desired.encode()), outside_project_unchanged=True,
                        changed_returns=2, added_imports=1)


def payloads(source_revision, parent_service_raw, parent_modes_raw, parent_modes_sha,
             parent_server_raw, parent_postgres_raw):
    """Only call after the operator's recipe/helpers have passed Git pin checks."""
    need(sha(parent_service_raw) == PARENT_SERVICE, 'actual_parent_service_changed')
    helper = module_at('public_beta_bound_service_patch', ROOT / 'tools/public_beta_bundle_20261106/service_patch.py')
    values, beta_binding = helper.payloads(parent_service_raw, source_revision)
    modes_source = git_blob(source_revision, 'server/archive_backend/match_modes.py')
    modes, modes_binding = derive_match_modes(parent_modes_raw, modes_source, parent_modes_sha)
    values['backend/archive_backend/match_modes.py'] = modes
    values['backend/archive_backend/http_profile_wire.py'] = git_blob(source_revision, 'server/archive_backend/http_profile_wire.py')
    timing = module_at('public_beta_bound_http_timing', ROOT / 'tools/public_beta_wire_release_20261106/http_timing_patch.py')
    server, postgres = timing.server(parent_server_raw), timing.postgres(parent_postgres_raw)
    values['backend/fishing_api/server.py'] = server
    values['backend/fishing_api/postgres.py'] = postgres
    values['backend/archive_backend/http_request_timing.py'] = git_blob(source_revision, 'server/archive_backend/http_request_timing.py')
    timing_binding = dict(parent_server_sha256=sha(parent_server_raw), parent_postgres_sha256=sha(parent_postgres_raw),
                         derived_server_sha256=sha(server), derived_postgres_sha256=sha(postgres),
                         diagnostic_only=True, permission_sql_retry_and_connection_policy_unchanged=True)
    bundle_path = 'server/bundles/' + NEW_BUNDLE + '/bundle.json'
    bundle_raw = git_blob(source_revision, bundle_path)
    need(sha(bundle_raw) == NEW_BUNDLE, 'frozen_public_beta_bundle_required')
    bundle = json.loads(bundle_raw)
    need(bundle.get('public_beta_delivery', {}).get('parent_hash') == PARENT_BUNDLE,
         'narrow_bundle_parent_changed')
    values['addon/' + bundle_path] = bundle_raw
    for name, content in bundle['sources'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts, 'bundle_relative_source_required')
        raw = git_blob(source_revision, 'server/bundles/' + NEW_BUNDLE + '/' + name)
        need(raw == content.encode('utf8'), 'bundle_source_git_mismatch')
        values['addon/server/bundles/' + NEW_BUNDLE + '/' + name] = raw
    # Derived pointers are declared production transformations. They apply
    # solely inside the new release; the old release and workspace stay intact.
    values['addon/server/bundles/current.json'] = canonical({'hash': NEW_BUNDLE, 'protocol': 1}) + b'\n'
    config = git_blob(source_revision, 'scripts/vscripts/config/generated/archive_http_bundle.lua')
    need(('hash = "' + NEW_BUNDLE + '"').encode() in config, 'new_client_bundle_binding_required')
    values['addon/scripts/vscripts/config/generated/archive_http_bundle.lua'] = config
    for name, raw in values.items():
        if name.endswith('.py'):
            compile(raw, name, 'exec')
    pins = {name: sha(raw) for name, raw in values.items()}
    binding = dict(recipe=RECIPE, source_revision=source_revision, parent_release=PARENT_RELEASE,
                   parent_manifest_sha256=PARENT_MANIFEST, parent_bundle=PARENT_BUNDLE,
                   new_bundle=NEW_BUNDLE, beta=beta_binding, match_modes=modes_binding,
                   http_timing=timing_binding, payload_sha256=pins,
                   configuration_admission_required=True, player_data_changes=False, payment_changes=False)
    return values, binding
