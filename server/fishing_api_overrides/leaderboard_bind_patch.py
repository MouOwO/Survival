"""Exact LF-only striped leaderboard binding overlay; no I/O or SQL execution."""
import hashlib
PARENT_SHA256='9de91c7e489dd114e6c32a522894434873e80448049380e1aafc224777bd10fc'
CHILD_SHA256='af4e0245ccf578de708a1e79b5f7d6ddae209ea003c57d78c46a4c5a2d16c12a'
_PATCHES=(('        self._bound = set()\n        self._lock = threading.RLock()\n', '        self._bound = set()\n        self._lock = threading.RLock()\n        # Fixed stripes bound memory; colliding accounts still serialize.\n        self._bind_locks = tuple(threading.RLock() for _ in range(128))\n'), ('def bind(self, account_id):\n        public, _ = public_identity(account_id)\n        # Avoid any repeated identity UPDATE or profile revision change. The\n        # database binding is also immutable and an idempotent insert.\n        with self._lock:\n            if public in self._bound:\n                return\n            result = self.app.rpc_client.rpc("archive_bind_leaderboard_identity", {\n                "p_account": self.app._database_account_id(public),\n                "p_public_account_id": public,\n            })\n            if not isinstance(result, dict) or result.get("ok") is not True:\n                raise ValueError("leaderboard_identity_unavailable")\n            if len(self._bound) >= 4096:\n                self._bound.clear()\n            self._bound.add(public)', 'def bind(self, account_id):\n        public, _ = public_identity(account_id)\n        # Avoid any repeated identity UPDATE or profile revision change. The\n        # database binding is also immutable and an idempotent insert.\n        with self._lock:\n            if public in self._bound:\n                return\n        with self._bind_locks[int(public) % len(self._bind_locks)]:\n            with self._lock:\n                if public in self._bound:\n                    return\n            result = self.app.rpc_client.rpc("archive_bind_leaderboard_identity", {\n                "p_account": self.app._database_account_id(public),\n                "p_public_account_id": public,\n            })\n            if not isinstance(result, dict) or result.get("ok") is not True:\n                raise ValueError("leaderboard_identity_unavailable")\n            with self._lock:\n                if len(self._bound) >= 4096:\n                    self._bound.clear()\n                self._bound.add(public)'))
def _sha(source):
    if type(source) is not str:
        raise ValueError('leaderboard_binding_source_type')
    return hashlib.sha256(source.encode('utf-8')).hexdigest()
def patch_source(source):
    if _sha(source) != PARENT_SHA256:
        raise ValueError('leaderboard_binding_parent_changed')
    for before, after in _PATCHES:
        if source.count(before) != 1:
            raise ValueError('leaderboard_binding_patch_anchor')
        source = source.replace(before, after, 1)
    if _sha(source) != CHILD_SHA256:
        raise ValueError('leaderboard_binding_child_mismatch')
    return source
def restore_source(source):
    if _sha(source) != CHILD_SHA256:
        raise ValueError('leaderboard_binding_child_changed')
    for before, after in reversed(_PATCHES):
        if source.count(after) != 1:
            raise ValueError('leaderboard_binding_restore_anchor')
        source = source.replace(after, before, 1)
    if _sha(source) != PARENT_SHA256:
        raise ValueError('leaderboard_binding_parent_mismatch')
    return source
