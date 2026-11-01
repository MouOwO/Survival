"""Release provenance and the common SDK mutation lease; no SDK on import.

Authority bytes are pinned by the common SDK boundary, never by a READY field.
The pinned validator retains all existing signature/feature/native acceptance
checks. This module additionally serializes publication, verifies lineage/CAS,
binds Git inputs and records an unreplayable pending intent before SDK mutation.
"""
from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import subprocess
import sys

sys.dont_write_bytecode = True


MAX_JSON = 16 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[2]
CANONICAL_JOURNAL = ROOT / 'output/four_accounts_20261022/steam_upload_state.json'
_ACTIVE = ContextVar('release_lineage_sdk_lease', default=None)
_SEAL = object()
MUTATIONS = frozenset(('CreateItem', 'StartItemUpdate', 'SubmitItemUpdate',
    'SetItemContent', 'SetItemTitle', 'SetItemDescription', 'SetItemTags',
    'SetItemPreview', 'SetItemVisibility', 'SetItemMetadata',
    'SetItemUpdateLanguage', 'AddItemPreviewFile', 'RemoveItemPreview',
    'UpdateItemPreviewFile', 'UpdateItemPreviewVideo', 'AddItemPreviewVideo',
    'SetAllowLegacyUpload', 'AddContentDescriptor', 'RemoveContentDescriptor',
    'DeleteItem'))
_HANDLE_SETTERS = MUTATIONS - {'CreateItem', 'StartItemUpdate', 'DeleteItem'}
_OTHER_MUTATIONS = frozenset(('SetUserItemVote','AddDependency','RemoveDependency',
    'AddAppDependency','RemoveAppDependency'))
_MUTATION_PREFIXES = ('SetItem','AddItem','RemoveItem','UpdateItem')


class Refused(ValueError):
    pass


def need(value, code):
    if not value:
        raise Refused(code)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'),
                       ensure_ascii=True) + '\n').encode('ascii')


def checked_sha(value):
    need(isinstance(value, str) and re.fullmatch('[a-f0-9]{64}', value), 'sha256_required')
    return value


def revision(value):
    need(isinstance(value, str) and re.fullmatch('[a-f0-9]{40}', value), 'immutable_git_revision_required')
    return value


def regular(path):
    path = Path(path).absolute()
    need(not path.is_symlink(), 'symlink_refused')
    for parent in (path, *path.parents):
        if parent.exists():
            need(not parent.is_symlink() and not (getattr(parent.stat(), 'st_file_attributes', 0) & 0x400),
                 'reparse_path_refused')
    return path


def read_json(path, limit=MAX_JSON):
    path = regular(path)
    need(path.is_file() and path.stat().st_size <= limit, 'bounded_regular_json_required')
    raw = path.read_bytes()
    need(len(raw) <= limit, 'json_grew_beyond_limit')
    value = json.loads(raw)
    need(isinstance(value, dict), 'json_object_required')
    return value, raw


def atomic_json(path, value):
    """Only under the shared lease. Unique temporary name; fsync then replace."""
    path = regular(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + secrets.token_hex(12) + '.pending')
    raw = canonical(value)
    with temporary.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    return sha(raw)


