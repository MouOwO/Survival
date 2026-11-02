"""0104 plus five existing UI/wire resources. Default has zero effects."""
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
_s=importlib.util.spec_from_file_location('snapshot0203_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_s);_s.loader.exec_module(a)
impl=a.frozen('build_release','a90154ce9ca13fb16f05273b5a50343ec08547a853f38978de3c74b3509c2af5')
PARENT_IMPL=impl
ARCHIVE='scripts/vscripts/systems/archive_service.lua'
ARCHIVE_SOURCE_SHA256='6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4'
impl.ARCHIVE=ARCHIVE;impl.ARCHIVE_SOURCE_SHA256=ARCHIVE_SOURCE_SHA256
impl.SEQUENCE=2026110204;impl.REVISION='WS4-LOTTERY-REPLAY-RECEIPT-04'
impl.PREFIX='20261102_ws4_lottery_replay_v11'
impl.OVERLAY=Path('D:/Survival_发布候选')/(impl.PREFIX+'_overlay')
impl.VIEW=Path('D:/Survival_发布候选')/(impl.PREFIX+'_view')
impl.TRUSTED=Path('D:/Survival_发布候选')/(impl.PREFIX+'_trusted_source')
impl.UNSIGNED=Path('D:/Survival_发布候选')/(impl.PREFIX+'_unsigned_review')
impl.OUTPUT=Path('D:/Survival_工坊输出')/impl.PREFIX
impl.REPORT=impl.ROOT/'output/lottery_replay_release_20261102'
impl.NATIVE_ADDON='svt_lr0204'
impl.FROZEN_V09_OUTPUTS=tuple([*(Path('D:/Survival_发布候选')/('20261102_ws4_lottery_hotfix_v09'+x)
    for x in ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261102_ws4_lottery_hotfix_v09',
    *(Path('D:/Survival_发布候选')/('20261102_ws4_lottery_snapshot_v10'+x)
    for x in ('_overlay','_view','_trusted_source','_unsigned_review')),
    Path('D:/Survival_工坊输出')/'20261102_ws4_lottery_snapshot_v10'])
impl.PAYLOADS=(*impl.PAYLOADS,ARCHIVE)
impl.ADDITIONAL_SOURCE_REVIEWS=(*impl.ADDITIONAL_SOURCE_REVIEWS,ARCHIVE)
impl.NEW_SOURCE_REVIEWS=impl.NEW_SOURCE_REVIEWS|{ARCHIVE}
impl.SOURCE_REVIEW_PINS={**impl.TRAINING_SOURCE_PINS,ARCHIVE:ARCHIVE_SOURCE_SHA256}
EXTRA_PINS={
    'scripts/vscripts/systems/archive_http_adapter.lua':'2607bf289995b6982b68ea55f03aa5abac22223f5cf84ffc6a898123be05de45',
    'scripts/vscripts/systems/lottery_http_service.lua':'b6e7c3f542d111e1eaceeb1414632fb50ecb1d2ad410ced17d84f3c506a743e3',
}
impl.PAYLOADS=(*impl.PAYLOADS,*EXTRA_PINS)
impl.ADDITIONAL_SOURCE_REVIEWS=(*impl.ADDITIONAL_SOURCE_REVIEWS,*EXTRA_PINS)
impl.NEW_SOURCE_REVIEWS=impl.NEW_SOURCE_REVIEWS|set(EXTRA_PINS)
impl.SOURCE_REVIEW_PINS.update(EXTRA_PINS)
impl.COMPILED={name:dict(pin) for name,pin in impl.COMPILED.items()}
impl.COMPILED['panorama/scripts/custom_game/lottery_cinematic_v1.vjs_c'].update(
    source_git_sha256='1dd739c29ea09a7457ed1ffa74f4e8e9187fb16ffd2313c8c16a0287cc99490c',
    source_sha256='ccd40509644557888e1c73a981bac4055a428ba9a27ab1678a0b6bbf5b500bc2',
    compiled_sha256='29f9dd98e211f9798a591808300c7d1be624a138709ca6dc6249d9eaccff3703')
impl.AUXILIARY_INPUTS=tuple(dict.fromkeys((*impl.AUXILIARY_INPUTS,
    *(('tools/lottery_replay_release_20261102/'+name) for name in
      ('adapt.py','build_release.py','ledger.py','release_checks.py','rehearsal.py',
       'verify_download.py','native_admission.py','validator.py','backend_deploy.py')),
    'publishing/workshop/release_authority_lottery_replay_20261102.json')))
impl.ledger=a.local('ledger')


def payloads(revision,*,source_bindings=None):
    b=impl;revision=b.immutable_revision(revision);b.compiled_pins_ready()
    values={n:b.blob(revision,n) for n in b.PAYLOADS}
    for name,pin in b.COMPILED.items():
        b.need(b.sha(values[name])==pin['compiled_sha256'],'Reviewed official artifact differs: '+name)
        binding=b.compiled_source_pin(pin,b.blob(revision,pin['source']))
        if source_bindings is not None:source_bindings[pin['source']]=binding
    b.need(set(b.SOURCE_REVIEW_PINS)==set(b.ADDITIONAL_SOURCE_REVIEWS)
        and all(b.sha(values[n])==pin for n,pin in b.SOURCE_REVIEW_PINS.items()),
        'Exact two presentation and one archive wire source reviews required')
    b.need(all(values.values()),'Empty scoped payload')
    return revision,values


def training_review(revision,values):
    b=impl
    return {n:dict(source_revision=revision,source_sha256=b.sha(values[n]),
        status='ROOT_REVIEWED_PRESENTATION_ONLY',
        review_role='REPLACE_EXISTING_PARENT_REVIEW' if n in b.REPLACED_PARENT_REVIEWS else 'ADD_NEW_SOURCE_REVIEW')
        for n in b.TRAINING_SOURCE_PINS}


def archive_review(revision,values):
    impl.need(impl.sha(values[ARCHIVE])==ARCHIVE_SOURCE_SHA256,'Reviewed archive UI-wire source differs')
    return dict(kind='ADDITIONAL_UI_WIRE_SOURCE_REVIEW',status='ROOT_REVIEWED_UI_WIRE_ONLY',
        source_revision=revision,source_path=ARCHIVE,source_sha256=ARCHIVE_SOURCE_SHA256,
        source_binding='EXACT_IMMUTABLE_GIT_BLOB',review_role='ADD_NEW_SOURCE_REVIEW',
        previously_reviewed0201_source_promoted=True,full_gameplay_claimed=False)


impl.payloads=payloads;impl.training_review=training_review;impl.archive_review=archive_review
a.function(impl,'trusted_review',[
    ('TRAINING_SOURCE_PINS','SOURCE_REVIEW_PINS'),('len(result)==19','len(result)==22'),
    ('replace router and add production review only','replace router and add production plus archive reviews only')])
a.function(impl,'plan',[
    ('training_ui_source_review=training_review(revision,values),',
     'training_ui_source_review=training_review(revision,values),archive_source_review=archive_review(revision,values),')])
for _name in ('prepare_unsigned','build_signed'):
    changes=[('*FROZEN_V08_OUTPUTS]','*FROZEN_V08_OUTPUTS,*FROZEN_V09_OUTPUTS]')]
    if _name=='build_signed':changes.append((
        'BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE','BUILT_SIGNED_PENDING_NATIVE_LOTTERY_SNAPSHOT_ACCEPTANCE'))
    a.function(impl,_name,changes)
_static=impl.static_plan


def static_plan():
    value=_static();value.update(status='STATIC_LOTTERY_SNAPSHOT_PLAN_ONLY_NO_EFFECTS',
        payload_count=7,additional_source_review_count=5,trusted_review_count=22,
        promoted_archive_source_sha256=ARCHIVE_SOURCE_SHA256,
        training_source_reviews=2,archive_wire_source_reviews=1,unpublished0201_remaining_source_domains=22)
    return value


impl.static_plan=static_plan
def __getattr__(name):return getattr(impl,name)
if __name__=='__main__':impl.main()
