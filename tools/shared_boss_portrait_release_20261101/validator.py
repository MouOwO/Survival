"""Canonical read-only release authority adapter. Import/default performs no SDK.

Native admission remains an explicit implementation prerequisite, not a
caller-controlled READY boolean or a development-equivalence substitution.
"""
from pathlib import Path
import importlib.util
import re

HERE=Path(__file__).resolve().parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
b=module('canonical_shared_boss_1107_builder',HERE/'build_release.py')
c=module('canonical_shared_boss_1107_checks',HERE/'release_checks.py')
OWNER,APP='76561198845461206',570
# Code review binds this exact evidence policy; real candidate evidence must
# still pass it. A code/test PASS is never ordinary-production acceptance.
NATIVE_ADMISSION_MODULE=HERE/'native_admission.py'
NATIVE_ADMISSION_SHA256='9a7d923532bbec9de9f7bf02b95b3ef2f5fd7b8deb3ede978db803be02265ae5'


def digest(value):
    b.need(isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None,'Explicit evidence SHA256 required')
    return value


def validate_bootstrap(request):
    b.need(isinstance(request,dict),'Structured bootstrap request required')
    report,parent=b.baseline(full=True)
    raw=b.JOURNAL.read_bytes();state=b.load(b.JOURNAL);b.require_parent_journal(state,report)
    snapshot=b.ledger.load_baseline(parent,b.pack.runtime.digest(b.BASE/b.pack.handoff.MANIFEST))
    b.need(request.get('canonical_journal_sha256')==b.sha(raw)
        and request.get('parent_manifest_sha256')==snapshot['parent_manifest_sha256']
        and request.get('source_revisions')==snapshot['source_anchors'],
        'Bootstrap request must exactly bind actual parent and reviewed ancestry cursors')
    return dict(workshop_id=b.ITEM,app_id=APP,owner=OWNER,
        canonical_journal_sha256=b.sha(raw),release_sequence=b.BASE_SEQUENCE,content_sha256=b.BASE_CONTENT,
        source_revisions=dict(snapshot['source_anchors']),parent_manifest_sha256=snapshot['parent_manifest_sha256'],
        resource_origins_sha256=snapshot['resource_origins_sha256'],source_anchor_is_full_published_tree=False)


def validate_release(request):
    b.need(isinstance(request,dict) and request.get('release_sequence')==b.SEQUENCE,
        'Only this exact candidate sequence is registered')
    b.need(NATIVE_ADMISSION_MODULE is not None and re.fullmatch('[a-f0-9]{64}',NATIVE_ADMISSION_SHA256 or ''),
        'PENDING_REAL_NATIVE_17_RESOURCE_ADMISSION_POLICY')
    path=Path(NATIVE_ADMISSION_MODULE).resolve()
    b.need(path.parent==HERE and path.is_file() and b.sha(path.read_bytes())==NATIVE_ADMISSION_SHA256,
        'Reviewed ordinary-production native admission policy changed')
    report,manifest,signed=c.validated_package(digest(request.get('report_sha256')),full=True)
    b.need(request.get('source_revisions')==report['source_revisions']
        and request.get('signed_manifest_sha256')==b.pack.runtime.digest(b.VIEW/b.pack.handoff.MANIFEST)
        and request.get('content_sha256',report['content_sha256'])==report['content_sha256'],
        'Request source/package binding differs')
    plan_path=Path(request.get('plan_path') or '').resolve()
    b.need(b.pack.runtime.within(plan_path,b.REPORT.resolve()) and plan_path.is_file(),
        'Explicit reviewed construction plan beneath this candidate report directory required')
    plan=b.reviewed_plan(plan_path,digest(request.get('plan_sha256')))
    recomputed,*_=b.plan(report['source_revisions']['game'],report['source_revisions']['content'],report['operator_revision'])
    b.need(b.parent.parent.same_plan(plan,recomputed),'Exact reviewed construction plan changed')
    # The signed report deliberately updates these four construction-state
    # fields and adds signature/VPK results. Every immutable plan field remains.
    projected={key:report.get(key) for key in plan}
    for key in ('status','dry_run','signing_key_read','signature_valid'):projected[key]=plan[key]
    b.need(b.parent.parent.same_plan(plan,projected),'Signed report differs from reviewed construction inputs')
    raw=b.JOURNAL.read_bytes();state=b.load(b.JOURNAL)
    b.need(b.sha(raw)==request.get('parent_journal_sha256'),'Publication journal changed')
    b.require_parent_journal(state,b.load(b.BASE_REPORT))
    acceptance=module('shared_boss_1107_native_admission',path).validate_native_release(request,report,manifest,signed)
    b.need(acceptance.get('ordinary_production_acceptance') is True
        and acceptance.get('content_sha256')==manifest['content_sha256']
        and acceptance.get('mean_fps',0)>=90 and acceptance.get('p95_ms',float('inf'))<=16.7,
        'Same signed production portraits/shared-boss behavior/FPS/stability acceptance required')
    return dict(workshop_id=b.ITEM,app_id=APP,owner=OWNER,release_sequence=b.SEQUENCE,
        generation=request['generation'],parent_journal_sha256=b.sha(raw),
        source_revisions=dict(report['source_revisions']),signed_manifest_sha256=request['signed_manifest_sha256'],
        report_sha256=request['report_sha256'],plan_sha256=request['plan_sha256'],content_sha256=manifest['content_sha256'],
        authenticated_parent_content_sha256=b.BASE_CONTENT,
        authenticated_parent_manifest_sha256=report['authenticated_parent_manifest_sha256'],
        parent_resource_origins_sha256=report['parent_resource_origins_sha256'],
        resource_origins_sha256=report['resource_origins_sha256'],package_dir=str(b.OUTPUT.resolve()))
