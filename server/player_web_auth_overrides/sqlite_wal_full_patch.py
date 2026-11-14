"""Exact opt-in hot-rate parent -> verified WAL/FULL startup; no I/O on import.

One existing Service/connection/RLock, same persisted per-rate transactions.
Only constructor PRAGMAs/readbacks change; failed startup closes once, no retry.
Version/vendor/multi-process gates are operator evidence, not a version-number
allowlist. This source experiment itself neither upgrades nor opens a database.
"""
import hashlib
TARGET='runtime/player_web_auth/service.py'
INPUT_SHA256='e2dfb18dd6396d314d6364821c48c029e284aabed1890b4b2bea0265ae329e92'
WAL_ONLY_SHA256='8dcff1a5203faf4e7e7d2de5409d93d30d3a0f43c3c93904b27f8d296a43bea8'
OUTPUT_SHA256='a13dbf9082b0517490ab051c92469d3b06c955489d9cfbec1bddd151de32d35e'
_PATCHES=[('            PRAGMA journal_mode=DELETE;', '            PRAGMA journal_mode=WAL;\n            PRAGMA synchronous=FULL;'), ('        self.db.row_factory = sqlite3.Row\n        self.db.executescript("""\n            PRAGMA journal_mode=WAL;\n            PRAGMA synchronous=FULL;\n', '        self.db.row_factory = sqlite3.Row\n        # Configure and verify the owned connection before any business schema.\n        # WAL remains one writer; never weaken FULL or retry a refused startup.\n        try:\n            self.db.execute("PRAGMA journal_mode=WAL").fetchone()\n            self.db.execute("PRAGMA synchronous=FULL")\n            journal = self.db.execute("PRAGMA journal_mode").fetchone()\n            synchronous = self.db.execute("PRAGMA synchronous").fetchone()\n            if (journal is None or journal[0] != "wal" or synchronous is None\n                    or type(synchronous[0]) is not int or synchronous[0] != 2):\n                raise ValueError("auth_database_wal_full_required")\n        except BaseException:\n            self.db.close()\n            raise\n        self.db.executescript("""\n')]

def _sha(value):return hashlib.sha256(value.encode('utf8')).hexdigest()
def _normal(value):
 if type(value)is not str or len(value)>256*1024:raise ValueError('sqlite_wal_source_invalid')
 value=value.replace('\r\n','\n')
 if '\r'in value:raise ValueError('sqlite_wal_bare_CR_invalid')
 return value

def _apply(value,restore=False):
 value=_normal(value)
 if _sha(value)!=(OUTPUT_SHA256 if restore else INPUT_SHA256):raise ValueError('sqlite_wal_exact_source_changed')
 pairs=[(b,a)for a,b in reversed(_PATCHES)]if restore else _PATCHES
 for i,(a,b)in enumerate(pairs):
  if value.count(a)!=1:raise ValueError('sqlite_wal_anchor_changed')
  value=value.replace(a,b)
  expected=WAL_ONLY_SHA256 if i==0 else (INPUT_SHA256 if restore else OUTPUT_SHA256)
  if _sha(value)!=expected:raise ValueError('sqlite_wal_intermediate_changed')
 compile(value,TARGET,'exec');return value

def patch_sources(inputs):
 if type(inputs)is not dict or set(inputs)!={TARGET}:raise ValueError('sqlite_wal_input_keys_invalid')
 return {TARGET:_apply(inputs[TARGET])}
def restore_sources(outputs):
 if type(outputs)is not dict or set(outputs)!={TARGET}:raise ValueError('sqlite_wal_output_keys_invalid')
 return {TARGET:_apply(outputs[TARGET],True)}
