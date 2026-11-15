"""Fixed opt-in read-context consolidation; preparation only, never a live patch.

Stable profile:4->2 RPCs; SQL helper work and full per-RPC authorization remain.
Online outbox K>0:reuse its bounded list, re-read normal pending after drain;
RPC count remains4+2K. Normal pending only:3+2K instead of4+2K.
No account cache, poller, scene scan, source I/O or extra DB lock is introduced.
"""
import hashlib
PARENTS={'fishing_api/postgres.py': '688935869534c5b545cf8a73ee80292c537ad2b280ea9750b7258ac6316b288d', 'archive_backend/service.py': '672a1e845ec17093c755d7a724fcc4978f8cc008d935e763e7105f300b73e2f8'}
OUTPUTS={'fishing_api/postgres.py': '6de9219de5a011160d6a96b524f2f2fe45a775925d9a1510dd2646392c81ad9c', 'archive_backend/service.py': '58bd3bd39793a45d6ff9b5f003de436f32c5be41a7e64800f9f2a091ea682bfd'}
OLD_RPC='    "archive_pending": _params(("p_account", "text", "hash")),\n'
NEW_RPC='    "archive_pending": _params(("p_account", "text", "hash")),\n    "archive_profile_context": _params(("p_account", "text", "hash"), ("p_hash", "text", "hash")),\n'
OLD_PROFILE='def profile(self,payload):\n        # Initialize defaults before the unchanged drain and authoritative read.\n        _,account=self.app._initialize_profile(payload)\n        self.drain_online(account)\n        for pending in self.app.rpc_client.rpc("archive_pending",{"p_account":account}):\n            result=self.finish_prepared(account,pending["id"],self.app.rpc_client.rpc("archive_resume",{"p_account":account,"p_id":pending["id"]}))\n            if not result.get("ok") and not result.get("terminal"):\n                # A contested/incomplete settlement is not a successfully loaded save.\n                raise TimeoutError("archive_pending_retry")\n        value=self.app.rpc_client.rpc("get_fishing_profile",{"p_account_id":account})\n        return self.app._public_response(value,account,payload["account_id"])'
NEW_PROFILE='def profile(self,payload):\n        # Preserve the original authenticated/default-initialization path.\n        _,account=self.app._initialize_profile(payload)\n        context=self.app.rpc_client.rpc("archive_profile_context",{"p_account":account,"p_hash":self.bundle.hash})\n        if type(context) is not dict or set(context)!={"online","pending","profile"}:\n            raise ValueError("archive_profile_context_invalid")\n        online,pending,ready_profile=context["online"],context["pending"],context["profile"]\n        if type(online) is not list or len(online)>64:\n            raise ValueError("archive_profile_context_invalid")\n        if online:\n            if pending is not None or ready_profile is not None:\n                raise ValueError("archive_profile_context_invalid")\n        elif type(pending) is not list or len(pending)>64:\n            raise ValueError("archive_profile_context_invalid")\n        elif pending:\n            if ready_profile is not None:\n                raise ValueError("archive_profile_context_invalid")\n        elif (type(ready_profile) is not dict or ready_profile.get("account_id")!=account\n                or type(ready_profile.get("schema_version")) is not int or ready_profile.get("schema_version")!=1 or type(ready_profile.get("save")) is not dict):\n            raise ValueError("archive_profile_context_invalid")\n        for operation in online+(pending or []):\n            if (type(operation) is not dict or set(operation)!={"id"}\n                    or type(operation["id"]) is not str or not 1<=len(operation["id"])<=256):\n                raise ValueError("archive_profile_context_invalid")\n        self.drain_online(account,pending=online)\n        if pending is None:\n            # Online settlement may produce/finish operations: read after drain,\n            # exactly where the original method reads its normal pending list.\n            pending=self.app.rpc_client.rpc("archive_pending",{"p_account":account})\n        for operation in pending:\n            result=self.finish_prepared(account,operation["id"],self.app.rpc_client.rpc("archive_resume",{"p_account":account,"p_id":operation["id"]}))\n            if not result.get("ok") and not result.get("terminal"):\n                raise TimeoutError("archive_pending_retry")\n        if ready_profile is None:\n            value=self.app.rpc_client.rpc("get_fishing_profile",{"p_account_id":account})\n        else:\n            value=ready_profile\n        return self.app._public_response(value,account,payload["account_id"])'
OLD_DRAIN='def drain_online(self,database_account):\n        # Persistent checkpoint outbox survives a Python crash between fishing and archive settlement.\n        pending=self.app.rpc_client.rpc("archive_online_pending",{"p_account":database_account,"p_hash":self.bundle.hash})\n        for operation in pending:\n            prepared=self.app.rpc_client.rpc("archive_resume",{"p_account":database_account,"p_id":operation["id"]})\n            result=self.finish_prepared(database_account,operation["id"],prepared)\n            if not result.get("ok"): raise TimeoutError("archive_online_pending")'
NEW_DRAIN='def drain_online(self,database_account,*,pending=None):\n        # Persistent checkpoint outbox survives a Python crash between fishing and archive settlement.\n        if pending is None:\n            pending=self.app.rpc_client.rpc("archive_online_pending",{"p_account":database_account,"p_hash":self.bundle.hash})\n        for operation in pending:\n            prepared=self.app.rpc_client.rpc("archive_resume",{"p_account":database_account,"p_id":operation["id"]})\n            result=self.finish_prepared(database_account,operation["id"],prepared)\n            if not result.get("ok"): raise TimeoutError("archive_online_pending")'
def checked(sources,pins):
 if type(sources)is not dict or set(sources)!=set(pins):raise ValueError('profile_context_source_set_invalid')
 result={}
 for name,h in pins.items():
  value=sources[name]
  if type(value)is not str:raise ValueError('profile_context_text_source_required')
  value=value.replace('\r\n','\n')
  if '\r' in value or hashlib.sha256(value.encode()).hexdigest()!=h:raise ValueError('profile_context_exact_source_required')
  result[name]=value
 return result
def substitute(value,old,new):
 if value.count(old)!=1:raise ValueError('profile_context_anchor_changed')
 return value.replace(old,new,1)
def patch_sources(sources):
 r=checked(sources,PARENTS);r['fishing_api/postgres.py']=substitute(r['fishing_api/postgres.py'],OLD_RPC,NEW_RPC)
 r['archive_backend/service.py']=substitute(r['archive_backend/service.py'],OLD_PROFILE,NEW_PROFILE)
 r['archive_backend/service.py']=substitute(r['archive_backend/service.py'],OLD_DRAIN,NEW_DRAIN)
 for name,value in r.items():compile(value,name,'exec')
 return checked(r,OUTPUTS)
def restore_sources(sources):
 r=checked(sources,OUTPUTS);r['fishing_api/postgres.py']=substitute(r['fishing_api/postgres.py'],NEW_RPC,OLD_RPC)
 r['archive_backend/service.py']=substitute(r['archive_backend/service.py'],NEW_PROFILE,OLD_PROFILE)
 r['archive_backend/service.py']=substitute(r['archive_backend/service.py'],NEW_DRAIN,OLD_DRAIN)
 return checked(r,PARENTS)
