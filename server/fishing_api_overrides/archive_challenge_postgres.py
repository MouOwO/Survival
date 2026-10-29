"""Add only the durable challenge-receipt RPC to the external PG transport.

Apply to a reviewed deployment copy alongside the SQL migration and archive
service. Existing signatures, runtime role/privilege checks and parameterized
SQL are preserved. This module never edits the installed external backend.
"""
from __future__ import annotations

import argparse
import ast
from copy import deepcopy
from pathlib import Path

ANCHOR = '\n}\nRUNTIME_ROLE = "goufayu_app"\n'
NAME = "archive_commit_challenge"
ADDITION = '''    # BEGIN SURVIVAL_CHALLENGE_RECEIPT_RPC_V1
    "archive_commit_challenge": _params(
        ("p_account", "text", "hash"), ("p_id", "text", "archive_id"),
        ("p_revision", "bigint", "revision"), ("p_archive", "jsonb", "object"),
        ("p_deltas", "jsonb", "object"), ("p_error", "text", "nullable_error"),
        ("p_response", "jsonb", "object")),
    # END SURVIVAL_CHALLENGE_RECEIPT_RPC_V1
'''


def signatures(tree):
    values = [node.value for node in tree.body if isinstance(node, ast.Assign)
              and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
              and node.targets[0].id == "RPC_SIGNATURES"]
    if len(values) != 1 or not isinstance(values[0], ast.Dict):
        raise ValueError("challenge_postgres_signature_layout_invalid")
    return values[0]


def patch_postgres(source):
    if not isinstance(source, str):
        raise ValueError("challenge_postgres_source_invalid")
    before = ast.parse(source)
    old = signatures(before)
    names = [ast.literal_eval(key) for key in old.keys]
    if len(names) != len(set(names)):
        raise ValueError("challenge_postgres_duplicate_signature")
    if NAME in names:
        if source.count(ADDITION) != 1:
            raise ValueError("challenge_postgres_partial_or_changed_patch")
        original = source.replace(ADDITION, "", 1)
        if patch_postgres(original) != source:
            raise ValueError("challenge_postgres_patch_mismatch")
        return source
    if source.count(ANCHOR) != 1 or "SURVIVAL_CHALLENGE_RECEIPT_RPC_V1" in source:
        raise ValueError("challenge_postgres_signature_anchor_invalid")
    if 'ALLOWED_FUNCTIONS = tuple(_signature(name, parameters) for name, parameters in RPC_SIGNATURES.items())' not in source:
        raise ValueError("challenge_postgres_derived_allowlist_required")
    patched = source.replace(ANCHOR, "\n" + ADDITION + ANCHOR[1:], 1)
    after = ast.parse(patched)
    new = signatures(after)
    new_names = [ast.literal_eval(key) for key in new.keys]
    if new_names != names + [NAME]:
        raise ValueError("challenge_postgres_signature_delta_invalid")
    compare = deepcopy(after)
    reduced = signatures(compare)
    reduced.keys, reduced.values = reduced.keys[:-1], reduced.values[:-1]
    if ast.dump(before, include_attributes=False) != ast.dump(compare, include_attributes=False):
        raise ValueError("challenge_postgres_unrelated_change")
    compile(patched, "<challenge-postgres-overlay>", "exec")
    return patched


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = patch_postgres(args.source.read_text(encoding="utf-8-sig"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8", newline="\n")
