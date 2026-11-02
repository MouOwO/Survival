"""Independent authenticated0104 plus four lottery/training UI replacements.

Default/--static-plan is pure static output, without OS/Git/key/SDK or writes.
--scope reads the worktree only and is never a release plan. A final plan or
unsigned review requires an explicit immutable source commit. --build is a
separate, future explicit operation requiring a reviewed-plan SHA and an
existing external key; it never uploads, deploys, installs or starts Dota.
"""
from collections import Counter
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = next((p for p in Path(__file__).resolve().parents if (p/'tools/shared_boss_portrait_release_20261101/source_baseline_0104.json').is_file()),None)
if ROOT is None: raise ValueError('Fixed project root unavailable')


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


parent = module('portrait_perf_v03_parent3102', ROOT/'tools/shop_recovery_20261031/build_release.py')
# release_checks has a historical bare import. Bind its exact frozen dependency
# only while loading it, preserving this tool's own build_release import name.
_prior = sys.modules.get('build_release')
sys.modules['build_release'] = parent
try:
    parent_checks = module('portrait_perf_v03_parent3102_checks', ROOT/'tools/shop_recovery_20261031/release_checks.py')
finally:
    if _prior is None: sys.modules.pop('build_release', None)
    else: sys.modules['build_release'] = _prior

five=module('shared_boss_v08_frozen_five0104',ROOT/'tools/admission_five_20261101/build_release.py')
_previous=sys.modules.get('build_release');sys.modules['build_release']=five
try:
    five_checks=module('shared_boss_v08_five0104_checks',ROOT/'tools/admission_five_20261101/release_checks.py')
finally:
    if _previous is None:sys.modules.pop('build_release',None)
    else:sys.modules['build_release']=_previous
APPROVED=tuple(five.APPROVED)
ADMISSION_PATHS=tuple(five.PAYLOADS)

