"""Private frozen0202 visual gate plus cold ordinary N1 archive acceptance.

No native/SDK action. The old four-pool/exit/restore and fatal-log checks stay
intact; old0202 screenshots cannot bind the new signed0203 report/process.
"""
from pathlib import Path
import importlib.util
import json
import re

HERE=Path(__file__).resolve().parent
_spec=importlib.util.spec_from_file_location('snapshot0203_native_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(a)
impl=a.frozen('native_admission','935f0958a188dce736baa08282b3b4cd2cd30794767ddb9e8060527600c7a8ab')
impl.SEQUENCE=2026110203
impl.KIND='LOTTERY_SNAPSHOT_ORDINARY_VISUAL_REVIEW'
impl.SCOPE='LOTTERY_PRESENTATION_AND_COLD_N1_ARCHIVE_NO_TRANSACTION'
ARCHIVE='scripts/vscripts/systems/archive_service.lua'
ARCHIVE_SHA='6a50c80d15ba98374d8a7df31aa664112070a8ffb4e8b71867a0fd1ae2cddec4'


def environment():
    checks=a.local('release_checks');ops=a.local('rehearsal')
    return checks,checks.b,ops


def trusted_review_lineage(report,b):
    router='scripts/vscripts/ui/ui_request_router.lua'
    added={'scripts/vscripts/ui/production_ui_service.lua',ARCHIVE}
    parent=b.base_trusted_review(b.load(b.BASE_REPORT));reviewed=report.get('trusted_review_pins',{})
    impl.need(len(parent)==18 and router in parent and not added.intersection(parent),
        'Authenticated original18 and exact new review roles required')
    impl.need(len(reviewed)==20 and set(reviewed)==set(parent)|added
        and set(reviewed).intersection(b.PAYLOADS)=={router,*added}
        and all(reviewed[name]==pin for name,pin in parent.items()if name!=router)
        and all(reviewed[name]==report['target_pins'][name]for name in (router,*added))
        and report['target_pins'][ARCHIVE]['sha256']==ARCHIVE_SHA,
        'Original17 unchanged, router replaced, production/archive added with exact reviewed wire bytes')
    impl.need(len(b.PAYLOADS)==5 and ARCHIVE in b.PAYLOADS
        and set(b.COMPILED)==set(b.PAYLOADS[:2]) and len(b.COMPILED)==2
        and set(report.get('source_artifact_pins',{}))=={pin['source']for pin in b.COMPILED.values()},
        'Exact five-resource scope and two compiled JS/CSS bindings required')
    return dict(parent_count=18,unchanged_parent_count=17,final_count=20,
        replaced_parent_paths=[router],added_paths=sorted(added),archive_source_sha256=ARCHIVE_SHA)


def cold_archive_acceptance(review,origin,process,bounds,text,reader):
    case=review.get('cold_archive',{})
    impl.need(case.get('kind')=='COLD_ORDINARY_N1_ARCHIVE_UI' and case.get('mode_id')=='standard'
        and case.get('difficulty_id')=='n1' and case.get('fresh_process_no_map_reload')is True
        and case.get('opened_via_normal_ui')is True,'Cold ordinary N1 and a normal archive open required')
    roles=('n1_gameplay','archive_open');captures=case.get('captures',{})
    impl.need(set(captures)==set(roles),'Cold N1 and populated archive captures required')
    shots=[impl.screenshot(captures[role],process,reader,origin)for role in roles]
    visual=case.get('visual_review',{})
    impl.need(all(visual.get(key)is True for key in ('n1_gameplay_confirmed','normal_archive_window_open','normal_archive_tabs_visible',
        'actual_rows_and_values_visible','not_loading_or_placeholder','no_ui_stall'))
        and visual.get('reviewed_png_sha256')==[shot['sha256']for shot in shots],
        'Root must review actual N1 and populated archive pixels, bound by SHA')
    impl.need(all(left['end']<right['start']for left,right in zip(shots,shots[1:]))
        and bounds[0]<=shots[0]['start'] and shots[-1]['end']<=bounds[1],
        'Cold N1 and archive pixels must be chronological inside native file-use observations')
    # No Tools-only ARCHIVE_UI_WIRE print is required in an ordinary client.
    # Existing readonly `archive_view_action_STAMP audit` may corroborate the
    # pictures. It is OPTIONAL: no new runtime print/command or player-row dump
    # is required to accommodate this admission policy.
    audits=[]
    for line in text.splitlines():
        marker='ARCHIVE_AUDIT '
        if marker not in line:continue
        raw=line.split(marker,1)[1]
        impl.need(len(raw)<=16384,'Bounded archive audit summary required')
        try:value=json.loads(raw)
        except ValueError:continue
        if (isinstance(value,dict) and value.get('open')is True and value.get('hidden')is False
            and value.get('visible')is True and type(value.get('rows'))is int
            and 0<value['rows']<=945 and isinstance(value.get('category'),str)
            and re.fullmatch('[a-z][a-z0-9_]{0,63}',value['category'])):
            audits.append(value)
    selected=case.get('displayed_category_id')
    impl.need(isinstance(selected,str)and re.fullmatch('[a-z][a-z0-9_]{0,63}',selected),
        'Root must identify the actual displayed archive category')
    first=review['lottery_previews']['map']['captures']['window_before']
    anchor=impl.screenshot(first,process,reader,origin)
    impl.need(all((shot['hwnd'],shot['width'],shot['height'])==(anchor['hwnd'],anchor['width'],anchor['height'])for shot in shots),
        'Cold archive and lottery cases must use the same ordinary native window')
    return dict(cold_ordinary_n1=True,opened_normally=True,native_screenshot_refs=len(shots),
        actual_snapshot_category=selected,
        optional_native_audit_rows=max((row['rows']for row in audits if row['category']==selected),default=None),
        actual_rows_and_tabs_root_reviewed=True,full_engine_log_fatal_serialization_absent=True,
        tools_page_summary_required=False,raw_archive_rows_exported_by_policy=False,
        wire_json_budget_is_native_byte_measurement=False)


_old_lottery_cases=impl.lottery_cases


def lottery_cases(review,origin,process,bounds,text,reader):
    value=_old_lottery_cases(review,origin,process,bounds,text,reader)
    value['cold_archive']=cold_archive_acceptance(review,origin,process,bounds,text,reader)
    return value


impl.environment=environment
impl.trusted_review_lineage=trusted_review_lineage
impl.lottery_cases=lottery_cases
# Exact one-predicate adaptation; every other signed-package, ordinary-process,
# fatal serialization, visual, same-handle-exit and restoration check is kept.
a.function(impl,'validate_native_release',[
    ('len(b.PAYLOADS)==4','len(b.PAYLOADS)==5'),
    ('Exact signed0202 four-resource candidate required','Exact signed0203 five-resource candidate required')])


def main(argv=None):
    import argparse
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    print(json.dumps(dict(status='STATIC_LOTTERY_SNAPSHOT_NATIVE_PLAN',release_sequence=impl.SEQUENCE,
        scope=impl.SCOPE,cold_archive_n1_required=True,pools=impl.POOLS,native_actions=0,
        sdk_initialized=False,ready_for_upload=False)))
    return 0


def __getattr__(name):return getattr(impl,name)
if __name__=='__main__':raise SystemExit(main())
