"""Update only the approved original Workshop item's primary preview image.

Uses the project's pinned Steam SDK/account. Never sets content, title,
description, visibility, tags, or developer metadata. Default is read-only.
"""
from pathlib import Path
import argparse,ctypes as C,hashlib,json,struct,sys,urllib.request,urllib.parse
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import steam_workshop_upload as sdk

ITEM=3824360109
SHARED_JOURNAL=ROOT/'output/four_accounts_20261022/steam_upload_state.json'
STATE=ROOT/'output/workshop_cover_20261101/preview_state.json'
COVER=ROOT/'publishing/workshop/gou_fayu_workshop.jpg'
APPROVED_PREVIEW_SHA256='00714bb69b9c400231f88112673b2fd881d50680a0a76ab63a1792256b679aa1'
PROTECTED=('id','owner','creator','consumer','file_type','visibility','content_file','content_bytes',
           'total_files_bytes','title_description_sha256','tags','metadata_sha256')

def digest(raw): return hashlib.sha256(raw).hexdigest()

def image_facts(path):
    raw=path.read_bytes()
    if not 0<len(raw)<1_000_000: raise ValueError('preview_must_be_below_one_megabyte')
    # The exact JPEG was independently decoded/verified during preparation.
    # Pin its bytes rather than adding imaging dependencies to the SDK runtime.
    if digest(raw)!=APPROVED_PREVIEW_SHA256: raise ValueError('approved_preview_sha256_required')
    return {'sha256':digest(raw),'bytes':len(raw),'width':1672,'height':941}

def fresh_item(steam):
    ids=(C.c_uint64*1)(ITEM)
    query=steam.ug('CreateQueryUGCDetailsRequest',C.c_uint64,[C.POINTER(C.c_uint64),C.c_uint32],ids,1)
    if query in (0,sdk.INVALID): raise RuntimeError('invalid_preview_details_query')
    try:
        for name,types,args in [('SetAllowCachedResponse',[C.c_uint64,C.c_uint32],(query,0)),
                                ('SetReturnMetadata',[C.c_uint64,C.c_bool],(query,True)),
                                ('SetReturnLongDescription',[C.c_uint64,C.c_bool],(query,True))]:
            if not steam.ug(name,C.c_bool,types,*args): raise RuntimeError('preview_query_setting_rejected')
        call=steam.ug('SendQueryUGCRequest',C.c_uint64,[C.c_uint64],query)
        response=steam.wait(call,sdk.Queried,3401,timeout=90)
        if response.handle!=query or response.returned!=1 or response.cached: raise RuntimeError('fresh_single_item_required')
        raw=C.create_string_buffer(9784)
        if not steam.ug('GetQueryUGCResult',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p],query,0,raw):
            raise RuntimeError('preview_details_unavailable')
        data=raw.raw
        item,result,kind,creator,consumer=struct.unpack_from('<Qiiii',data)
        owner=str(struct.unpack_from('<Q',data,8160)[0])
        if (item,result,creator,consumer,owner)!=(ITEM,1,sdk.APP,sdk.APP,sdk.OWNER):
            raise RuntimeError('original_item_owner_or_application_mismatch')
        preview=C.create_string_buffer(4096);metadata=C.create_string_buffer(65536)
        if not steam.ug('GetQueryUGCPreviewURL',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p,C.c_uint32],query,0,preview,len(preview)):
            raise RuntimeError('preview_url_unavailable')
        if not steam.ug('GetQueryUGCMetadata',C.c_bool,[C.c_uint64,C.c_uint32,C.c_void_p,C.c_uint32],query,0,metadata,len(metadata)):
            raise RuntimeError('developer_metadata_unavailable')
        return {'id':str(item),'owner':owner,'creator':creator,'consumer':consumer,'file_type':kind,
            'visibility':struct.unpack_from('<i',data,8180)[0],
            'content_file':str(struct.unpack_from('<Q',data,9216)[0]),
            'content_bytes':struct.unpack_from('<I',data,9492)[0],
            'total_files_bytes':struct.unpack_from('<Q',data,9776)[0],
            'title_description_sha256':digest(data[24:8160]),
            'tags':data[8187:9212].split(b'\0')[0].decode('utf-8'),
            'metadata_sha256':digest(metadata.value),'preview_url':preview.value.decode('utf-8'),
            'time_updated':struct.unpack_from('<I',data,8172)[0]}
    finally:
        steam.ug('ReleaseQueryUGCRequest',C.c_bool,[C.c_uint64],query)

