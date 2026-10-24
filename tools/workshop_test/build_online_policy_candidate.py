"""Reprotect exactly the online release policy in a NEW signed v03 candidate.

Default is a read-only plan. The v02 candidate and all other runtime bytes stay
unchanged. No installation, key creation, Workshop upload, or game launch occurs.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import json
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_web_auth_candidate as web

pack = web.pack
protect = web.protect_runtime_lua
ROOT = web.ROOT
BASE = Path("D:/Survival_发布候选/20261024_ws4_web_auth_v02")
BASE_TRUSTED = BASE.with_name(BASE.name + "_trusted_source")
BASE_SHA = "71beca29993e564be0def2e2251ef568c4ca2b52e3b7e340e711e6847dbbd9a3"
BASE_FILES = 6627
POLICY_MODULE = "scripts/vscripts/core/release_policy.lua"
RELEASE_PROFILE = "scripts/vscripts/config/release_profile.lua"
WEB_CONFIG = "scripts/vscripts/config/player_web_auth.lua"
MINIMUM_SEQUENCE = 2026102403
LUA = Path("C:/Program Files/lua/bin/lua5.1.exe")
LUAC = web.LUA_COMPILER
DEPENDENCY = Path("D:/Survival_安全工具/prometheus")


MATRIX = r'''
local plain, protected = arg[1], arg[2]
local checked = 0
local function load_policy(path, channel, config_kind, server, tools)
    local env = {}
    for _,name in ipairs({"assert","error","ipairs","pairs","next","select","pcall","xpcall",
        "tonumber","tostring","type","unpack","setmetatable","getmetatable","rawget","rawset","rawequal"}) do
        env[name] = _G[name]
    end
    env.math,env.string,env.table = {},{},{}
    for k,v in pairs(math) do env.math[k]=v end
    for k,v in pairs(string) do env.string[k]=v end
    for k,v in pairs(table) do env.table[k]=v end
    env.math.random=function() error("GAMEPLAY_RNG_FORBIDDEN") end
    env._G=env
    env.IsServer=function() return server end
    env.IsInToolsMode=function() return tools end
    env.require=function(name)
        if name=="config/release_profile" then return {channel=channel} end
        assert(name=="config/player_web_auth", "UNREVIEWED_POLICY_DEPENDENCY")
        if config_kind=="false" then return {enabled=false} end
        if config_kind=="true" then return {enabled=true} end
        if config_kind=="empty" then return {} end
        if config_kind=="malformed" then return "malformed" end
        if config_kind=="truthy" then return {enabled=1} end
        error("MISSING_WEB_AUTH_CONFIG")
    end
    local chunk=assert(loadfile(path));setfenv(chunk,env)
    return chunk()
end
for _,channel in ipairs({"development","production"}) do
    for _,kind in ipairs({"false","true","empty","malformed","truthy","missing"}) do
        for _,server in ipairs({false,true}) do
            for _,tools in ipairs({false,true}) do
                local expected=channel=="development" and kind=="false" and server and tools
                for _,path in ipairs({plain,protected}) do
                    local module=load_policy(path,channel,kind,server,tools)
                    assert(module.is_production()==(channel~="development"),"PRODUCTION_IDENTITY_CHANGED")
                    assert(module.development_allowed()==expected,"ONLINE_OR_OFFLINE_CHEAT_BOUNDARY_CHANGED")
                    local denied=module.denied_result()
                    assert(denied.ok==false and denied.error=="release_debug_disabled","DENIAL_CHANGED")
                end
                checked=checked+1
            end
        end
    end
end
print("ONLINE_POLICY_MATRIX_PASS\t"..checked)
'''


def authenticate_base():
    pinned, _ = pack.handoff.trusted_policy(pack.handoff.POLICY)
    with web.trusted_root(BASE_TRUSTED):
        base, manifest, signature, _ = pack.authenticate(BASE)
    web.need(manifest["content_sha256"] == BASE_SHA and manifest["file_count"] == BASE_FILES,
             "Immutable v02 candidate identity mismatch")
    web.need(signature["key_id"] == pinned["integrity"]["trusted_key_id"], "v02 trusted key differs from checkout pin")
    web.need(signature["release_sequence"] == 2026102402, "Unexpected v02 release sequence")
    pack.runtime.require_production(base)
    web.need(b"enabled = true" in pack.protect_data.source_path(base, WEB_CONFIG).read_bytes(),
             "v02 web authorization must stay enabled")
    return base, manifest, signature


def protect_one(raw, base, work, dependency, lua, luac):
    base = pack.handoff.regular_path(base)
    policy = pack.handoff.load_json(ROOT / "tools/lua_protection_policy.json")
    protect.check_policy(policy)
    web.need(POLICY_MODULE in policy["business_modules"], "Release policy is not an approved protected business module")
    identity = protect.dependency_identity(dependency, policy)
    web.need(lua.is_file() and luac.is_file(), "Reviewed Lua 5.1 tools are missing")
    source, output = work / "source", work / "protected"
    for directory in (source, output):
        for name in (RELEASE_PROFILE, WEB_CONFIG):
            target = directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(pack.protect_data.source_path(base, name).read_bytes())
        pack.runtime.require_production(directory)
    plain = source / POLICY_MODULE
    plain.parent.mkdir(parents=True, exist_ok=True)
    plain.write_bytes(raw)
    protected = output / POLICY_MODULE
    protected.parent.mkdir(parents=True, exist_ok=True)
    protect.syntax_check([plain], luac)
    seed = int(hashlib.sha256((POLICY_MODULE + web.sha(raw)).encode("ascii")).hexdigest()[:8], 16) % 2147483646 + 1
    protect.run([str(lua), str(protect.SUPPORT / "prometheus_offline_driver.lua"), str(dependency.resolve()),
                 str(plain), str(protected), str(seed), "baseline"])
    transformed = protected.read_bytes()
    web.need(transformed != raw, "Protected policy was not transformed; plaintext substitution rejected")
    protect.syntax_check([protected], luac)
    semantic = protect.compare_values(source, output, [{"path": POLICY_MODULE, "kind": "business"}], lua, work)
    probe = work / "online_policy_matrix.lua"
    probe.write_text(MATRIX, encoding="ascii", newline="\n")
    report = protect.run([str(lua), str(probe), str(plain), str(protected)])
    web.need(report.strip() == "ONLINE_POLICY_MATRIX_PASS\t48", "Protected policy behavior matrix failed")
    protect.dependency_identity(dependency, policy)
    web.need(plain.read_bytes() == raw, "Policy source changed during protection")
    return transformed, {"module": POLICY_MODULE, "source_sha256": web.sha(raw), "runtime_sha256": web.sha(transformed),
                         "seed": seed, "steps": policy["steps"], "dependency": identity,
                         "semantic_verification": semantic, "behavior_matrix_cases": 48,
                         "plaintext_substitution": False, "generated_modules_rebuilt": 0}


def audit_change(old, new, transformed, protected):
    before = {row["path"]: row for row in old["files"]}
    after = {row["path"]: row for row in new["files"]}
    web.need(before.keys() == after.keys(), "Runtime inventory additions/removals are forbidden")
    changed = {name for name in before if before[name] != after[name]}
    web.need(changed == {POLICY_MODULE}, "Only the protected central policy may change")
    web.need(len(protected) == 180 and POLICY_MODULE in protected, "The protected 180-module set changed")
    web.need(after[POLICY_MODULE]["sha256"] == web.sha(transformed), "Protected output changed during staging")
    web.need(all(before[name] == after[name] for name in protected if name != POLICY_MODULE),
             "Another protected module changed")
    return {"path": POLICY_MODULE, "before": before[POLICY_MODULE], "after": after[POLICY_MODULE]}


def build(args):
    base, baseline, signature = authenticate_base()
    protected = web.protected_paths(baseline)
    source = pack.protect_data.source_path(ROOT, POLICY_MODULE).read_bytes()
    head = web.git("rev-parse", "HEAD").decode("ascii").strip()
    result = {"ok": True, "status": "READ_ONLY_PLAN", "base_content_sha256": BASE_SHA,
              "base_files": BASE_FILES, "release_sequence": args.sequence,
              "allowed_changes": [POLICY_MODULE], "protected_modules": 180,
              "reviewed_head": head, "policy_source_sha256": web.sha(source),
              "online_cheats_allowed": False, "release_profile_sha256": pack.runtime.digest(base / RELEASE_PROFILE),
              "workshop_upload_performed": False, "game_started": False}
    if not args.build:
        return result
    web.need(args.sequence >= MINIMUM_SEQUENCE and args.sequence > signature["release_sequence"], "Release sequence must advance")
    web.need(args.signing_key is not None, "--build requires --signing-key")
    destination, trusted, package_output, key = web.output_paths(args, base)
    with tempfile.TemporaryDirectory(prefix="ws4-online-policy-") as folder:
        transformed, protection = protect_one(source, base, Path(folder), args.prometheus_root, args.lua, args.luac)
    destination.mkdir(parents=True, exist_ok=False)
    for row in baseline["files"]:
        target = destination / row["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack.protect_data.source_path(base, row["path"]), target)
    (destination / POLICY_MODULE).write_bytes(transformed)
    manifest = pack.runtime.manifest(destination)
    changed = audit_change(baseline, manifest, transformed, protected)
    web.need(pack.protect_data.source_path(ROOT, POLICY_MODULE).read_bytes() == source,
             "Reviewed policy source changed during build")
    web.need(web.git("rev-parse", "HEAD").decode("ascii").strip() == head, "Reviewed HEAD changed during build")
    trusted.mkdir(parents=True, exist_ok=False)
    for name in (*pack.handoff.GATE_FILES, pack.handoff.ACCESS_FILE, *web.POLICY_FILES):
        origin = base if name not in web.POLICY_FILES else BASE_TRUSTED
        target = trusted / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pack.protect_data.source_path(origin, name).read_bytes())
    pack.runtime.atomic_write_json(destination / pack.handoff.MANIFEST, manifest)
    pack.protect_data.sign_manifest(destination / pack.handoff.MANIFEST, key,
                                    destination / pack.handoff.SIGNATURE, args.sequence)
    with web.trusted_root(trusted):
        pack.authenticate(destination)
        packaged = None
        if package_output is not None:
            package_output.mkdir(parents=True, exist_ok=False)
            packaged = pack.package(destination, package_output, "3824360109", build=True)
    result.update(status="SIGNED_ONLINE_POLICY_REQUIRES_NATIVE_TEST", content_sha256=manifest["content_sha256"],
                  runtime_policy_sha256=web.sha(transformed), candidate={"content_sha256": manifest["content_sha256"]},
                  files=manifest["file_count"], changed=[changed], protection=protection,
                  other_protected_modules_preserved=179, all_other_runtime_bytes_preserved=True,
                  private_key_copied=False, signature_valid=True, destination=str(destination),
                  trusted_source=str(trusted), packaged=packaged, native_smoke="NOT_RUN")
    pack.runtime.atomic_write_json(destination / "_online_policy_provenance.json", result)
    return result


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build", action="store_true")
    result.add_argument("--destination", type=Path)
    result.add_argument("--trusted-source", type=Path)
    result.add_argument("--signing-key", type=Path)
    result.add_argument("--sequence", type=int, default=MINIMUM_SEQUENCE)
    result.add_argument("--package-output", type=Path)
    result.add_argument("--prometheus-root", type=Path, default=DEPENDENCY)
    result.add_argument("--lua", type=Path, default=LUA)
    result.add_argument("--luac", type=Path, default=LUAC)
    return result


def main():
    try:
        print(json.dumps(build(parser().parse_args()), ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"ok": False, "error": "online_policy_build_failed", "detail": str(error)[:500]}, ensure_ascii=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
