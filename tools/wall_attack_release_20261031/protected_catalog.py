"""Reprotect the single reviewed asset-catalogue delta in a NEW external work tree.

The normal protection policy and its pinned Prometheus adapter remain authoritative.
This helper never selects/rebuilds business modules, signs, uploads, or writes an
installed addon. Callers must supply the catalogue hash from their verified baseline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time

TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
import protect_runtime_lua as protection

RELATIVE = "scripts/vscripts/config/generated/asset_catalog.lua"
ROW = {"path": RELATIVE, "kind": "generated_table"}
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
LUAC = Path("C:/Program Files/lua/bin/luac5.1.exe")
PRIVATE_MARKERS = (b"local shared_math=math\nlocal math={}\n", b"PRIVATE_DATA_RNG_SEED_FIXED")
BASELINE_WRAPPER = '''local M=require("config/generated/baseline_asset_catalog")
assert(type(M)=="table" and type(M.rows)=="table" and type(M.by_id)=="table", "CATALOG_SHAPE")
local found
for _,row in ipairs(M.rows) do
    if row.asset_id=="hero_permanent_hero_blademaster" then
        assert(found==nil, "DUPLICATE_BLADEMASTER")
        found=row
    end
end
assert(found and found.model_skin==1, "BASELINE_BLADEMASTER_SKIN_MUST_BE_1")
assert(rawequal(found,M.by_id.hero_permanent_hero_blademaster), "CATALOG_ROW_ALIAS")
found.model_skin=0
return M
'''


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _no_links(path: Path) -> None:
    for node in (path, *path.parents):
        if protection.runtime.is_link(node):
            raise ValueError("Linked input/output path is not permitted: " + str(node))


def _private_wrapper(raw: bytes) -> bool:
    raw = raw.replace(b"\r\n", b"\n")
    return raw.startswith(b"return(function(...)\n") and all(marker in raw for marker in PRIVATE_MARKERS)


def reprotect_asset_catalog(target_source: bytes, baseline_catalog: Path, work: Path,
                            dependency: Path, lua: Path = LUA, luac: Path = LUAC,
                            *, expected_baseline_sha256: str,
                            source_path: Path | None = None) -> dict:
    """Return a verified protected output path, preserving all input files.

    ``target_source`` must equal the full baseline return value after changing
    only the existing blademaster model_skin from numeric 1 to numeric 0. Both
    this delta check and target/output equality use the existing restricted Lua
    value verifier (including alias identity and forbidden gameplay RNG checks).
    The caller can track the original plaintext file with ``source_path``.
    """
    if not isinstance(target_source, bytes) or not target_source:
        raise ValueError("Nonempty immutable target source bytes are required")
    target_source.decode("utf-8-sig", errors="strict")
    if not re.fullmatch(r"[0-9a-f]{64}", expected_baseline_sha256):
        raise ValueError("An explicit lowercase baseline SHA256 is required")
    baseline_catalog, work, dependency = Path(baseline_catalog), Path(work), Path(dependency)
    for path in (baseline_catalog, work, dependency):
        _no_links(path)
    baseline_catalog = baseline_catalog.resolve(strict=True)
    if not baseline_catalog.is_file() or tuple(p.lower() for p in baseline_catalog.parts[-5:]) != tuple(RELATIVE.split("/")):
        raise ValueError("Expected the canonical baseline asset_catalog.lua path")
    baseline_root = baseline_catalog.parents[4]
    baseline_before = protection.runtime.checksums(baseline_catalog)
    if baseline_before["sha256"] != expected_baseline_sha256:
        raise ValueError("Baseline protected catalogue SHA256 does not match")
    baseline_bytes = baseline_catalog.read_bytes()
    if _sha(baseline_bytes) != expected_baseline_sha256 or not _private_wrapper(baseline_bytes):
        raise ValueError("Baseline must retain its audited generated-table private RNG wrapper")
    # Reuse the original absolute/new/external installed-tree boundary guard.
    work = protection.checked_destination(protection.ROOT, work)
    dependency = dependency.resolve(strict=True)
    if (protection.runtime.within(work, baseline_root) or protection.runtime.within(baseline_root, work)
            or protection.runtime.within(work, dependency) or protection.runtime.within(dependency, work)):
        raise ValueError("Work directory overlaps immutable baseline/dependency")
    source_before = None
    if source_path is not None:
        source_path = Path(source_path)
        _no_links(source_path)
        source_path = source_path.resolve(strict=True)
        source_before = protection.runtime.checksums(source_path)
        if source_before["sha256"] != _sha(target_source):
            raise ValueError("Tracked source file differs from supplied target bytes")
        if protection.runtime.within(work, source_path.parent) or protection.runtime.within(source_path.parent, work):
            raise ValueError("Work directory overlaps tracked source")
    policy_path = protection.POLICY
    policy_bytes = policy_path.read_bytes()
    policy = json.loads(policy_bytes.decode("utf-8-sig"))
    protection.check_policy(policy)
    optional = policy.get("optional_generated_string_obfuscation", {})
    if optional.get("step") != "EncryptStrings" or "generated" not in optional.get("allowed_scope", "").lower():
        raise ValueError("Pinned policy does not authorize private generated-table string protection")
    if not lua.is_file() or not luac.is_file():
        raise ValueError("Explicit Lua 5.1 and luac 5.1 executables are required")
    identity = protection.dependency_identity(dependency, policy)
    support = [protection.SUPPORT / "prometheus_offline_driver.lua", protection.SUPPORT / "verify_values.lua"]
    support_before = {str(path): protection.runtime.checksums(path) for path in support}
    if protection.run([str(lua), "-e", 'assert(_VERSION=="Lua 5.1","LUA51_REQUIRED");io.write(_VERSION)']) != "Lua 5.1":
        raise ValueError("Lua 5.1 interpreter verification failed")
    work.mkdir(parents=False, exist_ok=False)
    source_root, protected_root, normalized_root = (work / name for name in ("source", "protected", "baseline_normalized"))
    plain = source_root / RELATIVE
    output = protected_root / RELATIVE
    normalized = normalized_root / RELATIVE
    baseline_copy = normalized.with_name("baseline_asset_catalog.lua")
    for path in (plain, output, normalized):
        path.parent.mkdir(parents=True, exist_ok=True)
    plain.write_bytes(target_source)
    normalized.write_text(BASELINE_WRAPPER, encoding="ascii", newline="\n")
    baseline_copy.write_bytes(baseline_bytes)
    seed = int(hashlib.sha256((RELATIVE + _sha(target_source)).encode("ascii")).hexdigest()[:8], 16) % 2147483646 + 1
    report = {"schema": 1, "kind": "reviewed_single_asset_catalog_reprotection", "status": "INCOMPLETE",
              "path": RELATIVE, "baseline_catalog": str(baseline_catalog), "baseline_sha256": expected_baseline_sha256,
              "target_source_sha256": _sha(target_source), "source_path": str(source_path) if source_path else None,
              "output_path": str(output), "work": str(work), "dependency": identity,
              "policy_sha256": _sha(policy_bytes), "steps": ["ConstantArray", "EncryptStrings", "NumbersToExpressions", "WrapInFunction"],
              "adapter": str(support[0]), "private_rng": True, "seed": seed,
              "allowed_delta": {"asset_id": "hero_permanent_hero_blademaster", "field": "model_skin", "before": 1, "after": 0},
              "business_modules_transformed": [], "plaintext_fallback": False,
              "production_modified": False, "signing_performed": False, "upload_performed": False,
              "native_smoke": "NOT_RUN", "claim": policy["claim"]}
    report_path = work / "catalog_protection_report.json"
    protection.runtime.atomic_write_json(report_path, report)

    def unchanged() -> None:
        if protection.runtime.checksums(baseline_catalog) != baseline_before:
            raise ValueError("Immutable baseline changed during catalogue protection")
        if plain.read_bytes() != target_source or _sha(baseline_copy.read_bytes()) != expected_baseline_sha256:
            raise ValueError("External staged source changed during catalogue protection")
        if source_path is not None and protection.runtime.checksums(source_path) != source_before:
            raise ValueError("Tracked development source changed during catalogue protection")
        if policy_path.read_bytes() != policy_bytes:
            raise ValueError("Protection policy changed during catalogue protection")
        for path in support:
            if protection.runtime.checksums(path) != support_before[str(path)]:
                raise ValueError("Protection support changed during catalogue protection")
        protection.dependency_identity(dependency, policy)

    try:
        protection.syntax_check([plain, normalized, baseline_copy], luac)
        baseline_check = work / "baseline_compare"
        baseline_check.mkdir()
        report["baseline_delta_verification"] = protection.compare_values(normalized_root, source_root, [ROW], lua, baseline_check)
        started = time.perf_counter()
        protection.run([str(lua), str(support[0]), str(dependency), str(plain), str(output), str(seed), "generated_table_strings"])
        result = output.read_bytes()
        if result == target_source or not _private_wrapper(result):
            raise ValueError("Catalogue transformation did not retain protected private-RNG output")
        protection.syntax_check([output], luac)
        compare_work = work / "protected_compare"
        compare_work.mkdir()
        report["semantic_verification"] = protection.compare_values(source_root, protected_root, [ROW], lua, compare_work)
        report["build_seconds"] = time.perf_counter() - started
        report["output"] = protection.runtime.checksums(output)
        unchanged()
        report["source_hashes_unchanged"] = True
        report["status"] = "PASS_REQUIRES_NATIVE_SMOKE"
        protection.runtime.atomic_write_json(report_path, report)
        return report
    except Exception as error:
        report["status"] = "FAILED_DO_NOT_PUBLISH"
        report["error"] = str(error)
        try:
            unchanged()
            report["source_hashes_unchanged"] = True
        except Exception as integrity_error:
            report["source_hashes_unchanged"] = False
            report["integrity_error"] = str(integrity_error)
        # Only this new, unverified output is removed; no input is ever rewritten.
        if output.exists():
            output.unlink()
        protection.runtime.atomic_write_json(report_path, report)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--baseline-catalog", type=Path, required=True)
    parser.add_argument("--baseline-sha256", required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--prometheus-root", type=Path, required=True)
    parser.add_argument("--lua", type=Path, default=LUA)
    parser.add_argument("--luac", type=Path, default=LUAC)
    args = parser.parse_args()
    report = reprotect_asset_catalog(args.source.read_bytes(), args.baseline_catalog, args.work,
                                    args.prometheus_root, args.lua, args.luac,
                                    expected_baseline_sha256=args.baseline_sha256, source_path=args.source)
    print(json.dumps({"status": report["status"], "output_path": report["output_path"], "sha256": report["output"]["sha256"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
