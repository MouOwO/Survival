"""Canonical publisher checks; temporary runtime trees, never Lua execution/upload."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_cloud_canonical_publisher", ROOT / "tools/publish_test_release.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
INFO = b'"AddonInfo" { "maps" "ws4_entry" "IsPlayable" "1" "EnablePickRules" "0" "ws4_entry" {"MaxPlayers" "4"} "template_map" {"MaxPlayers" "4"} }'
MAIN = b'''-- Reviewed fixture entry; full MAIN hashes remain the signature pipeline's job.
if type(GetMapName) == "function" and GetMapName() == "ws4_entry" then
    local entry = require("systems/native_cloud_handoff")
    function Precache() end
    function Activate()
        local ok, reason = entry.activate()
        if not ok then print("[WS4-ENTRY-05] server_unavailable reason=" .. tostring(reason)) end
    end
    return
end
'''
WEB = "scripts/vscripts/config/player_web_auth.lua"
SESSION = "scripts/vscripts/config/session_multiplayer_test.lua"
CASH = "scripts/vscripts/config/commerce_payment_access.lua"


class NativeCloudCanonicalLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.candidate = self.base / "candidate"
        self.candidate.mkdir()
        self.write("addoninfo.txt", INFO)
        for name in {"maps/ws4_entry.vpk", "maps/template_map.vpk"}:
            self.write(name, b"native map fixture")
        for name in tool.GATE_FILES:
            self.write(name, (ROOT / name).read_bytes())
        self.write("scripts/vscripts/addon_game_mode.lua", MAIN)
        # The real generated table is protected, so development plaintext is
        # deliberately not a source fixture for that byte pin. Use one opaque
        # temporary payload to exercise the same checksum gate without copying
        # production protected artifacts into source or depending on D: paths.
        self.assertEqual(tool.NATIVE_CLOUD_ENTRY_PINS["scripts/vscripts/config/generated/multiplayer_rules.lua"],
                         "ca025ed911a17295fa6c081e660836b9256e5b04ec8b91d3a172e9cff4cca2d1")
        pins = dict(tool.NATIVE_CLOUD_ENTRY_PINS)
        protected_fixture = b"opaque protected generated runtime fixture"
        pins["scripts/vscripts/config/generated/multiplayer_rules.lua"] = tool.hashlib.sha256(protected_fixture).hexdigest()
        context = patch.object(tool, "NATIVE_CLOUD_ENTRY_PINS", pins)
        context.start(); self.addCleanup(context.stop)
        for name in tool.NATIVE_CLOUD_ENTRY_PINS:
            raw = protected_fixture if name.endswith("config/generated/multiplayer_rules.lua") else (ROOT / name).read_bytes()
            self.assertEqual(tool.hashlib.sha256(raw).hexdigest(), tool.NATIVE_CLOUD_ENTRY_PINS[name],
                             "guard requires freshly reviewed real source pins, not fixture-provided hashes")
            self.write(name, raw)
        self.write(tool.NATIVE_CLOUD_ENTRY_GATE_FILES[2], tool.NATIVE_CLOUD_INERT_CLIENT)
        self.write(tool.runtime.RELEASE_PROFILE, b'return {channel="production",native_cloud_roster_required=true}')
        self.write(tool.ACCESS_FILE, ('return {enabled=true,allowed_steamids={' +
                   ','.join('"' + sid + '"' for sid in tool.NATIVE_CLOUD_TESTERS) + '}}').encode())
        self.write(WEB, b'return {enabled=true,base_url="https://pay.xiaofengnet.com/ws4-web"}')
        self.write(SESSION, b'return {enabled=false,expected_map="template_map"}')
        self.write(CASH, b'return {enabled=true,connection_helper=false,expected_map="template_map",base_url="https://pay.xiaofengnet.com/ws4-web"}')

    def write(self, name, raw):
        path = self.candidate / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)

    def check(self):
        tool.require_single_map(self.candidate)

    def test_exact_entry4_passes_canonical_guard_and_retains_pin_bindings(self):
        self.check()
        for name in tool.runtime.SCENE_MAPS:
            self.write(name, b"existing portrait scene")
        self.check()
        # Cash remains an independently controlled capability: disabling it
        # does not turn this layout into the unrelated session-memory mode.
        self.write(CASH, (self.candidate / CASH).read_bytes().replace(b"enabled=true", b"enabled=false"))
        self.check()

    def test_common_production_parser_keeps_legacy_grammar_and_only_adds_exact_native_true(self):
        for raw in (b'return {channel="production"}',b"return {channel='production',}",
                    b'return {channel="production",native_cloud_roster_required=true}',
                    b'return {channel="production",native_cloud_roster_required=true,};'):
            self.write(tool.runtime.RELEASE_PROFILE,raw)
            tool.runtime.require_production(self.candidate)
        for raw in (b'return {channel="production",native_cloud_roster_required=false}',
                    b'return {channel="development",native_cloud_roster_required=true}',
                    b'return {channel="production",native_cloud_roster_required="true"}',
                    b'return {channel="production",native_cloud_roster_required=true,unknown=true}',
                    b'return {channel="production",native_cloud_roster_required=true,native_cloud_roster_required=true}',
                    b'return {channel="production",native_cloud_roster_required=dynamic}',
                    b'return {channel="production"}; print("dynamic")'):
            self.write(tool.runtime.RELEASE_PROFILE,raw)
            with self.assertRaises(ValueError):tool.runtime.require_production(self.candidate)

    def test_old_template4_and_legacy_entry1_keep_their_existing_guards(self):
        self.write("addoninfo.txt", b'"AddonInfo" {"maps" "template_map" "IsPlayable" "1" "template_map" {"MaxPlayers" "4"}}')
        self.check()
        self.write("addoninfo.txt", b'"AddonInfo" {"maps" "ws4_entry" "IsPlayable" "1" "ws4_entry" {"MaxPlayers" "1"} "template_map" {"MaxPlayers" "4"}}')
        self.write(tool.ENTRY_GATE_FILES[0], b"legacy reviewed entry fixture")
        self.write(tool.ENTRY_GATE_FILES[1], b"legacy reviewed client fixture")
        self.check()
        (self.candidate / tool.ENTRY_GATE_FILES[0]).unlink()
        with self.assertRaises(ValueError): self.check()

    def test_wrong_capacity_extra_exposed_map_or_extra_layout_key_rejected(self):
        for raw in (INFO.replace(b'"MaxPlayers" "4"', b'"MaxPlayers" "2"', 1),
                    INFO.replace(b'"template_map" {"MaxPlayers" "4"}', b'"template_map" {"MaxPlayers" "1"}'),
                    INFO.replace(b'"maps" "ws4_entry"', b'"maps" "ws4_entry template_map"'),
                    INFO.replace(b'"EnablePickRules" "0"', b'"EnablePickRules" "1"'),
                    INFO.replace(b'"IsPlayable" "1"', b'"IsPlayable" "0"'),
                    INFO.replace(b'"IsPlayable" "1"', b'"IsPlayable" "1" "hidden_extra" {"MaxPlayers" "4"}')):
            with self.subTest(raw=raw):
                self.write("addoninfo.txt", raw)
                with self.assertRaises(ValueError): self.check()

    def test_missing_runtime_is_rejected_for_every_new_entry_dependency(self):
        names = {"maps/ws4_entry.vpk", "maps/template_map.vpk", *tool.NATIVE_CLOUD_ENTRY_GATE_FILES,
                 *tool.NATIVE_CLOUD_ENTRY_PINS, "scripts/vscripts/addon_game_mode.lua", tool.ACCESS_FILE,
                 tool.runtime.RELEASE_PROFILE, WEB, SESSION, CASH}
        for name in names:
            with self.subTest(name=name):
                path = self.candidate / name; raw = path.read_bytes(); path.unlink()
                with self.assertRaises((ValueError, FileNotFoundError)): self.check()
                self.write(name, raw)

    def test_extra_runtime_map_rejected_including_nested_vpk(self):
        for name in ("maps/debug.vpk", "maps/other/template_map.vpk"):
            with self.subTest(name=name):
                self.write(name, b"unexpected map")
                with self.assertRaisesRegex(ValueError, "extra or missing gameplay map"): self.check()
                (self.candidate / name).unlink()

    def test_bare_client_launch_or_modified_reviewed_module_rejected(self):
        name = tool.NATIVE_CLOUD_ENTRY_GATE_FILES[2]
        for raw in (b'SendToConsole("dota_launch_custom_game 3824360109 template_map")',
                    tool.NATIVE_CLOUD_INERT_CLIENT + b"-- extra\n", b"return {}\n"):
            self.write(name, raw)
            with self.assertRaisesRegex(ValueError, "inert source"): self.check()
        self.write(name, tool.NATIVE_CLOUD_INERT_CLIENT)
        for name in tool.NATIVE_CLOUD_ENTRY_PINS:
            raw = (self.candidate / name).read_bytes()
            self.write(name, raw + b"\n-- unreviewed change\n")
            with self.assertRaisesRegex(ValueError, "runtime pin differs"): self.check()
            self.write(name, raw)

    def test_main_marker_must_be_an_actual_early_entry_branch(self):
        for raw in (MAIN.replace(b"entry.activate()", b"entry.disabled()"), MAIN.replace(b"native_cloud_handoff", b"workshop_entry"),
                    b"--[[\n" + MAIN + b"\n]]\n", b"local disabled=true\n" + MAIN,
                    MAIN.replace(b'if type(GetMapName)', b'--if type(GetMapName)'), MAIN + MAIN):
            self.write("scripts/vscripts/addon_game_mode.lua", raw)
            with self.assertRaisesRegex(ValueError, "MAIN must activate"): self.check()

    def test_nonproduction_or_disabled_mismatched_roster_rejected(self):
        self.write(tool.runtime.RELEASE_PROFILE, b'return {channel="development"}')
        with self.assertRaises(ValueError): self.check()
        for raw in (b'return {channel="production"}',b'return {channel="production",native_cloud_roster_required=false}',
                    b'return {channel="production",native_cloud_roster_required="true"}'):
            self.write(tool.runtime.RELEASE_PROFILE,raw)
            with self.assertRaises(ValueError):self.check()
        self.write(tool.runtime.RELEASE_PROFILE, b'return {channel="production",native_cloud_roster_required=true}')
        original = (self.candidate / tool.ACCESS_FILE).read_bytes()
        for raw in (original.replace(b"enabled=true", b"enabled=false"),
                    original.replace(tool.NATIVE_CLOUD_TESTERS[0].encode(), b"76561198000000001"),
                    original + b"; print('dynamic')"):
            self.write(tool.ACCESS_FILE, raw)
            with self.assertRaises(ValueError): self.check()

    def test_cloud_flags_origin_unknown_or_duplicate_literal_fields_rejected(self):
        for name, before, after in ((WEB, b"enabled=true", b"enabled=false"), (WEB, b"pay.xiaofengnet.com", b"attacker.invalid"),
                                    (SESSION, b"enabled=false", b"enabled=true"), (CASH, b"connection_helper=false", b"connection_helper=true"),
                                    (CASH, b'expected_map="template_map"', b'expected_map="ws4_lobby"'),
                                    (WEB, b"enabled=true", b"enabled=true,unknown=true"),
                                    (WEB, b"enabled=true", b"enabled=true,enabled=true"),
                                    (WEB, b"enabled=true", b"enabled=dynamic_value")):
            raw = (self.candidate / name).read_bytes(); self.write(name, raw.replace(before, after))
            with self.subTest(name=name, after=after), self.assertRaises(ValueError): self.check()
            self.write(name, raw)

    def test_new_guard_files_must_also_be_signed_and_match_reviewed_root(self):
        manifest = {"files": [{"path": name} for name in (*tool.GATE_FILES, *tool.NATIVE_CLOUD_ENTRY_GATE_FILES, tool.ACCESS_FILE)]}
        trusted = self.base / "reviewed"
        for name in (*tool.GATE_FILES, *tool.NATIVE_CLOUD_ENTRY_GATE_FILES):
            path = trusted / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((self.candidate / name).read_bytes())
        with patch.object(tool, "ROOT", trusted):
            tool.require_reviewed_gate(self.candidate, manifest)
            for name in tool.NATIVE_CLOUD_ENTRY_GATE_FILES:
                bad = {"files": [row for row in manifest["files"] if row["path"] != name]}
                with self.assertRaisesRegex(ValueError, "missing an admission guard"): tool.require_reviewed_gate(self.candidate, bad)
            name = tool.NATIVE_CLOUD_ENTRY_GATE_FILES[1]
            self.write(name, (self.candidate / name).read_bytes() + b"\n-- changed")
            with self.assertRaisesRegex(ValueError, "differs from reviewed"): tool.require_reviewed_gate(self.candidate, manifest)


if __name__ == "__main__": unittest.main()
