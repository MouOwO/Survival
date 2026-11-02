"""Promote only reviewed archive wire bytes from0201; defer its other22 sources."""
from pathlib import Path
import importlib.util

HERE=Path(__file__).resolve().parent
_s=importlib.util.spec_from_file_location('snapshot0203_ledger_adapt',HERE/'adapt.py')
a=importlib.util.module_from_spec(_s);_s.loader.exec_module(a)
impl=a.frozen('ledger','f4df058c3a7342297d8e4b91d0912097601a4fb7217a2fc5ebe18a3a9fc1e116')
ARCHIVE='scripts/vscripts/systems/archive_service.lua'
_parent_deferred=impl.deferred0201
_parent_audit=impl.audit


def deferred0201(b):
    result=_parent_deferred(b)
    a.need(ARCHIVE in result['game'],'Archive was not in the frozen0201 deferred domain')
    result={'game':set(result['game'])-{ARCHIVE},'content':set(result['content'])}
    a.need(len(result['game'])==19 and len(result['content'])==3,
           'Exactly remaining16 runtime plus3 game authors and3 content mirrors must remain deferred')
    return result


def audit(b,*args):
    result=_parent_audit(b,*args)
    a.need(len(result['changed_runtime_paths'])==8
        and ARCHIVE in result['changed_runtime_paths']
        and len(result['deferred_unpublished0201_sources'])==22,
        'Exact five replacements and22 remaining0201 deferred sources required')
    result.update(kind='FIVE_UI_AND_ARCHIVE_WIRE_RESOURCES_WITH_EXPLICIT_REMAINING0201_DEFERRALS',
        payload_selection='FIVE_BOUND_GIT_OUTPUTS_VS_AUTHENTICATED0104_RESOURCE_ROWS',
        promoted0201_source=dict(path=ARCHIVE,source_sha256=b.ARCHIVE_SOURCE_SHA256,
            scope='PREVIOUSLY_REVIEWED_UI_WIRE_ONLY'))
    return result


impl.deferred0201=deferred0201
def __getattr__(name):return getattr(impl,name)
