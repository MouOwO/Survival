"""Exact business-catalogue generation binding for newly rendered release families.

This adds one reviewed producer, not an exclusion by directory or file type.
Frozen historical families are never patched. The collector and signing verifier
both execute immutable generator bytes against in-memory schema bytes, extract
the public key/nonce from the immutable generated module, encrypt again and
compare the complete resulting module. O(input bytes) explicit operator work;
no game timer, SDK, network, account, database, key creation or runtime write.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

HELPER = "tools/business_wire_binding.py"
GENERATOR = "tools/seal_business_wire_catalog.py"
SCHEMA = "server/player_web_auth/business_wire_schema.json"
CATALOG = "scripts/vscripts/config/generated/business_wire_catalog.lua"
LOADER = "scripts/vscripts/core/local_config_cipher.lua"
INPUTS = (SCHEMA, CATALOG, LOADER)
OPERATORS = (HELPER, GENERATOR)
KIND = "IMMUTABLE_BUSINESS_WIRE_CATALOG_ENCRYPTION_REPLAY"
MAX_SCHEMA = 256 * 1024
MAX_INPUT = 1024 * 1024


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def lf(raw):
    return raw.replace(b"\r\n", b"\n")


def canonical(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False,
                      sort_keys=True, separators=(",", ":")).encode("utf-8")


def need(condition, code):
    if not condition:
        raise ValueError(code)


EXECUTED_SOURCE_LF_SHA256 = sha(lf(Path(__file__).read_bytes()))
SEAL_SOURCE_LF_SHA256 = sha(lf(Path(__file__).with_name("seal_business_wire_catalog.py").read_bytes()))


def operator_identity(root):
    """Bind cached helper execution and the reviewed seal source at import time."""
    expected = {HELPER: EXECUTED_SOURCE_LF_SHA256, GENERATOR: SEAL_SOURCE_LF_SHA256}
    for name, digest in expected.items():
        need(sha(lf((Path(root) / name).read_bytes())) == digest,
             "business_wire_operator_changed_after_import:" + name)
    return expected


def replay(*, source_revisions, input_bytes, operator_bytes):
    """Pure replay from explicit immutable bytes, never a working-tree import.

    Revision:path provenance is independently checked by the caller's existing
    Git readers. The input and operator sets here are exact, not caller-chosen
    patterns. Byte hashes identify provenance, but the generator actually runs.
    """
    need(type(source_revisions) is dict and set(source_revisions) == {"game", "content", "operator"}
         and all(type(x) is str and re.fullmatch(r"[0-9a-f]{40}", x) for x in source_revisions.values()),
         "business_wire_exact_source_triple_required")
    expected_inputs = {"game:" + name for name in INPUTS}
    need(type(input_bytes) is dict and set(input_bytes) == expected_inputs,
         "business_wire_exact_input_readset_required")
    need(type(operator_bytes) is dict and set(operator_bytes) == set(OPERATORS),
         "business_wire_exact_operator_readset_required")
    for name, raw in {**input_bytes, **operator_bytes}.items():
        need(type(raw) is bytes and 0 < len(raw) <= MAX_INPUT,
             "business_wire_bounded_raw_bytes_required:" + name)
    need(len(input_bytes["game:" + SCHEMA]) <= MAX_SCHEMA,
         "business_wire_schema_budget_exceeded")
    need(sha(lf(operator_bytes[HELPER])) == EXECUTED_SOURCE_LF_SHA256,
         "business_wire_helper_not_exact_loaded_operator")
    need(sha(lf(operator_bytes[GENERATOR])) == SEAL_SOURCE_LF_SHA256,
         "business_wire_generator_not_exact_reviewed_operator")

    namespace = {"__name__": "_immutable_business_wire_seal", "__file__": str(Path(__file__).with_name("seal_business_wire_catalog.py"))}
    exec(compile(operator_bytes[GENERATOR], GENERATOR, "exec"), namespace)

    class SchemaInput:
        reads = 0

        def read_bytes(self):
            self.reads += 1
            need(self.reads == 1, "business_wire_generator_schema_readset_changed")
            return input_bytes["game:" + SCHEMA]

    source = SchemaInput()
    namespace["SCHEMA"] = source
    schema_raw, fingerprint, plaintext = namespace["material"]()
    need(source.reads == 1, "business_wire_generator_did_not_read_exact_schema")
    generated = input_bytes["game:" + CATALOG]
    matched = namespace["FORMAT"].fullmatch(generated.decode("ascii"))
    need(matched is not None, "business_wire_generated_module_format_invalid")
    _, public_key, public_nonce, stated_hash = matched.groups()
    need(stated_hash == fingerprint, "business_wire_generated_schema_hash_mismatch")
    key, nonce = bytes.fromhex(public_key), bytes.fromhex(public_nonce)
    # This is real encryption, not only decrypt/hash checking or string search.
    ciphertext = namespace["crypt"](plaintext, key, nonce)
    rebuilt = namespace["render"](ciphertext, key, nonce, fingerprint)
    need(rebuilt == generated, "business_wire_generated_module_replay_mismatch")
    namespace["verify"](rebuilt, plaintext, fingerprint)
    return {
        "kind": KIND, "source_revisions": dict(source_revisions),
        "schema_path": SCHEMA, "catalog_path": CATALOG, "loader_path": LOADER,
        "schema_sha256": fingerprint, "schema_bytes": len(schema_raw),
        "plaintext_sha256": sha(plaintext), "ciphertext_sha256": sha(ciphertext),
        "generated_lua_sha256": sha(rebuilt), "generated_lua_bytes": len(rebuilt),
        "public_key": public_key, "public_nonce": public_nonce,
        "generator_entry": "material -> crypt -> render -> verify",
        "complete_generated_bytes_equal": True, "encryption_reexecuted": True,
        "schema_read_count": source.reads, "working_tree_generator_used": False,
        "source_readset": {name: {"sha256": sha(raw), "bytes": len(raw)}
                           for name, raw in sorted(input_bytes.items())},
        "operator_readset": {name: {"sha256": sha(raw), "lf_sha256": sha(lf(raw)), "bytes": len(raw)}
                             for name, raw in sorted(operator_bytes.items())},
        "runtime_files_written": 0, "sdk_calls": 0, "network_calls": 0,
        "private_key_read": False, "confidentiality_from_client_claimed": False,
    }


def _evidence(proof, ledger):
    return {"kind": KIND, "sha256": ledger.sha(ledger.canonical(proof)),
            "source_revisions": dict(proof["source_revisions"]), "verification": proof}


def install_collector(namespace):
    original_dependencies = namespace["loaded_dependencies"]
    original_production = namespace["load_production"]

    def dependencies():
        result = original_dependencies()
        result.update(operator_identity(namespace["ROOT"]))
        return result

    def production(ctx, spec, targets, originals):
        original_production(ctx, spec, targets, originals)
        if CATALOG not in ctx.trees["game"]:
            need(SCHEMA not in ctx.trees["game"], "business_wire_schema_without_generated_catalog")
            return
        inputs = {"game:" + name: ctx.content("game:" + name) for name in INPUTS}
        operators = {name: ctx.operator_blob(ctx.pins["operator"], name) for name in OPERATORS}
        proof = replay(source_revisions=ctx.pins, input_bytes=inputs, operator_bytes=operators)
        evidence = _evidence(proof, namespace["ledger"])
        # The generated Lua must already have a real protection target. This
        # helper never substitutes plaintext or invents a protection receipt.
        namespace["_attach_generation"](ctx, targets, CATALOG, inputs["game:" + CATALOG],
                                         list(inputs), evidence)
        originals.append(evidence)

    namespace["loaded_dependencies"] = dependencies
    namespace["load_production"] = production


def install_exact_review(namespace):
    original_load = namespace["load_review_blobs"]
    original_reviews = namespace["make_reviews"]

    def load(sources, rows, pins):
        blobs = original_load(sources, rows, pins)
        if CATALOG in sources.trees["game"]:
            for name in INPUTS:
                blobs[name] = sources.get("game", name)
            for name in OPERATORS:
                blobs["operator:" + name] = namespace["compiler"].run_git(
                    namespace["ROOT"], "show", pins["operator"] + ":" + name)
        return blobs

    def reviews(scope, scope_sha256, pins, blobs, facts, scan, scan_sha256):
        selected = [row for row in scope["decisions"]
                    if row["inventory_status"] == "UNMAPPED_SOURCE_PENDING"
                    and row["source"]["path"] == SCHEMA]
        need(len(selected) <= 1 and all(row["source"]["repo"] == "game" for row in selected),
             "business_wire_exact_standalone_schema_required")
        filtered = dict(scope, decisions=[row for row in scope["decisions"] if row not in selected])
        result = original_reviews(filtered, scope_sha256, pins, blobs, facts, scan, scan_sha256)
        if not selected:
            return result
        proof = replay(source_revisions=pins,
            input_bytes={"game:" + name: blobs[name] for name in INPUTS},
            operator_bytes={name: blobs["operator:" + name] for name in OPERATORS})
        row, fact, raw = selected[0], facts["game:" + SCHEMA], blobs[SCHEMA]
        need(fact["git_oid"] == row["source"]["head_oid"]
             and fact["sha256"] == row["candidate"]["sha256"] == sha(raw)
             and fact["source_revision"] == pins["game"], "business_wire_schema_scope_fact_mismatch")
        refs = [{"source_id": key, "git_oid": value["git_oid"], "sha256": value["sha256"],
                 "matches": value["matches"][SCHEMA], "reference_role": value["reference_role"]}
                for key, value in scan["references"].items() if SCHEMA in value["matches"]]
        result["reviews"].append({
            "source_id": "game:" + SCHEMA, "source_revision": pins["game"],
            "git_oid": fact["git_oid"], "sha256": sha(raw), "bytes": len(raw),
            "classification": "EXACT_BUSINESS_WIRE_SCHEMA_REENCRYPTED_BY_IMMUTABLE_GENERATOR",
            "checks": proof, "references": refs,
            "reason": "Reexecuted the selected immutable generator on this exact schema with the public key/nonce extracted from the committed Lua, and reproduced every generated byte. The standalone schema is retained in Git; the encrypted Lua and its loader require separate protected/identity runtime bindings. This is not a directory exclusion or client gameplay acceptance.",
            "standalone_runtime_file_required": False, "authority_granted": False,
            "retained_in_git": True, "scope_action_proposal": "non_runtime_standalone_exact_path_review",
            "semantic_or_build_dependency": True,
            "runtime_targets_requiring_separate_generator_or_compiler_binding": [CATALOG],
        })
        result["reviews"].sort(key=lambda entry: entry["source_id"])
        result["scope"]["actual_unmapped_count"] += 1
        result["scope"]["standalone_review_count"] += 1
        result["scope"]["exact_paths"] = sorted([*result["scope"]["exact_paths"], SCHEMA])
        return result

    namespace["load_review_blobs"] = load
    namespace["make_reviews"] = reviews


def install_package(namespace):
    # The new family _loaded_paths includes both helper and generator before
    # its import-time snapshot. Keep its existing exact operator gate intact.
    identities = operator_identity(namespace["ROOT"])
    for name, expected in identities.items():
        need(namespace["LOADED_OPERATOR_SHA256"].get(name) == expected,
             "business_wire_package_operator_identity_missing:" + name)
    original = namespace["verify_original_evidence"]

    def verify(evidence, pins, manifest, bindings, **kwargs):
        # Preserve the original exact three-producer contract and every check.
        # A separate exact build-input proof augments its answer afterwards.
        answer = original(evidence, pins, manifest, bindings, **kwargs)
        rows = {row["path"]: row for row in manifest["files"]}
        source_raw = kwargs.get("source_raw")
        if CATALOG not in rows:
            need(not isinstance(source_raw, dict) or "game:" + CATALOG not in source_raw,
                 "business_wire_runtime_catalog_missing")
            return answer
        need(type(source_raw) is dict and all("game:" + name in source_raw for name in INPUTS),
             "business_wire_signing_complete_readset_required")
        operators = {name: namespace["pending"]._git(namespace["ROOT"], "show", pins["operator"] + ":" + name,
                     counts=namespace["Counter"]()) for name in OPERATORS}
        proof = replay(source_revisions=pins,
            input_bytes={"game:" + name: source_raw["game:" + name] for name in INPUTS},
            operator_bytes=operators)
        ledger = namespace["ledger"]
        selected = [row for row in bindings if row["resource"] == CATALOG]
        need(len(selected) == 1 and selected[0]["kind"] == "protected",
             "business_wire_real_catalog_protection_required")
        binding = selected[0]
        expected_inputs = {"game:" + name: sha(source_raw["game:" + name]) for name in INPUTS}
        need(all(binding["inputs"].get(key) == digest for key, digest in expected_inputs.items()),
             "business_wire_catalog_generation_inputs_not_bound")
        need(SCHEMA not in rows and LOADER in rows
             and ledger.fingerprint(rows[LOADER]) == ledger.byte_fingerprint(source_raw["game:" + LOADER]),
             "business_wire_loader_missing_or_schema_exposed")
        receipts = kwargs.get("binding_receipts")
        receipt_sha = binding.get("receipt_sha256")
        need(type(receipts) is dict and receipt_sha in receipts,
             "business_wire_raw_binding_receipt_required")
        receipt = ledger.document(receipts[receipt_sha], receipt_sha)
        expected_record = _evidence(proof, ledger)
        reference = {"kind": KIND, "original_receipt_sha256": expected_record["sha256"],
                     "original_source_revisions": dict(pins)}
        entry = receipt.get("bindings", {}).get(CATALOG, {})
        need(entry.get("original_receipts", []).count(reference) == 1
             and sum(ledger.canonical(item) == ledger.canonical(expected_record)
                     for item in receipt.get("original_receipts", [])) == 1,
             "business_wire_original_replay_receipt_mismatch")
        answer["business_wire"] = proof
        return answer

    namespace["verify_original_evidence"] = verify


def install(namespace, role):
    """Called only by newly rendered, committed family source."""
    need(role in ("collector", "exact_review", "package"), "business_wire_unknown_release_hook")
    operator_identity(namespace["ROOT"])
    {"collector": install_collector, "exact_review": install_exact_review,
     "package": install_package}[role](namespace)
