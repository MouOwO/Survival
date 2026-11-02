"""Read-only five-resource snapshot hotfix authentication; parent0202 unchanged."""
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
_s=importlib.util.spec_from_file_location('snapshot0203_checks_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_s);_s.loader.exec_module(a)
impl=a.frozen('release_checks','08cbcd0ef9e5aac45cd0e13afbe0dd01ff9ef5591a2f521cb7769b5086bdfcda')
builder=a.local('build_release');impl.b=builder.impl
a.function(impl,'validated_package',[
    ('BUILT_SIGNED_PENDING_NATIVE_LOTTERY_ACCEPTANCE','BUILT_SIGNED_PENDING_NATIVE_LOTTERY_SNAPSHOT_ACCEPTANCE')])
_parent_validate=impl.validated_package


def validated_package(expected_report_sha256,*,full=False):
    report,manifest,signed=_parent_validate(expected_report_sha256,full=full)
    b=impl.b;_,values=b.payloads(report['source_revision'])
    b.need(report.get('archive_source_review')==b.archive_review(report['source_revision'],values)
        and len(report['trusted_review_pins'])==20
        and len(report['training_ui_source_review'])==2,
        'Training2 plus archive UIWire1 exact source roles required')
    return report,manifest,signed


def __getattr__(name):return getattr(impl,name)
