"""One committed, explicitly authorized visibility experiment; no content upload.

The shared publication lease spans both submissions and the bounded test window.
An external restore_now.json can shorten that window, never lengthen it. There
are no scene scans or game timers: the wait checks one file at 4 Hz for <=180s.
"""
from __future__ import annotations
import ctypes as C
import json
from pathlib import Path
import time

from release_lineage_20261101 import guard
from release_packager.core import baseline, git, write_new
from release_description import fresh_item, PROTECTED

APPROVAL = 'publishing/workshop/visibility_hosting_test_20261118.json'
OPERATORS = ('tools/release_pipeline.py', 'tools/release_visibility_test.py',
             'tools/release_description.py', 'tools/release_lineage_20261101/guard.py',
             'tools/release_sdk_lineage_hook.py', 'tools/steam_workshop_upload.py',
             'tools/release_packager/core.py')
PROPOSAL_SHA = '3a53333eed71d26365bbef942c7b38fa926ac4a1287fba5d99f4bed521f402d3'


def validate_approval(value, item):
    guard.need(value == dict(schema=1, workshop_id=item,
        authorization_question='call_06c1964f80c9482f927728908c92dbfe',
        authorization_answer='授权临时公开并恢复', proposal_sha256=PROPOSAL_SHA,
        initial_visibility=3, test_visibility=0, final_visibility=3,
        maximum_public_seconds=600, restore_start_after_seconds=180,
        preserve_runtime_backend_and_five_account_admission=True),
        'exact_explicit_temporary_visibility_authorization_required')
    guard.need(item == '3824360109', 'only_original_authorized_item')


def authorization_budget(state):
    """Carry the first, verified failed-environment window into one final retest."""
    prior = state.get('last_visibility_test_receipt')
    if prior is None:
        return dict(previous_receipt=None, public_seconds_before=0.0)
    receipt, raw = guard.read_json(prior['path'])
    guard.need(guard.sha(raw) == prior['sha256']
               and receipt.get('status') == 'VISIBILITY_TEST_RESTORED_UNLISTED'
               and receipt.get('final_visibility') == 3
               and not receipt.get('authorization_closed', False), 'visibility_authorization_already_closed')
    request, request_raw = guard.read_json(Path(prior['path']).parent / 'request.json')
    guard.need(guard.sha(request_raw) == receipt['request_sha256']
               and request['approval']['proposal_sha256'] == PROPOSAL_SHA,
               'same_authorization_verified_prior_window_required')
    spent = receipt['public_to_verified_restore_seconds']
    guard.need(type(spent) in (int, float) and 0 <= spent <= 300,
               'insufficient_authorized_time_for_final_retest')
    return dict(previous_receipt=prior, public_seconds_before=spent)


def plan(auth, source, report):
    project = Path(auth.policy['repositories']['game'])
    guard.revision(source)
    guard.need(git(project, 'rev-parse', 'HEAD').decode().strip() == source,
               'current_committed_visibility_operator_required')
    for relative in (*OPERATORS, APPROVAL):
        guard.need((project / relative).read_bytes() == git(project, 'show', source + ':' + relative),
                   'uncommitted_visibility_operator:' + relative)
    approval = json.loads((project / APPROVAL).read_bytes())
    validate_approval(approval, auth.policy['workshop_id'])
    current = baseline(project)
    request = dict(schema=1, kind='TEMPORARY_VISIBILITY_TEST', authority_sha256=auth.digest,
        parent_journal_sha256=current['journal_sha256'], generation=current['lineage']['generation'] + 1,
        release_sequence=current['baseline']['parent_sequence'],
        steam_manifest=current['baseline']['official_parent_manifest'],
        baseline_sha256=current['cursor']['baseline_sha256'], approval=approval,
        authorization_budget=authorization_budget(current['lineage']),
        source_revisions={'game': source, 'content': git(auth.policy['repositories']['content'],
            'rev-parse', 'HEAD').decode().strip()}, operator_files=list(OPERATORS))
    report = guard.regular(report)
    report.mkdir(parents=True, exist_ok=False)
    write_new(report / 'request.json', request)
    return dict(status='VISIBILITY_TEST_PLAN_NO_SDK', request=str(report / 'request.json'),
                request_sha256=guard.sha((report / 'request.json').read_bytes()))


def verify_snapshot(before, after, visibility):
    guard.need(after['visibility'] == visibility, 'official_visibility_not_verified')
    guard.need(all(before[k] == after[k] for k in (*PROTECTED, 'description') if k != 'visibility'),
               'visibility_update_changed_protected_fields')


