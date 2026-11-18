"""Publish only committed Workshop description text through the common SDK lease."""
from __future__ import annotations
import ctypes as C
import hashlib
import json
from pathlib import Path
import struct

from release_lineage_20261101 import guard
from release_packager.core import baseline, canonical, git, read, write_new

TEXT = 'publishing/workshop/public_description_20261118.json'
OPERATORS = ('tools/release_pipeline.py', 'tools/release_description.py',
             'tools/release_lineage_20261101/guard.py', 'tools/release_sdk_lineage_hook.py',
             'tools/steam_workshop_upload.py', 'tools/release_packager/core.py')
PROTECTED = ('item', 'owner', 'creator', 'consumer', 'kind', 'title', 'visibility',
             'content_file', 'content_bytes', 'total_files_bytes', 'tags',
             'metadata_sha256', 'preview_url')


def validate_text(value, item):
    guard.need(set(value) == {'schema', 'workshop_id', 'description'}
               and value['schema'] == 1 and value['workshop_id'] == item,
               'fixed_description_document_required')
    text = value['description']
    guard.need(isinstance(text, str) and 0 < len(text.encode('utf8')) < 8000
               and '\0' not in text and '官方 QQ 玩家群：1098603739' in text
               and not any(word in text for word in ('付费', '支付', '收费', '充值', '退款', '问题反馈')),
               'reviewed_public_description_required')
    return text


def plan(auth, source, report):
    project = Path(auth.policy['repositories']['game'])
    current = baseline(project)
    guard.revision(source)
    guard.need(git(project, 'rev-parse', 'HEAD').decode().strip() == source,
               'current_committed_description_source_required')
    raw = git(project, 'show', source + ':' + TEXT)
    guard.need((project / TEXT).read_bytes() == raw, 'uncommitted_description_refused')
    description = validate_text(json.loads(raw), auth.policy['workshop_id'])
    for relative in OPERATORS:
        guard.need((project / relative).read_bytes() == git(project, 'show', source + ':' + relative),
                   'uncommitted_description_operator:' + relative)
    request = dict(schema=1, kind='COMMITTED_DESCRIPTION_ONLY',
                   authority_sha256=auth.digest,
                   parent_journal_sha256=current['journal_sha256'],
                   generation=current['lineage']['generation'] + 1,
                   release_sequence=current['baseline']['parent_sequence'],
                   steam_manifest=current['baseline']['official_parent_manifest'],
                   baseline_sha256=current['cursor']['baseline_sha256'],
                   source_revisions={'game': source, 'content': git(
                       auth.policy['repositories']['content'], 'rev-parse', 'HEAD').decode().strip()},
                   operator_files=list(OPERATORS), description=description,
                   description_sha256=guard.sha(description.encode('utf8')),
                   description_source_sha256=guard.sha(raw))
    report = guard.regular(report)
    report.mkdir(parents=True, exist_ok=False)
    write_new(report / 'request.json', request)
    return dict(status='DESCRIPTION_PLAN_NO_SDK', request=str(report / 'request.json'),
                request_sha256=guard.sha((report / 'request.json').read_bytes()),
                description=description, release_sequence=request['release_sequence'])


