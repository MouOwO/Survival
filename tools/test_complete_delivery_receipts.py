"""Original-receipt contract and byte checks; synthetic bytes, no native claims."""
from copy import deepcopy
import hashlib
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import ledger as m

PINS = {"game": "a" * 40, "content": "b" * 40, "operator": "c" * 40}
fp = m.byte_fingerprint


def oid(raw): return hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()


def compiler_case(texture=False):
    name = "panorama/images/example.vtex_c" if texture else "panorama/scripts/example.vjs_c"
    source_name = name.replace(".vtex_c", ".vtex").replace(".vjs_c", ".js")
    raw = b'"m_fileName" "string" "panorama/images/pixel.png"\n' if texture else b"function f() {}\n"
    payload = raw.replace(b"\n", b"\r\n")
    source = {"repo": "content", "path": source_name, "oid": oid(raw), "mode": "100644", "git_blob": fp(raw), "content": fp(raw),
              "lfs": False, "source_revision": PINS["content"], "compiler_input": fp(payload), "normalization": "IMMUTABLE_GIT_TEXT_TO_COMPILER_CRLF_ONLY"}
    data = b"actual texture metadata" if texture else payload
    metadata_size = 28 + len(data)
    artifact = struct.pack("<IHHII", metadata_size, 12, 0, 8, 1) + struct.pack("<4sII", b"DATA", 8, len(data)) + data
    if texture: artifact += b"actual external pixel payload"
    tool = b"# original compile operator\n"; inventory = b"# original source inventory operator\n"
    tools = {"tools/release_compile_scope.py": tool, "tools/release_pending_inventory.py": inventory}
    operator = {"revision": PINS["operator"], "tools_lf_sha256": {key: m.sha(value) for key, value in tools.items()}}
    row = {"resource": name, "status": "READY_FOR_ISOLATED_OFFICIAL_COMPILE", "sources": [source], "primary_source": source_name, "engine_references": []}
    plan = {"kind": "IMMUTABLE_ISOLATED_OFFICIAL_COMPILE_PLAN", "source_revisions": {key: PINS[key] for key in ("game", "content")},
            "operator_binding": operator, "tool_sha256": m.sha(tool), "scope_sha256": "d" * 64,
            "resources": [row], "inputs": {source_name: source}, "counts": {"READY_FOR_ISOLATED_OFFICIAL_COMPILE": 1}}
    log = b"1 compiled, 0 failed\n"; log_sha = m.sha(log)
    result = {"resource": name, "status": "OFFICIALLY_COMPILED_AND_SOURCE_BOUND", "compiler_exit_code": 0,
              "inputs": [source], "primary_source": source_name, "engine_references": [], "compiler_log_sha256": log_sha,
              "artifact": fp(artifact), "blocks": [{"tag": "DATA", **{key: value for key, value in fp(data).items() if key != "md5"}}],
              "compiled_js_DATA_equals_input": None if texture else True, "rerl_bytes": 0, "resource_metadata_bytes": metadata_size,
              "texture_external_payload_bytes": len(artifact) - metadata_size, "texture_external_payload_sha256": m.sha(artifact[metadata_size:]) if texture else None}
    proof = {"kind": "ISOLATED_OFFICIAL_COMPILER_PROOF", "source_revisions": plan["source_revisions"], "operator_binding": operator,
             "compiler_sha256": "e" * 64, "scope_sha256": plan["scope_sha256"], "tool_sha256": m.sha(tool),
             "complete": True, "sdk_calls": 0, "git_mutations": 0, "project_worktree_writes": 0,
             "results": [result], "counts": {"OFFICIALLY_COMPILED_AND_SOURCE_BOUND": 1}}
    return dict(plan=plan, proof=proof, source_revisions=PINS.copy(), compiler_sha256="e" * 64, operator_tools=tools,
                source_bytes={"content:" + source_name: raw}, artifacts={name: artifact}, compiler_logs={log_sha: log})


