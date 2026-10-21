"""Assemble and sign a new external candidate; native Dota smoke is still required.

No Workshop upload, game startup, source rewrite, private-key copy or plaintext
fallback is performed. Trust policy and the public key come from this checkout.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import build_runtime_release as api
import protect_runtime_lua as lua_protection
import protect_data
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

POLICY = Path(__file__).with_name("protection_policy.json")
LUA_POLICY = TOOLS / "lua_protection_policy.json"
MANIFEST = "_release_manifest.json"
SIGNATURE = "_release_signature.json"
READY = "_RELEASE_READY_FOR_NATIVE_SMOKE.json"
FAILED = "_RELEASE_FAILED.json"


def load_json(path: Path) -> dict:
    def unique(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise ValueError("Duplicate JSON field in release policy/report")
            result[name] = value
        return result
    data = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique)
    if not isinstance(data, dict):
        raise ValueError("Expected release policy/report object")
    return data


def source_file(root: Path, relative: str) -> Path:
    # The stricter backup helper also rejects Windows device/ADS aliases and
    # linked ancestors. This function only reads explicit regular files.
    return protect_data.source_path(root, relative)


def trusted_configuration(source: Path, policy_path: Path, lua_policy_path: Path) -> tuple[dict, dict, Path]:
    policy = load_json(policy_path)
    lua_policy = load_json(lua_policy_path)
    lua_protection.check_policy(lua_policy)
    integrity = policy.get("integrity", {})
    distribution = policy.get("lua_distribution", {})
    if (policy.get("schema") != 1 or policy.get("channel") != "production"
            or integrity.get("manifest_schema") != 2 or integrity.get("change_index") != "md5"
            or integrity.get("integrity_hash") != "sha256" or integrity.get("signature") != "Ed25519"
            or integrity.get("activation_requires_full_file_verification") is not True
            or distribution.get("require_generated_string_obfuscation") is not True
            or distribution.get("source_mutation_allowed") is not False
            or distribution.get("release_profile_must_remain_plaintext_production") is not True
            or distribution.get("native_smoke_required_before_workshop_upload") is not True):
        raise ValueError("Unsupported or weakened trusted release policy")
    minimum = integrity.get("minimum_release_sequence")
    if type(minimum) is not int or not 1 <= minimum < 2 ** 64:
        raise ValueError("Invalid trusted minimum release sequence")
    declared_lua_policy = distribution.get("policy")
    if (not api.safe_relative(declared_lua_policy)
            or source_file(source, declared_lua_policy).resolve() != lua_policy_path.resolve()):
        raise ValueError("Loaded Lua policy does not match the trusted policy path")
    key_name = integrity.get("trusted_public_key")
    if not api.safe_relative(key_name):
        raise ValueError("Unsafe trusted public key path")
    public_path = source_file(source, key_name)
    public = serialization.load_pem_public_key(public_path.read_bytes())
    if not isinstance(public, Ed25519PublicKey) or protect_data.public_id(public) != integrity.get("trusted_key_id"):
        raise ValueError("Trusted public key identity mismatch")
    return policy, lua_policy, public_path


def protection_evidence(source: Path, protected: Path, lua_policy: dict, source_manifest: dict) -> tuple[dict, list[dict]]:
    report_path = source_file(protected, "_lua_protection_report.json")
    report = load_json(report_path)
    expected_policy = hashlib.sha256(api.canonical_bytes(lua_policy)).hexdigest()
    if (report.get("schema") != 1 or report.get("kind") != "offline_lua51_protection"
            or report.get("status") != "PASS_REQUIRES_NATIVE_SMOKE"
            or report.get("policy_sha256") != expected_policy
            or report.get("source_modified") is not False
            or report.get("network_used_for_transform") is not False
            or report.get("workshop_upload_performed") is not False):
        raise ValueError("Protected Lua report is failed, stale, or does not match the trusted policy")
    dependency = report.get("dependency", {})
    for field, value in lua_policy["dependency"].items():
        if dependency.get(field) != value:
            raise ValueError("Protected Lua dependency pin mismatch")
    if dependency.get("verified_source_tree_sha256") != lua_policy["dependency"]["source_tree_sha256"]:
        raise ValueError("Protected Lua dependency source was not verified")
    # Confirm the audited local source has not changed, without executing it.
    lua_protection.dependency_identity(Path(dependency["path"]), lua_policy)
    strings = report.get("generated_string_obfuscation", {})
    if (strings.get("enabled") is not True or strings.get("step") != "EncryptStrings"
            or strings.get("private_rng") is not True or strings.get("cryptographic_confidentiality") is not False
            or report.get("steps") != lua_policy["steps"]
            or report.get("generated_steps") != ["ConstantArray", "EncryptStrings", "NumbersToExpressions", "WrapInFunction"]):
        raise ValueError("Required isolated data-string obfuscation is missing")
    syntax, semantics = report.get("syntax", {}), report.get("semantic_verification", {})
    if (syntax.get("status") != "PASS" or semantics.get("status") != "PASS"
            or semantics.get("all_generated_values_exact") is not True
            or semantics.get("gameplay_rng_untouched_while_loading") is not True
            or semantics.get("new_runtime_io_os_debug_dependency") is not False
            or sorted(semantics.get("business_probe_modules", [])) != sorted(lua_policy["business_modules"])):
        raise ValueError("Protected Lua syntax, exact-value, business or RNG checks are incomplete")
    lua_paths = [row["path"] for row in source_manifest["files"]
                 if row["path"].startswith("scripts/vscripts/") and row["path"].endswith(".lua")]
    expected = lua_protection.selected_files(lua_paths, lua_policy)
    files = report.get("files")
    if (not isinstance(files, list) or len(files) != len(expected) or report.get("selected_files") != len(expected)
            or [{"path": row.get("path"), "kind": row.get("kind")} for row in files] != expected):
        raise ValueError("Protected Lua selection is incomplete, duplicated or outside the trusted selection")
    if semantics.get("summary", {}).get("files") != len(expected):
        raise ValueError("Protected Lua semantic file count mismatch")
    snapshots = {row["path"]: row for row in source_manifest["files"]}
    for row in files:
        relative = row["path"]
        before = {name: snapshots[relative][name] for name in ("bytes", "md5", "sha256")}
        if row.get("before") != before or api.checksums(source_file(source, relative)) != before:
            raise ValueError("Original Lua changed after protection: " + relative)
        after = api.checksums(source_file(protected, relative))
        if row.get("after") != after or after["sha256"] == before["sha256"]:
            raise ValueError("Protected Lua bytes changed or transformation is missing: " + relative)
    return report, expected


def new_destination(source: Path, protected: Path, destination: Path, key_file: Path) -> Path:
    destination = protect_data.external(destination, source)
    if api.within(destination, protected) or api.within(protected, destination):
        raise ValueError("Destination must not overlap the protected Lua input")
    if api.within(key_file, destination) or api.within(destination, key_file):
        raise ValueError("Signing key must be separate from the candidate")
    if destination.exists():
        raise ValueError("Destination already exists; no existing candidate is overwritten")
    return destination


def assemble(source: Path, destination: Path, protected_lua: Path, signing_key: Path, sequence: int,
             *, policy_path: Path = POLICY, lua_policy_path: Path = LUA_POLICY,
             lua: Path = Path("C:/Program Files/lua/bin/lua5.1.exe"),
             luac: Path = Path("C:/Program Files/lua/bin/luac5.1.exe")) -> dict:
    source = source.resolve(strict=True)
    protected_lua = protect_data.external(protected_lua, source)
    if not protected_lua.is_dir():
        raise ValueError("Protected Lua input must be an existing external directory")
    signing_key = protect_data.external(signing_key)
    if api.within(signing_key, protected_lua):
        raise ValueError("Signing key must not be stored with protected Lua")
    destination = new_destination(source, protected_lua, destination, signing_key)
    work = destination.parent / ("." + destination.name + ".assembly-" + uuid.uuid4().hex)
    failure = {"schema": 1, "status": "FAILED_DO_NOT_PUBLISH", "native_smoke_test": "NOT_RUN",
               "workshop_upload_performed": False, "private_key_copied": False}
    try:
        policy, lua_policy, public_key = trusted_configuration(source, policy_path, lua_policy_path)
        minimum = policy["integrity"]["minimum_release_sequence"]
        if type(sequence) is not int or not minimum <= sequence < 2 ** 64:
            raise ValueError("Release sequence is below trusted minimum or invalid")
        signing = serialization.load_pem_private_key(signing_key.read_bytes(), password=None)
        if (not isinstance(signing, Ed25519PrivateKey)
                or protect_data.public_id(signing.public_key()) != policy["integrity"]["trusted_key_id"]):
            raise ValueError("Signing key does not match the fixed trusted public key")
        del signing
        trusted_hashes = {path: api.digest(path) for path in (policy_path, lua_policy_path, public_key)}
        source_manifest = api.manifest(source)
        evidence, selected = protection_evidence(source, protected_lua, lua_policy, source_manifest)
        evidence_hash = api.digest(protected_lua / "_lua_protection_report.json")
        api.stage(source, work, source_manifest)
        selected_by_path = {row["path"]: row for row in evidence["files"]}
        for relative, row in selected_by_path.items():
            original = source_file(protected_lua, relative)
            if api.checksums(original) != row["after"]:
                raise ValueError("Protected Lua input changed before copy: " + relative)
            target = source_file(work, relative)
            shutil.copyfile(original, target)
            if api.checksums(target) != row["after"]:
                raise ValueError("Protected Lua copy verification failed: " + relative)
        # Re-run executable checks. The local evidence JSON is provenance, not
        # a cryptographic attestation that its booleans are true.
        lua_files = [work / row["path"] for row in source_manifest["files"]
                     if row["path"].startswith("scripts/vscripts/") and row["path"].endswith(".lua")]
        lua_protection.syntax_check(lua_files, luac)
        check_work = work / "_assembly_checks"
        check_work.mkdir()
        semantic_checks = lua_protection.compare_values(source, work, selected, lua, check_work)
        final_manifest = api.manifest(work)
        final_manifest["source_root"] = str(destination)
        original_by_path = {row["path"]: row for row in source_manifest["files"]}
        if {row["path"] for row in final_manifest["files"]} != set(original_by_path):
            raise ValueError("Runtime inventory changed unexpectedly during assembly")
        for row in final_manifest["files"]:
            expected = (selected_by_path[row["path"]]["after"] if row["path"] in selected_by_path
                        else {name: original_by_path[row["path"]][name] for name in ("bytes", "md5", "sha256")})
            if {name: row[name] for name in ("bytes", "md5", "sha256")} != expected:
                raise ValueError("Unexpected final runtime bytes: " + row["path"])
        full_verification = api.verify(work, final_manifest)
        if not full_verification["ok"]:
            raise ValueError("Final whole-runtime verification failed")
        if any(api.digest(path) != digest for path, digest in trusted_hashes.items()):
            raise ValueError("Trusted policy or public key changed during assembly")
        # Verify original selected source/candidate hashes again immediately
        # before publishing the signed candidate; unselected Lua is copied from
        # the latest source selection rather than an older Lua-only candidate.
        protection_evidence(source, protected_lua, lua_policy, source_manifest)
        if api.digest(protected_lua / "_lua_protection_report.json") != evidence_hash:
            raise ValueError("Protected Lua report changed during assembly")
        api.atomic_write_json(work / MANIFEST, final_manifest)
        protect_data.sign_manifest(work / MANIFEST, signing_key, work / SIGNATURE, sequence=sequence)
        authenticated = protect_data.verify_signature(work / MANIFEST, work / SIGNATURE, public_key, minimum_sequence=minimum)
        full_verification["root"] = str(destination)
        full_verification["verified_before_atomic_rename"] = True
        api.atomic_write_json(work / "_release_verification.json", full_verification)
        result = {"schema": 1, "status": "READY_FOR_NATIVE_SMOKE_ONLY", "ready_for_upload": False,
                  "native_smoke_test": "NOT_RUN", "workshop_upload_performed": False,
                  "destination": str(destination), "release_sequence": sequence,
                  "content_sha256": final_manifest["content_sha256"], "runtime_files": final_manifest["file_count"],
                  "runtime_bytes": final_manifest["bytes"], "protected_lua_files": len(selected),
                  "all_lua_syntax_checked": len(lua_files), "semantic_checks": semantic_checks,
                  "full_file_verification": True, "signature_verification": authenticated,
                  "manifest": MANIFEST, "signature": SIGNATURE, "private_key_copied": False,
                  "lua_provenance_report_sha256": evidence_hash, "provenance_report_is_not_attestation": True,
                  "trusted_policy_sha256": trusted_hashes[policy_path],
                  "lua_policy_sha256": hashlib.sha256(api.canonical_bytes(lua_policy)).hexdigest(),
                  "cryptographic_runtime_resource_encryption": False,
                  "source_modified": False}
        api.atomic_write_json(work / READY, result)
        if destination.exists():
            raise ValueError("Destination appeared during assembly; refusing to overwrite")
        if (api.is_link(work) or work.resolve(strict=True) != work
                or destination.resolve(strict=False) != destination
                or work.parent.resolve(strict=True) != destination.parent.resolve(strict=True)):
            raise ValueError("Assembly rename paths changed or escaped the explicit target parent")
        work.rename(destination)  # Windows rename refuses an existing directory.
        return result
    except Exception as error:
        failure["error"] = str(error)
        failure["partial_workspace"] = str(work) if work.exists() else None
        if work.exists():
            # A readiness marker may have been written just before a rename
            # failed. Never leave conflicting readiness in a failed workspace.
            marker = work / READY
            if marker.exists():
                marker.unlink()
            api.atomic_write_json(work / FAILED, failure)
        if not destination.exists():
            try:
                destination.mkdir(parents=True, exist_ok=False)
            except FileExistsError:
                pass  # A concurrent unrelated directory is never changed.
            else:
                api.atomic_write_json(destination / FAILED, failure)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True, help="NEW absolute external full runtime candidate")
    parser.add_argument("--protected-lua", type=Path, required=True, help="Verified external string-protected Lua candidate")
    parser.add_argument("--signing-key", type=Path, required=True, help="Explicit external Ed25519 private-key file; never copied")
    parser.add_argument("--sequence", type=int, required=True, help="Signed monotonically managed release sequence")
    args = parser.parse_args()
    try:
        result = assemble(ROOT, args.destination, args.protected_lua, args.signing_key, args.sequence)
    except Exception as error:
        print("Release assembly failed: " + str(error), file=sys.stderr)
        return 1
    print(json.dumps({name: result[name] for name in ("status", "destination", "release_sequence", "runtime_files",
                                                    "runtime_bytes", "protected_lua_files", "content_sha256", "ready_for_upload")}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