def fresh_item(steam, item, sdk):
    ids = (C.c_uint64 * 1)(int(item))
    query = steam.ug('CreateQueryUGCDetailsRequest', C.c_uint64,
                     [C.POINTER(C.c_uint64), C.c_uint32], ids, 1)
    guard.need(query not in (0, sdk.INVALID), 'valid_description_query_required')
    try:
        for name, types, argument in (
                ('SetAllowCachedResponse', [C.c_uint64, C.c_uint32], 0),
                ('SetReturnMetadata', [C.c_uint64, C.c_bool], True),
                ('SetReturnLongDescription', [C.c_uint64, C.c_bool], True)):
            guard.need(steam.ug(name, C.c_bool, types, query, argument), 'description_query_setting_rejected')
        call = steam.ug('SendQueryUGCRequest', C.c_uint64, [C.c_uint64], query)
        response = steam.wait(call, sdk.Queried, 3401, timeout=90)
        guard.need(response.result == 1 and response.handle == query and response.returned == 1
                   and not response.cached, 'fresh_official_description_query_required')
        raw = C.create_string_buffer(9784)
        guard.need(steam.ug('GetQueryUGCResult', C.c_bool,
                           [C.c_uint64, C.c_uint32, C.c_void_p], query, 0, raw), 'description_result_missing')
        data = raw.raw
        item_id, result, kind, creator, consumer = struct.unpack_from('<Qiiii', data)
        owner = str(struct.unpack_from('<Q', data, 8160)[0])
        guard.need((str(item_id), result, creator, consumer, owner)
                   == (item, 1, sdk.APP, sdk.APP, sdk.OWNER), 'original_item_identity_required')
        metadata = C.create_string_buffer(65536)
        preview = C.create_string_buffer(4096)
        guard.need(steam.ug('GetQueryUGCMetadata', C.c_bool,
                           [C.c_uint64, C.c_uint32, C.c_void_p, C.c_uint32],
                           query, 0, metadata, len(metadata)), 'description_metadata_query_failed')
        guard.need(steam.ug('GetQueryUGCPreviewURL', C.c_bool,
                           [C.c_uint64, C.c_uint32, C.c_void_p, C.c_uint32],
                           query, 0, preview, len(preview)), 'description_preview_query_failed')
        return dict(item=str(item_id), owner=owner, creator=creator, consumer=consumer, kind=kind,
                    title=data[24:153].split(b'\0')[0].decode('utf8'),
                    description=data[153:8153].split(b'\0')[0].decode('utf8'),
                    visibility=struct.unpack_from('<i', data, 8180)[0],
                    content_file=str(struct.unpack_from('<Q', data, 9216)[0]),
                    content_bytes=struct.unpack_from('<I', data, 9492)[0],
                    total_files_bytes=struct.unpack_from('<Q', data, 9776)[0],
                    tags=data[8187:9212].split(b'\0')[0].decode('utf8'),
                    metadata_sha256=guard.sha(metadata.value), preview_url=preview.value.decode('utf8'),
                    time_updated=struct.unpack_from('<I', data, 8172)[0])
    finally:
        steam.ug('ReleaseQueryUGCRequest', C.c_bool, [C.c_uint64], query)


def verify_snapshots(before, after, description):
    guard.need(after['description'] == description, 'official_description_differs_from_committed_text')
    guard.need(all(before[key] == after[key] for key in PROTECTED),
               'description_update_changed_protected_fields')


def publish(auth, report, request_sha):
    import steam_workshop_upload as sdk
    report = guard.regular(report)
    path = report / 'request.json'
    request, raw = guard.read_json(path)
    guard.need(guard.sha(raw) == guard.checked_sha(request_sha), 'exact_description_request_sha_required')
    guard.need(request.get('operator_files') == list(OPERATORS), 'complete_description_operator_binding_required')
    validate_text({'schema': 1, 'workshop_id': auth.policy['workshop_id'],
                   'description': request['description']}, auth.policy['workshop_id'])
    guard.need(not (report / 'intent.json').exists(), 'existing_description_intent_requires_verification_not_resubmit')
    with guard.description_lease(auth, request) as lease:
        write_new(report / 'intent.json', {'request_sha256': request_sha, 'kind': 'DESCRIPTION_ONLY',
                                          'generation': request['generation']})
        with sdk.Steam() as steam:
            before = fresh_item(steam, auth.policy['workshop_id'], sdk)
            write_new(report / 'before.json', before)
            guard.need(before['visibility'] == 3, 'preserve_original_unlisted_item_required')
            handle = steam.ug('StartItemUpdate', C.c_uint64, [C.c_uint32, C.c_uint64],
                              sdk.APP, int(auth.policy['workshop_id']))
            guard.need(steam.ug('SetItemDescription', C.c_bool, [C.c_uint64, C.c_char_p],
                               handle, request['description'].encode('utf8')), 'description_setter_rejected')
            call = steam.ug('SubmitItemUpdate', C.c_uint64, [C.c_uint64, C.c_char_p], handle, b'')
            response = steam.wait(call, sdk.Submitted, 3404, timeout=180)
            guard.need(response.result == 1 and str(response.item) == auth.policy['workshop_id']
                       and not response.legal, 'successful_description_sdk_receipt_required')
            write_new(report / 'submitted.json', {'submit_result': response.result, 'item': str(response.item)})
            after = fresh_item(steam, auth.policy['workshop_id'], sdk)
            write_new(report / 'after.json', after)
            verify_snapshots(before, after, request['description'])
        receipt = dict(status='DESCRIPTION_VERIFIED_OFFICIAL', submit_result=1,
                       workshop_id=auth.policy['workshop_id'], description_sha256=request['description_sha256'],
                       request_sha256=request_sha, source_revisions=request['source_revisions'],
                       release_sequence=request['release_sequence'], steam_manifest=request['steam_manifest'],
                       protected_fields_unchanged=list(PROTECTED), content_upload_performed=False,
                       canonical_package_journal_changed=False)
        write_new(report / 'verification.json', receipt)
        lease.finish_description(receipt, report / 'verification.json')
        return receipt