def compiler_inputs(case):
    value = deepcopy(case); plan = m.canonical(value.pop("plan")); proof = value.pop("proof")
    proof["plan_sha256"] = m.sha(plan); proof = m.canonical(proof)
    return dict(plan_raw=plan, plan_sha256=m.sha(plan), proof_raw=proof, proof_sha256=m.sha(proof), **value)


def protection_case():
    overrides = ["addoninfo.txt", "scripts/vscripts/addon_game_mode_client.lua", "scripts/vscripts/config/commerce_payment_access.lua",
                 "scripts/vscripts/config/player_web_auth.lua", "scripts/vscripts/config/release_profile.lua",
                 "scripts/vscripts/config/workshop_connection.lua", "scripts/vscripts/core/test_access_policy.lua"]
    generated, business = "scripts/vscripts/config/generated/example.lua", "scripts/vscripts/core/release_policy.lua"
    sources = {name: ("original " + name + "\n").encode() for name in [*overrides, generated, business]}
    production = sources.copy()
    for name in overrides: production[name] = ("production " + name + "\n").encode()
    selected = [{"path": name, "kind": "generated_table" if name == generated else "business"} for name in sorted((generated, business))]
    dependency_files = {"LICENSE": b"original license", "cli.lua": b"cli", "src/main.lua": b"main"}
    records = [{"path": name, "bytes": len(raw), "sha256": m.sha(raw)} for name, raw in sorted(dependency_files.items(), key=lambda pair: tuple(p.lower() for p in Path(pair[0]).parts))]
    dependency = {"source_tree_files": 3, "source_tree_sha256": m.sha(m.canonical(records)[:-1]), "license_sha256": m.sha(dependency_files["LICENSE"])}
    identity = {**dependency, "verified_source_tree_sha256": dependency["source_tree_sha256"]}
    policy = {"generated_prefix": "scripts/vscripts/config/generated/", "generated_exclusions": {"item_resources.lua": "separate resolver"},
              "business_modules": [business], "always_plaintext": [overrides[4]], "steps": ["ConstantArray", "NumbersToExpressions", "WrapInFunction"],
              "dependency": dependency}
    policy_raw = m.canonical(policy)
    tools = {"tools/protect_runtime_lua.py": b"protection operator\n", "tools/complete_delivery_release_20261103/production.py": b"production operator\n",
             "tools/lua_protection_policy.json": policy_raw}
    plain = [{"path": name, "source_revision": PINS["game"], "git_oid": oid(raw), "source_sha256": m.sha(raw), "source_bytes": len(raw)}
             for name, raw in sorted(sources.items()) if name.endswith(".lua")]
    output = {row["path"]: b"verified transformed " + production[row["path"]] for row in selected}
    rows = [{**row, "before": fp(production[row["path"]]), "after": fp(output[row["path"]]),
             "seed": int(m.sha((row["path"] + m.sha(production[row["path"]])).encode())[:8], 16) % 2147483646 + 1} for row in selected]
    proof = {"kind": "offline_lua51_protection", "status": "PASS_REQUIRES_NATIVE_SMOKE", "policy_sha256": m.sha(m.canonical(policy)[:-1]),
             "dependency": identity, "source_modified": False, "network_used_for_transform": False, "workshop_upload_performed": False,
             "generated_string_obfuscation": {"enabled": True, "private_rng": True}, "generated_steps": ["ConstantArray", "EncryptStrings", "NumbersToExpressions", "WrapInFunction"],
             "steps": policy["steps"], "files": rows, "selected_files": len(rows), "source_files": len(plain), "syntax": {"status": "PASS", "all_lua_files": len(plain)},
             "semantic_verification": {"status": "PASS", "all_generated_values_exact": True, "gameplay_rng_untouched_while_loading": True,
                 "new_runtime_io_os_debug_dependency": False, "summary": {"files": len(rows)}, "files": [{"path": row["path"]} for row in rows], "business_probe_modules": [business]}}
    binaries = {"lua": b"original Lua binary", "luac": b"original luac binary"}
    prep = {"kind": "COMPLETE0302_PRODUCTION_LUA_PREPARATION_NOT_RELEASE_AUTHORITY", "source_revisions": PINS.copy(), "protection_verified": True,
            "baseline_manifest_sha256": "d" * 64, "sdk_calls": 0, "git_mutations": 0, "installed_tree_writes": 0, "pinned_prometheus": identity,
            "plain_inputs": plain, "production_overrides": [{"path": name, "source_sha256": m.sha(sources[name]), "production_sha256": m.sha(production[name]),
                "production_bytes": len(production[name]), "parent_sha256": "f" * 64} for name in overrides], "protection_selected": selected,
            "executed_operator_inputs": [{"path": name, "revision": PINS["operator"], "git_sha256": m.sha(raw), "executed_lf_sha256": m.sha(raw), "normalization": "CRLF_TO_LF"} for name, raw in tools.items()],
            "lua_binaries": {name: {"sha256": m.sha(raw)} for name, raw in binaries.items()},
            "behavior_probes": {"five_account_engine_io_simulation": True, "four_configs_constant_policy_only": True, "deleted_preview_dependency_absent": True,
                "hosted_lobby_and_original_entry_engine_io_simulation": True, "actual_steam_login": False, "native_acceptance": False, "http_calls": 0, "sdk_calls": 0},
            "protected_bindings": [{"path": row["path"], "kind": row["kind"], "source_revision": PINS["game"], "source_sha256": row["before"]["sha256"],
                "production_sha256": row["after"]["sha256"], "production_bytes": row["after"]["bytes"], "exact_values_and_rng_verified": True} for row in rows]}
    return dict(prep=prep, proof=proof, policy_raw=policy_raw, policy_sha256=m.sha(policy_raw), source_revisions=PINS.copy(),
                source_bytes=sources, production_inputs=production, protected_outputs=output, operator_tools=tools,
                dependency_files=dependency_files, lua_binaries=binaries)


