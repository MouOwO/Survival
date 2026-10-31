"""Scoped portrait/performance/hero-teleport release over verified3102.

--scope reads the worktree only and is never a release plan. A final plan or
unsigned review requires an explicit immutable source commit. --build is a
separate, future explicit operation requiring a reviewed-plan SHA and an
existing external key; it never uploads, deploys, installs or starts Dota.
"""
from collections import Counter
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


parent = module('portrait_perf_parent3102', ROOT/'tools/shop_recovery_20261031/build_release.py')
# release_checks has a historical bare import. Bind its exact frozen dependency
# only while loading it, preserving this tool's own build_release import name.
_prior = sys.modules.get('build_release')
sys.modules['build_release'] = parent
try:
    parent_checks = module('portrait_perf_parent3102_checks', ROOT/'tools/shop_recovery_20261031/release_checks.py')
finally:
    if _prior is None: sys.modules.pop('build_release', None)
    else: sys.modules['build_release'] = _prior

inc, pack, need = parent.inc, parent.pack, parent.need
BASE_REPORT = ROOT/'output/shop_recovery_20261031/package.json'
BASE_REPORT_SHA = 'fede692a9d442c7ae4dc24032300d9a4620f1646e963bb7aeb758ff2866dc555'
BASE_RECORD = ROOT/'publishing/workshop/shop_recovery_20261031_v01.json'
BASE_RECORD_SHA = 'cdff00e8f042ee61baee39d7aa198409bd5d3ee1e94c3084da60781eb7ea7df8'
BASE_CONTENT = '318491d5f839653d888c350dcaa7fb639189ec427779004879819d3ac9b45352'
BASE, BASE_TRUSTED = parent.VIEW, parent.TRUSTED
BASE_VPK = parent.OUTPUT/(parent.ITEM+'.vpk')
JOURNAL = parent.parent.JOURNAL
ITEM, BASE_SEQUENCE, SEQUENCE = '3824360109', 2026103102, 2026110101
REVISION = 'WS4-PORTRAIT-PERF-TELEPORT-01'
PREFIX = '20261101_ws4_portrait_perf_teleport_v01'
OVERLAY = Path('D:/Survival_发布候选')/(PREFIX+'_overlay')
VIEW = Path('D:/Survival_发布候选')/(PREFIX+'_view')
TRUSTED = Path('D:/Survival_发布候选')/(PREFIX+'_trusted_source')
UNSIGNED = Path('D:/Survival_发布候选')/(PREFIX+'_unsigned_review')
OUTPUT = Path('D:/Survival_工坊输出')/PREFIX
REPORT = ROOT/'output/arcade_portrait_release_20261031'
NATIVE_ADDON = 'svt_ap1101'
MODE = 'scripts/vscripts/config/mode_release_config.lua'
BUNDLE = parent.parent.BUNDLE
EXPECTED_BUNDLE = parent.parent.EXPECTED_BUNDLE
PAYLOADS = (
    'panorama/scripts/custom_game/monster_portrait_renderer.vjs_c',
    'scripts/vscripts/systems/hero_teleport_access.lua',
    'scripts/vscripts/systems/hero_skill_system.lua',
    'scripts/vscripts/systems/commerce_runtime.lua',
    'scripts/vscripts/abilities/ability_survival_hero_ball_lightning.lua',
    'panorama/scripts/custom_game/commerce_actions.vjs_c',
    *(directory+'/addon_'+language+'.txt' for directory in
      ('resource','resource/localization','panorama/localization') for language in ('schinese','english')),
)
COMPILED = {
    PAYLOADS[0]: {'source':'panorama/src/scripts/custom_game/monster_portrait_renderer.js',
        'source_git_sha256':'0171c9c8be163a4da3a4e88bef099e354d68319843143e2be67550ce33af25a1',
        'source_sha256':'2bff46da002ffdef17b69eef6fa3dc28df374deee8ce4a878f3568634bd701c7',
        'source_normalization':'GIT_LF_TO_COMPILER_CRLF_ONLY',
        'compiled_sha256':'d83c2d9165a1efc048bfe8a8426ac0e8ce747e12432d071a8aec86545062bade'},
    PAYLOADS[5]: {'source':'panorama/src/scripts/custom_game/commerce_actions.js',
        'source_git_sha256':'ec4952c371d18c0cbedbac7f0f146d4bcd7ad5023d515ae07c2d9e3587efd00e',
        'source_sha256':'ec4952c371d18c0cbedbac7f0f146d4bcd7ad5023d515ae07c2d9e3587efd00e',
        'source_normalization':'IDENTITY',
        'compiled_sha256':'8415bee0e577baa4df96212434647c7f9a430105f622ce633cfe107ad95cf85e'},
}
AUXILIARY_INPUTS = (
    'tools/arcade_portrait_release_20261031/build_release.py',
    'tools/arcade_portrait_release_20261031/release_checks.py',
    'tools/shop_recovery_20261031/build_release.py',
    'tools/shop_recovery_20261031/release_checks.py',
    *parent.parent.AUXILIARY_INPUTS,
)
sha = lambda raw: hashlib.sha256(raw).hexdigest()
load = parent.load
checks = parent.checks
scene_maps = parent.parent.scene_maps
blob = parent.parent.blob


