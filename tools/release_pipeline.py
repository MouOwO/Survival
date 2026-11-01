"""One pinned release entry. Default is static; publication requires a live lease.

Git projection is incremental against authenticated published resource bytes.
The Steam upload remains a complete verified VPK set, not a runtime hot patch.
"""
from __future__ import annotations

import argparse
import copy
import importlib
import json
from pathlib import Path
import sys
from types import ModuleType

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_sdk_lineage_hook as hook
from release_lineage_20261101 import guard

MAX_REQUEST = 1024 * 1024


def authority():
    """Only the common SDK's tracked authority, never a caller policy path."""
    return guard.load_authority(hook.AUTHORITY_FILE, hook.AUTHORITY_SHA256)


def pinned_bytes(auth, prefix, *, limit=1024 * 1024):
    path = guard.regular(auth.policy.get(prefix + '_path', ''))
    guard.need(Path(auth.policy.get(prefix + '_path', '')).is_absolute(), 'fixed_pipeline_input_path_required')
    pin = guard.checked_sha(auth.policy.get(prefix + '_sha256'))
    guard.need(path.is_file() and path.stat().st_size <= limit, 'bounded_pipeline_input_required')
    raw = path.read_bytes()
    guard.need(len(raw) <= limit and guard.sha(raw) == pin, 'pinned_pipeline_input_changed:' + prefix)
    return path, raw


def pinned_module(auth, prefix):
    path, raw = pinned_bytes(auth, prefix)
    module = ModuleType('release_pipeline_' + prefix + '_' + guard.sha(raw)[:16])
    module.__file__ = str(path)
    # Execute exactly the verified bytes rather than asking a loader to reopen.
    exec(compile(raw, str(path), 'exec'), module.__dict__)
    return module


def recipe(auth):
    return pinned_module(auth, 'recipe')


def request_json(builder, path, expected_sha256):
    pin = guard.checked_sha(expected_sha256)
    path = guard.regular(path)
    base = guard.regular(builder.REPORT).resolve()
    guard.need(path.resolve().is_relative_to(base) and path.resolve() != base,
               'request_must_be_beneath_authenticated_recipe_report_directory')
    value, raw = guard.read_json(path, MAX_REQUEST)
    guard.need(guard.sha(raw) == pin, 'explicit_request_sha256_mismatch')
    return value


def static_status():
    return dict(status='STATIC_RELEASE_PIPELINE_NO_EFFECTS',
        commands=['status', 'plan', 'prepare', 'build', 'rehearsal', 'bootstrap', 'preflight', 'publish'],
        authority_override_supported=False, sdk_initialized=False,
        files_written=0, publication_performed=False,
        incremental_projection='AUTHENTICATED_RESOURCE_BASE_PLUS_COMPLETE_IMMUTABLE_GIT_BINDINGS',
        steam_delivery='COMPLETE_VERIFIED_VPK_SET_NOT_RUNTIME_HOT_PATCH')


def _template(auth):
    path, raw = pinned_bytes(auth, 'listing_template', limit=65536)
    value = json.loads(raw)
    guard.need(isinstance(value, dict) and value.get('visibility_requested') == 'unlisted'
               and value.get('workshop_id') == auth.policy['workshop_id'], 'fixed_original_unlisted_listing_required')
    cover_name = value.get('cover')
    guard.need(isinstance(cover_name, str) and cover_name, 'reviewed_cover_path_required')
    relative = Path(cover_name)
    guard.need(relative.is_absolute() or (relative.name == cover_name and cover_name not in ('.', '..')),
               'relative_template_cover_must_be_a_leaf')
    cover = guard.regular(path.parent / cover_name)
    guard.need(cover.is_file() and cover.stat().st_size < 1024 * 1024
               and guard.sha(cover.read_bytes()) == guard.checked_sha(value.get('cover_sha256')),
               'reviewed_tracked_cover_changed')
    return value, cover


def derived_listing(auth, validated):
    template, cover = _template(auth)
    listing = copy.deepcopy(template)
    listing.update(runtime_content_sha256=validated['content_sha256'], release_sequence=validated['release_sequence'])
    return listing, cover


def _write_same_or_new(builder, path, raw):
    path = guard.regular(path)
    if path.exists():
        guard.need(path.is_file() and path.read_bytes() == raw, 'different_derived_input_already_exists')
    else:
        builder.inc.write_new(path, raw)


def listing_file(auth, builder, validated):
    listing, cover = derived_listing(auth, validated)
    folder = guard.regular(builder.REPORT) / 'pipeline_listing'
    # A relative leaf keeps the pinned template verbatim while making the exact
    # tracked preview available beside the derived listing expected by the SDK.
    relative = Path(listing['cover'])
    if not relative.is_absolute():
        guard.need(relative.name == str(relative) and relative.name not in ('.', '..'),
                   'relative_template_cover_must_be_a_leaf')
        _write_same_or_new(builder, folder / relative.name, cover.read_bytes())
    path = folder / 'listing.json'
    _write_same_or_new(builder, path, (json.dumps(listing, ensure_ascii=False, indent=2) + '\n').encode('utf8'))
    return path


def _sdk():
    return importlib.import_module('steam_workshop_upload')