def protection_inputs(case):
    value = deepcopy(case); proof = m.canonical(value.pop("proof")); prep = value.pop("prep")
    prep["protection_report_sha256"] = m.sha(proof); prep = m.canonical(prep)
    return dict(production_raw=prep, production_sha256=m.sha(prep), protection_raw=proof, protection_sha256=m.sha(proof), **value)


def generator_case():
    tool, gen = "tools/complete_delivery_release_20261103/generator_binding.py", "tools/build_item_resources.py"
    jsons = ["data/ui/item_resources.json", "data/presentation/approved_names_20261030.json"]
    adapters = ["panorama/src/scripts/custom_game/item_art_remaining_5d5c1152eb.js", "panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js"]
    lua = "scripts/vscripts/config/generated/item_resources.lua"
    names = ["panorama/src/scripts/custom_game/common/item_resources.js", lua, "panorama/src/scripts/custom_game/native_ui_icons.js",
             "panorama/src/scripts/custom_game/archive_v10_icons.js", *adapters]
    source = {"game:" + name: (b'{"fixture":1}\n' if name in jsons else b"// adapter\n") for name in [*jsons, *adapters]}
    outputs = {name: source.get("game:" + name, ("output " + name + "\n").encode()) for name in names}
    mirrors = {"panorama/" + name[len("panorama/src/"):]: raw.replace(b"\n", b"\r\n") for name, raw in outputs.items() if name != lua}
    operators = {tool: b"fixture committed binding tool\n", gen: b"fixture committed generator\n"}
    def fact(raw, commit): return {"commit": commit, "git_oid": oid(raw), **fp(raw)}
    proof = {"kind": "IMMUTABLE_ITEM_RESOURCE_GENERATOR_PROOF", "source_revisions": PINS.copy(), "generator_exit_code": 0,
             "immutable_rebuild_equals_target": True, "sdk_calls": 0, "network_calls": 0, "runtime_files_modified": False, "protected": False, "compiled": False,
             "binding_tool": {"path": tool, "operator_revision": PINS["operator"], "exact_committed_tool": True, "diagnostic_only": False,
                              "operator_blob": fact(operators[tool], PINS["operator"]), "loaded_lf_sha256": m.sha(operators[tool])},
             "generator": {"path": gen, **fact(operators[gen], PINS["operator"])},
             "executed_operator_inputs": {gen: {"revision": PINS["operator"], "normalization": "IDENTITY_EXACT_GIT_BYTES",
                 "git_sha256": m.sha(operators[gen]), "executed_sha256": m.sha(operators[gen]), "executed_lf_sha256": m.sha(operators[gen])}},
             "inputs": {key: fact(raw, PINS["game"]) for key, raw in source.items()},
             "input_normalizations": {name: {"normalization": "LF_TO_CRLF", "git_sha256": m.sha(source["game:" + name]),
                 "executed": fp(source["game:" + name].replace(b"\n", b"\r\n"))} for name in jsons},
             "outputs": {name: {"repo": "game", "path": name, **fact(raw, PINS["game"]), "inputs": sorted(source), "generated_exact_git_bytes": True,
                 "kind": "executable_resolver_not_protected" if name == lua else "authored_js_requires_official_compile"} for name, raw in outputs.items()},
             "content_mirrors": {name: {**fact(raw, PINS["content"]), "normalization": "CRLF_TO_LF_ONLY", "normalized_sha256": m.sha(raw.replace(b"\r\n", b"\n"))}
                                 for name, raw in mirrors.items()},
             "execution": {"python": fp(b"fixture python"), "isolated_python": True, "only_reviewed_inputs_exported": True,
                 "outputs_initially_absent_except_two_adapters": True, "commands": [{"mode": mode, "exit_code": 0, "stdout_sha256": "e" * 64,
                     "result": {"status": status, "outputs": names}} for mode, status in (("generate", "GENERATED"), ("check", "CHECK_PASS"))]},
             "checks": {"six_outputs_exact": True, "five_content_mirrors_equal": True, "generate_then_check": True, "no_unreviewed_file_writes": True}}
    return dict(proof=proof, source_revisions=PINS.copy(), input_bytes=source, output_bytes=outputs, content_mirrors=mirrors,
                operator_bytes=operators, python_bytes=b"fixture python")