def immutable_revision(value):
    need(re.fullmatch(r'[a-f0-9]{40}', value or '') is not None, 'Explicit immutable40 source revision required')
    need(parent.parent.revision(value) == value, 'Source commit identity differs')
    return value


def baseline(*, full=False, require_current_journal=True):
    report, manifest, signed = parent_checks.validated_package(BASE_REPORT_SHA, full=full)
    need(pack.runtime.digest(BASE_RECORD) == BASE_RECORD_SHA, 'Frozen3102 delivery record changed')
    record = load(BASE_RECORD)
    need(record['status'] == 'UPLOADED_AND_OFFICIAL_DOWNLOAD_FULLY_VERIFIED'
        and record['release_sequence'] == BASE_SEQUENCE and record['content_sha256'] == BASE_CONTENT
        and record['runtime_files'] == 6917 and record['protected_modules'] == 184
        and record['steam_manifest'] == '2484609663754935010' and record['visibility'] == 'unlisted'
        and record['package_files'] == report['package_files'], 'Officially verified3102 baseline required')
    receipt_path = ROOT/record['download_receipt']['path']
    need(pack.runtime.digest(receipt_path) == record['download_receipt']['sha256'], 'Official3102 receipt changed')
    receipt = load(receipt_path)
    need(receipt['status'] == 'OFFICIAL_REFRESH_NATIVE_DOWNLOAD_FULLY_VERIFIED'
        and receipt['content_sha256'] == BASE_CONTENT and receipt['release_sequence'] == BASE_SEQUENCE
        and receipt['steam_manifest'] == record['steam_manifest'] and receipt['signed_resources_verified'] == 6917
        and receipt['protected_modules_verified'] == 184 and receipt['verification']['signature_valid']
        and receipt['verification']['package_files'] == report['package_files'], 'Complete official3102 verification required')
    need(manifest['content_sha256'] == BASE_CONTENT and manifest['file_count'] == 6917
        and signed['release_sequence'] == BASE_SEQUENCE, 'Signed3102 identity differs')
    if require_current_journal:
        state = load(JOURNAL)
        need(state.get('uploaded') is True and state.get('workshop_id') == ITEM
            and state.get('visibility_requested') == 3 and state.get('release_sequence') == BASE_SEQUENCE
            and state.get('content_sha256') == BASE_CONTENT and state.get('package_files') == report['package_files']
            and state.get('legal_agreement_required') is False, 'Canonical journal is not the successful3102 parent')
    need(re.search(rb'(?m)^M\.all_difficulties_unlocked\s*=\s*false\s*$', (BASE/MODE).read_bytes()),
        '3102 normal online default must remain false')
    # archive_http_bundle is an already protected generated module. Its literal
    # strings need not survive protection; bind its exact signed bytes instead.
    bundle_row=next(row for row in manifest['files'] if row['path']==BUNDLE)
    need(report['archive_bundle_hash']==EXPECTED_BUNDLE
        and checks((BASE/BUNDLE).read_bytes())=={key:bundle_row[key] for key in ('bytes','md5','sha256')},
        'Frozen protected d573 bundle differs')
    return report, manifest


def compiled_source_pin(pin, committed):
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


def payloads(revision, *, source_bindings=None):
    revision = immutable_revision(revision)
    values = {name:blob(revision,name) for name in PAYLOADS}
    for name,pin in COMPILED.items():
        need(sha(values[name]) == pin['compiled_sha256'], 'Reviewed official UI artifact differs: '+name)
        binding=compiled_source_pin(pin,blob(revision,pin['source']))
        if source_bindings is not None:source_bindings[pin['source']]=binding
    boundary = values[PAYLOADS[1]]
    need(re.search(rb'\bCOOLDOWN\s*=\s*10\b', boundary) and b'"teleporter"' in boundary
        and b'caster_player' in boundary and b'current_deadlines' in boundary, 'Hero teleport shared boundary missing')
    need(b'hero_teleport_access.synchronize' in values[PAYLOADS[2]]
        and b'hero_teleport_access.commit' in values[PAYLOADS[3]]
        and b'hero_teleport_access.check' in values[PAYLOADS[4]], 'Both hero teleport entry points must use the boundary')
    need(all(values.values()), 'Empty scoped payload')
    return revision, values


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


