"""Exact additive expiry/logout indexes; no import/database I/O.
Only five CREATE INDEX statements in the existing schema script may change.
DELETE predicates, transactions, clocks, rate policy and cleanup frequency stay byte-identical.
"""
import ast,hashlib
TARGET='runtime/player_web_auth/service.py'
EXPERIMENT_ID='sqlite-auth-expiry-index-v1'
SPECS={'a62b2355e84fb56bbc0e9613c2c00354f4e385599b483ea0cd4132d5d514b4b5': 'acdd532fffd66e86907f22ed34bcd2b04d12a240ae38018420e8729060e5586b', 'e2dfb18dd6396d314d6364821c48c029e284aabed1890b4b2bea0265ae329e92': '842ac27041e69f494c33782256d322a926e5b7f68f75ef5c914c39ee42caa11e', 'a13dbf9082b0517490ab051c92469d3b06c955489d9cfbec1bddd151de32d35e': '7fcc7a7f3eb1c1bce248dc4299f2f21d15b950693bca038f8ee02e5063d32e73', 'd6d602e76adaaa8340114506b4438094d7d81487d8cbb4a19c9c2856e734c382': 'fc76cbf5d54c8e2ff2382fa5ebd9500fbac81399db90b6e6e70ce085d8902c8b'}
DDL='            CREATE INDEX IF NOT EXISTS challenges_expires_token_expires_idx ON challenges(expires,COALESCE(token_expires,0));\n            CREATE INDEX IF NOT EXISTS browsers_expires_idx ON browsers(expires);\n            CREATE INDEX IF NOT EXISTS flows_expires_idx ON flows(expires);\n            CREATE INDEX IF NOT EXISTS nonces_expires_idx ON nonces(expires);\n            CREATE INDEX IF NOT EXISTS flows_sid_hash_idx ON flows(sid_hash);\n'
ANCHOR='                PRIMARY KEY(key,bucket));\n'
def _normal(s):
 if type(s)is not str or len(s)>256*1024:raise ValueError('auth_expiry_source_invalid')
 s=s.replace('\r\n','\n')
 if '\r'in s:raise ValueError('auth_expiry_bare_CR')
 return s
def _sha(s):return hashlib.sha256(s.encode('utf8')).hexdigest()
def _scrub(tree):
 cls=next(n for n in tree.body if isinstance(n,ast.ClassDef)and n.name=='Service');ctor=next(n for n in cls.body if isinstance(n,ast.FunctionDef)and n.name=='__init__')
 calls=[n for n in ast.walk(ctor)if isinstance(n,ast.Call)and isinstance(n.func,ast.Attribute)and n.func.attr=='executescript']
 if len(calls)!=1 or len(calls[0].args)!=1 or not isinstance(calls[0].args[0],ast.Constant):raise ValueError('auth_expiry_ctor_script_changed')
 calls[0].args[0]=ast.Constant(value='ONLY_FIVE_INDEX_DDL');return ast.dump(tree,include_attributes=False)
def _apply(source,restore=False):
 source=_normal(source);digest=_sha(source)
 if restore:
  reverse={v:k for k,v in SPECS.items()}
  if digest not in reverse:raise ValueError('auth_expiry_child_changed')
  a,b=ANCHOR+DDL,ANCHOR;wanted=reverse[digest]
 else:
  if digest not in SPECS:raise ValueError('auth_expiry_parent_changed')
  a,b=ANCHOR,ANCHOR+DDL;wanted=SPECS[digest]
 if source.count(a)!=1:raise ValueError('auth_expiry_anchor_changed')
 result=source.replace(a,b,1)
 if _sha(result)!=wanted:raise ValueError('auth_expiry_output_changed')
 compile(result,TARGET,'exec')
 if _scrub(ast.parse(source))!=_scrub(ast.parse(result)):raise ValueError('auth_expiry_AST_delta_changed')
 return result
def patch_sources(inputs):
 if type(inputs)is not dict or set(inputs)!={TARGET}:raise ValueError('auth_expiry_source_keys_invalid')
 return {TARGET:_apply(inputs[TARGET])}
def restore_sources(outputs):
 if type(outputs)is not dict or set(outputs)!={TARGET}:raise ValueError('auth_expiry_child_keys_invalid')
 return {TARGET:_apply(outputs[TARGET],True)}
