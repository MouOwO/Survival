"""Add the two tutorial RPC signatures to an existing PostgreSQL transport.

The backend transport lives outside this addon. Build a reviewed overlay with
this additive patch before deploying the paired SQL migration. It changes only
RPC_SIGNATURES and preserves all existing validation, privilege/readiness
checks, timeout handling and parameterized SQL.
"""
from __future__ import annotations

import argparse
import ast
from copy import deepcopy
from pathlib import Path

ANCHOR = '\n}\nRUNTIME_ROLE = "goufayu_app"\n'
ADDITION = '''    # BEGIN SURVIVAL_ONBOARDING_RPC_V1
    "onboarding_state": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id")),
    "onboarding_finish": _params(("p_account", "text", "hash"),
        ("p_session", "text", "request_id"), ("p_outcome", "text", "reward_id")),
    # END SURVIVAL_ONBOARDING_RPC_V1
'''
NAMES = {"onboarding_state", "onboarding_finish"}


def signatures(tree):
    values = [node.value for node in tree.body if isinstance(node, ast.Assign)
              and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
              and node.targets[0].id == "RPC_SIGNATURES"]
    if len(values) != 1 or not isinstance(values[0], ast.Dict):
        raise ValueError("onboarding_postgres_signature_layout_invalid")
    return values[0]


def patch_postgres(source):
    if not isinstance(source, str):
        raise ValueError("onboarding_postgres_source_invalid")
    before = ast.parse(source)
    old = signatures(before)
    names = [ast.literal_eval(key) for key in old.keys]
    if len(names) != len(set(names)):
        raise ValueError("onboarding_postgres_duplicate_signature")
    if set(names) & NAMES:
        if not NAMES <= set(names) or source.count(ADDITION) != 1:
            raise ValueError("onboarding_postgres_partial_or_changed_patch")
        # Also verify this exact patch can be removed and reapplied safely.
        original = source.replace(ADDITION, "", 1)
        if patch_postgres(original) != source:
            raise ValueError("onboarding_postgres_patch_mismatch")
        return source
    if source.count(ANCHOR) != 1 or "SURVIVAL_ONBOARDING_RPC_V1" in source:
        raise ValueError("onboarding_postgres_signature_anchor_invalid")
    if 'ALLOWED_FUNCTIONS = tuple(_signature(name, parameters) for name, parameters in RPC_SIGNATURES.items())' not in source:
        raise ValueError("onboarding_postgres_derived_allowlist_required")
    patched = source.replace(ANCHOR, "\n" + ADDITION + ANCHOR[1:], 1)
    after = ast.parse(patched)
    new = signatures(after)
    new_names = [ast.literal_eval(key) for key in new.keys]
    if new_names[:len(names)] != names or set(new_names)-set(names) != NAMES:
        raise ValueError("onboarding_postgres_signature_delta_invalid")
    compare = deepcopy(after)
    reduced = signatures(compare)
    reduced.keys, reduced.values = reduced.keys[:len(names)], reduced.values[:len(names)]
    if ast.dump(before,include_attributes=False) != ast.dump(compare,include_attributes=False):
        raise ValueError("onboarding_postgres_unrelated_change")
    compile(patched, "<onboarding-postgres-overlay>", "exec")
    return patched


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args = parser.parse_args()
    output = patch_postgres(args.source.read_text(encoding="utf-8-sig"))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(output,encoding="utf-8",newline="\n")
