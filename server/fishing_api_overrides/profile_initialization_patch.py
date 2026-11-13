"""Remove only ArchiveService.profile's discarded early profile read.

No SQL, guard, reset, protocol, cache or drain changes. Each call still ensures
account/defaults, settles both existing online passes and reads the final profile.
Cold identity binding and VIP reconciliation remain their installed wrappers.
An early profile-read failure can now occur after later drain work; arbitrary
DDL/corrupt-data/error ordering is not claimed equivalent. Startup/readiness and
all remaining per-RPC checks remain required. O(source bytes), two fixed files.
"""
from __future__ import annotations
import hashlib

PARENTS = {'fishing_api/application.py': '5bcc930a034aa72096098c2e8446d2321cff33f2ee75168d77d9b1c46a812b92', 'archive_backend/service.py': 'c059165933c6398dc9e02309116ac9d5717874aacaaf1b267fd4f54347ec9a42'}
OUTPUTS = {'fishing_api/application.py': '9c4ca317f35073c4c873216c829ab25432efa317842c3c3696ee2b22b715c608', 'archive_backend/service.py': '672a1e845ec17093c755d7a724fcc4978f8cc008d935e763e7105f300b73e2f8'}
BLOCKS = {'fishing_api/application.py': ('    def profile(self, payload: dict[str, Any]) -> Any:\n        account_id = _string(payload, "account_id", ACCOUNT_ID)\n        database_account_id = self._database_account_id(account_id)\n        self._ensure_gameplay_stats(database_account_id)\n        response = self.rpc_client.rpc("get_fishing_profile", {\n            "p_account_id": database_account_id,\n        })\n        return self._public_response(response, database_account_id, account_id)\n', '    def _initialize_profile(self, payload: dict[str, Any]) -> tuple[str, str]:\n        account_id = _string(payload, "account_id", ACCOUNT_ID)\n        database_account_id = self._database_account_id(account_id)\n        self._ensure_gameplay_stats(database_account_id)\n        return account_id, database_account_id\n\n    def profile(self, payload: dict[str, Any]) -> Any:\n        account_id, database_account_id = self._initialize_profile(payload)\n        response = self.rpc_client.rpc("get_fishing_profile", {\n            "p_account_id": database_account_id,\n        })\n        return self._public_response(response, database_account_id, account_id)\n'), 'archive_backend/service.py': ('        # Called after the existing profile loader initializes a new player.\n        value=self.app.profile(payload)\n        account=self.app._database_account_id(payload["account_id"])\n', '        # Initialize defaults before the unchanged drain and authoritative read.\n        _,account=self.app._initialize_profile(payload)\n')}

def _need(value, code):
    if not value: raise ValueError(code)

def _texts(sources):
    _need(type(sources) is dict and set(sources)==set(PARENTS), 'profile_init_source_set_invalid')
    result={}
    for name,content in sources.items():
        _need(type(content) is str, 'profile_init_source_invalid')
        content=content.replace('\r\n','\n')
        _need('\r' not in content, 'profile_init_source_invalid')
        result[name]=content
    return result

def _digests(sources):
    return {name:hashlib.sha256(content.encode('utf8')).hexdigest()for name,content in sources.items()}

def restore_sources(sources):
    source=_texts(sources)
    _need(_digests(source)==OUTPUTS, 'profile_init_output_changed')
    result={}
    for name,content in source.items():
        before,after=BLOCKS[name]
        _need(content.count(after)==1, 'profile_init_output_anchor_invalid')
        result[name]=content.replace(after,before,1)
    _need(_digests(result)==PARENTS, 'profile_init_parent_changed')
    return result

def patch_sources(sources):
    source=_texts(sources)
    if _digests(source)==OUTPUTS:
        restore_sources(source)
        return source
    _need(_digests(source)==PARENTS, 'profile_init_baseline_mismatch')
    result={}
    for name,content in source.items():
        before,after=BLOCKS[name]
        _need(content.count(before)==1, 'profile_init_parent_anchor_invalid')
        result[name]=content.replace(before,after,1)
        compile(result[name],name,'exec')
    _need(_digests(result)==OUTPUTS and restore_sources(result)==source, 'profile_init_unrelated_change')
    return result
