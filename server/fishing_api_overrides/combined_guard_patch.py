"""Combine the existing two full catalog checks; no cache or omitted predicate.

Preparation only. The exact filtered/reset parent and the existing reviewed
combiner are pinned. Per RPC one statement replaces two, still checking every
role, relation and allowed-function property in that transaction. Catalog work
remains O(C+F), C=user catalog objects, F=the fixed RPC whitelist. No warmup or
steady authorization cache, and no additional retained per-account state.
"""
from __future__ import annotations

import ast
import hashlib

PARENT_SHA256 = '894df9749b0dbe72f64d2c893587efb5248bfa7f2d0dbc534dbf015a624aafad'
COMBINER_SHA256 = '7d151834d617147915b60823989e628f2307423b7803c8285d55ae62b67c367e'


def patch_postgres(source, combiner):
    if (type(source) is not str or type(combiner) is not bytes
            or hashlib.sha256(source.encode()).hexdigest() != PARENT_SHA256
            or hashlib.sha256(combiner).hexdigest() != COMBINER_SHA256):
        raise ValueError('combined_guard_exact_parent_required')
    namespace = {'__name__': 'reviewed_transport_combiner'}
    exec(compile(combiner, '<pinned-transport-combiner>', 'exec'), namespace)
    method = namespace['_method'](source, '_check_runtime')
    if source.count('\ndef _json_dumps') != 1 or source.count(method) != 1:
        raise ValueError('combined_guard_anchor_changed')
    result = source.replace('\ndef _json_dumps', '\n_PRINCIPAL_CHECK = '
                            + repr(namespace['merged_sql'](source)) + '\n\ndef _json_dumps', 1)
    result = result.replace(method, namespace['MERGED_CHECK'].strip(), 1)
    old, new = ast.parse(source), ast.parse(result)
    for tree in (old, new):
        tree.body = [n for n in tree.body if not (
            isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
            and n.targets[0].id == '_PRINCIPAL_CHECK')]
        for cls in tree.body:
            if isinstance(cls, ast.ClassDef) and cls.name == 'PostgresRpcClient':
                cls.body = [m for m in cls.body if not (
                    isinstance(m, ast.FunctionDef) and m.name == '_check_runtime')]
    if ast.dump(old, include_attributes=False) != ast.dump(new, include_attributes=False):
        raise ValueError('combined_guard_unrelated_change')
    compile(result, '<combined-full-guard-v1>', 'exec')
    return result