@contextmanager
def exclusive_lock(path):
    """One fixed item-wide OS lock, independent of caller journal filenames."""
    path = regular(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        if stream.seek(0, 2) == 0:
            stream.write(b'0')
            stream.flush()
        stream.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Refused('publication_already_owned') from None
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt':
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


@dataclass(frozen=True)
class Authority:
    policy_path: Path
    digest: str
    policy: dict


def load_authority(path, expected_sha256):
    authority_path = Path(path).absolute()
    checked_sha(expected_sha256)
    policy, raw = read_json(path, 65536)
    need(sha(raw) == expected_sha256 and policy.get('schema') == 1, 'pinned_release_authority_required')
    for key in ('canonical_journal', 'lineage_state', 'publication_lock', 'validator_path'):
        need(isinstance(policy.get(key), str) and Path(policy[key]).is_absolute(), 'fixed_absolute_policy_paths_required')
        regular(policy[key])
    paths = [Path(policy[key]).resolve() for key in ('canonical_journal', 'lineage_state', 'publication_lock')]
    need(len(set(paths)) == 3, 'separate_journal_lineage_lock_paths_required')
    need(paths[2] == Path(str(paths[0]) + '.lock'), 'canonical_sdk_publication_lock_required')
    checked_sha(policy.get('validator_sha256'))
    need(type(policy.get('app_id')) is int and isinstance(policy.get('workshop_id'), str)
         and policy['workshop_id'].isdigit() and isinstance(policy.get('owner'), str), 'fixed_item_identity_required')
    need(isinstance(policy.get('repositories'), dict) and set(policy['repositories']) == {'game', 'content'},
         'two_fixed_repositories_required')
    for repo_path in policy['repositories'].values():
        need(isinstance(repo_path, str) and Path(repo_path).is_absolute(), 'absolute_git_repository_required')
    return Authority(authority_path, expected_sha256, copy.deepcopy(policy))


def _validator(authority):
    # Re-read both trusted inputs; a copied READY JSON never reaches this code.
    policy, raw = read_json(authority.policy_path, 65536)
    need(sha(raw) == authority.digest and policy == authority.policy, 'release_authority_changed')
    path = regular(policy['validator_path'])
    need(path.is_file() and path.stat().st_size <= 1024 * 1024
         and sha(path.read_bytes()) == policy['validator_sha256'], 'trusted_release_validator_changed')
    spec = importlib.util.spec_from_file_location('private_release_validator_' + authority.digest[:16], path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _git(repo, *args):
    result = subprocess.run(['git', '--no-replace-objects', '-c',
        'safe.directory=' + Path(repo).resolve().as_posix(), '-C', str(repo), *args], check=False,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    need(result.returncode == 0, 'git_provenance_check_failed')
    need(len(result.stdout) <= 64 * 1024 * 1024, 'git_result_exceeds_budget')
    return result.stdout


def require_ancestor(repo, ancestor, target):
    revision(ancestor); revision(target)
    need(_git(repo, 'rev-parse', '--verify', target + '^{commit}').decode().strip() == target,
         'exact_target_commit_required')
    _git(repo, 'merge-base', '--is-ancestor', ancestor, target)


def git_changes(repo, parent, target):
    require_ancestor(repo, parent, target)
    data = _git(repo, 'diff', '--no-ext-diff', '--no-renames', '--name-status', '-z', parent, target).split(b'\0')
    if data[-1:] == [b'']:
        data.pop()
    need(len(data) % 2 == 0, 'unexpected_git_diff_protocol')
    result = []
    for index in range(0, len(data), 2):
        kind, name = data[index].decode('ascii'), data[index + 1].decode('utf8')
        need(kind in ('A', 'M', 'D', 'T'), 'unclassified_git_change')
        resource_path(name)
        result.append({'path': name, 'kind': kind})
    return result


def resource_path(name):
    need(isinstance(name, str) and name and '\\' not in name and ':' not in name,
         'relative_posix_resource_path_required')
    path = PurePosixPath(name)
    need(not path.is_absolute() and str(path) == name and all(part not in ('.', '..', '') for part in path.parts),
         'canonical_resource_path_required')
    return name


def derive_payload_plan(parent_manifest, repositories, bindings, *, parent_origins, parent_manifest_sha256,
                        non_runtime_paths=(), allow_remove=()):
    """Derive ALL immutable Git changes against the authenticated published base.

    Each binding: resource, inputs[{repo,path}], output{repo,path}, kind
    (identity/compiled), source_pins{repo:path:sha256}, artifact_sha256.
    Non-runtime classification is an explicit exact-path set, never a broad
    implicit docs/tools exclusion. The registered validator authenticates these
    mappings and the parent signature before admitting any resulting plan.
    """
    need(set(repositories) == {'game', 'content'}, 'game_and_content_revisions_required')
    checked_sha(parent_manifest_sha256)
    parent_rows = parent_manifest.get('files')
    need(isinstance(parent_rows, list), 'authenticated_parent_file_rows_required')
    rows = {}
    for row in parent_rows:
        name = resource_path(row['path'])
        need(name not in rows, 'duplicate_parent_resource')
        checked_sha(row['sha256'])
        rows[name] = copy.deepcopy(row)
    need(set(parent_origins) == set(rows), 'complete_authenticated_parent_resource_origins_required')
    for name, origin in parent_origins.items():
        need(origin.get('resource_sha256') == rows[name]['sha256']
             and origin.get('kind') in ('git_blob', 'compiled', 'frozen_signed_resource'),
             'parent_resource_origin_mismatch')
        if origin['kind'] != 'frozen_signed_resource':
            revision(origin.get('commit'))
    input_index = {}
    output_index = {}
    for binding in bindings:
        name = resource_path(binding['resource'])
        need(name not in output_index and binding.get('kind') in ('identity', 'compiled'), 'unique_resource_binding_required')
        output_index[name] = binding
        sources = binding['inputs'] + [binding['output']]
        need(binding['inputs'] and (binding['kind'] != 'identity'
             or binding['inputs'] == [binding['output']]), 'identity_requires_same_git_input_and_output')
        for source in sources:
            key = (source['repo'], resource_path(source['path']))
            need(key[0] in repositories, 'unknown_source_repository')
            input_index.setdefault(key, set()).add(name)
    ignored = {(entry['repo'], resource_path(entry['path'])) for entry in non_runtime_paths}
    need(ignored.isdisjoint(input_index), 'runtime_source_cannot_be_ignored')
    changes, affected = {}, set()
    for role, repo in repositories.items():
        changes[role] = git_changes(repo['path'], repo['parent'], repo['target'])
        for change in changes[role]:
            key = (role, change['path'])
            need(key in input_index or key in ignored, 'unmapped_git_change:' + role + ':' + change['path'])
            affected.update(input_index.get(key, ()))
    removed, changed, source_pins = [], {}, {}
    allowed_remove = set(allow_remove)
    # A published package can be a frozen older tree + selected overlays. Its
    # source_revision label does NOT say every blob in that commit was shipped.
    # Git diff audits coverage; actual signed-parent row hashes choose payloads.
    for name in sorted(output_index):
        binding = output_index[name]
        output = binding['output']; repo = repositories[output['repo']]
        output_deleted = any(row['path'] == output['path'] and row['kind'] == 'D' for row in changes[output['repo']])
        if output_deleted:
            need(name in rows and name in allowed_remove, 'resource_removal_requires_explicit_review')
            removed.append(name); del rows[name]
            continue
        for source in binding['inputs']:
            key = source['repo'] + ':' + source['path']; source_repo = repositories[source['repo']]
            raw = _git(source_repo['path'], 'show', source_repo['target'] + ':' + source['path'])
            need(sha(raw) == binding['source_pins'].get(key), 'immutable_source_binding_mismatch')
            source_pins[key] = sha(raw)
        raw = _git(repo['path'], 'show', repo['target'] + ':' + output['path'])
        need(sha(raw) == binding['artifact_sha256'], 'immutable_artifact_binding_mismatch')
        old = rows.get(name)
        if old is None or old['sha256'] != sha(raw):
            changed[name] = {'bytes': len(raw), 'sha256': sha(raw),
                             'md5': hashlib.md5(raw).hexdigest()}
            rows[name] = {**(old or {}), 'path': name, **changed[name]}
    plan = dict(schema=1,kind='GIT_DERIVED_AUTHENTICATED_PARENT_PROJECTION',
        source_revisions={role: {'parent': value['parent'], 'target': value['target']} for role, value in repositories.items()},
        parent_manifest_sha256=parent_manifest_sha256,
        parent_manifest_object_sha256=sha(canonical(parent_manifest)),git_changes=changes,
        parent_origins_sha256=sha(canonical(parent_origins)),
        comparison_strategy='ALL_DECLARED_RUNTIME_BINDINGS_VS_AUTHENTICATED_PARENT_RESOURCE_HASHES',
        changed_resources=changed,removed_resources=removed,source_pins=source_pins,
        projected_rows=[rows[name] for name in sorted(rows)],unaffected_parent_rows_preserved=True,
        steam_upload_kind='FULL_VERIFIED_VPK_DIRECTORY_NOT_RUNTIME_HOTPATCH')
    return {**plan, 'plan_sha256': sha(canonical(plan))}


def _identity(authority, value):
    p = authority.policy
    need(value.get('workshop_id') == p['workshop_id'] and value.get('app_id') == p['app_id']
         and value.get('owner') == p['owner'], 'release_item_identity_mismatch')


def bootstrap_lineage(authority, request):
    """Explicit reviewed migration; never guess a missing content Git baseline."""
    with exclusive_lock(authority.policy['publication_lock']):
        need(not Path(authority.policy['lineage_state']).exists(), 'lineage_already_bootstrapped')
        state, raw = read_json(authority.policy['canonical_journal'])
        _identity(authority, state)
        need(state.get('uploaded') is True and state.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',
             'successful_published_bootstrap_parent_required')
        evidence = _validator(authority).validate_bootstrap(copy.deepcopy(request))
        need(evidence['canonical_journal_sha256'] == sha(raw)
             and evidence['release_sequence'] == state['release_sequence']
             and evidence['content_sha256'] == state['content_sha256'], 'authenticated_bootstrap_parent_mismatch')
        need(set(evidence['source_revisions']) == {'game', 'content'}, 'known_published_dual_git_baseline_required')
        checked_sha(evidence['parent_manifest_sha256'])
        checked_sha(evidence['resource_origins_sha256'])
        need(evidence.get('source_anchor_is_full_published_tree') is False,
             'mixed_frozen_parent_must_not_claim_full_git_export')
        for role, commit in evidence['source_revisions'].items():
            require_ancestor(authority.policy['repositories'][role], commit, commit)
        need(Path(authority.policy['canonical_journal']).read_bytes() == raw, 'bootstrap_parent_changed')
        atomic_json(authority.policy['lineage_state'], dict(schema=1,generation=0,pending=None,
            head=dict(sequence=state['release_sequence'],content_sha256=state['content_sha256'],
                      canonical_journal_sha256=sha(raw),source_revisions=evidence['source_revisions'],
                      manifest_sha256=evidence['parent_manifest_sha256'],
                      resource_origins_sha256=evidence['resource_origins_sha256'])))


class _Lease:
    def __init__(self, seal, authority, validated, state, expected_journal_sha, parent):
        need(seal is _SEAL, 'opaque_release_lease_required')
        self.authority, self.validated, self.state = authority, validated, state
        self.pid, self.expected_journal_sha = os.getpid(), expected_journal_sha
        self.token, self.handle, self.submit_started = secrets.token_hex(24), None, False
        self.alive, self.completed, self.prepared_write = True, False, None
        self.parent = copy.deepcopy(parent)
        self.failed, self.inflight = False, None

    def check(self):
        need(self.alive and not self.failed and not self.completed and self.pid == os.getpid() and _ACTIVE.get() is self,
             'live_same_process_release_lease_required')
        need(sha(Path(self.authority.policy['canonical_journal']).read_bytes()) == self.expected_journal_sha,
             'canonical_journal_changed_outside_owned_lease')
        current, _ = read_json(self.authority.policy['lineage_state'])
        need(current == self.state, 'publication_generation_changed')

    def mark_submitted(self, receipt):
        self.check()
        need(self.submit_started and self.handle is not None and self.inflight is None,
             'native_submit_result_not_observed')
        state, raw = read_json(self.authority.policy['canonical_journal'])
        _identity(self.authority, state)
        need(receipt == state and state.get('uploaded') is True
             and state.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
             and state.get('release_sequence') == self.validated['release_sequence']
             and state.get('content_sha256') == self.validated['content_sha256'], 'successful_same_candidate_receipt_required')
        result = dict(schema=1,generation=self.state['pending']['generation'],pending=None,
            head=dict(sequence=state['release_sequence'],content_sha256=state['content_sha256'],
                canonical_journal_sha256=sha(raw),source_revisions=self.validated['source_revisions'],
                manifest_sha256=self.validated['signed_manifest_sha256'],
                resource_origins_sha256=self.validated['resource_origins_sha256']))
        atomic_json(self.authority.policy['lineage_state'], result)
        self.completed = True


@contextmanager
def release_lease(authority, request, *, preflight=False):
    need(_ACTIVE.get() is None, 'nested_release_lease_refused')
    with exclusive_lock(authority.policy['publication_lock']):
        state, _ = read_json(authority.policy['lineage_state'])
        need(state.get('schema') == 1 and state.get('pending') is None, 'pending_publication_requires_separate_reconciliation')
        parent, raw = read_json(authority.policy['canonical_journal'])
        _identity(authority, parent)
        need(parent.get('uploaded') is True and parent.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST',
             'unknown_or_pending_canonical_parent_refused')
        need(sha(raw) == state['head']['canonical_journal_sha256'] == request['parent_journal_sha256'],
             'stale_published_parent_cas')
        need(type(request['generation']) is int and request['generation'] == state['generation'] + 1,
             'next_publication_generation_required')
        need(type(request['release_sequence']) is int and request['release_sequence'] > parent['release_sequence'],
             'strictly_new_release_sequence_required')
        validated = _validator(authority).validate_release(copy.deepcopy(request))
        _identity(authority, validated)
        for key in ('release_sequence','generation','parent_journal_sha256','source_revisions',
                    'signed_manifest_sha256','report_sha256','plan_sha256'):
            need(validated.get(key) == request.get(key), 'trusted_validator_request_binding_mismatch:' + key)
        for key in ('signed_manifest_sha256','report_sha256','plan_sha256','content_sha256'):
            checked_sha(validated.get(key))
        need(validated.get('authenticated_parent_content_sha256') == parent['content_sha256'], 'wrong_authenticated_resource_base')
        need(validated.get('authenticated_parent_manifest_sha256') == state['head']['manifest_sha256']
             and validated.get('parent_resource_origins_sha256') == state['head']['resource_origins_sha256'],
             'wrong_authenticated_resource_origin_base')
        checked_sha(validated.get('resource_origins_sha256'))
        need(set(validated['source_revisions']) == {'game','content'}, 'both_source_revisions_required')
        for role, target in validated['source_revisions'].items():
            repo = authority.policy['repositories'][role]
            require_ancestor(repo, state['head']['source_revisions'][role], target)
            for required in authority.policy.get('required_feature_ancestors', {}).get(role, []):
                require_ancestor(repo, required, target)
        need(Path(authority.policy['canonical_journal']).read_bytes() == raw, 'parent_changed_during_full_validation')
        need(Path(validated['package_dir']).is_absolute(), 'authenticated_absolute_package_directory_required')
        if preflight:
            # Same lock and complete admission, but no intent or SDK capability.
            # Publication must revalidate under its own subsequently held lease.
            yield copy.deepcopy(validated)
            return
        pending = dict(generation=request['generation'],release_sequence=request['release_sequence'],
            parent_journal_sha256=sha(raw),content_sha256=validated['content_sha256'],
            signed_manifest_sha256=validated['signed_manifest_sha256'],report_sha256=validated['report_sha256'],
            plan_sha256=validated['plan_sha256'],source_revisions=validated['source_revisions'],
            status='INTENT_PRESERVED_UNTIL_SUCCESS_OR_EXPLICIT_RECONCILIATION')
        state = {**state, 'pending': pending}
        atomic_json(authority.policy['lineage_state'], state)
        lease = _Lease(_SEAL, authority, validated, state, sha(raw), parent)
        token = _ACTIVE.set(lease)
        try:
            yield lease
            need(lease.completed, 'publication_not_completed_pending_preserved')
        finally:
            lease.alive = False
            _ACTIVE.reset(token)


def preflight_release(authority, request):
    """Complete read-only admission; returned data grants no SDK mutation permit."""
    with release_lease(authority, request, preflight=True) as validated:
        return copy.deepcopy(validated)


class _Permit:
    def __init__(self, lease, suffix):
        self.lease, self.suffix, self.used = lease, suffix, False

    def observe_result(self, result):
        lease = self.lease
        lease.check()
        need(not self.used and lease.inflight is self, 'single_owned_native_result_required')
        self.used = True
        valid = (type(result) is int and result not in (0, 2**64 - 1)) if self.suffix in (
            'StartItemUpdate', 'SubmitItemUpdate') else result is True
        if not valid:
            lease.failed = True
            raise Refused('sdk_mutation_failed_pending_preserved')
        if self.suffix == 'StartItemUpdate':
            lease.handle = result
        lease.inflight = None


def require_sdk_mutation(suffix, args, *, authority_sha256):
    """Common Steam.fn/ug must call before EVERY mutating native API call."""
    if suffix not in MUTATIONS:
        need(suffix not in _OTHER_MUTATIONS and not suffix.startswith(_MUTATION_PREFIXES),
             'unreviewed_sdk_mutation_refused_before_native_call')
        return None
    lease = _ACTIVE.get()
    need(isinstance(lease, _Lease) and lease.authority.digest == authority_sha256,
         'reviewed_release_lease_required_before_sdk_mutation')
    lease.check()
    need(lease.inflight is None, 'prior_native_call_outcome_unknown_pending_preserved')
    need(not lease.submit_started, 'no_mutations_after_submit')
    if suffix in ('CreateItem','DeleteItem'):
        raise Refused('existing_original_item_only')
    if suffix == 'StartItemUpdate':
        need(lease.handle is None and len(args) >= 2
             and int(args[0]) == lease.authority.policy['app_id']
             and str(int(args[1])) == lease.authority.policy['workshop_id'], 'wrong_update_item_or_app')
    elif suffix in _HANDLE_SETTERS:
        need(args and lease.handle is not None and int(args[0]) == lease.handle, 'foreign_update_handle')
        if suffix == 'SetItemContent':
            supplied = args[1].decode('utf8') if isinstance(args[1], bytes) else str(args[1])
            need(Path(supplied).resolve() == Path(lease.validated['package_dir']).resolve(), 'unvalidated_upload_directory')
        if suffix == 'SetItemVisibility':
            need(len(args) >= 2 and type(args[1]) is int and args[1] == 3,
                 'reviewed_unlisted_visibility_required')
        if suffix == 'SubmitItemUpdate':
            lease.submit_started = True  # Unknown/exception is deliberately not replayable.
    permit = _Permit(lease, suffix)
    lease.inflight = permit
    return permit


def observe_sdk_result(suffix, result, *, authority_sha256):
    lease = _ACTIVE.get()
    need(isinstance(lease, _Lease) and lease.authority.digest == authority_sha256, 'owned_sdk_result_required')
    need(isinstance(lease.inflight, _Permit) and lease.inflight.suffix == suffix, 'owned_native_call_required')
    lease.inflight.observe_result(result)


def before_journal_write(path, value, *, authority_sha256=None):
    lease = _ACTIVE.get()
    target = Path(path).resolve()
    if target != CANONICAL_JOURNAL.resolve() and (lease is None or
            target != Path(lease.authority.policy['canonical_journal']).resolve()):
        return False
    need(isinstance(lease, _Lease) and lease.authority.digest == authority_sha256,
         'release_lease_required_before_canonical_journal_write')
    lease.check()
    _identity(lease.authority, value)
    need(value.get('release_sequence') in (lease.state['head']['sequence'], lease.validated['release_sequence']),
         'journal_sequence_outside_owned_transition')
    if value.get('release_sequence') == lease.validated['release_sequence']:
        need(value.get('content_sha256') == lease.validated['content_sha256'], 'journal_candidate_content_changed')
        expected_history = list(lease.parent.get('release_history', []))
        if lease.parent.get('previous_release') is not None:
            expected_history.append(lease.parent['previous_release'])
        previous = value.get('previous_release', {})
        need(value.get('release_history', []) == expected_history
             and all(previous.get(key) == lease.parent.get(key) for key in
                     ('release_sequence', 'content_sha256', 'vpk_sha256', 'package_files')),
             'journal_published_history_or_parent_lost')
    else:
        need(value.get('content_sha256') == lease.parent['content_sha256']
             and value.get('previous_release') == lease.parent.get('previous_release')
             and value.get('release_history', []) == lease.parent.get('release_history', []),
             'journal_parent_history_changed')
    lease.prepared_write = canonical(value)
    return True


def after_journal_write(path, raw_sha256, *, authority_sha256=None):
    lease = _ACTIVE.get()
    target = Path(path).resolve()
    if target != CANONICAL_JOURNAL.resolve() and (lease is None or
            target != Path(lease.authority.policy['canonical_journal']).resolve()):
        return False
    need(isinstance(lease, _Lease) and lease.authority.digest == authority_sha256,
         'release_lease_required_after_canonical_journal_write')
    need(lease.prepared_write is not None and checked_sha(raw_sha256), 'owned_journal_write_not_prepared')
    # The SDK may use indented JSON, so compare parsed values plus actual raw SHA.
    actual, raw = read_json(path)
    need(raw_sha256 == sha(raw) and canonical(actual) == lease.prepared_write, 'atomic_journal_write_differs_from_prepared_value')
    lease.expected_journal_sha = raw_sha256
    lease.prepared_write = None
    return True