def submit_preview(steam,cover,state_path=STATE):
    facts=image_facts(cover)
    if state_path.exists():
        raise RuntimeError('existing_preview_request_requires_verification_not_resubmit')
    before=fresh_item(steam)
    if before['visibility']!=3: raise RuntimeError('original_unlisted_visibility_required')
    handle=steam.ug('StartItemUpdate',C.c_uint64,[C.c_uint32,C.c_uint64],sdk.APP,ITEM)
    if handle in (0,sdk.INVALID): raise RuntimeError('invalid_preview_update_handle')
    if not steam.ug('SetItemPreview',C.c_bool,[C.c_uint64,C.c_char_p],handle,str(cover.resolve()).encode('utf-8')):
        raise RuntimeError('preview_setter_rejected')
    state={'status':'SUBMIT_REQUEST_PENDING','item':str(ITEM),'preview':facts,'before':before,
           'mutating_setters':['SetItemPreview'],'content_upload_requested':False}
    sdk.journal(state_path,state)
    call=steam.ug('SubmitItemUpdate',C.c_uint64,[C.c_uint64,C.c_char_p],handle,b'')
    response=steam.wait(call,sdk.Submitted,3404,timeout=180)
    if response.item!=ITEM or response.legal: raise RuntimeError('unexpected_preview_submission_result')
    state.update(status='PREVIEW_SUBMITTED',submit_result=1)
    sdk.journal(state_path,state)
    after=fresh_item(steam);state['after']=after
    changed=[name for name in PROTECTED if before[name]!=after[name]]
    state['protected_fields_changed']=changed
    state['status']='PREVIEW_SUBMITTED_VERIFY_IMAGE' if not changed else 'PROTECTED_METADATA_CHANGED_REVIEW_REQUIRED'
    sdk.journal(state_path,state)
    if changed: raise RuntimeError('unexpected_workshop_content_or_metadata_change')
    return state

def download_preview(url):
    def approved(value):
        parts=urllib.parse.urlsplit(value)
        return parts.scheme=='https' and parts.hostname=='images.steamusercontent.com' and not parts.username and parts.port in (None,443)
    if not approved(url): raise ValueError('official_preview_cdn_required')
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url,timeout=20)as response:
        if response.status!=200 or not approved(response.geturl()): raise RuntimeError('preview_cdn_response_invalid')
        raw=response.read(1_000_001)
    if not 0<len(raw)<1_000_000: raise RuntimeError('remote_preview_size_invalid')
    return raw

def verify_preview(steam,state_path=STATE):
    state=json.loads(state_path.read_bytes())
    if state.get('item')!=str(ITEM) or state['preview']['sha256']!=APPROVED_PREVIEW_SHA256:
        raise ValueError('approved_preview_journal_required')
    current=fresh_item(steam)
    changed=[name for name in PROTECTED if state['before'][name]!=current[name]]
    if changed: raise RuntimeError('verification_protected_metadata_changed')
    raw=download_preview(current['preview_url'])
    if digest(raw)!=APPROVED_PREVIEW_SHA256 or len(raw)!=state['preview']['bytes']:
        raise RuntimeError('remote_preview_bytes_do_not_match_approved_image')
    (state_path.parent/'verified_remote_preview.jpg').write_bytes(raw)
    state.update(status='PREVIEW_VERIFIED_CDN',after=current,protected_fields_changed=[],
                 remote_preview_sha256=digest(raw),remote_preview_bytes=len(raw),remote_preview_verified=True)
    sdk.journal(state_path,state)
    return state

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--inspect',action='store_true')
    parser.add_argument('--verify',action='store_true')
    args=parser.parse_args()
    if sum([args.apply,args.inspect,args.verify])>1: parser.error('choose apply, inspect or verify')
    if args.inspect:
        with sdk.Steam()as steam: value={'status':'READ_ONLY_PREVIEW_INSPECTION','item':fresh_item(steam)}
    elif args.verify:
        with sdk.Steam()as steam: value=verify_preview(steam)
    elif not args.apply:
        value={'status':'READ_ONLY_PREVIEW_PLAN','item':str(ITEM),'preview':image_facts(COVER),
               'mutating_setters':['SetItemPreview'],'content_upload_requested':False}
    else:
        with sdk.publication_lock(SHARED_JOURNAL):
            journal=json.loads(SHARED_JOURNAL.read_bytes())
            if journal.get('status')=='SUBMIT_REQUEST_PENDING': raise RuntimeError('content_publication_pending')
            with sdk.Steam()as steam: value=submit_preview(steam,COVER)
    print(json.dumps(value,ensure_ascii=False),flush=True)
    return 0

if __name__=='__main__': raise SystemExit(main())
