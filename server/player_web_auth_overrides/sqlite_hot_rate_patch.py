"""Exact observed-PWA source experiment: indexed, once-per-new-minute rate pruning.

No import side effects, WAL change, authorization cache or transaction batching.
Per request the original persisted UPSERT+SELECT remains; startup adds one index.
After wall-clock rollback, old buckets inserted behind the high-water minute may
remain until the next strictly newer minute. Effective current-bucket counters
and 429 behavior stay authoritative; housekeeping retention is not byte-identical.
"""
import hashlib
TARGET='runtime/player_web_auth/service.py'
EXPERIMENT_ID='sqlite-rate-prune-v1'
INPUT_SHA256='a62b2355e84fb56bbc0e9613c2c00354f4e385599b483ea0cd4132d5d514b4b5'
OUTPUT_SHA256='e2dfb18dd6396d314d6364821c48c029e284aabed1890b4b2bea0265ae329e92'
_PATCHES=[('                PRIMARY KEY(key,bucket));\n        """)', '                PRIMARY KEY(key,bucket));\n            CREATE INDEX IF NOT EXISTS limits_bucket_idx ON limits(bucket);\n        """)'), ('        self.db.commit()\n\n    def close(self):', '        self.db.commit()\n        self._rate_cleanup_bucket = None\n\n    def close(self):'), ('    def rate(self, scope, actor, maximum):\n        now = int(self.clock())\n        key, bucket = self._derived("rate:" + scope + ":" + actor), now // 60\n        with self.lock, self.db:\n            self.db.execute("DELETE FROM limits WHERE bucket < ?", (bucket - 1,))\n            self.db.execute("INSERT INTO limits VALUES(?,?,1) ON CONFLICT(key,bucket) DO UPDATE SET count=count+1", (key, bucket))\n            count = self.db.execute("SELECT count FROM limits WHERE key=? AND bucket=?", (key, bucket)).fetchone()[0]\n        if count > maximum:\n            raise AuthError("rate_limited", 429)\n', '    def rate(self, scope, actor, maximum):\n        now = int(self.clock())\n        key, bucket = self._derived("rate:" + scope + ":" + actor), now // 60\n        with self.lock:\n            # Pruning is housekeeping, never an authorization or counter cache.\n            # Publish only after commit; a failed transaction must retry it.\n            prune = self._rate_cleanup_bucket is None or bucket > self._rate_cleanup_bucket\n            with self.db:\n                if prune:\n                    self.db.execute("DELETE FROM limits WHERE bucket < ?", (bucket - 1,))\n                self.db.execute("INSERT INTO limits VALUES(?,?,1) ON CONFLICT(key,bucket) DO UPDATE SET count=count+1", (key, bucket))\n                count = self.db.execute("SELECT count FROM limits WHERE key=? AND bucket=?", (key, bucket)).fetchone()[0]\n            if prune:\n                self._rate_cleanup_bucket = bucket\n        if count > maximum:\n            raise AuthError("rate_limited", 429)\n')]
def _normal(value):
 if type(value)is not str or len(value)>256*1024:raise ValueError('sqlite_rate_source_invalid')
 value=value.replace('\r\n','\n')
 if '\r'in value:raise ValueError('sqlite_rate_bare_CR_invalid')
 return value
def _sha(value):return hashlib.sha256(value.encode('utf8')).hexdigest()
def _apply(value,restore=False):
 value=_normal(value);expected=OUTPUT_SHA256 if restore else INPUT_SHA256
 if _sha(value)!=expected:raise ValueError('sqlite_rate_exact_source_changed')
 pairs=[(b,a)for a,b in reversed(_PATCHES)]if restore else _PATCHES
 for a,b in pairs:
  if value.count(a)!=1:raise ValueError('sqlite_rate_anchor_changed')
  value=value.replace(a,b)
 if _sha(value)!=(INPUT_SHA256 if restore else OUTPUT_SHA256):raise ValueError('sqlite_rate_output_changed')
 compile(value,TARGET,'exec');return value
def patch_sources(inputs):
 if type(inputs)is not dict or set(inputs)!={TARGET}:raise ValueError('sqlite_rate_input_keys_invalid')
 return {TARGET:_apply(inputs[TARGET])}
def restore_sources(outputs):
 if type(outputs)is not dict or set(outputs)!={TARGET}:raise ValueError('sqlite_rate_output_keys_invalid')
 return {TARGET:_apply(outputs[TARGET],True)}