def publish(auth, builder, request):
    """Full revalidation under the canonical SDK lock, held exactly once."""
    with guard.release_lease(auth, request) as lease:
        validated = lease.validated
        report_path = guard.regular(builder.REPORT) / 'package.json'
        report, raw = guard.read_json(report_path)
        guard.need(guard.sha(raw) == validated['report_sha256'], 'validated_package_report_changed')
        listing_path = listing_file(auth, builder, validated)
        vpk = Path(builder.OUTPUT) / (auth.policy['workshop_id'] + '.vpk')
        guard.need(Path(builder.OUTPUT).resolve() == Path(validated['package_dir']).resolve(),
                   'recipe_and_lease_package_directories_differ')
        sdk = _sdk()
        # The lease already owns canonical+'.lock', including compatibility with
        # a previously started old publisher. Never take sdk.publication_lock.
        with builder.scene_maps(), builder.inc.trusted_source(builder.TRUSTED):
            listing, cover, facts = sdk.validate_upload(builder.VIEW, vpk, listing_path, report_path)
            expected_listing, _ = derived_listing(auth, validated)
            guard.need(listing == expected_listing, 'sdk_listing_differs_from_pinned_template')
            for key in ('content_sha256', 'release_sequence', 'vpk_sha256', 'package_files'):
                guard.need(key in report and facts.get(key) == report[key], 'sdk_package_facts_differ:' + key)
            guard.need(facts['content_sha256'] == validated['content_sha256']
                       and facts['release_sequence'] == validated['release_sequence'], 'sdk_candidate_differs_from_live_lease')
            lease.check()
            with sdk.Steam() as steam:
                result = sdk.publish(steam, listing, cover, vpk, facts,
                    Path(auth.policy['canonical_journal']), apply=True, update_existing=True)
            # This is the actual SDK return and canonical receipt, never a READY
            # constant. Unknown failures leave the lease intent for reconciliation.
            lease.mark_submitted(result)
            return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='command')
    actions.add_parser('status')
    for command in ('plan', 'prepare', 'build'):
        action = actions.add_parser(command)
        action.add_argument('--source-revision', required=True)
        action.add_argument('--content-source-revision', required=True)
        action.add_argument('--operator-revision', required=True)
        action.add_argument('--report', type=Path, required=True)
        if command in ('prepare', 'build'):
            action.add_argument('--reviewed-plan', type=Path, required=True)
            action.add_argument('--reviewed-plan-sha256', required=True)
        if command == 'build': action.add_argument('--key', type=Path, required=True)
    action = actions.add_parser('rehearsal')
    action.add_argument('action', nargs='?', default='plan', choices=['plan','stage','launch','inspect','close','restore'])
    action.add_argument('--transaction'); action.add_argument('--report-sha256'); action.add_argument('--label')
    for command in ('bootstrap', 'preflight', 'publish'):
        action = actions.add_parser(command)
        action.add_argument('--request', type=Path, required=True)
        action.add_argument('--request-sha', required=True)
        if command == 'publish': action.add_argument('--apply', action='store_true', required=True)
    args = parser.parse_args(argv)
    if args.command in (None, 'status'):
        print(json.dumps(static_status())); return 0
    auth = authority()
    if args.command == 'rehearsal':
        ops = pinned_module(auth, 'rehearsal')
        delegated = [args.action]
        for name in ('transaction', 'report_sha256', 'label'):
            if getattr(args, name) is not None: delegated += ['--' + name.replace('_', '-'), getattr(args, name)]
        return ops.main(delegated)
    builder = recipe(auth)
    if args.command in ('plan', 'prepare', 'build'):
        delegated = [] if args.command == 'plan' else ['--' + args.command]
        for name in ('source_revision', 'content_source_revision', 'operator_revision', 'report',
                     'reviewed_plan', 'reviewed_plan_sha256', 'key'):
            if getattr(args, name, None) is not None: delegated += ['--' + name.replace('_', '-'), str(getattr(args, name))]
        return builder.main(delegated)
    request = request_json(builder, args.request, args.request_sha)
    if args.command == 'bootstrap':
        guard.bootstrap_lineage(auth, request)
        result = dict(status='LINEAGE_BOOTSTRAPPED_FROM_AUTHENTICATED_PUBLISHED_PARENT', sdk_initialized=False,
                      publication_performed=False)
    elif args.command == 'preflight':
        result = guard.preflight_release(auth, request)
        derived_listing(auth, result)  # Read-only template/cover admission, no derived files.
        result = dict(status='FULL_RELEASE_PREFLIGHT_PASS_NO_SDK_CAPABILITY',
            release_sequence=result['release_sequence'], content_sha256=result['content_sha256'],
            generation=request['generation'], publication_performed=False, files_written=0, sdk_initialized=False)
    else: result = publish(auth, builder, request)
    print(json.dumps(result, ensure_ascii=True)); return 0


if __name__ == '__main__':
    try: raise SystemExit(main())
    except Exception as error:
        print(json.dumps(dict(status='RELEASE_PIPELINE_REFUSED_PRESERVE_PENDING_AND_BACKUPS',
            error_type=type(error).__name__, reason=str(error) if isinstance(error, ValueError) else 'OPERATION_FAILED_NO_AUTOMATIC_RETRY', automatic_retry=False,
            publication_outcome='NOT_ASSERTED_ON_FAILURE_RECONCILE_PRESERVED_INTENT')), flush=True)
        raise SystemExit(2)
