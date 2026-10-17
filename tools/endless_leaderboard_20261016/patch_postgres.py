"""Exact additive RPC allowlist patch for the reviewed live PostgreSQL client.

The original transport, role/ACL checks and every old signature stay byte-for-byte
unchanged.  The new two-argument binding is strictly validated in both the HTTP
handler and SQL.  Its public account ID reuses the existing bounded-text kind,
``nullable_error``, solely as a transport envelope: unlike ``request_id``, this
kind accepts legitimate account IDs shorter than eight characters.  It does not
replace the SQL decimal/range checks and grants no table permissions.

Only the exact reviewed upstream text (or this exact patch applied to it) is
accepted.  Unknown future releases must be reviewed before updating the digest.
No file is read/written by importing this module or calling patch_postgres().
"""
from __future__ import annotations

import ast
import hashlib


REVIEWED_BASE_SHA256 = "a97b8f5e03a5211cd7cf0f270942525d7cb471ddb132b35186334fb9c5d29462"
ANCHOR = '\n}\nRUNTIME_ROLE = "goufayu_app"\n'
ADDITION = '''    # BEGIN SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1
    "archive_bind_leaderboard_identity": _params(
        ("p_account", "text", "hash"),
        ("p_public_account_id", "text", "nullable_error")),
    "archive_endless_leaderboard": _params(),
    # END SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1
'''
NAMES = {"archive_bind_leaderboard_identity", "archive_endless_leaderboard"}


def _need(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _base(text: str) -> str:
    _need(isinstance(text, str), "postgres_source_type_invalid")
    if "SURVIVAL_ENDLESS_LEADERBOARD_RPC_V1" in text:
        _need(text.count(ADDITION) == 1, "postgres_patch_marker_changed")
        text = text.replace(ADDITION, "", 1)
    _need(_sha(text) == REVIEWED_BASE_SHA256, "postgres_source_not_reviewed")
    _need(text.count(ANCHOR) == 1, "postgres_signature_anchor_changed")
    return text


def restore_postgres(text: str) -> str:
    """Return the exact original source, rejecting modified/partial patches."""
    return _base(text)


def patch_postgres(text: str) -> str:
    """Add exactly two reviewed RPC signatures, idempotently and fail closed."""
    original = _base(text)
    patched = original.replace(ANCHOR, "\n" + ADDITION + ANCHOR[1:], 1)
    _need(restore_postgres(patched) == original, "postgres_reverse_patch_invalid")
    before, after = ast.parse(original), ast.parse(patched)
    dictionaries = lambda tree: [node.value for node in tree.body
        if isinstance(node, ast.Assign) and len(node.targets) == 1
        and isinstance(node.targets[0], ast.Name)
        and node.targets[0].id == "RPC_SIGNATURES"]
    old, new = dictionaries(before), dictionaries(after)
    _need(len(old) == len(new) == 1 and isinstance(old[0], ast.Dict)
          and isinstance(new[0], ast.Dict), "postgres_signature_structure_changed")
    old_names = [ast.literal_eval(key) for key in old[0].keys]
    new_names = [ast.literal_eval(key) for key in new[0].keys]
    _need(len(new_names) == len(set(new_names))
          and set(new_names) - set(old_names) == NAMES
          and new_names[:len(old_names)] == old_names,
          "postgres_signature_delta_invalid")
    # Removing only the two new dictionary entries must restore the entire AST,
    # including the strict ALLOWED_FUNCTIONS derivation and _convert() behavior.
    new[0].keys[:] = new[0].keys[:len(old_names)]
    new[0].values[:] = new[0].values[:len(old_names)]
    _need(ast.dump(before, include_attributes=False)
          == ast.dump(after, include_attributes=False), "postgres_unrelated_ast_change")
    compile(patched, "<reviewed-postgres-leaderboard-patch>", "exec")
    return patched