def generator_inputs(case):
    value = deepcopy(case); proof = m.canonical(value.pop("proof"))
    return dict(proof_raw=proof, proof_sha256=m.sha(proof), **value)


class OriginalReceiptTests(unittest.TestCase):
    def test_raw_movie_runtime_copy_requires_exact_dual_authors_and_recorded_bytes(self):
        c = compiler_case(); name = "panorama/videos/custom_game/map.webm"; raw = b"\x1aE\xdf\xa3raw movie"
        fact = dict(path=name, oid=oid(raw), mode="100644", git_blob=fp(raw), content=fp(raw), lfs=False)
        pin = dict(fact, repo="content", source_revision=PINS["content"], compiler_input=fp(raw), normalization="BINARY_GIT_IDENTITY",
                   game_author=dict(fact, repo="game", source_revision=PINS["game"]))
        c["plan"]["resources"][0]["sources"].append(pin)
        c["plan"]["inputs"][name] = pin
        c["proof"]["results"][0]["inputs"].append(pin)
        c["proof"]["results"][0]["runtime_raw_dependencies"] = {name: fp(raw)}
        c["source_bytes"].update({"content:" + name: raw, "game:" + name: raw})
        m.verify_compiler_receipt(**compiler_inputs(c))
        for replacement in ({}, {name: fp(raw + b"changed")}):
            bad = deepcopy(c); bad["proof"]["results"][0]["runtime_raw_dependencies"] = replacement
            with self.assertRaisesRegex(ValueError, "compiler_raw_movie_runtime_binding_mismatch"):
                m.verify_compiler_receipt(**compiler_inputs(bad))
        bad = deepcopy(c); del bad["proof"]["results"][0]["runtime_raw_dependencies"]
        with self.assertRaisesRegex(ValueError, "compiler_raw_movie_runtime_binding_mismatch"):
            m.verify_compiler_receipt(**compiler_inputs(bad))
        bad = deepcopy(c); del bad["plan"]["inputs"][name]["game_author"]
        with self.assertRaisesRegex(ValueError, "compiler_raw_movie_dual_author_required"):
            m.verify_compiler_receipt(**compiler_inputs(bad))

    def test_real_compiler_schema_and_actual_js_data(self):
        result = m.verify_compiler_receipt(**compiler_inputs(compiler_case()))
        self.assertEqual(len(result["outputs"]), 1); self.assertFalse(result["publication_ready"])

    def test_texture_external_pixels_are_allowed_and_independently_bound(self):
        c = compiler_case(True); result = m.verify_compiler_receipt(**compiler_inputs(c))
        self.assertEqual(result["outputs"][next(iter(c["artifacts"]))], fp(next(iter(c["artifacts"].values()))))
        c["proof"]["results"][0]["texture_external_payload_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "external_texture"): m.verify_compiler_receipt(**compiler_inputs(c))

    def test_texture_block_cannot_claim_external_pixels_as_metadata(self):
        c = compiler_case(True); key = next(iter(c["artifacts"])); raw = bytearray(c["artifacts"][key]); struct.pack_into("<I", raw, 24, len(raw) - 28)
        c["artifacts"][key] = bytes(raw); c["proof"]["results"][0]["artifact"] = fp(bytes(raw))
        with self.assertRaisesRegex(ValueError, "block_invalid"): m.verify_compiler_receipt(**compiler_inputs(c))

    def test_nontexture_trailing_payload_and_fake_data_flags_refused(self):
        c = compiler_case(); key = next(iter(c["artifacts"])); c["artifacts"][key] += b"unreviewed tail"; c["proof"]["results"][0]["artifact"] = fp(c["artifacts"][key])
        with self.assertRaisesRegex(ValueError, "header_invalid"): m.verify_compiler_receipt(**compiler_inputs(c))
        c = compiler_case(); key = next(iter(c["artifacts"])); raw = c["artifacts"][key].replace(b"function", b"FUNCTION"); c["artifacts"][key] = raw; c["proof"]["results"][0]["artifact"] = fp(raw)
        with self.assertRaisesRegex(ValueError, "js_data"): m.verify_compiler_receipt(**compiler_inputs(c))

    def test_original_compiler_source_operator_log_and_complete_sets_are_required(self):
        for kind in ("source", "operator", "exit", "log", "count", "missing"):
            with self.subTest(kind=kind):
                c = compiler_case()
                if kind == "source": c["source_bytes"][next(iter(c["source_bytes"]))] += b"changed"
                elif kind == "operator": c["operator_tools"]["tools/release_compile_scope.py"] += b"changed"
                elif kind == "exit": c["proof"]["results"][0]["compiler_exit_code"] = False
                elif kind == "log":
                    log = b"10 failed"; c["proof"]["results"][0]["compiler_log_sha256"] = m.sha(log); c["compiler_logs"] = {m.sha(log): log}
                elif kind == "count": c["proof"]["counts"] = {"OFFICIALLY_COMPILED_AND_SOURCE_BOUND": 2}
                else: c["artifacts"].clear()
                with self.assertRaises(ValueError): m.verify_compiler_receipt(**compiler_inputs(c))

    def test_lfs_requires_original_pointer_and_exact_resolved_payload(self):
        c = compiler_case(); key = next(iter(c["source_bytes"])); raw = c["source_bytes"][key]
        pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:" + m.sha(raw).encode() + b"\nsize " + str(len(raw)).encode() + b"\n"
        pin = c["plan"]["resources"][0]["sources"][0]
        pin.update(lfs=True, git_blob=fp(pointer), oid=oid(pointer))
        c["source_bytes"][key] = {"git_blob": pointer, "content": raw}
        self.assertEqual(len(m.verify_compiler_receipt(**compiler_inputs(c))["outputs"]), 1)
        c["source_bytes"][key]["content"] += b"changed"
        with self.assertRaisesRegex(ValueError, "resolved_lfs_pointer_identity"): m.verify_compiler_receipt(**compiler_inputs(c))
        c["source_bytes"][key] = pointer
        with self.assertRaisesRegex(ValueError, "unresolved_lfs_pointer"): m.verify_compiler_receipt(**compiler_inputs(c))

    def test_original_protection_and_all_selected_actual_bytes(self):
        result = m.verify_protection_receipt(**protection_inputs(protection_case()))
        self.assertEqual(len(result["protected_outputs"]), 2); self.assertEqual(len(result["production_overrides"]), 7)
        self.assertFalse(result["publication_ready"])

    def test_all_value_rng_dependency_binary_and_no_plaintext_fallback(self):
        for kind in ("values", "rng", "selected", "dependency", "binary", "plaintext", "seed", "policy", "override", "operator"):
            with self.subTest(kind=kind):
                c = protection_case()
                if kind == "values": c["proof"]["semantic_verification"]["files"].pop()
                elif kind == "rng": c["proof"]["semantic_verification"]["gameplay_rng_untouched_while_loading"] = False
                elif kind == "selected": c["protected_outputs"].pop(next(iter(c["protected_outputs"])))
                elif kind == "dependency": c["dependency_files"]["LICENSE"] += b"changed"
                elif kind == "binary": c["lua_binaries"]["lua"] += b"changed"
                elif kind == "plaintext":
                    key = next(iter(c["protected_outputs"])); c["protected_outputs"][key] = c["production_inputs"][key]
                elif kind == "seed": c["proof"]["files"][0]["seed"] += 1
                elif kind == "policy": c["operator_tools"]["tools/lua_protection_policy.json"] += b"changed"
                elif kind == "override": c["prep"]["production_overrides"].pop()
                else: c["prep"]["executed_operator_inputs"][0]["git_sha256"] = "0" * 64
                with self.assertRaises(ValueError): m.verify_protection_receipt(**protection_inputs(c))

    def test_generator_original_input_normalization_outputs_and_content_mirrors(self):
        result = m.verify_item_generator_receipt(**generator_inputs(generator_case()))
        self.assertEqual(len(result["outputs"]), 6); self.assertFalse(result["publication_ready"])

    def test_generator_diagnostic_tool_unknown_normalization_and_mixed_bytes_refused(self):
        for kind in ("diagnostic", "normalization", "source", "output", "mirror", "operator", "binary", "count", "compiled"):
            with self.subTest(kind=kind):
                c = generator_case()
                if kind == "diagnostic": c["proof"]["binding_tool"]["exact_committed_tool"] = False
                elif kind == "normalization": c["proof"]["input_normalizations"][next(iter(c["proof"]["input_normalizations"]))]["normalization"] = "AUTODETECT"
                elif kind == "source": c["input_bytes"][next(iter(c["input_bytes"]))] += b"changed"
                elif kind == "output": c["output_bytes"][next(iter(c["output_bytes"]))] += b"changed"
                elif kind == "mirror": c["content_mirrors"][next(iter(c["content_mirrors"]))] += b"changed"
                elif kind == "operator": c["operator_bytes"]["tools/build_item_resources.py"] += b"changed"
                elif kind == "binary": c["python_bytes"] += b"changed"
                elif kind == "count": c["proof"]["execution"]["commands"].pop()
                else: c["proof"]["compiled"] = True
                with self.assertRaises(ValueError): m.verify_item_generator_receipt(**generator_inputs(c))


if __name__ == "__main__": unittest.main()
