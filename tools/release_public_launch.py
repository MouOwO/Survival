"""Permanent public launch through the common item-wide publication lease."""
from __future__ import annotations
import ctypes as C
import json
from pathlib import Path

from release_lineage_20261101 import guard
from release_packager.core import baseline, git, source_state, write_new
from release_description import fresh_item, PROTECTED, validate_text

APPROVAL = 'publishing/workshop/public_launch_approval_20261119.json'
TEXT = 'publishing/workshop/public_description_20261118.json'
OPERATORS = ('tools/release_pipeline.py', 'tools/release_public_launch.py',
             'tools/release_description.py', 'tools/release_lineage_20261101/guard.py',
             'tools/release_sdk_lineage_hook.py', 'tools/steam_workshop_upload.py',
             'tools/release_packager/core.py')
BACKEND_SOURCES = ('server/archive_backend/test_access.py', 'server/player_web_auth/service.py',
                   'server/player_web_auth/run.py', 'server/payment_backend/service.py',
                   'server/payment_backend/endpoints.py')


def proof(path, expected):
    path = guard.regular(path)
    value, raw = guard.read_json(path, limit=1024 * 1024)
    guard.need(guard.sha(raw) == guard.checked_sha(expected), 'launch_proof_changed')
    return value


def change_note(approval):
    text = validate_text({'schema': 1, 'workshop_id': '3824360109',
                          'description': approval.get('change_note')}, '3824360109')
    guard.need(text.startswith('正式开放：') and len(text.encode('utf8')) < 1000,
               'bounded_committed_public_launch_note_required')
    return text


def backend_source_matches(project, deployed, published):
    """Later compiler/operator commits may retain identical deployed backend bytes."""
    guard.require_ancestor(project, guard.revision(deployed), guard.revision(published))
    return all(git(project, 'show', deployed + ':' + path)
               == git(project, 'show', published + ':' + path) for path in BACKEND_SOURCES)


def validate_request(auth, request, current):
    project = Path(auth.policy['repositories']['game'])
    source = guard.revision(request['source_revisions']['game'])
    guard.need(git(project, 'rev-parse', 'HEAD').decode().strip() == source,
               'current_committed_public_launch_source_required')
    for relative in (*OPERATORS, APPROVAL, TEXT):
        guard.need((project / relative).read_bytes() == git(project, 'show', source + ':' + relative),
                   'uncommitted_public_launch_operator:' + relative)
    approval = json.loads(git(project, 'show', source + ':' + APPROVAL))
    guard.need(approval == request['approval'] and approval['workshop_id'] == '3824360109'
               and approval['authorization_statement'] == '伐木工问题已解决，现在可以直接上线了'
               and approval['financial_scope_answer'] == '保留已支付余额和权益，仅重置玩法进度'
               and approval['initial_visibility'] == 3 and approval['final_visibility'] == 0
               and approval['keep_steam_verification'] is True,
               'explicit_permanent_public_launch_authorization_required')
    change_note(approval)
    guard.need(request['operator_files'] == list(OPERATORS), 'complete_public_launch_operator_binding_required')
    guard.need(git(auth.policy['repositories']['content'], 'rev-parse', 'HEAD').decode().strip()
               == request['source_revisions']['content'], 'public_launch_content_source_changed')
    sources = source_state(project, current['baseline'])
    guard.need(not sources['pending_sources'] and not sources['dirty_runtime']
               and current['report'].get('public_admission_enabled') is True,
               'fully_delivered_public_admission_runtime_required')
    backend = proof(**request['proofs']['backend'])
    guard.need(backend.get('status') == 'PUBLIC_BACKEND_ACTIVE_PAID_PRESERVED'
               and backend.get('host') == '47.111.16.128' and backend.get('database') == 'goufayu_ws4'
               and backend.get('public_admission') == {'api': True, 'web': True, 'payment': True}
               and backend_source_matches(project, backend.get('source_revision'),
                                          current['report']['source_revisions']['game'])
               and all(backend.get(key) is True for key in ('financial_history_preserved',
                   'paid_inventory_preserved', 'balances_preserved', 'full_backup_verified',
                   'old_auth_revoked', 'fresh_health_verified')),
               'verified_public_backend_and_paid_preserving_reset_required')
    build = proof(**request['proofs']['launcher_build'])
    acceptance = proof(**request['proofs']['launcher_acceptance'])
    https = proof(**request['proofs']['launcher_https'])
    binding = build['binding']
    guard.need(binding.get('access_mode') == 'public'
               and binding['release_sequence'] == request['release_sequence']
               and binding['steam_manifest'] == request['steam_manifest']
               and binding['package_files'] == current['report']['package_files']
               and acceptance.get('exe_sha256') == build['exe_sha256']
               and acceptance.get('release_sequence') == request['release_sequence']
               and acceptance.get('steam_manifest') == request['steam_manifest']
               and all(acceptance.get(key) is True for key in ('helper_ready_observed',
                   'user_confirmed_entered_game', 'current_client_ingame_visually_observed'))
               and https.get('status') == 'PUBLIC_LAUNCHER_HTTPS_VERIFIED'
               and https.get('exe_sha256') == build['exe_sha256']
               and https.get('all_files_verified') is True,
               'compatible_actual_exe_and_public_https_required')
    text = validate_text(json.loads(git(project, 'show', source + ':' + TEXT)), auth.policy['workshop_id'])
    guard.need('现已开放' in text and '本轮测试资格' not in text and '计划于' not in text,
               'current_public_launch_description_required')
    return text