def update(steam, sdk, item, visibility, report, label):
    handle = steam.ug('StartItemUpdate', C.c_uint64, [C.c_uint32, C.c_uint64], sdk.APP, int(item))
    guard.need(steam.ug('SetItemVisibility', C.c_bool, [C.c_uint64, C.c_int], handle, visibility),
               'visibility_setter_rejected')
    started = time.monotonic()
    write_new(report / (label + '_submit_intent.json'), dict(visibility=visibility, unix=time.time()))
    # A missing callback is not a retry authorization. The caller queries state.
    try:
        call = steam.ug('SubmitItemUpdate', C.c_uint64, [C.c_uint64, C.c_char_p], handle, b'')
        response = steam.wait(call, sdk.Submitted, 3404, timeout=60)
        result = dict(result=response.result, item=str(response.item), legal=bool(response.legal))
    except Exception as error:
        result = dict(outcome='CALLBACK_UNKNOWN_NO_REPLAY', error_type=type(error).__name__)
    write_new(report / (label + '_callback.json'), result)
    return started, result


def early_restore(report, request_sha):
    path = report / 'restore_now.json'
    if not path.exists():
        return False
    value, _ = guard.read_json(path, limit=4096)
    return value == {'request_sha256': request_sha, 'restore_now': True}


def run(auth, report, request_sha):
    import steam_workshop_upload as sdk
    report = guard.regular(report)
    request, raw = guard.read_json(report / 'request.json')
    guard.need(guard.sha(raw) == guard.checked_sha(request_sha), 'exact_visibility_request_sha_required')
    validate_approval(request['approval'], auth.policy['workshop_id'])
    guard.need(not (report / 'intent.json').exists(), 'existing_visibility_intent_no_automatic_resubmit')
    request['request_sha256'] = request_sha
    with guard.visibility_test_lease(auth, request) as lease:
        write_new(report / 'intent.json', dict(request_sha256=request_sha,
                  generation=request['generation'], final_visibility=3))
        with sdk.Steam() as steam:
            before = {language: fresh_item(steam, auth.policy['workshop_id'], sdk, language,
                       timeout=30) for language in ('schinese', 'english')}
            write_new(report / 'before.json', before)
            guard.need(all(v['visibility'] == 3 for v in before.values()), 'initial_unlisted_state_required')
            started, public_result = update(steam, sdk, auth.policy['workshop_id'], 0, report, 'public')
            public = None
            test_error = None
            try:
                public = fresh_item(steam, auth.policy['workshop_id'], sdk, timeout=30)
                write_new(report / 'public.json', public)
                verify_snapshot(before['schinese'], public, 0)
            except Exception as error:
                test_error = type(error).__name__ + ':' + str(error)
                write_new(report / 'test_error.json', dict(error=test_error, restore_required=True))
        # SteamAPI_Shutdown runs before the observation window. The publication
        # lock/lease remains held; the client already exists before public submit.
        try:
            if test_error is None:
                print(json.dumps(dict(status='PUBLIC_VERIFIED_SDK_RELEASED_TEST_WINDOW',
                    restore_after_seconds=180, request_sha256=request_sha)), flush=True)
                while time.monotonic() - started < 180 and not early_restore(report, request_sha):
                    time.sleep(0.25)
        except Exception as error:
            test_error = type(error).__name__ + ':' + str(error)
            write_new(report / 'window_error.json', dict(error=test_error, restore_required=True))
        finally:
            lease.prepare_restore_attempt(public, query_attempted=True)
            with sdk.Steam() as steam:
                receipt = restore(steam, sdk, auth, report, request, request_sha, lease,
                                  before, started, public_result, test_error)
        return receipt


def restore(steam, sdk, auth, report, request, request_sha, lease, before, started,
            public_result, test_error):
    _, restore_result = update(steam, sdk, auth.policy['workshop_id'], 3, report, 'restore')
    after = {language: fresh_item(steam, auth.policy['workshop_id'], sdk, language,
             timeout=30) for language in ('schinese', 'english')}
    write_new(report / 'after.json', after)
    for language in after:
        verify_snapshot(before[language], after[language], 3)
    elapsed = time.monotonic() - started
    receipt = dict(status='VISIBILITY_TEST_RESTORED_UNLISTED', request_sha256=request_sha,
        final_visibility=3, public_to_verified_restore_seconds=elapsed,
        maximum_public_seconds=600,
        cumulative_public_seconds=request['authorization_budget']['public_seconds_before'] + elapsed,
        within_authorized_window=request['authorization_budget']['public_seconds_before'] + elapsed <= 600,
        authorization_closed=request['authorization_budget']['previous_receipt'] is not None,
        authorization_budget=request['authorization_budget'],
        public_callback=public_result, restore_callback=restore_result,
        test_error=test_error, release_sequence=request['release_sequence'],
        steam_manifest=request['steam_manifest'], source_revisions=request['source_revisions'],
        protected_fields_unchanged=True, content_upload_performed=False,
        canonical_package_journal_changed=False, backend_changed=False)
    write_new(report / 'verification.json', receipt)
    lease.finish_visibility_test(report / 'verification.json')
    return receipt