def trusted_review(report):
    expected = report['trusted_review_pins']
    allowed_handoff = {'output/release_test_handoff/svt_s3102/'+name for name in
        ('_release_manifest.json','_release_signature.json','handoff.json')}
    need(inc.all_files(BASE_TRUSTED)-set(expected) <= allowed_handoff, 'Unknown parent trusted-source extras')
    result = {name:checks((BASE_TRUSTED/name).read_bytes()) for name in sorted(expected)}
    need(len(result) == 16 and result == expected and not set(result).intersection(PAYLOADS), 'Original16 admission reviews changed')
    return result


def plan(revision):
    revision = immutable_revision(revision)
    base_report, old = baseline()
    source_bindings={}
    revision, values = payloads(revision,source_bindings=source_bindings)
    after, changed = projected(old,values)
    need(set(changed) == set(PAYLOADS) and after['file_count'] == 6918, 'Exact12 replacements/one added module required')
    before_names = {row['path'] for row in old['files']}
    need(set(changed)-before_names == {PAYLOADS[1]}, 'Only hero_teleport_access may be added')
    selected = {row['path'] for row in parent.parent.previous.base.protection.selected_files(
        [row['path'] for row in after['files']], load(ROOT/'tools/lua_protection_policy.json'))}
    need(len(selected) == 184 and not selected.intersection(changed), 'All184 protected modules must remain byte-identical')
    review = trusted_review(base_report)
    tree, groups, rewritten, moves = parent.parent.previous.base.parent.rotation_plan(
        inc.read_entries(BASE_VPK),old,after,set(changed))
    sizes = [sum(item['row']['bytes'] for item in group) for group in groups]
    disk = inc.capacity(VIEW,OUTPUT,2*sum(map(len,changed.values()))+2**22,
        sum(sizes[index] for index in rewritten),pack.HEADER.size+len(tree)+48,0)
    result = dict(schema=1,status='PLAN_ONLY_NOT_SIGNED',dry_run=True,workshop_id=ITEM,
        release_sequence=SEQUENCE,revision=REVISION,source_revision=revision,
        baseline_release_sequence=BASE_SEQUENCE,baseline_content_sha256=BASE_CONTENT,
        baseline_report_sha256=BASE_REPORT_SHA,baseline_record_sha256=BASE_RECORD_SHA,
        canonical_journal_sha256=pack.runtime.digest(JOURNAL),
        target_pins={name:checks(raw) for name,raw in sorted(changed.items())},
        source_artifact_pins=source_bindings,
        changed_runtime_paths=sorted(changed),added_runtime_paths=[PAYLOADS[1]],removed_runtime_paths=[],
        files=after['file_count'],content_sha256=after['content_sha256'],manifest_fields=sorted(after),
        protected_modules_preserved=184,trusted_review_pins=review,
        auxiliary_input_pins={name:checks((ROOT/name).read_bytes()) for name in AUXILIARY_INPUTS},
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


def prepare_unsigned(revision, reviewed, reviewed_sha):
    expected = reviewed_plan(reviewed,reviewed_sha)
    actual,_,manifest,values,_,_ = plan(revision)
    need(parent.parent.same_plan(expected,actual), 'Reviewed source/plan changed')
    inc.external(UNSIGNED,exists=False)
    need(not UNSIGNED.exists(), 'New unsigned-review directory required')
    inc.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,UNSIGNED,OVERLAY,VIEW,TRUSTED,OUTPUT])
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
    final,*_ = plan(revision)
    need(parent.parent.same_plan(actual,final), 'Inputs changed during unsigned preparation')
    actual.update(status='UNSIGNED_REVIEW_READY_NOT_PUBLISHABLE',reviewed_plan_sha256=reviewed_sha)
    return actual