inc, pack, need = parent.inc, parent.pack, parent.need
BASE_REPORT = ROOT/'output/admission_five_20261101/package.json'
BASE_REPORT_SHA = '70306be7a42962172fddce88bc8c4ac12dc5e73db1119d97839b871115aa01b6'
BASE_RECORD = ROOT/'publishing/workshop/account_admission_20261101_v01.json'
BASE_RECORD_SHA = '663ae83f0cb138fdde2baf4af05b48af14edc496aab0308a51c3f8abfd3b88a4'
BASE_CONTENT = '6ffc0816d040ffe4a4d7a3db472c74dc18b96fad36f5f204cba5b0879ab5489f'
BASE, BASE_TRUSTED = five.VIEW, five.TRUSTED
BASE_VPK = five.OUTPUT/(five.ITEM+'.vpk')
JOURNAL = parent.parent.JOURNAL
ITEM, BASE_SEQUENCE, SEQUENCE = '3824360109', 2026110104, 2026110202
REVISION = 'WS4-LOTTERY-HOTFIX-02'
PREFIX = '20261102_ws4_lottery_hotfix_v09'
OVERLAY = Path('D:/Survival_发布候选')/(PREFIX+'_overlay')
VIEW = Path('D:/Survival_发布候选')/(PREFIX+'_view')
TRUSTED = Path('D:/Survival_发布候选')/(PREFIX+'_trusted_source')
UNSIGNED = Path('D:/Survival_发布候选')/(PREFIX+'_unsigned_review')
OUTPUT = Path('D:/Survival_工坊输出')/PREFIX
REPORT = ROOT/'output/lottery_hotfix_release_20261102'
_V01_PREFIX='20261101_ws4_portrait_perf_teleport_v01'
FROZEN_V01_OUTPUTS=(
    *(Path('D:/Survival_发布候选')/(_V01_PREFIX+suffix) for suffix in
      ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/_V01_PREFIX,
)
FROZEN_V02_OUTPUTS=(
    *(Path('D:/Survival_发布候选')/('20261101_ws4_portrait_perf_teleport_v02'+suffix) for suffix in
      ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261101_ws4_portrait_perf_teleport_v02',
)
FROZEN_V03_OUTPUTS=(
    *(Path('D:/Survival_发布候选')/('20261101_ws4_portrait_perf_teleport_snapshot_v03'+suffix) for suffix in
      ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261101_ws4_portrait_perf_teleport_snapshot_v03',
)
FROZEN_V05_OUTPUTS=(
    *(Path('D:/Survival_发布候选')/('20261101_ws4_portrait_perf_five_v05'+suffix) for suffix in
      ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261101_ws4_portrait_perf_five_v05',
)
FROZEN_V06_OUTPUTS=(
    *(Path('D:/Survival_发布候选')/('20261101_ws4_portrait_perf_five_v06'+suffix) for suffix in
      ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261101_ws4_portrait_perf_five_v06',
)
FROZEN_V07_OUTPUTS=tuple([*(Path('D:/Survival_发布候选')/('20261101_ws4_shared_boss_portrait_v07'+s) for s in ('_overlay','_view','_trusted_source','_unsigned_review')),Path('D:/Survival_工坊输出')/'20261101_ws4_shared_boss_portrait_v07'])
FROZEN_V08_OUTPUTS=tuple([*(Path('D:/Survival_发布候选')/('20261102_ws4_shared_boss_portrait_v08'+x) for x in ('_overlay','_view','_trusted_source','_unsigned_review')),Path('D:/Survival_工坊输出')/'20261102_ws4_shared_boss_portrait_v08'])
NATIVE_ADDON = 'svt_lf0202'
MODE='scripts/vscripts/config/mode_release_config.lua'
BUNDLE=parent.parent.BUNDLE
EXPECTED_BUNDLE=parent.parent.EXPECTED_BUNDLE
PAYLOADS=('panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c', 'panorama/styles/custom_game/lottery_cinematic_v1.vcss_c', 'scripts/vscripts/ui/production_ui_service.lua', 'scripts/vscripts/ui/ui_request_router.lua')
ADDED_RUNTIME_PATHS=()
COMPILED={'panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c': {'source': 'panorama/src/scripts/custom_game/lottery_cinematic_v1.js', 'content_source': 'panorama/scripts/custom_game/lottery_cinematic_v1.js', 'source_git_sha256': 'f817d8b1e66c1c73b0b55dcdd8252ed567b64de886a812aecb3d9bc3f64a0816', 'source_sha256': 'a20d60e165e7e8e3f2f61031e3a99e390ba70cee0483094181e2120a88bdf8ea', 'source_normalization': 'GIT_LF_TO_COMPILER_CRLF_ONLY', 'compiled_sha256': 'f0b89bcb3c8abb82b962c5e1e2e6b944e5ea7d85749397429f95d117a3d20d23'}, 'panorama/styles/custom_game/lottery_cinematic_v1.vcss_c': {'source': 'panorama/src/styles/custom_game/lottery_cinematic_v1.css', 'content_source': 'panorama/styles/custom_game/lottery_cinematic_v1.css', 'source_git_sha256': '75f0597e8cd6a97f356633a06b3e71e46d8ac5ea858000564c5afe8fa9f48c57', 'source_sha256': 'b9cb926cf5a9f951e27cdf98a0485745aafc459e78d6e374c9e9ee69ebac8a35', 'source_normalization': 'GIT_LF_TO_COMPILER_CRLF_ONLY', 'compiled_sha256': '691c18f7f061ea6c04d56a1984d6ebe39043c1cf05e01402a826ce8611b50024'}}
TRAINING_SOURCE_PINS={'scripts/vscripts/ui/production_ui_service.lua': '7ee4ac210eae16108ed19995b83498f34a42ac43dd82805c859689f2f123f1d4', 'scripts/vscripts/ui/ui_request_router.lua': 'e5e30c37537db9b8512ccc142170fc7f6691adadaf291b62fc6647fbf1cf3529'}
ADDITIONAL_SOURCE_REVIEWS=PAYLOADS[2:]
AUXILIARY_INPUTS = (
    'tools/lottery_hotfix_release_20261102/build_release.py',
    'tools/lottery_hotfix_release_20261102/release_checks.py',
    'tools/shared_boss_portrait_release_20261101/git_export.py',
    'tools/shared_boss_portrait_release_20261101/historical_parent.py',
    'tools/shared_boss_portrait_release_20261101/ledger.py',
    'tools/lottery_hotfix_release_20261102/ledger.py',
    'tools/portrait_resolution_release_20261102/build_release.py',
    'tools/shared_boss_portrait_release_20261101/source_baseline_0104.json',
    'tools/lottery_hotfix_release_20261102/validator.py',
    'tools/lottery_hotfix_release_20261102/native_admission.py',
    'tools/lottery_hotfix_release_20261102/rehearsal.py',
    'tools/lottery_hotfix_release_20261102/verify_download.py',
    'tools/arcade_portrait_release_20261031/publish.py',
    'tools/arcade_portrait_release_20261031/build_release.py',
    'tools/arcade_portrait_release_20261031/release_checks.py',
    'tools/arcade_portrait_release_v02_20261101/rehearsal.py',
    'tools/arcade_portrait_release_v02_20261101/build_release.py',
    'tools/arcade_portrait_release_v02_20261101/release_checks.py',
    'tools/arcade_portrait_release_v03_20261101/rehearsal_v03.py',
    'tools/arcade_portrait_release_v03_20261101/rehearsal_v04.py',
    'tools/map_c6/console-session.cjs',
    'tools/map_c6/console.cjs',
    'tools/release_sdk_lineage_hook.py',
    'tools/release_pipeline.py',
    'tools/release_lineage_20261101/guard.py',
    'publishing/workshop/release_authority_20261102.json',
    'publishing/workshop/release_listing_template_20261101.json',
    'publishing/workshop/gou_fayu_workshop.jpg',
    'tools/shop_recovery_20261031/build_release.py',
    'tools/shop_recovery_20261031/release_checks.py',
    *five.AUXILIARY_INPUTS,
)
AUXILIARY_INPUTS=tuple(dict.fromkeys(AUXILIARY_INPUTS))
sha = lambda raw: hashlib.sha256(raw).hexdigest()
load = parent.load
checks = parent.checks
@contextmanager
def scene_maps():
    # Five-account admission applies only inside this candidate's checks. The
    # 0104 parent validator nests its frozen four-account3102 context correctly.
    values={name:(BASE/name).read_bytes() for name in ADMISSION_PATHS}
    with five.scene_maps(),five.admission_context(values):yield


def preserved_admission(old,after):
    before={row['path']:row for row in old['files']};rows={row['path']:row for row in after['files']}
    need(not set(ADMISSION_PATHS).intersection(PAYLOADS),'Portrait scope must never overlap six admission resources')
    need(all(name in before and rows.get(name)==before[name] for name in ADMISSION_PATHS),
        'All six five-account admission manifest rows must remain exact')
    return {name:dict(before[name]) for name in ADMISSION_PATHS}

git_export = module('shared_boss_v08_git_export',ROOT/'tools/shared_boss_portrait_release_20261101/git_export.py')
historical_parent = module('shared_boss_v08_historical_parent',ROOT/'tools/shared_boss_portrait_release_20261101/historical_parent.py')
ledger = module('lottery_hotfix_resource_ledger',ROOT/'tools/lottery_hotfix_release_20261102/ledger.py')


def blob_at(repository,revision,path):
    need(re.fullmatch('[a-f0-9]{40}',revision or '') is not None,'Explicit immutable source commit required')
    need(pack.runtime.safe_relative(path),'Safe immutable source-relative path required')
    result=subprocess.run(['git','-c','safe.directory='+Path(repository).resolve().as_posix(),
        '--no-replace-objects','-C',str(repository),'show',revision+':'+path],
        capture_output=True,timeout=30)
    need(result.returncode==0 and len(result.stdout)<=16*1024*1024,'Cannot read bounded immutable source input')
    return result.stdout


def blob(revision,path):
    raw=blob_at(ROOT,revision,path)
    if raw.startswith(b'version https://git-lfs.github.com/spec/v1\n'):
        pointer=re.fullmatch(rb'version https://git-lfs.github.com/spec/v1\noid sha256:([a-f0-9]{64})\nsize ([0-9]+)\n',raw)
        need(pointer is not None,'Malformed immutable LFS source pointer')
        resolved=pack.protect_data.source_path(ROOT,path).read_bytes()
        need(sha(resolved)==pointer[1].decode() and len(resolved)==int(pointer[2]),
            'Resolved LFS payload differs from immutable Git source pointer')
        return resolved
    return raw


def immutable_revision(value):
    need(re.fullmatch(r'[a-f0-9]{40}', value or '') is not None, 'Explicit immutable40 source revision required')
    result=subprocess.run(['git','--no-replace-objects','-C',str(ROOT),'rev-parse','--verify',value+'^{commit}'],
        capture_output=True,timeout=30)
    need(result.returncode==0 and result.stdout.strip()==value.encode('ascii'),'Source commit identity differs')
    return value


def require_parent_journal(state,report):
    need(state.get('uploaded') is True and state.get('workshop_id') == ITEM
        and state.get('status') == 'SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST'
        and state.get('owner') == '76561198845461206' and state.get('app_id') == 570
        and state.get('visibility_requested') == 3 and state.get('release_sequence') == BASE_SEQUENCE
        and state.get('content_sha256') == BASE_CONTENT and state.get('package_files') == report['package_files']
        and state.get('vpk_sha256') == report['vpk_sha256']
        and state.get('vpk_bytes') == report['package_files'][0]['bytes']
        and state.get('legal_agreement_required') is False,
        'Canonical journal is not the successful0104 parent; preserve unknown/pending state')


def baseline(*, full=False, require_current_journal=True):
    report, manifest, signed = historical_parent.validate(SimpleNamespace(**globals()),full=full)
    need(pack.runtime.digest(BASE_RECORD) == BASE_RECORD_SHA, 'Frozen0104 delivery record changed')
    record = load(BASE_RECORD)
    need(record['status'] == 'UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED'
        and record['release_sequence'] == BASE_SEQUENCE and record['content_sha256'] == BASE_CONTENT
        and record['runtime_files'] == 6917 and record['protected_modules'] == 184
        and record['steam_manifest'] == '7025356658517360342' and record['visibility'] == 'unlisted'
        and record['package_files'] == report['package_files'], 'Officially verified0104 baseline required')
    need(record['approved_accounts']==5 and record['max_players']==4
        and sorted(record['approved_steamids64'])==sorted(APPROVED),'Exact officially approved five-account parent required')
    with scene_maps():need(pack.handoff.configured_ids(BASE)==sorted(APPROVED),'Exact signed five-account parent roster required')
    receipt_path = ROOT/record['download_receipt']['path']
    need(pack.runtime.digest(receipt_path) == record['download_receipt']['sha256'], 'Official3102 receipt changed')
    receipt = load(receipt_path)
    need(receipt['status'] == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
        and receipt['content_sha256'] == BASE_CONTENT and receipt['release_sequence'] == BASE_SEQUENCE
        and receipt['steam_manifest'] == record['steam_manifest'] and receipt['signed_resources_verified'] == 6917
        and receipt['protected_modules_verified'] == 184 and receipt['verification']['signature_valid']
        and receipt['verification']['package_files'] == report['package_files'], 'Complete official0104 verification required')
    need(manifest['content_sha256'] == BASE_CONTENT and manifest['file_count'] == 6917
        and signed['release_sequence'] == BASE_SEQUENCE, 'Signed0104 identity differs')
    if require_current_journal:
        require_parent_journal(load(JOURNAL),report)
    need(re.search(rb'(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$', (BASE/MODE).read_bytes()),
        '0104 normal online default must remain false')
    # archive_http_bundle is an already protected generated module. Its literal
    # strings need not survive protection; bind its exact signed bytes instead.
    bundle_row=next(row for row in manifest['files'] if row['path']==BUNDLE)
    need(report['archive_bundle_hash']==EXPECTED_BUNDLE
        and checks((BASE/BUNDLE).read_bytes())=={key:bundle_row[key] for key in ('bytes','md5','sha256')},
        'Frozen protected d573 bundle differs')
    return report, manifest


def compiled_pins_ready():
    need(set(COMPILED)==set(PAYLOADS[:2]) and len({p['source'] for p in COMPILED.values()})==2,'Exactly two compiler bindings required')
    for pin in COMPILED.values():
        need(all(re.fullmatch('[a-f0-9]{64}',pin.get(k) or '') for k in ('source_git_sha256','source_sha256','compiled_sha256')),'PENDING_OFFICIAL_COMPILER_PROOF')
        need(pin['source_normalization'] in ('IDENTITY','GIT_LF_TO_COMPILER_CRLF_ONLY'),'Reviewed compiler normalization required')


def compiled_source_pin(pin, committed):
    need(all(re.fullmatch(r'[a-f0-9]{64}',pin.get(key) or '') is not None for key in
        ('source_git_sha256','source_sha256','compiled_sha256')),'PENDING_OFFICIAL_COMPILER_PROOF')
    need(sha(committed)==pin['source_git_sha256'], 'Reviewed Git UI source differs: '+pin['source'])
    normalization=pin['source_normalization']
    if normalization=='GIT_LF_TO_COMPILER_CRLF_ONLY':
        # text eol=crlf controls checkout bytes; Git still stores the LF blob.
        # This is the only admitted conversion, never a whitespace/text rewrite.
        need(b'\r' not in committed, 'Git UI blob must contain LF only before CRLF reconstruction')
        compiler_input=committed.replace(b'\n',b'\r\n')
    else:
        need(normalization=='IDENTITY', 'Unreviewed UI source normalization')
        compiler_input=committed
    need(sha(compiler_input)==pin['source_sha256'], 'Reviewed official compiler input differs: '+pin['source'])
    return dict(git_blob=checks(committed),compiler_input=checks(compiler_input),normalization=normalization,
        compiled_artifact_sha256=pin['compiled_sha256'])


def payloads(revision,*,source_bindings=None):
    revision=immutable_revision(revision);compiled_pins_ready()
    values={name:blob(revision,name) for name in PAYLOADS}
    for name,pin in COMPILED.items():
        need(sha(values[name])==pin['compiled_sha256'],'Reviewed artifact differs: '+name)
        binding=compiled_source_pin(pin,blob(revision,pin['source']))
        if source_bindings is not None:source_bindings[pin['source']]=binding
    need(set(TRAINING_SOURCE_PINS)==set(ADDITIONAL_SOURCE_REVIEWS) and all(sha(values[n])==v for n,v in TRAINING_SOURCE_PINS.items()),'Training UI source review differs')
    need(all(values.values()),'Empty scoped payload')
    return revision,values


def projected(old, values):
    # Preserve unknown manifest and per-row fields. Recompute every derived
    # count we own, including the advisory by_directory field omitted by older
    # thin builders; only manifest_payload fields define the content identity.
    rows = {row['path']:copy.deepcopy(row) for row in old['files']}
    changed = {name:raw for name,raw in values.items() if name not in rows or sha(raw) != rows[name]['sha256']}
    for name,raw in changed.items(): rows[name] = {**rows.get(name,{}), 'path':name, **checks(raw)}
    result = copy.deepcopy(old)
    result.update(files=[rows[name] for name in sorted(rows)], file_count=len(rows),
        bytes=sum(row['bytes'] for row in rows.values()),
        by_directory=dict(sorted(Counter(name.split('/')[0] for name in rows).items())))
    result['content_sha256'] = sha(pack.runtime.manifest_payload(result))
    pack.runtime.validate_manifest(result)
    return result, changed


def base_trusted_review(report):
    expected = report['trusted_review_pins']
    allowed_handoff = {'output/release_test_handoff/'+five.ADDON+'/'+name for name in
        ('_release_manifest.json','_release_signature.json','handoff.json')}
    need(inc.all_files(BASE_TRUSTED)-set(expected) <= allowed_handoff, 'Unknown parent trusted-source extras')
    result = {name:checks((BASE_TRUSTED/name).read_bytes()) for name in sorted(expected)}
    need(len(result) == 18 and result == expected and not set(result).intersection(PAYLOADS), 'Original18 five-account admission reviews changed')
    return result


def trusted_review(report,values):
    result=base_trusted_review(report)
    for name in ADDITIONAL_SOURCE_REVIEWS:
        need(name not in result and sha(values[name])==TRAINING_SOURCE_PINS[name],'New immutable training review required')
        result[name]=checks(values[name])
    need(len(result)==20 and set(result).intersection(PAYLOADS)==set(ADDITIONAL_SOURCE_REVIEWS),'Original18 plus two training reviews required')
    return result


def training_review(revision,values):
    return {n:dict(source_revision=revision,source_sha256=sha(values[n]),status='ROOT_REVIEWED_PRESENTATION_ONLY') for n in ADDITIONAL_SOURCE_REVIEWS}


def source_lineage(revision,content_revision,old,values,source_bindings):
    return ledger.audit(SimpleNamespace(**globals()),revision,content_revision,old,values,source_bindings)


def operator_inputs(operator_revision):
    operator_revision=immutable_revision(operator_revision)
    pins,bindings={},{}
    for name in AUXILIARY_INPUTS:
        committed=blob_at(ROOT,operator_revision,name)
        physical=pack.protect_data.source_path(ROOT,name).read_bytes()
        if physical==committed:normalization='IDENTITY'
        else:
            need(b'\r' not in committed and committed.replace(b'\n',b'\r\n')==physical,
                'DIRTY_OR_UNCOMMITTED_AUXILIARY_INPUT: '+name)
            normalization='GIT_LF_TO_OPERATOR_CRLF_ONLY'
        pins[name]=checks(physical)
        bindings[name]=dict(git_blob=checks(committed),physical_input=pins[name],normalization=normalization)
    return operator_revision,pins,bindings


def plan(revision,content_revision=None,operator_revision=None):
    revision = immutable_revision(revision)
    compiled_pins_ready()
    operator_revision,operator_pins,operator_bindings=operator_inputs(operator_revision)
    base_report, old = baseline()
    source_bindings={}
    revision, values = payloads(revision,source_bindings=source_bindings)
    lineage=source_lineage(revision,content_revision,old,values,source_bindings)
    need(lineage['complete'] is True and not lineage['unknown_changes'],
        'UNREVIEWED_GIT_RUNTIME_SOURCE_GAP: '+','.join(lineage['unknown_changes']))
    after, changed = projected(old,values)
    admission=preserved_admission(old,after)
    need(set(changed) == set(PAYLOADS) and after['file_count'] == 6917, 'Exactly four replacements with6917 resources required')
    before_names = {row['path'] for row in old['files']}
    need(set(changed)-before_names == set(ADDED_RUNTIME_PATHS), 'Only hero teleport boundary and shared boss registry may be added')
    selected = {row['path'] for row in parent.parent.previous.base.protection.selected_files(
        [row['path'] for row in after['files']], load(ROOT/'tools/lua_protection_policy.json'))}
    need(len(selected) == 184 and not selected.intersection(changed), 'All184 protected modules must remain byte-identical')
    review = trusted_review(base_report,values)
    tree, groups, rewritten, moves = parent.parent.previous.base.parent.rotation_plan(
        inc.read_entries(BASE_VPK),old,after,set(changed))
    sizes = [sum(item['row']['bytes'] for item in group) for group in groups]
    disk = inc.capacity(VIEW,OUTPUT,2*sum(map(len,changed.values()))+2**22,
        sum(sizes[index] for index in rewritten),pack.HEADER.size+len(tree)+48,0)
    result = dict(schema=1,status='PLAN_ONLY_NOT_SIGNED',dry_run=True,workshop_id=ITEM,
        release_sequence=SEQUENCE,revision=REVISION,source_revision=revision,
        operator_revision=operator_revision,operator_source_is_runtime_source=operator_revision==revision,
        operator_source_bindings=operator_bindings,
        baseline_release_sequence=BASE_SEQUENCE,baseline_content_sha256=BASE_CONTENT,
        baseline_report_sha256=BASE_REPORT_SHA,baseline_record_sha256=BASE_RECORD_SHA,
        canonical_journal_sha256=pack.runtime.digest(JOURNAL),
        target_pins={name:checks(raw) for name,raw in sorted(changed.items())},
        source_artifact_pins=source_bindings,
        git_runtime_lineage=lineage,
        source_revisions=lineage['source_revisions'],
        authenticated_parent_manifest_sha256=lineage['actual_parent_manifest_sha256'],
        parent_resource_origins_sha256=lineage['parent_resource_origins_sha256'],
        resource_origins_sha256=lineage['resource_origins_sha256'],
        changed_runtime_paths=sorted(changed),added_runtime_paths=list(ADDED_RUNTIME_PATHS),removed_runtime_paths=[],
        files=after['file_count'],content_sha256=after['content_sha256'],manifest_fields=sorted(after),
        protected_modules_preserved=184,trusted_review_pins=review,
        training_ui_source_review=training_review(revision,values),
        approved_steamids64=list(APPROVED),max_players=4,preserved_admission_rows=admission,
        auxiliary_input_pins=operator_pins,
        rebuilt_archives=sorted(rewritten),archive_migrations=moves,disk_preflight=disk,
        candidate=str(VIEW),trusted_source=str(TRUSTED),unsigned_review=str(UNSIGNED),
        output=str(OUTPUT/(ITEM+'.vpk')),baseline_package_files=base_report['package_files'],
        container_bytes=after['bytes']+pack.HEADER.size+len(tree)+48,native_addon=NATIVE_ADDON,
        all_difficulties_unlocked=False,archive_bundle_hash=EXPECTED_BUNDLE,
        account_gates_payment_policy_preserved=True,backend_deployment_performed=False,
        signing_key_read=False,signature_valid=False,ready_for_upload=False,
        workshop_upload_performed=False,native_test='NOT_RUN',online_fps='NOT_MEASURED_FOR_THIS_PACKAGE')
    return result,old,after,changed,tree,groups


def reviewed_plan(path, expected_sha):
    need(re.fullmatch(r'[a-f0-9]{64}',expected_sha or '') is not None
        and pack.runtime.digest(path) == expected_sha, 'Explicit reviewed-plan SHA required')
    result = load(path)
    need(result.get('status') == 'PLAN_ONLY_NOT_SIGNED' and result.get('dry_run') is True
        and result.get('signature_valid') is False and 'payload_changed' not in result,
        'A real unsigned plan is required; do not treat unsigned payloads as authenticated')
    return result


def prepare_unsigned(revision, reviewed, reviewed_sha,content_revision=None,operator_revision=None):
    expected = reviewed_plan(reviewed,reviewed_sha)
    content_revision=content_revision or expected['source_revisions']['content']
    operator_revision=operator_revision or expected['operator_revision']
    actual,_,manifest,values,_,_ = plan(revision,content_revision,operator_revision)
    need(parent.parent.same_plan(expected,actual), 'Reviewed source/plan changed')
    inc.external(UNSIGNED,exists=False)
    need(not UNSIGNED.exists(), 'New unsigned-review directory required')
    inc.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,UNSIGNED,OVERLAY,VIEW,TRUSTED,OUTPUT,*FROZEN_V01_OUTPUTS,*FROZEN_V02_OUTPUTS,*FROZEN_V03_OUTPUTS,*FROZEN_V05_OUTPUTS,*FROZEN_V06_OUTPUTS,*FROZEN_V07_OUTPUTS,*FROZEN_V08_OUTPUTS])
    UNSIGNED.mkdir(parents=True,exist_ok=False)
    marker = dict(status='UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD',content_sha256=manifest['content_sha256'],
        release_sequence=SEQUENCE,source_revision=revision,signing_key_read=False,signature_valid=False)
    inc.write_new(UNSIGNED/'_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json',pack.runtime.canonical_bytes(marker)+b'\n')
    for name,raw in values.items(): inc.write_new(UNSIGNED/name,raw)
    inc.write_new(UNSIGNED/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(manifest)+b'\n')
    need(inc.all_files(UNSIGNED) == set(values)|{pack.handoff.MANIFEST,'_UNSIGNED_DO_NOT_INSTALL_OR_UPLOAD.json'},
        'Unsigned review contains unexpected files or a copied signature')
    need(not (UNSIGNED/pack.handoff.SIGNATURE).exists(), 'Unsigned review must have no signature')
    need(all(checks((UNSIGNED/name).read_bytes()) == actual['target_pins'][name] for name in values), 'Unsigned payload changed')
    final,*_ = plan(revision,content_revision,operator_revision)
    need(parent.parent.same_plan(actual,final), 'Inputs changed during unsigned preparation')
    actual.update(status='UNSIGNED_REVIEW_READY_NOT_PUBLISHABLE',reviewed_plan_sha256=reviewed_sha)
    return actual


def build_signed(revision, reviewed, reviewed_sha, key,content_revision=None,operator_revision=None):
    expected = reviewed_plan(reviewed,reviewed_sha)
    content_revision=content_revision or expected['source_revisions']['content']
    operator_revision=operator_revision or expected['operator_revision']
    actual,old,manifest,values,tree,groups = plan(revision,content_revision,operator_revision)
    need(parent.parent.same_plan(expected,actual), 'Reviewed source/plan changed before key use')
    need(key is not None, 'Existing external signing key required')
    key = pack.handoff.regular_path(pack.protect_data.external(key,source=BASE))
    for target in (OVERLAY,TRUSTED,VIEW,OUTPUT):
        inc.external(target,exists=False);need(not target.exists(), 'All final output directories must be NEW')
        need(not pack.runtime.within(key,target) and not pack.runtime.within(target,key.parent), 'Key/output overlap')
    inc.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,OVERLAY,TRUSTED,VIEW,OUTPUT,UNSIGNED,*FROZEN_V01_OUTPUTS,*FROZEN_V02_OUTPUTS,*FROZEN_V03_OUTPUTS,*FROZEN_V05_OUTPUTS,*FROZEN_V06_OUTPUTS,*FROZEN_V07_OUTPUTS,*FROZEN_V08_OUTPUTS])
    # Full portrait context covers every validation, including parent postchecks;
    # do not repeat the frozen3101/3102 postcheck omission.
    with scene_maps():
        baseline(full=True)
        OVERLAY.mkdir(parents=True,exist_ok=False);TRUSTED.mkdir(parents=True,exist_ok=False)
        for name,raw in values.items():inc.write_new(OVERLAY/name,raw)
        for name,pin in actual['trusted_review_pins'].items():
            raw=values[name] if name in ADDITIONAL_SOURCE_REVIEWS else (BASE_TRUSTED/name).read_bytes()
            need(checks(raw)==pin,'Trusted review drift')
            inc.write_new(TRUSTED/name,raw)
        inc.write_new(OVERLAY/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(manifest)+b'\n')
        pack.protect_data.sign_manifest(OVERLAY/pack.handoff.MANIFEST,key,OVERLAY/pack.handoff.SIGNATURE,SEQUENCE)
        _,_,metadata=inc.metadata(OVERLAY)
        sources,changed=inc.validate_merged(BASE,OVERLAY,old,manifest,TRUSTED)
        need(changed==set(values),'Merged payload scope changed')
        inc.materialize(VIEW,sources,changed,manifest,metadata)
        with inc.trusted_source(TRUSTED):
            _,verified,signed,_=pack.authenticate(VIEW)
        need(verified==manifest and signed['release_sequence']==SEQUENCE,'Signed view identity differs')
        verification,files=inc.build_volumes(VIEW,OUTPUT,BASE_VPK,tree,groups,set(actual['rebuilt_archives']),manifest,'hardlink')
        need(pack.package_inventory(BASE_VPK)==actual['baseline_package_files'] and pack.runtime.verify(BASE,old)['ok'],
            'Immutable0104 parent changed')
    final,*_=plan(revision,content_revision,operator_revision)
    need(parent.parent.same_plan(actual,final),'Inputs or canonical publication changed during build')
    actual.update(status='BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE',dry_run=False,signing_key_read=True,
        signature_valid=True,full_runtime_validator_passed=True,payload_changed=False,
        payload_changed_basis='Full signed VIEW authentication and exact VPK verification passed; packaging did not alter signed runtime bytes',
        signature_sha256=pack.runtime.digest(VIEW/pack.handoff.SIGNATURE),package_files=files,
        vpk_sha256=files[0]['sha256'],verification=verification)
    return actual


def scope():
    _,old=baseline();values={n:pack.protect_data.source_path(ROOT,n).read_bytes() for n in PAYLOADS};after,changed=projected(old,values)
    return dict(status='READ_ONLY_WORKTREE_SCOPE_NOT_RELEASE_PLAN',source_revision=None,worktree_only=True,payloads={n:checks(v) for n,v in values.items()},changed_runtime_paths=sorted(changed),proposed_file_count=after['file_count'],candidate_directories_created=0,signing_key_read=False,workshop_upload_performed=False)


def static_plan():
    return dict(status='STATIC_LOTTERY_HOTFIX_PLAN_ONLY_NO_EFFECTS',workshop_id=ITEM,release_sequence=SEQUENCE,revision=REVISION,baseline_release_sequence=BASE_SEQUENCE,baseline_content_sha256=BASE_CONTENT,payload_count=4,payloads=list(PAYLOADS),proposed_file_count=6917,protected_modules_preserved=184,compilation_sources=COMPILED,additional_source_review_count=2,source_revision=None,requires_immutable_source_revision=True,requires_immutable_operator_revision=True,source_lineage_required=True,unpublished0201_preserved=True,files_written=0,signing_key_read=False,steam_initialized=False,ready_for_upload=False,canonical_journal_written=False,production_functional_admission=False)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument('--static-plan',action='store_true')
    modes.add_argument('--scope',action='store_true')
    modes.add_argument('--prepare',action='store_true')
    modes.add_argument('--build',action='store_true',help='Future separately authorized signature/VPK build; never uploads')
    parser.add_argument('--source-revision')
    parser.add_argument('--content-source-revision')
    parser.add_argument('--operator-revision')
    parser.add_argument('--reviewed-plan',type=Path)
    parser.add_argument('--reviewed-plan-sha256')
    parser.add_argument('--key',type=Path)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args(argv)
    supplied=any((args.scope,args.prepare,args.build,args.source_revision,args.content_source_revision,args.operator_revision,args.reviewed_plan,
        args.reviewed_plan_sha256,args.key,args.report))
    if args.static_plan or not supplied:
        need(not supplied,'Static plan cannot take source/report/key or action arguments')
        print(json.dumps(static_plan(),ensure_ascii=False));return
    # Admit the report path before any output/key operation, including --build.
    target=args.report.resolve() if args.report else None
    need(args.scope or target is not None,'An explicit NEW report is required')
    if target is not None:
        need(pack.runtime.within(target,REPORT.resolve()) and not target.exists(),'NEW report beneath this tool output required')
    if args.build:need(target==(REPORT/'package.json').resolve(),'Signed build report must be package.json for the validator')
    if args.scope:
        need(args.source_revision is None and args.content_source_revision is None and args.operator_revision is None
            and args.key is None and args.reviewed_plan is None,'Scope is worktree-only, without key or plan')
        result=scope()
    else:
        immutable_revision(args.source_revision)
        if args.prepare or args.build:
            need(args.reviewed_plan is not None,'Explicit reviewed plan required')
            if args.build:result=build_signed(args.source_revision,args.reviewed_plan,args.reviewed_plan_sha256,args.key,args.content_source_revision,args.operator_revision)
            else:
                need(args.key is None,'Unsigned preparation must not accept a key')
                result=prepare_unsigned(args.source_revision,args.reviewed_plan,args.reviewed_plan_sha256,args.content_source_revision,args.operator_revision)
        else:
            need(args.key is None,'Read-only plan must not accept a key')
            result,*_=plan(args.source_revision,args.content_source_revision,args.operator_revision)
    if target is not None:
        inc.write_new(target,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({name:result[name] for name in ('status','files','proposed_file_count','content_sha256','ready_for_upload') if name in result}))


if __name__=='__main__':main()
