"""Plan, or explicitly sign, a new thin native-cloud candidate.

The default verifies frozen SHOP02, HELPER04/2706, native UI receipts and every
projected change without reading a signing key or writing a candidate. --build
only creates the fixed new thin overlay and review sources. It never publishes,
installs, launches Dota, compiles UI, creates a view/VPK, or copies a private key.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
REFRESH_FILE = ROOT / "tools/arcade_cleanup_20261027/build_refresh.py"
REFRESH_LF_SHA = "2d06cc50dc8569c8e841a36ceeaf982af35d068cd620b092eec8d7f839b7c882"
PAYMENT_BUILDER_FILE = ROOT / "tools/arcade_payment_link_20261027/build_helper_candidate.py"
PAYMENT_BUILDER_LF_SHA = "cb737b166eb6b605609eaf3661aaecdaac2969ebe270af599abaa249c500b0f9"
RUNTIME_VALIDATOR_FILE = ROOT / "tools/build_runtime_release.py"
RUNTIME_VALIDATOR_LF_SHA = "2b321bf45df70463e84684d982d3a83189b9b3a5f7565b972bb14383de363e81"
# Review the reused builders before importing their code. Windows checkout line
# endings are immaterial here; all runtime/map/UI pins below use exact bytes.
for _file, _pin in ((REFRESH_FILE, REFRESH_LF_SHA), (PAYMENT_BUILDER_FILE, PAYMENT_BUILDER_LF_SHA),
                   (RUNTIME_VALIDATOR_FILE,RUNTIME_VALIDATOR_LF_SHA)):
    if hashlib.sha256(_file.read_bytes().replace(b"\r\n", b"\n")).hexdigest() != _pin:
        raise ValueError("Frozen dependency builder changed: " + _file.name)
sys.path.insert(0, str(REFRESH_FILE.parent))
import build_refresh as refresh
import build_workshop_entry_candidate as entry

helper, web, pack, frozen = refresh.helper, refresh.web, refresh.pack, refresh.frozen
need, read_input, row_bytes = web.need, helper.read_input, refresh.row_bytes
BASE, BASE_TRUSTED, BASE_SHA = refresh.BASE, refresh.BASE_TRUSTED, refresh.BASE_SHA
BASE_SEQUENCE, BASE_FILES = refresh.BASE_SEQUENCE, refresh.BASE_FILES
HELPER06 = Path("D:/Survival_发布候选/20261027_ws4_refresh_helper_v04_overlay")
HELPER06_TRUSTED = HELPER06.with_name(HELPER06.name + "_trusted_source")
HELPER06_SHA = "c7264a14a09a8bc9961578213b85c4e7c1b829e16eacc045e4fe4672f71a7872"
HELPER06_SEQUENCE = 2026102706
REVISION, RELEASE_SEQUENCE = "WS4-NATIVE-CLOUD-02", 2026102708
DESTINATION = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_overlay")
TRUSTED_DESTINATION = DESTINATION.with_name(DESTINATION.name + "_trusted_source")
VIEW = Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_view")
PACKAGE = Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v02")
MAIN, CLIENT = helper.MAIN, "scripts/vscripts/addon_game_mode_client.lua"
ADDONINFO, MAP = "addoninfo.txt", "maps/ws4_entry.vpk"
HANDOFF = "scripts/vscripts/systems/native_cloud_handoff.lua"
ROSTER = "scripts/vscripts/systems/native_cloud_roster.lua"
RELEASE_CONFIG = pack.runtime.RELEASE_PROFILE
AUTO = "scripts/vscripts/systems/native_setup_auto_start.lua"
STARTUP = "scripts/vscripts/systems/startup_loading_service.lua"
MAP_SOURCE = "maps/ws4_entry.vmap"
HANDOFF_SHA = "74525fecec2367d9af5a49073e357b6024eb20a8e6dd44be96123c2e9f64ebf1"
ROSTER_SHA = "cc3f4a5f753749d8ee184a8862adc50061e00282ac9a7b2aed352b894adeb0e7"
RELEASE_CONFIG_BASE_SHA = "f217f9a3a893433aa38d1b76afdb6b3dd319056cffec2ff9a9d37beaee7aa746"
RELEASE_CONFIG_SHA = "0aea9330088965cc7cb3c9a6e900b0401b968e37d2d1fbcf92387b0a57f66890"
AUTO_BASE_SHA = "f47fb858b108d88460273112f61559b55784826f882b4ad248cd4399018a1c22"
STARTUP_BASE_SHA = "c0293001b2f1c85492b35cf28aff157e5d54ddbdcf00b3cbf7ccead0739d3a0d"
AUTO_SHA = "d4a43d9295997489b129adafe757a0aadc87320e7c66672e313797beddbf8aea"
STARTUP_SHA = "78e2be24e9b7a5a68866a183c994faf2b7240f1d36db6a3227a6a80f441727c5"
STARTUP_SOURCE_SHA = "95070e73ba064820ef98b6255c1f51e223549af75a6152b34e038888f353d658"
MAP_SHA = "abce9c7f6a1159303c799ec9a8b40afa7f724e7bf4c52509038e490afa67fecb"
MAP_SOURCE_SHA = "9b92938f8f582e1b69592a0b6699264bc7eb39836427a58e07abdf9f46920928"
ADDONINFO_BASE_SHA = "079accc9976da77481a465a883a2e9991ed217828b5f41cd159bf19258a1d197"
ADDONINFO_SHA = "bd3fc075f57875ca6f1da93c2383bd13635277faabad91ced546fdc2ba8567e2"
CLIENT_BASE_SHA = "db095896002b6f63b47484908285448c9ca2bdae70f2dce718ab2d53b02e3fd8"
CLIENT_SHA = "f4e069479bfceb852e817f9e794b761203a4e442a5a52b406632532d9c9d4576"
MAIN_SHA = "cc6323bbe12ec383e1bcbb945ac767e1527ac60b00be3b6aa4673f780eb39966"
CASH_SHA = "4101b074267fe5f05d2a50b5e5ddda2ae82a5b83ba71901cb2ce8409d57d4ff9"
COMMAND = b"changelevel template_map gamemode=15 customgamemode=3824360109 nomapvalidation=1"
OLD_REQUIRE = b'local entry = require("systems/workshop_entry")'
NEW_REQUIRE = b'local entry = require("systems/native_cloud_handoff")'
CLIENT_INERT = b"-- The native entry handoff is owned by the server; never launch a local map here.\nreturn {}\n"
LAYOUT = {"addoninfo": {"maps": "ws4_entry", "isplayable": "1", "enablepickrules": "0",
                        "ws4_entry": {"maxplayers": "4"}, "template_map": {"maxplayers": "4"}}}
ADDED = refresh.ADDED | {MAP, HANDOFF, ROSTER}
REMOVE = refresh.REMOVE
ALLOWLIST = refresh.ALLOWLIST | {ADDONINFO, CLIENT, MAP, HANDOFF, ROSTER, STARTUP, RELEASE_CONFIG}
MODIFIED = ALLOWLIST - ADDED
EXPECTED_FILES = BASE_FILES + len(ADDED) - len(REMOVE)
SPACE_RESERVE = 32 * 1024 * 1024


def reviewed_pins():
    refresh.reviewed_pins()
    need(RELEASE_SEQUENCE > HELPER06_SEQUENCE > BASE_SEQUENCE and EXPECTED_FILES == 6658
         and len(ALLOWLIST) == 48 and len(ADDED) == 22 and len(REMOVE) == 1,
         "Native-cloud fixed sequence or exact scope differs")
    need(HELPER06 == refresh.VARIANTS["helper"]["destination"]
         and refresh.VARIANTS["helper"]["sequence"] == HELPER06_SEQUENCE,
         "Must reuse the successful HELPER04/2706, not retired HELPER03")
    need(pack.handoff.NATIVE_CLOUD_ENTRY_LAYOUT == LAYOUT
         and pack.handoff.NATIVE_CLOUD_INERT_CLIENT == CLIENT_INERT
         and pack.handoff.NATIVE_CLOUD_ENTRY_PINS.get(HANDOFF) == HANDOFF_SHA
         and pack.handoff.NATIVE_CLOUD_ENTRY_PINS.get(ROSTER) == ROSTER_SHA,
         "Shared native-cloud publisher guard differs from this reviewed layout and entry source")
    for value in (HANDOFF_SHA, ROSTER_SHA, RELEASE_CONFIG_BASE_SHA, RELEASE_CONFIG_SHA, AUTO_BASE_SHA, STARTUP_BASE_SHA, AUTO_SHA, STARTUP_SHA, STARTUP_SOURCE_SHA,
                  MAP_SHA, MAP_SOURCE_SHA, ADDONINFO_BASE_SHA, ADDONINFO_SHA,
                  CLIENT_BASE_SHA, CLIENT_SHA, MAIN_SHA, CASH_SHA, HELPER06_SHA):
        need(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value), "Missing reviewed native-cloud pin")


def patch_main(raw):
    need(web.sha(raw) == refresh.MAIN_OUTPUT_SHA, "Frozen HELPER06 MAIN preimage differs")
    result = helper.replace_once(raw, OLD_REQUIRE, NEW_REQUIRE)
    need(web.sha(result) == MAIN_SHA and helper.replace_once(result, NEW_REQUIRE, OLD_REQUIRE) == raw,
         "MAIN exceeds the single entry require replacement")
    return result


def patch_release_profile(raw):
    need(web.sha(raw) == RELEASE_CONFIG_BASE_SHA, "Frozen production release profile preimage differs")
    anchor = b'    channel = "production",\r\n'
    result = helper.replace_once(raw, anchor, anchor + b'    native_cloud_roster_required = true,\r\n')
    need(web.sha(result) == RELEASE_CONFIG_SHA, "Native roster profile exceeds the single explicit flag")
    return result


def patch_addoninfo(raw):
    need(web.sha(raw) == ADDONINFO_BASE_SHA, "Frozen AddonInfo preimage differs")
    result = helper.replace_once(raw, b'"maps"              "template_map"', b'"maps"              "ws4_entry"')
    result = helper.replace_once(result, b'"ws4_entry"\r\n    {\r\n        "MaxPlayers"    "1"',
                                 b'"ws4_entry"\r\n    {\r\n        "MaxPlayers"    "4"')
    validate_layout(result)
    need(web.sha(result) == ADDONINFO_SHA, "AddonInfo differs from the exact two changes")
    return result


def validate_layout(raw):
    # The legacy publisher requires entry capacity=1. This stricter, new exact
    # layout explicitly reviews capacity=4; no old publishing guard is weakened.
    need(pack.handoff.kv(raw.decode("utf-8-sig")) == LAYOUT,
         "Native-cloud exposes only ws4_entry 4 and internal template_map 4")


def client_bytes(frozen_raw):
    need(web.sha(frozen_raw) == CLIENT_BASE_SHA, "Frozen client preimage differs")
    result = CLIENT_INERT
    need(web.sha(result) == CLIENT_SHA and not re.search(rb"SendToConsole|ServerCmd|dota_launch_custom_game|SendCustomGameEvent", result),
         "Entry client must be inert and contain no local launch/command")
    return result


def validate_handoff(raw):
    need(web.sha(raw) == HANDOFF_SHA, "Reviewed handoff source changed")
    commands = re.findall(rb'local COMMAND = "([^"\r\n]+)"', raw)
    need(commands == [COMMAND] and b'SendToServerConsole, COMMAND .. " ws4_native_roster=" .. table.concat(accounts, "_")' in raw
         and b'IsServer() == true and IsClient() == false and IsInToolsMode() == false' in raw
         and b'"ws4_entry", 4, 0.1, 1, 120' in raw
         and b'call(PlayerResource, "GetPlayerCount")' in raw and b'"sv_cheats"' in raw
         and b'GetCustomGamePlayerCount' not in raw,
         "Handoff command, context, capacity or complete-roster gate differs")
    need(b'method(GameRules, "State_Get")' in raw
         and b'DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP' in raw
         and b'DOTA_GAMERULES_STATE_POST_GAME' in raw
         and b'if state < setup then return false, "waiting_native_load" end' in raw
         and b'if state >= post_game then return nil, "native_game_finished" end' in raw
         and b'local final_phase_ready, final_phase_reason = native_phase()' in raw,
         "Handoff must wait for native SETUP, stop at POST_GAME and recheck before commit")
    need(b'run.expected_floor = math.max(run.expected_floor or 0, count)' in raw
         and b'local registered, count_reason = registered_count(run)' in raw
         and b'if expected ~= required or required ~= #rows then' in raw,
         "Handoff must retain the native registered-roster high-water mark across WAIT and SETUP")
    required = set(re.findall(rb'require\("([^"\r\n]+)"\)', raw))
    need(required == {b"config/release_profile", b"config/test_access", b"config/generated/multiplayer_rules", b"core/test_access_policy"}
         and not re.search(rb"CreateHTTPRequest|CustomGameEventManager|SendToConsole\s*\(|ForceGameStart|FinishCustomGameSetup", raw),
         "Handoff imports business/HTTP modules or exposes a client launch path")


def validate_roster(raw):
    need(web.sha(raw) == ROSTER_SHA and b'local OPTION = "ws4_native_roster"' in raw
         and b'call(GameRules, "GetGameSessionConfigValue", OPTION, "")' in raw
         and b'function M.complete_roster()' in raw
         and b'local channel, flag = profile.channel, profile.native_cloud_roster_required' in raw
         and b'"native_roster_option_required"' in raw
         and b'"native_roster_configuration_changed"' in raw,
         "Reviewed server-owned cross-map roster contract differs")


def service_patch_body(raw, kind):
    """The same additive gates apply to frozen release and current sources.

    Preserve all existing lines and original newline style. Callers which build
    a release must also use service_patch's exact frozen preimage/output pins.
    """
    need(kind in {"auto", "startup"} and b"native_cloud_roster" not in raw,
         "Roster service patch is unknown or already present")
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    def replace(before, after):
        nonlocal raw
        raw = helper.replace_once(raw, before.replace(b"\n", newline), after.replace(b"\n", newline))
    imported = b'local native_cloud_roster = require("systems/native_cloud_roster")\n'
    gate = (b'local function expected_roster_complete()\n'
            b'    local ok, complete = pcall(native_cloud_roster.complete_roster)\n'
            b'    return ok and complete == true\nend\n\n')
    if kind == "auto":
        anchor = b'local rules = require("config/generated/multiplayer_rules")\n'
        replace(anchor, anchor + imported)
        replace(b'local function maximum()\n', gate + b'local function maximum()\n')
        anchor = b'    if waiting_for_player then return waiting("waiting_connection", ids) end\n'
        replace(anchor, anchor + b'    if not expected_roster_complete() then return waiting("waiting_expected_roster", ids) end\n')
    else:
        anchor = b'local web_auth = require("systems/player_web_auth")\n'
        replace(anchor, anchor + imported)
        replace(b'local function lobby_roster_available()\n', gate + b'local function lobby_roster_available()\n')
        replace(b'    return state ~= nil and state >= minimum\n',
                b'    return state ~= nil and state >= minimum and expected_roster_complete()\n')
        replace(b'    all_loaded = all_loaded and count > 0\n',
                b'    all_loaded = all_loaded and count > 0 and expected_roster_complete()\n')
    return raw


def service_patch(raw, kind):
    before, after = ((AUTO_BASE_SHA, AUTO_SHA) if kind == "auto" else (STARTUP_BASE_SHA, STARTUP_SHA))
    need(web.sha(raw) == before, "Frozen " + kind + " service preimage differs")
    result = service_patch_body(raw, kind)
    need(web.sha(result) == after, "Frozen " + kind + " service exceeds reviewed additive gates")
    return result


def no_credentials(patches):
    for name, raw in patches.items():
        need(name in ALLOWLIST and pack.runtime.safe_relative(name), "Unsafe or foreign native-cloud runtime path")
        need(not re.search(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|Bearer [A-Za-z0-9_.~-]{20,}", raw)
             and not re.search(rb"(?:access_token|api_token|merchant_secret|client_secret)\s*=\s*[\"'][A-Za-z0-9_.~-]{20,}[\"']", raw),
             "Credential literal cannot enter native-cloud runtime")


def trust_names():
    return (*helper.previous.trust_names(), HANDOFF, ROSTER)


def capture_common(base, before, payment, payment_manifest, protected):
    """Reproduce all original strict common gates, sourcing f47 from HELPER06.

    ROOT now includes the new roster gate. The old f47 common remains bound to
    its successful signed HELPER06; it is then patched additively below. The
    historical refresh builder and its pin are kept immutable.
    """
    snapshots = {}
    patches = refresh.capture_payment(base,before,payment,payment_manifest,protected,snapshots)
    patches.update(refresh.capture_ui(snapshots)); patches.update(refresh.capture_particles(snapshots))
    patches[MAIN] = refresh.frozen_main(read_input(base/MAIN,snapshots))
    for name, expected in ((refresh.POLICY,refresh.POLICY_SHA),(AUTO,AUTO_BASE_SHA),(refresh.ENVIRONMENT,refresh.ENVIRONMENT_SHA)):
        raw = read_input((HELPER06 if name == AUTO else ROOT)/name,snapshots)
        if name == refresh.POLICY: raw = web.lf(raw)
        need(web.sha(raw)==expected,"Reviewed frozen common Lua differs: "+name)
        patches[name]=raw
    for name,expected in helper.FROZEN_CODE_PINS.items():
        need(web.sha(read_input(base/name,snapshots))==expected,"Frozen main/profile/provider preimage differs")
    provider=read_input(base/helper.PROVIDER,snapshots)
    need(b"web_auth.resolve(body.account_id, session, send, on_error)" in provider,"Frozen provider lacks per-account PWA")
    need("scripts/vscripts/debug/offline_logic_test.lua" not in {row["path"] for row in before["files"]}
         and b'require("debug/' not in patches[refresh.POLICY] and b"require('debug/" not in patches[refresh.POLICY]
         and b'package.loaded["debug/offline_logic_test"]' in patches[refresh.POLICY],
         "Production policy must tolerate the absent offline debug module")
    trusted=refresh.trust_inputs(base,snapshots);trusted[MAIN]=patches[MAIN]
    for path in (REFRESH_FILE,ROOT/"tools/lua_protection_policy.json",PAYMENT_BUILDER_FILE):read_input(path,snapshots)
    need(set(patches)==refresh.ALLOWLIST,"Frozen refresh common scope differs")
    return snapshots,patches,trusted


def cloud_patches(base, common, snapshots):
    need(set(common) == refresh.ALLOWLIST, "Incomplete or foreign refresh common scope")
    patches = dict(common)
    patches[MAIN] = patch_main(common[MAIN])
    patches[ADDONINFO] = patch_addoninfo(read_input(base / ADDONINFO, snapshots))
    # The signed frozen release never included the independent development-lobby
    # prefix. Keep this release inert; do not import undeployed ROOT dependencies.
    patches[CLIENT] = client_bytes(read_input(base / CLIENT, snapshots))
    handoff = read_input(ROOT / HANDOFF, snapshots); validate_handoff(handoff); patches[HANDOFF] = handoff
    roster = read_input(ROOT / ROSTER, snapshots); validate_roster(roster); patches[ROSTER] = roster
    patches[AUTO] = service_patch(common[AUTO], "auto")
    patches[STARTUP] = service_patch(read_input(base / STARTUP, snapshots), "startup")
    patches[RELEASE_CONFIG] = patch_release_profile(read_input(base / RELEASE_CONFIG, snapshots))
    need(web.sha(read_input(ROOT/AUTO,snapshots)) == AUTO_SHA
         and web.sha(read_input(ROOT/STARTUP,snapshots)) == STARTUP_SOURCE_SHA,
         "Current roster gate source changed from its separate reviewed development preimage")
    compiled_map = read_input(ROOT / MAP, snapshots)
    need(web.sha(compiled_map) == MAP_SHA and len(compiled_map) == 144203, "Frozen entry map artifact differs")
    entry.validate_entry_map(compiled_map)
    need(web.sha(read_input(helper.CONTENT / MAP_SOURCE, snapshots)) == MAP_SOURCE_SHA, "Entry map editable source differs")
    patches[MAP] = compiled_map
    patches[helper.CASH_CONFIG] = helper.replace_once(common[helper.CASH_CONFIG],
        b"connection_helper = true", b"connection_helper = false")
    need(web.sha(patches[helper.CASH_CONFIG]) == CASH_SHA
         and patches[helper.WEB_CONFIG] == common[helper.WEB_CONFIG]
         and patches[helper.SESSION_CONFIG] == common[helper.SESSION_CONFIG], "Cloud flags exceed helper=false only")
    need(set(patches) == ALLOWLIST, "Native-cloud overlay scope differs")
    no_credentials(patches)
    return patches


def project(before, patches):
    pack.runtime.validate_manifest(before)
    need(set(patches) == ALLOWLIST, "Native-cloud projection scope differs")
    old = {row["path"]:row for row in before["files"]}
    need(REMOVE | MODIFIED <= old.keys() and not ADDED & old.keys(), "Native-cloud preimage inventory differs")
    rows = {name:dict(row) for name,row in old.items() if name not in REMOVE}
    rows.update({name:dict(path=name, **row_bytes(raw)) for name,raw in patches.items()})
    after = {name:before[name] for name in ("schema", "kind", "hash_algorithms")}
    after.update(files=[rows[name] for name in sorted(rows)],file_count=len(rows),bytes=sum(row["bytes"] for row in rows.values()))
    after["content_sha256"] = web.sha(pack.runtime.manifest_payload(after))
    return after


def audit_changes(before, after, patches, protected):
    pack.runtime.validate_manifest(before); pack.runtime.validate_manifest(after)
    old,new = ({row["path"]:row for row in item["files"]} for item in (before,after))
    need(set(patches) == ALLOWLIST and before["file_count"] == BASE_FILES and after["file_count"] == EXPECTED_FILES
         and old.keys()-new.keys() == REMOVE and new.keys()-old.keys() == ADDED, "Native-cloud complete inventory differs")
    changed = {name for name in old.keys() & new.keys() if old[name] != new[name]}
    expected = {name for name,raw in patches.items() if name in old and old[name] != dict(path=name,**row_bytes(raw))}
    need(changed == expected and all(new[name] == dict(path=name,**row_bytes(raw)) for name,raw in patches.items()),
         "Native-cloud changes frozen runtime outside exact overlay bytes")
    need(len(protected) == len(set(protected)) == 180 and set(protected) == set(frozen.protected_paths(before))
         and not set(protected) & (ALLOWLIST | REMOVE) and all(old[name] == new[name] for name in protected),
         "Native-cloud protected 180-module inventory or bytes differ")
    for name in (helper.PROFILE, helper.PROVIDER, pack.handoff.ACCESS_FILE, "maps/template_map.vpk"):
        need(old[name] == new[name], "Frozen identity/profile/provider/gameplay map differs: " + name)
    need(pack.runtime.CRITICAL <= new.keys(), "Native-cloud removes a critical runtime file")
    validate_layout(patches[ADDONINFO]); validate_handoff(patches[HANDOFF]); validate_roster(patches[ROSTER]); no_credentials(patches)
    need(web.sha(patches[AUTO]) == AUTO_SHA and web.sha(patches[STARTUP]) == STARTUP_SHA,
         "Frozen party gates differ from the reviewed additive service patches")
    need(web.sha(patches[RELEASE_CONFIG]) == RELEASE_CONFIG_SHA,
         "Native-cloud release profile must require its original cross-map roster")
    return [dict(path=name,before=old.get(name),after=new.get(name)) for name in sorted(changed | ADDED | REMOVE)]


def authenticate_helper06(base, before, common, signed, snapshots):
    expected = refresh.project(before, refresh.variant_patches(common,"helper"))
    need(expected["content_sha256"] == HELPER06_SHA and expected["file_count"] == 6655,
         "Common projection no longer equals successful HELPER04/2706")
    for name in refresh.METADATA: read_input(HELPER06 / name,snapshots)
    for name in helper.previous.trust_names(): read_input(HELPER06_TRUSTED / name,snapshots)
    checked = refresh.verify_merged(base,HELPER06,before,expected,HELPER06_TRUSTED,HELPER06_SEQUENCE,signed["key_id"])
    need(checked["release_sequence"] == HELPER06_SEQUENCE, "Wrong helper signature generation")
    return expected


def verify_cloud(base, destination, before, after, trusted, key_id):
    need(set(trust_names()) == set(helper.previous.trust_names()) | {HANDOFF, ROSTER} and len(trust_names()) == 14,
         "Native-cloud review-source inventory differs")
    actual = set()
    for current,folders,files in os.walk(trusted,followlinks=False):
        for name in (*folders,*files): need(not pack.protect_data.linked(Path(current)/name), "Linked review source forbidden")
        actual.update((Path(current)/name).relative_to(trusted).as_posix() for name in files)
    need(actual == set(trust_names()), "Native-cloud review-source directory contains foreign files")
    signed = refresh.verify_merged(base,destination,before,after,trusted,RELEASE_SEQUENCE,key_id)
    for name in (HANDOFF, ROSTER):
        need(pack.protect_data.source_path(trusted,name).read_bytes() == pack.protect_data.source_path(destination,name).read_bytes(),
             "Signed native-cloud entry module differs from its reviewed source")
    validate_layout(pack.protect_data.source_path(destination,ADDONINFO).read_bytes())
    validate_handoff(pack.protect_data.source_path(destination,HANDOFF).read_bytes())
    validate_roster(pack.protect_data.source_path(destination,ROSTER).read_bytes())
    return signed


def verify_complete_view(view, trusted, manifest):
    """Mandatory shared publisher guards for the later real full merged view.

    A thin overlay is deliberately insufficient. The caller must first build
    and hash the complete, immutable view; no partial/virtual filesystem is used.
    """
    view = pack.handoff.regular_path(Path(view))
    need(manifest["file_count"] == EXPECTED_FILES, "Wrong native-cloud full-view inventory")
    pack.runtime.validate_manifest(manifest)
    with web.trusted_root(trusted):
        pack.handoff.require_single_map(view)
        pack.handoff.require_reviewed_gate(view, manifest)
    need(pack.runtime.verify(view, manifest)["ok"], "Native-cloud full merged view differs from signed projection")
    return dict(canonical_single_map=True, canonical_reviewed_gate=True, complete_view_hashes=True)


def output_paths(args,base):
    fixed = (DESTINATION,TRUSTED_DESTINATION,VIEW,PACKAGE)
    for path in fixed:
        checked=pack.protect_data.external(path,source=base)
        pack.handoff.regular_path(checked,must_exist=False)
        need(not checked.exists(), "Native-cloud output already exists")
        for source in (ROOT,helper.CONTENT,BASE,refresh.HELPER,HELPER06,BASE_TRUSTED,HELPER06_TRUSTED):
            need(not pack.runtime.within(checked,source) and not pack.runtime.within(source,checked), "Native-cloud output overlaps an input")
    for index,left in enumerate(fixed):
        for right in fixed[index+1:]:
            need(not pack.runtime.within(left,right) and not pack.runtime.within(right,left), "Native-cloud output directories overlap")
    options=argparse.Namespace(destination=DESTINATION,trusted_source=TRUSTED_DESTINATION,package_output=None,signing_key=args.signing_key)
    destination,trusted,_,key=web.output_paths(options,base)
    for path in fixed:
        need(not pack.runtime.within(key,path) and not pack.runtime.within(path,key.parent), "Native-cloud output overlaps private key directory")
    return destination,trusted,key


def build(args):
    need(not args.build or args.signing_key is not None, "--build requires --key (external signing key)")
    reviewed_pins()
    base,before,signed,base_metadata,payment,payment_manifest,payment_metadata=refresh.authenticate_inputs()
    policy,_=pack.handoff.trusted_policy(pack.handoff.POLICY)
    need(RELEASE_SEQUENCE >= policy["integrity"]["minimum_release_sequence"], "Native-cloud sequence is below trusted floor")
    protected=helper.protected_paths(before)
    head=web.git("rev-parse","HEAD",root=ROOT).decode("ascii").strip()
    snapshots,common,trust=capture_common(base,before,payment,payment_manifest,protected)
    authenticate_helper06(base,before,common,signed,snapshots)
    patches=cloud_patches(base,common,snapshots)
    for name in (MAIN,CLIENT,HANDOFF,ROSTER,STARTUP): trust[name]=patches[name]
    need(set(trust)==set(trust_names()), "Native-cloud review-source scope differs")
    for path in (Path(__file__),REFRESH_FILE,PAYMENT_BUILDER_FILE,RUNTIME_VALIDATOR_FILE,Path(pack.handoff.__file__)):read_input(path,snapshots)
    after=project(before,patches);changes=audit_changes(before,after,patches,protected)
    result=dict(ok=True,status="READ_ONLY_PLAN",revision=REVISION,release_sequence=RELEASE_SEQUENCE,
        base_content_sha256=BASE_SHA,base_files=BASE_FILES,helper06_content_sha256=HELPER06_SHA,
        helper06_sequence=HELPER06_SEQUENCE,helper06_signed_common_verified=True,
        projected_content_sha256=after["content_sha256"],expected_files=EXPECTED_FILES,
        destination=str(DESTINATION),trusted_source=str(TRUSTED_DESTINATION),view=str(VIEW),package=str(PACKAGE),
        reviewed_head=head,changed=changes,allowed_additions=sorted(ADDED),allowed_removals=sorted(REMOVE),
        patch_sha256={name:web.sha(raw) for name,raw in sorted(patches.items())},
        compile_receipt_sha256=refresh.COMPILE_REPORT_SHA,ui_records=12,particles=15,
        runtime_validator_lf_sha256=RUNTIME_VALIDATOR_LF_SHA,
        protected_modules_preserved=180,protected_modules_rebuilt=0,frozen_gameplay_body_preserved=True,
        main_patch="single_entry_require_after_frozen_auto_setup",client_patch="inert_server_owned_entry_no_local_launch",
        default_map="ws4_entry",entry_capacity=4,gameplay_map="template_map",gameplay_capacity=4,
        four_accounts_preserved=True,production_preserved=True,online_cheats_allowed=False,
        web_auth=True,session_only=False,cash_code_enabled=True,connection_helper=False,
        required_checkout_edits=["AddonInfo default ws4_entry/capacity4","MAIN entry require native_cloud_handoff only",
                                 "ROOT client retains its existing development-lobby prefix; remaining entry code becomes inert return (prefix omitted from frozen release)"],
        exact_layout_guard="ws4_entry4_template_map4_replaces_legacy_single_entry_guard_only",
        entry_native_phase_gate="wait_for_SETUP_stop_at_POST_GAME_120_seconds_total_budget",
        target_expected_roster_gate="server_observed_account_option_before_native_countdown_admission_and_profiles_release",
        native_cloud_roster_required=True,development_release_profile_modified=False,
        service_patches={AUTO:AUTO_SHA,STARTUP:STARTUP_SHA},
        full_view_canonical_guard="NOT_RUN_requires_real_complete_view_verify_complete_view",
        full_view_canonical_required=True,
        gameplay_unpublished_changes_included=False,transport_probe_modules_included=False,
        native_entry_handoff_acceptance="NOT_RUN",multiplayer_cloud_auth_acceptance="NOT_RUN",
        prior_C3_acceptance="FAIL_guest_disconnected_or_remained_on_old_map_do_not_infer_two_player_success",
        prior_release07_status="UPLOAD_FAILED_EResult2_unavailable_native_count_API_NOT_READY",
        this_candidate_payment_acceptance="NOT_RUN",workshop_upload_performed=False,
        alias_installed=False,game_started=False,real_order_created=False,ui_compiled=False,
        private_key_copied=False,external_full_candidate_created=False,merged_view_created=False,vpk_packaged=False)
    helper.require_unchanged(snapshots,head)
    pack.inventory_unchanged(base,base_metadata);pack.inventory_unchanged(payment,payment_metadata)
    if not args.build:return result
    helper.check_lua(patches)
    destination,trusted,key=output_paths(args,base)
    needed=sum(len(patches[row["path"]]) for row in changes if row["after"] is not None)+sum(map(len,trust.values()))
    need(destination.parent.is_dir() and shutil.disk_usage(destination.parent).free >= needed+SPACE_RESERVE,
         "Insufficient space for native-cloud thin overlay and reserve")
    changed=refresh.stage_thin(destination,before,after,patches)
    trusted.mkdir(parents=True,exist_ok=False)
    for name,raw in trust.items():refresh.write_new(trusted/name,raw)
    refresh.write_new(destination/pack.handoff.MANIFEST,pack.runtime.canonical_bytes(after)+b"\n")
    helper.require_unchanged(snapshots,head)
    pack.protect_data.sign_manifest(destination/pack.handoff.MANIFEST,key,destination/pack.handoff.SIGNATURE,RELEASE_SEQUENCE)
    checked=verify_cloud(base,destination,before,after,trusted,signed["key_id"])
    need(pack.runtime.verify(base,before)["ok"], "Immutable SHOP02 changed during native-cloud build")
    helper.require_unchanged(snapshots,head)
    pack.inventory_unchanged(base,base_metadata);pack.inventory_unchanged(payment,payment_metadata)
    result.update(status="SIGNED_THIN_NATIVE_CLOUD_REQUIRES_NATIVE_TEST",content_sha256=after["content_sha256"],
                  signature=checked,thin_runtime_files=len(changed),full_merged_hash_verification=True)
    return result


def parser():
    result=argparse.ArgumentParser(description=__doc__)
    result.add_argument("--build",action="store_true")
    result.add_argument("--key","--signing-key",dest="signing_key",type=Path)
    return result


def main(argv=None):
    try:result=build(parser().parse_args(argv))
    except Exception as error:
        print(json.dumps(dict(ok=False,status="BLOCKED_DO_NOT_SIGN_OR_UPLOAD",error=str(error)),ensure_ascii=True));return 1
    print(json.dumps(result,ensure_ascii=True,indent=2));return 0


if __name__=="__main__":raise SystemExit(main())
