"""Native-cloud projection tests use disposable fixtures, never release keys."""
from contextlib import ExitStack
from copy import deepcopy
import base64
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_native_cloud as candidate
sys.path.insert(0, str(candidate.REFRESH_FILE.parent))
import test_build_refresh as prior_tests
manifest = prior_tests.manifest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class NativeCloudTests(unittest.TestCase):
    def fixture(self):
        files, common, protected = prior_tests.RefreshTests().fixture()
        for name in (candidate.ADDONINFO, candidate.CLIENT, candidate.STARTUP, candidate.RELEASE_CONFIG):
            if name not in files:
                del files[next(name for name in files if name.startswith("materials/fixture_"))]
            files[name] = (candidate.BASE / name).read_bytes()
        patches = dict(common)
        patches[candidate.MAIN] = candidate.patch_main(candidate.refresh.frozen_main((candidate.BASE / candidate.MAIN).read_bytes()))
        patches[candidate.ADDONINFO] = candidate.patch_addoninfo(files[candidate.ADDONINFO])
        patches[candidate.CLIENT] = candidate.client_bytes(files[candidate.CLIENT])
        patches[candidate.HANDOFF] = (candidate.ROOT / candidate.HANDOFF).read_bytes()
        patches[candidate.ROSTER] = (candidate.ROOT / candidate.ROSTER).read_bytes()
        patches[candidate.AUTO] = candidate.service_patch((candidate.HELPER06/candidate.AUTO).read_bytes(),"auto")
        patches[candidate.STARTUP] = candidate.service_patch((candidate.BASE/candidate.STARTUP).read_bytes(),"startup")
        patches[candidate.RELEASE_CONFIG] = candidate.patch_release_profile(files[candidate.RELEASE_CONFIG])
        patches[candidate.MAP] = (candidate.ROOT / candidate.MAP).read_bytes()
        patches[candidate.helper.CASH_CONFIG] = b"return {enabled = true, connection_helper = false}\n"
        return files, patches, protected

    def test_default_is_readonly_with_new_fixed_sequence_paths_and_four_player_layout(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build); self.assertIsNone(args.signing_key)
        candidate.reviewed_pins()
        self.assertEqual((candidate.RELEASE_SEQUENCE, candidate.EXPECTED_FILES), (2026102708, 6658))
        self.assertEqual((len(candidate.ALLOWLIST), len(candidate.ADDED), len(candidate.REMOVE)), (48, 22, 1))
        self.assertEqual(candidate.HELPER06_SEQUENCE, 2026102706)
        self.assertEqual(candidate.DESTINATION, Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_overlay"))
        self.assertEqual(candidate.VIEW, Path("D:/Survival_发布候选/20261027_ws4_native_cloud_v02_view"))
        self.assertEqual(candidate.PACKAGE, Path("D:/Survival_工坊输出/20261027_ws4_native_cloud_v02"))
        with patch.object(candidate.refresh, "authenticate_inputs", side_effect=AssertionError("IO before key gate")):
            with self.assertRaisesRegex(ValueError, "requires --key"):
                candidate.build(candidate.parser().parse_args(["--build"]))

    def test_projection_preserves_every_frozen_byte_and_180_modules(self):
        files, patches, protected = self.fixture(); before = manifest(files)
        after = candidate.project(before, patches)
        changes = candidate.audit_changes(before, after, patches, protected)
        old, new = ({row["path"]:row for row in doc["files"]} for doc in (before, after))
        self.assertEqual(len(new), 6658)
        self.assertEqual(new.keys() - old.keys(), candidate.ADDED)
        self.assertEqual(old.keys() - new.keys(), candidate.REMOVE)
        self.assertTrue(all(old[name] == new[name] for name in old if name not in candidate.ALLOWLIST | candidate.REMOVE))
        self.assertEqual(candidate.frozen.protected_paths(before), candidate.frozen.protected_paths(after))
        self.assertEqual({row["path"] for row in changes if row["after"] is None}, candidate.REMOVE)
        self.assertNotIn("scripts/vscripts/systems/native_transport_probe.lua", new)

    def test_rejects_foreign_gameplay_profile_provider_roster_protected_and_extra_paths(self):
        files, patches, protected = self.fixture(); before = manifest(files)
        final = {name:raw for name,raw in files.items() if name not in candidate.REMOVE}; final.update(patches)
        for name in (candidate.helper.PROFILE, candidate.helper.PROVIDER, candidate.pack.runtime.RELEASE_PROFILE,
                     candidate.pack.handoff.ACCESS_FILE, "maps/template_map.vpk", protected[0], candidate.MAIN, candidate.HANDOFF):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.audit_changes(before, manifest(dict(final, **{name:b"unreviewed"})), patches, protected)
        for bad in (dict(patches, **{"scripts/vscripts/foreign.lua":b"extra"}),
                    {name:raw for name,raw in patches.items() if name != candidate.MAP}):
            with self.assertRaises(ValueError): candidate.project(before, bad)
        with self.assertRaises(ValueError):
            candidate.audit_changes(before, candidate.project(before, patches), patches, protected[:-1])

    def test_main_changes_only_one_require_on_frozen_gameplay_body(self):
        raw = candidate.refresh.frozen_main((candidate.BASE / candidate.MAIN).read_bytes())
        result = candidate.patch_main(raw)
        self.assertEqual(result.replace(candidate.NEW_REQUIRE, candidate.OLD_REQUIRE, 1), raw)
        self.assertEqual(candidate.web.sha(result), candidate.MAIN_SHA)
        for bad in (raw + b"-- unpublished gameplay", raw.replace(candidate.OLD_REQUIRE, b"local entry = {}")):
            with self.assertRaises(ValueError): candidate.patch_main(bad)

    def test_production_profile_patch_adds_one_explicit_flag_without_touching_development_profile(self):
        current=(candidate.ROOT/candidate.RELEASE_CONFIG).read_bytes()
        before=(candidate.BASE/candidate.RELEASE_CONFIG).read_bytes()
        after=candidate.patch_release_profile(before)
        self.assertEqual(after.replace(b'    native_cloud_roster_required = true,\r\n',b'',1),before)
        self.assertEqual(candidate.web.sha(after),candidate.RELEASE_CONFIG_SHA)
        self.assertEqual((candidate.ROOT/candidate.RELEASE_CONFIG).read_bytes(),current)
        for bad in (after,before+b'-- foreign',current):
            with self.assertRaises(ValueError):candidate.patch_release_profile(bad)

    def test_service_gates_are_additive_frozen_patches_and_preserve_unpublished_root_startup(self):
        imported=b'local native_cloud_roster = require("systems/native_cloud_roster")\n'
        gate=(b'local function expected_roster_complete()\n'
              b'    local ok, complete = pcall(native_cloud_roster.complete_roster)\n'
              b'    return ok and complete == true\nend\n\n')
        def remove(raw,kind):
            newline=b"\r\n" if b"\r\n" in raw else b"\n"
            raw=raw.replace(imported.replace(b"\n",newline),b"",1).replace(gate.replace(b"\n",newline),b"",1)
            if kind=='auto':raw=raw.replace(b'    if not expected_roster_complete() then return waiting("waiting_expected_roster", ids) end'+newline,b'',1)
            else:raw=raw.replace(b' and expected_roster_complete()',b'')
            return raw
        for name,kind,root in ((candidate.AUTO,'auto',candidate.HELPER06),(candidate.STARTUP,'startup',candidate.BASE)):
            before=(root/name).read_bytes();after=candidate.service_patch(before,kind)
            self.assertEqual(remove(after,kind),before)
            self.assertEqual(after.count(imported.strip()),1)
            with self.assertRaises(ValueError):candidate.service_patch(after,kind)
            with self.assertRaises(ValueError):candidate.service_patch(before+b'-- foreign',kind)
        root=(candidate.ROOT/candidate.STARTUP).read_bytes();preimage=remove(root,'startup')
        self.assertEqual(candidate.web.sha(preimage),'338aafa9c8bc2b4d148f679830dfc6fd8f0adb08e5bc9815331285c2f1e4ca97')
        self.assertEqual(candidate.service_patch_body(preimage,'startup'),root)
        self.assertNotEqual(root,candidate.service_patch((candidate.BASE/candidate.STARTUP).read_bytes(),'startup'))
        with self.assertRaises(ValueError):candidate.service_patch(preimage,'startup')

    def test_release_client_is_inert_and_does_not_import_development_lobby(self):
        raw = (candidate.BASE / candidate.CLIENT).read_bytes()
        result = candidate.client_bytes(raw)
        self.assertEqual(result, candidate.CLIENT_INERT)
        self.assertEqual((len(result), candidate.web.sha(result)), (93, candidate.CLIENT_SHA))
        self.assertNotIn(b"ws4_lobby", result); self.assertNotIn(b"hosted_lobby", result)
        self.assertEqual(result.splitlines()[-1], b"return {}")
        for bad in (raw+b"changed", (candidate.ROOT/candidate.CLIENT).read_bytes()):
            with self.assertRaises(ValueError): candidate.client_bytes(bad)

    def test_layout_exposes_exact_entry_four_internal_template_four(self):
        raw = candidate.patch_addoninfo((candidate.BASE / candidate.ADDONINFO).read_bytes())
        candidate.validate_layout(raw)
        for bad in (raw.replace(b'"MaxPlayers"    "4"', b'"MaxPlayers"    "1"', 1),
                    raw.replace(b'"ws4_entry"', b'"template_map"', 1),
                    raw.replace(b'"EnablePickRules"', b'"EnableOther"')):
            with self.assertRaises(ValueError): candidate.validate_layout(bad)
        parsed = deepcopy(candidate.LAYOUT); parsed["addoninfo"]["foreign_map"] = {"maxplayers":"4"}
        with patch.object(candidate.pack.handoff,"kv",return_value=parsed), self.assertRaises(ValueError):
            candidate.validate_layout(raw)

    def test_handoff_has_exact_command_context_capacity_imports_and_no_client_command(self):
        raw = (candidate.ROOT/candidate.HANDOFF).read_bytes(); candidate.validate_handoff(raw)
        for bad in (raw.replace(b"customgamemode=3824360109", b"addon=3824360109"),
                    raw.replace(b'"ws4_entry", 4,', b'"ws4_entry", 1,'),
                    raw.replace(b'method(GameRules, "State_Get")', b'method(GameRules, "State_Absent")'),
                    raw.replace(b'call(PlayerResource, "GetPlayerCount")', b'call(GameRules, "GetCustomGamePlayerCount")'),
                    raw.replace(b'run.expected_floor = math.max(run.expected_floor or 0, count)', b'run.expected_floor = count'),
                    raw.replace(b'local final_phase_ready, final_phase_reason = native_phase()',b'local final_phase_ready, final_phase_reason = true, nil'),
                    raw+b'\nrequire("systems/commerce_payment_service")\n', raw+b'\nSendToConsole("launch")\n'):
            # Even an intentionally re-pinned test cannot relax structural gates.
            with self.subTest(bad=bad[-80:]), patch.object(candidate,"HANDOFF_SHA",candidate.web.sha(bad)):
                with self.assertRaises(ValueError): candidate.validate_handoff(bad)

    def test_signed_helper06_must_equal_frozen_common_and_successful_generation(self):
        files, common, _ = prior_tests.RefreshTests().fixture(); before = manifest(files)
        expected = candidate.refresh.project(before, candidate.refresh.variant_patches(common,"helper"))
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate,"HELPER06_SHA",expected["content_sha256"]))
            stack.enter_context(patch.object(candidate,"read_input",return_value=b"reviewed metadata"))
            verify = stack.enter_context(patch.object(candidate.refresh,"verify_merged",return_value={"release_sequence":candidate.HELPER06_SEQUENCE}))
            candidate.authenticate_helper06(Path("base"),before,common,{"key_id":"same"},{})
            self.assertEqual(verify.call_args.args[1],candidate.HELPER06)
            self.assertEqual(verify.call_args.args[-2],2026102706)
            verify.return_value={"release_sequence":2026102704}
            with self.assertRaises(ValueError): candidate.authenticate_helper06(Path("base"),before,common,{"key_id":"same"},{})
            verify.return_value={"release_sequence":2026102706}
            bad=dict(common);bad[candidate.refresh.SERVICE]=b"obsolete auto-start service"
            with self.assertRaisesRegex(ValueError,"successful HELPER04"):
                candidate.authenticate_helper06(Path("base"),before,bad,{"key_id":"same"},{})

    def test_cloud_capture_uses_frozen_main_and_client_only_and_helper_false_is_only_flag_change(self):
        _,common,_=prior_tests.RefreshTests().fixture()
        common[candidate.MAIN]=candidate.refresh.frozen_main((candidate.BASE/candidate.MAIN).read_bytes())
        common[candidate.AUTO]=(candidate.HELPER06/candidate.AUTO).read_bytes()
        common[candidate.helper.CASH_CONFIG]=(candidate.HELPER06/candidate.helper.CASH_CONFIG).read_bytes()
        touched=[]
        def read(path,snapshots):
            self.assertNotIn(path,(candidate.ROOT/candidate.MAIN,candidate.ROOT/candidate.CLIENT))
            raw=path.read_bytes();touched.append(path);snapshots[path]=raw;return raw
        with patch.object(candidate,"read_input",side_effect=read):
            result=candidate.cloud_patches(candidate.BASE,common,{})
        self.assertEqual(set(result),candidate.ALLOWLIST)
        self.assertEqual(result[candidate.helper.CASH_CONFIG],common[candidate.helper.CASH_CONFIG].replace(b"connection_helper = true",b"connection_helper = false",1))
        self.assertEqual(candidate.web.sha(result[candidate.helper.CASH_CONFIG]),candidate.CASH_SHA)
        self.assertEqual(result[candidate.helper.WEB_CONFIG],common[candidate.helper.WEB_CONFIG])
        self.assertEqual(result[candidate.helper.SESSION_CONFIG],common[candidate.helper.SESSION_CONFIG])
        self.assertNotIn(candidate.helper.PROFILE,result);self.assertNotIn(candidate.helper.PROVIDER,result)
        self.assertIn(candidate.helper.CONTENT/candidate.MAP_SOURCE,touched)
        self.assertEqual(result[candidate.AUTO],candidate.service_patch(common[candidate.AUTO],"auto"))
        self.assertEqual(result[candidate.STARTUP],candidate.service_patch((candidate.BASE/candidate.STARTUP).read_bytes(),"startup"))
        self.assertNotEqual(result[candidate.STARTUP],(candidate.ROOT/candidate.STARTUP).read_bytes())

    def test_fixed_output_paths_reject_existing_nested_and_key_directory_overlap(self):
        with tempfile.TemporaryDirectory(prefix="ws4-native-cloud-paths-") as temporary:
            root=Path(temporary).resolve();base=root/"base";base.mkdir()
            key=root/"private"/"fixture.pem";key.parent.mkdir();key.write_bytes(b"fixture path only: never read")
            paths={"DESTINATION":root/"thin","TRUSTED_DESTINATION":root/"trusted","VIEW":root/"view","PACKAGE":root/"package"}
            with ExitStack() as stack:
                for name,value in paths.items():stack.enter_context(patch.object(candidate,name,value))
                args=candidate.parser().parse_args(["--key",str(key)])
                self.assertEqual(candidate.output_paths(args,base),(paths["DESTINATION"],paths["TRUSTED_DESTINATION"],key))
                with patch.object(candidate,"VIEW",paths["DESTINATION"]/"nested"),self.assertRaises(ValueError):candidate.output_paths(args,base)
                with patch.object(candidate,"PACKAGE",key.parent/"package"),self.assertRaises(ValueError):candidate.output_paths(args,base)
                paths["DESTINATION"].mkdir()
                with self.assertRaises(ValueError):candidate.output_paths(args,base)

    def test_changed_only_staging_never_copies_or_hardlinks_frozen_data(self):
        files, patches, _ = self.fixture(); before=manifest(files); after=candidate.project(before,patches)
        with tempfile.TemporaryDirectory(prefix="ws4-native-cloud-thin-") as temporary:
            target=Path(temporary)/"thin"
            with patch.object(candidate.shutil,"copyfile",side_effect=AssertionError("full copy")), patch.object(candidate.os,"link",side_effect=AssertionError("hardlink")):
                changed=candidate.refresh.stage_thin(target,before,after,patches)
            actual={path.relative_to(target).as_posix() for path in target.rglob("*") if path.is_file()}
            self.assertEqual(actual,changed)
            self.assertTrue({candidate.MAP,candidate.HANDOFF,candidate.CLIENT,candidate.ADDONINFO} <= actual)
            self.assertFalse(candidate.REMOVE & actual)
            self.assertNotIn("maps/template_map.vpk",actual)
            self.assertTrue(all((target/name).read_bytes()==patches[name] for name in actual))

    def signed_fixture(self, temporary):
        root=Path(temporary).resolve();base,target,trusted=(root/name for name in ("base","thin","trusted"))
        public_name="tools/release_security/trusted_public_key.pem";policy_name="tools/release_security/protection_policy.json"
        names=candidate.helper.previous.trust_names()
        runtime_names=set(names)-{public_name,policy_name}
        original={name:("old:"+name).encode() for name in runtime_names}
        original[candidate.ADDONINFO]=(candidate.BASE/candidate.ADDONINFO).read_bytes()
        original["materials/unchanged.vmat_c"]=b"same frozen data"
        final={name:("new:"+name).encode() for name in runtime_names}
        final[candidate.CLIENT]=candidate.CLIENT_INERT
        final.update({candidate.ADDONINFO:candidate.patch_addoninfo(original[candidate.ADDONINFO]),
                      candidate.HANDOFF:(candidate.ROOT/candidate.HANDOFF).read_bytes(),
                      candidate.ROSTER:(candidate.ROOT/candidate.ROSTER).read_bytes(),
                      "materials/unchanged.vmat_c":original["materials/unchanged.vmat_c"]})
        before,after=manifest(original),manifest(final)
        for name,raw in original.items():candidate.refresh.write_new(base/name,raw)
        for name,raw in final.items():
            if original.get(name)!=raw:candidate.refresh.write_new(target/name,raw)
        key=Ed25519PrivateKey.generate();public=key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo)
        key_id=candidate.pack.protect_data.public_id(key.public_key());sequence=candidate.RELEASE_SEQUENCE
        policy={"integrity":{"minimum_release_sequence":sequence,"trusted_key_id":key_id}}
        for name in names:
            candidate.refresh.write_new(trusted/name,public if name==public_name else b"fixture policy" if name==policy_name else final[name])
        for name in (candidate.HANDOFF,candidate.ROSTER):candidate.refresh.write_new(trusted/name,final[name])
        document=dict(schema=2,algorithm="Ed25519",key_id=key_id,release_sequence=sequence,content_sha256=after["content_sha256"],
                      signature=base64.b64encode(key.sign(candidate.pack.protect_data.DOMAIN+struct.pack(">Q",sequence)+candidate.pack.runtime.manifest_payload(after))).decode())
        candidate.refresh.write_new(target/candidate.pack.handoff.MANIFEST,candidate.pack.runtime.canonical_bytes(after)+b"\n")
        candidate.refresh.write_new(target/candidate.pack.handoff.SIGNATURE,json.dumps(document).encode())
        return base,target,trusted,before,after,key_id,policy,public_name

    def test_full_merged_hash_signature_and_fourteen_review_files_reject_tampering(self):
        for fault in (None,"base","thin","signature","trusted_handoff","extra_trusted","extra_thin"):
            with self.subTest(fault=fault),tempfile.TemporaryDirectory(prefix="ws4-native-cloud-sign-") as temporary:
                base,target,trusted,before,after,key_id,policy,public_name=self.signed_fixture(temporary)
                if fault=="base":(base/"materials/unchanged.vmat_c").write_bytes(b"changed")
                if fault=="thin":(target/candidate.CLIENT).write_bytes(b"changed")
                if fault=="trusted_handoff":(trusted/candidate.HANDOFF).write_bytes(b"not reviewed")
                if fault=="extra_trusted":candidate.refresh.write_new(trusted/"private_key.pem",b"not a release source")
                if fault=="extra_thin":candidate.refresh.write_new(target/"foreign.lua",b"extra")
                if fault=="signature":
                    path=target/candidate.pack.handoff.SIGNATURE;doc=json.loads(path.read_bytes());doc["signature"]=base64.b64encode(b"x"*64).decode();path.write_text(json.dumps(doc))
                with patch.object(candidate.pack.handoff,"trusted_policy",return_value=(policy,trusted/public_name)):
                    if fault is None:self.assertTrue(candidate.verify_cloud(base,target,before,after,trusted,key_id)["signature_valid"])
                    else:
                        with self.assertRaises(Exception):candidate.verify_cloud(base,target,before,after,trusted,key_id)

    def test_secrets_and_unsafe_runtime_paths_are_rejected(self):
        for raw in (b"-----BEGIN PRIVATE KEY-----", b"Bearer "+b"x"*30, b'client_secret = "'+b"x"*30+b'"'):
            with self.assertRaises(ValueError):candidate.no_credentials({candidate.HANDOFF:raw})
        with self.assertRaises(ValueError):candidate.no_credentials({"../foreign.lua":b"unsafe"})

    def test_full_view_api_calls_shared_publisher_guards_and_requires_complete_hashes(self):
        # The canonical guard's own entry4 fixtures are covered by its dedicated
        # suite. Here exercise wrapper wiring, trusted scope and fail propagation.
        with tempfile.TemporaryDirectory(prefix="ws4-native-cloud-full-guard-") as temporary:
            root=Path(temporary).resolve();view=root/'view';view.mkdir();trusted=root/'trusted';trusted.mkdir()
            doc=manifest({'one.lua':b'one'});calls=[]
            def guard(path):
                self.assertEqual(candidate.pack.handoff.ROOT,trusted);self.assertEqual(path,view);calls.append('layout')
            def reviewed(path,value):self.assertEqual(value,doc);calls.append('reviewed')
            with ExitStack() as stack:
                stack.enter_context(patch.object(candidate,'EXPECTED_FILES',1))
                layout=stack.enter_context(patch.object(candidate.pack.handoff,'require_single_map',side_effect=guard))
                stack.enter_context(patch.object(candidate.pack.handoff,'require_reviewed_gate',side_effect=reviewed))
                hashes=stack.enter_context(patch.object(candidate.pack.runtime,'verify',return_value={'ok':True}))
                self.assertEqual(candidate.verify_complete_view(view,trusted,doc),{'canonical_single_map':True,'canonical_reviewed_gate':True,'complete_view_hashes':True})
                self.assertEqual(calls,['layout','reviewed'])
                hashes.return_value={'ok':False}
                with self.assertRaisesRegex(ValueError,'full merged view'):candidate.verify_complete_view(view,trusted,doc)
                layout.side_effect=ValueError('canonical rejects wrong entry')
                with self.assertRaisesRegex(ValueError,'canonical rejects'):candidate.verify_complete_view(view,trusted,doc)

    def test_plan_has_no_key_read_compile_sign_install_package_or_external_writes(self):
        files,patches,protected=self.fixture();before=manifest(files)
        trust={name:b"reviewed" for name in candidate.helper.previous.trust_names()}
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate.refresh,"authenticate_inputs",return_value=(Path("base"),before,{"key_id":"same"},{},Path("payment"),{},{})))
            stack.enter_context(patch.object(candidate,"capture_common",return_value=({}, {}, trust)))
            stack.enter_context(patch.object(candidate,"authenticate_helper06"))
            stack.enter_context(patch.object(candidate,"cloud_patches",return_value=patches))
            stack.enter_context(patch.object(candidate.helper,"protected_paths",return_value=protected))
            stack.enter_context(patch.object(candidate.helper,"require_unchanged"))
            stack.enter_context(patch.object(candidate.pack,"inventory_unchanged"))
            stack.enter_context(patch.object(candidate.web,"git",return_value=b"fixture-head\n"))
            stack.enter_context(patch.object(candidate.pack.handoff,"trusted_policy",return_value=({"integrity":{"minimum_release_sequence":2026102701}},None)))
            for owner,name in ((candidate.helper,"check_lua"),(candidate,"output_paths"),(candidate.refresh,"stage_thin"),
                               (candidate.refresh,"write_new"),(candidate.pack.protect_data,"sign_manifest"),(candidate.pack,"package"),(candidate.os,"link")):
                stack.enter_context(patch.object(owner,name,side_effect=AssertionError("unexpected side effect")))
            stack.enter_context(patch.object(Path,"mkdir",side_effect=AssertionError("mkdir")))
            result=candidate.build(candidate.parser().parse_args(["--key","DO_NOT_READ.pem"]))
        self.assertEqual((result["status"],result["expected_files"]),("READ_ONLY_PLAN",6658))
        self.assertTrue(result["web_auth"]);self.assertFalse(result["session_only"]);self.assertFalse(result["connection_helper"])
        for name in ("ui_compiled","private_key_copied","real_order_created","game_started","workshop_upload_performed","alias_installed","merged_view_created","vpk_packaged"):
            self.assertFalse(result[name])


if __name__=="__main__":unittest.main(verbosity=2)