def plan(auth, source, report, proofs):
    project = Path(auth.policy['repositories']['game'])
    current = baseline(project)
    request = dict(schema=1, kind='PERMANENT_PUBLIC_LAUNCH', authority_sha256=auth.digest,
        parent_journal_sha256=current['journal_sha256'], generation=current['lineage']['generation'] + 1,
        release_sequence=current['baseline']['parent_sequence'],
        steam_manifest=current['baseline']['official_parent_manifest'],
        baseline_sha256=current['cursor']['baseline_sha256'],
        source_revisions={'game': source, 'content': git(auth.policy['repositories']['content'],
                          'rev-parse', 'HEAD').decode().strip()},
        approval=json.loads((project / APPROVAL).read_bytes()), operator_files=list(OPERATORS),
        proofs={name: {'path': str(Path(path).resolve()), 'expected': guard.sha(Path(path).read_bytes())}
                for name, path in proofs.items()})
    guard.need(set(proofs) == {'backend', 'launcher_build', 'launcher_acceptance', 'launcher_https'},
               'complete_public_launch_proofs_required')
    validate_request(auth, request, current)
    report = guard.regular(report)
    report.mkdir(parents=True, exist_ok=False)
    write_new(report / 'request.json', request)
    return dict(status='PUBLIC_LAUNCH_PLAN_NO_SDK', request=str(report / 'request.json'),
                request_sha256=guard.sha((report / 'request.json').read_bytes()))


def verify_snapshot(before, after):
    guard.need(after['visibility'] == 0 and all(before[key] == after[key]
               for key in (*PROTECTED, 'description') if key != 'visibility'),
               'public_visibility_or_protected_metadata_not_verified')


def run(auth, report, request_sha):
    import steam_workshop_upload as sdk
    report = guard.regular(report)
    request, raw = guard.read_json(report / 'request.json')
    guard.need(guard.sha(raw) == guard.checked_sha(request_sha), 'exact_public_launch_request_sha_required')
    guard.need(not (report / 'intent.json').exists(), 'existing_launch_intent_no_automatic_resubmit')
    request['request_sha256'] = request_sha
    with guard.public_launch_lease(auth, request) as lease:
        write_new(report / 'intent.json', dict(request_sha256=request_sha, final_visibility=0))
        text = validate_text(json.loads((Path(auth.policy['repositories']['game']) / TEXT).read_bytes()),
                             auth.policy['workshop_id'])
        with sdk.Steam() as steam:
            before = {language: fresh_item(steam, auth.policy['workshop_id'], sdk, language)
                      for language in ('schinese', 'english')}
            write_new(report / 'before.json', before)
            guard.need(all(row['visibility'] == 3 and row['description'] == text for row in before.values()),
                       'verified_unlisted_launch_copy_required_before_public')
            handle = steam.ug('StartItemUpdate', C.c_uint64, [C.c_uint32, C.c_uint64],
                               sdk.APP, int(auth.policy['workshop_id']))
            guard.need(steam.ug('SetItemVisibility', C.c_bool, [C.c_uint64, C.c_int], handle, 0),
                       'public_visibility_setter_rejected')
            try:
                call = steam.ug('SubmitItemUpdate', C.c_uint64, [C.c_uint64, C.c_char_p],
                                 handle, change_note(request['approval']).encode('utf8'))
                response = steam.wait(call, sdk.Submitted, 3404, timeout=60)
                callback = dict(result=response.result, item=str(response.item), legal=bool(response.legal))
            except Exception as error:
                callback = dict(outcome='UNKNOWN_NO_REPLAY', error_type=type(error).__name__)
            write_new(report / 'callback.json', callback)
            guard.need(callback.get('legal') is not True, 'steam_legal_acceptance_required')
            after = {language: fresh_item(steam, auth.policy['workshop_id'], sdk, language)
                     for language in ('schinese', 'english')}
            write_new(report / 'after.json', after)
            for language in before:
                verify_snapshot(before[language], after[language])
        receipt = dict(status='PUBLIC_LAUNCH_VERIFIED_OFFICIAL', artifact_root=str(report),
                       request_sha256=request_sha, release_sequence=request['release_sequence'],
                       steam_manifest=request['steam_manifest'], final_visibility=0,
                       callback=callback, both_languages_verified=True, package_bytes_changed=False)
        write_new(report / 'receipt.json', receipt)
        lease.finish_public_launch(report / 'receipt.json')
        return receipt