def build_signed(revision, reviewed, reviewed_sha, key):
    expected = reviewed_plan(reviewed,reviewed_sha)
    actual,old,manifest,values,tree,groups = plan(revision)
    need(parent.parent.same_plan(expected,actual), 'Reviewed source/plan changed before key use')
    need(key is not None, 'Existing external signing key required')
    key = pack.handoff.regular_path(pack.protect_data.external(key,source=BASE))
    for target in (OVERLAY,TRUSTED,VIEW,OUTPUT):
        inc.external(target,exists=False);need(not target.exists(), 'All final output directories must be NEW')
        need(not pack.runtime.within(key,target) and not pack.runtime.within(target,key.parent), 'Key/output overlap')
    inc.disjoint([BASE,BASE_TRUSTED,BASE_VPK.parent,OVERLAY,TRUSTED,VIEW,OUTPUT,UNSIGNED])
    # Full portrait context covers every validation, including parent postchecks;
    # do not repeat the frozen3101/3102 postcheck omission.
    with scene_maps():
        baseline(full=True)
        OVERLAY.mkdir(parents=True,exist_ok=False);TRUSTED.mkdir(parents=True,exist_ok=False)
        for name,raw in values.items():inc.write_new(OVERLAY/name,raw)
        for name,pin in actual['trusted_review_pins'].items():
            raw=(BASE_TRUSTED/name).read_bytes();need(checks(raw)==pin,'Trusted review drift')
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
            'Immutable3102 parent changed')
    final,*_=plan(revision)
    need(parent.parent.same_plan(actual,final),'Inputs or canonical publication changed during build')
    actual.update(status='BUILT_SIGNED_PENDING_NATIVE_PERF_ACCEPTANCE',dry_run=False,signing_key_read=True,
        signature_valid=True,full_runtime_validator_passed=True,payload_changed=False,
        payload_changed_basis='Full signed VIEW authentication and exact VPK verification passed; packaging did not alter signed runtime bytes',
        signature_sha256=pack.runtime.digest(VIEW/pack.handoff.SIGNATURE),package_files=files,
        vpk_sha256=files[0]['sha256'],verification=verification)
    return actual


def scope():
    base_report,old=baseline()
    values={name:pack.protect_data.source_path(ROOT,name).read_bytes() for name in PAYLOADS}
    after,changed=projected(old,values)
    return dict(status='READ_ONLY_WORKTREE_SCOPE_NOT_RELEASE_PLAN',worktree_only=True,source_revision=None,
        proposed_sequence=SEQUENCE,revision=REVISION,baseline_release_sequence=BASE_SEQUENCE,
        payloads={name:checks(raw) for name,raw in sorted(values.items())},changed_runtime_paths=sorted(changed),
        proposed_file_count=after['file_count'],protected_modules_preserved=184,
        original_trusted_reviews=len(trusted_review(base_report)),candidate_directories_created=0,
        signing_key_read=False,signature_valid=False,ready_for_upload=False,workshop_upload_performed=False)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    modes=parser.add_mutually_exclusive_group()
    modes.add_argument('--scope',action='store_true')
    modes.add_argument('--prepare',action='store_true')
    modes.add_argument('--build',action='store_true',help='Future separately authorized signature/VPK build; never uploads')
    parser.add_argument('--source-revision')
    parser.add_argument('--reviewed-plan',type=Path)
    parser.add_argument('--reviewed-plan-sha256')
    parser.add_argument('--key',type=Path)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    # Admit the report path before any output/key operation, including --build.
    target=args.report.resolve() if args.report else None
    need(args.scope or target is not None,'An explicit NEW report is required')
    if target is not None:
        need(pack.runtime.within(target,REPORT.resolve()) and not target.exists(),'NEW report beneath this tool output required')
    if args.build:need(target==(REPORT/'package.json').resolve(),'Signed build report must be package.json for the validator')
    if args.scope:
        need(args.source_revision is None and args.key is None and args.reviewed_plan is None,'Scope is worktree-only, without key or plan')
        result=scope()
    else:
        immutable_revision(args.source_revision)
        if args.prepare or args.build:
            need(args.reviewed_plan is not None,'Explicit reviewed plan required')
            if args.build:result=build_signed(args.source_revision,args.reviewed_plan,args.reviewed_plan_sha256,args.key)
            else:
                need(args.key is None,'Unsigned preparation must not accept a key')
                result=prepare_unsigned(args.source_revision,args.reviewed_plan,args.reviewed_plan_sha256)
        else:
            need(args.key is None,'Read-only plan must not accept a key')
            result,*_=plan(args.source_revision)
    if target is not None:
        inc.write_new(target,(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode())
    print(json.dumps({name:result[name] for name in ('status','files','proposed_file_count','content_sha256','ready_for_upload') if name in result}))


if __name__=='__main__':main()
