"""Thin refresh isolation tests; use temporary fixtures, never release keys."""
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
import build_refresh as candidate
sys.path.insert(0, str(candidate.ROOT / "tools/workshop_test"))
from test_web_auth_candidate import manifest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def resource(data):
    return struct.pack("<IHHII4sII", 28 + len(data), 12, 0, 8, 1, b"DATA", 8, len(data)) + data


class RefreshTests(unittest.TestCase):
    def fixture(self):
        policy = candidate.pack.handoff.load_json(candidate.ROOT / "tools/lua_protection_policy.json")
        protected = list(policy["business_modules"]) + [policy["generated_prefix"] + "fixture_%03d.lua" % i for i in range(176)]
        files = {name: ("protected:" + name).encode() for name in protected}
        files.update({name: ("frozen:" + name).encode() for name in candidate.MODIFIED | candidate.REMOVE})
        files.update({name: ("critical:" + name).encode() for name in candidate.pack.runtime.CRITICAL if name not in files})
        files.update({"maps/template_map.vpk": b"one unchanged map", candidate.helper.PROVIDER: b"same PWA provider",
                      candidate.helper.PROFILE: b"same profile", "scripts/vscripts/config/test_access.lua": b"same four accounts"})
        files[candidate.helper.WEB_CONFIG] = b"return {enabled = false}\n"
        files[candidate.helper.SESSION_CONFIG] = b"return {enabled = true}\n"
        files.update({"materials/fixture_%04d.vmat_c" % i: b"unchanged" for i in range(candidate.BASE_FILES - len(files))})
        common = {name: ("reviewed:" + name).encode() for name in candidate.ALLOWLIST}
        common[candidate.helper.WEB_CONFIG] = b"return {enabled = true}\n"
        common[candidate.helper.SESSION_CONFIG] = b"return {enabled = false}\n"
        common[candidate.helper.CASH_CONFIG] = b"return {enabled = true, connection_helper = true}\n"
        return files, common, protected

    def test_default_is_readonly_and_fixed_variants_use_separate_new_paths(self):
        args = candidate.parser().parse_args([])
        self.assertFalse(args.build); self.assertIsNone(args.signing_key); self.assertEqual(args.variant, "native")
        candidate.reviewed_pins()
        self.assertEqual((candidate.BASE_FILES, candidate.EXPECTED_FILES, len(candidate.ADDED)), (6637, 6655, 19))
        self.assertEqual(candidate.REMOVE, {"panorama/styles/custom_game/commerce_wallet.vcss_c"})
        self.assertEqual(candidate.VARIANTS["native"]["sequence"], 2026102705)
        self.assertEqual(candidate.VARIANTS["helper"]["sequence"], 2026102706)
        self.assertEqual(candidate.VARIANTS["native"]["destination"], Path("D:/Survival_发布候选/20261027_ws4_refresh_native_v02_overlay"))
        self.assertEqual(candidate.VARIANTS["helper"]["destination"], Path("D:/Survival_发布候选/20261027_ws4_refresh_helper_v04_overlay"))
        self.assertTrue(all("_overlay" in value["destination"].name for value in candidate.VARIANTS.values()))
        with patch.object(candidate, "authenticate_inputs", side_effect=AssertionError("base access")), self.assertRaises(ValueError):
            candidate.build(candidate.parser().parse_args(["--build"]))

    def test_variant_projection_preserves_every_unrelated_byte_and_180_modules(self):
        files, common, protected = self.fixture(); before = manifest(files)
        for variant in candidate.VARIANTS:
            with self.subTest(variant=variant):
                patches = candidate.variant_patches(common, variant); after = candidate.project(before, patches)
                changes = candidate.audit_changes(before, after, patches, protected)
                old, new = ({row["path"]:row for row in document["files"]} for document in (before, after))
                self.assertEqual(len(new), 6655); self.assertEqual(new.keys() - old.keys(), candidate.ADDED)
                self.assertTrue(all(old[name] == new[name] for name in old if name not in candidate.ALLOWLIST | candidate.REMOVE))
                self.assertEqual({name for name in old if name not in new}, candidate.REMOVE)
                self.assertEqual({row["path"] for row in changes if row["after"] is None}, candidate.REMOVE)
                self.assertEqual(candidate.frozen.protected_paths(after), candidate.frozen.protected_paths(before))
        native = candidate.variant_patches(common, "native"); online = candidate.variant_patches(common, "helper")
        self.assertEqual(native[candidate.helper.WEB_CONFIG], files[candidate.helper.WEB_CONFIG])
        self.assertEqual(native[candidate.helper.SESSION_CONFIG], files[candidate.helper.SESSION_CONFIG])
        self.assertIn(b"enabled = false, connection_helper = false", native[candidate.helper.CASH_CONFIG])
        self.assertIn(b"enabled = true, connection_helper = true", online[candidate.helper.CASH_CONFIG])
        self.assertEqual(online, common); self.assertIn(b"enabled = true", common[candidate.helper.WEB_CONFIG])

    def test_any_foreign_gameplay_roster_map_policy_or_protected_change_is_rejected(self):
        files, common, protected = self.fixture(); before = manifest(files)
        patches = candidate.variant_patches(common, "native")
        final = {name:raw for name,raw in files.items() if name not in candidate.REMOVE}; final.update(patches)
        for name in (candidate.helper.PROVIDER, candidate.helper.PROFILE, "maps/template_map.vpk", protected[0],
                     "scripts/vscripts/config/test_access.lua", candidate.pack.runtime.RELEASE_PROFILE):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.audit_changes(before, manifest(dict(final, **{name:b"foreign"})), patches, protected)
        for name in (candidate.MAIN, candidate.SERVICE, candidate.POLICY):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.audit_changes(before, manifest(dict(final, **{name:b"not reviewed bytes"})), patches, protected)
        for bad in (dict(patches, **{"scripts/vscripts/foreign.lua":b"extra"}), {name:raw for name,raw in patches.items() if name != candidate.SERVICE}):
            with self.assertRaises(ValueError): candidate.project(before, bad)
        final["scripts/vscripts/foreign.lua"] = b"new gameplay architecture"
        with self.assertRaises(ValueError): candidate.audit_changes(before, manifest(final), patches, protected)

    def test_main_is_a_single_frozen_insertion_without_current_worktree_dependencies(self):
        raw = (b"-- frozen gameplay\r\nlocal x=true\r\n"
               b'            print("[MULTIPLAYER_SESSION] admission_finished authentication_and_assets_ready=true")\r\n'
               b"        end,\r\n    })\r\n    logger.info(\r\n-- end\r\n")
        inserted = b'    require("systems/native_setup_auto_start").init()\r\n'
        after = raw.replace(b"    logger.info(", inserted + b"    logger.info(")
        with patch.dict(candidate.helper.FROZEN_CODE_PINS, {candidate.MAIN:candidate.web.sha(raw)}), patch.object(candidate,"MAIN_OUTPUT_SHA",candidate.web.sha(after)):
            self.assertEqual(candidate.frozen_main(raw), after)
            self.assertEqual(candidate.frozen_main(raw).replace(inserted,b"",1), raw)
            for bad in (raw+b"unpublished main change", raw+raw):
                with self.assertRaises(ValueError): candidate.frozen_main(bad)

    def ui_fixture(self):
        root, content = Path("fixture_root"), Path("fixture_content")
        receipt_path, logs = root/"output/compile.json", root/"output/logs"
        rows, inputs = [], {}
        for index, source in enumerate(sorted(candidate.SOURCES)):
            raw = ("// source %d\r\n" % index).encode(); compiled = candidate.compiled_name(source)
            runtime = resource(raw if source.endswith(".js") else b"compiled native XML/CSS DATA")
            log = logs/(Path(source).name+".log")
            rows.append(dict(source="panorama/src/"+source, content="panorama/"+source, compiled=compiled,
                             source_sha256=candidate.web.sha(raw), compiled_sha256=candidate.web.sha(runtime), compiled_bytes=len(runtime),log=str(log)))
            inputs[root/"panorama/src"/source]=raw; inputs[content/"panorama"/source]=raw
            inputs[root/compiled]=runtime; inputs[log]=("1 compiled, 0 failed, %d skipped\n" % candidate.COMPILE_SKIPPED.get(source,0)).encode("ascii")
        receipt=dict(ok=True,kind="WS4_ARCADE_CLEANUP_COMPILE",original_102_bytes_preserved=True,records=rows)
        return root,content,receipt_path,logs,receipt,inputs

    def capture_ui(self, fixture, overrides=None):
        root,content,receipt_path,logs,receipt,inputs=fixture
        raw=json.dumps(receipt).encode(); inputs[receipt_path]=raw
        def read(path,snapshots): snapshots[path]=inputs[path]; return inputs[path]
        with ExitStack() as stack:
            for name,value in (("ROOT",root),("CONTENT",content),("COMPILE_REPORT",receipt_path),("COMPILE_REPORT_SHA",candidate.web.sha(raw)),("COMPILE_LOG_DIRECTORY",logs),("COMPILE_LOG_OVERRIDES",overrides or {})):
                stack.enter_context(patch.object(candidate,name,value))
            stack.enter_context(patch.object(candidate,"read_input",side_effect=read))
            return candidate.capture_ui({})

    def test_twelve_ui_outputs_require_exact_mirrors_unique_sources_and_native_data(self):
        self.assertEqual(set(self.capture_ui(self.ui_fixture())), candidate.UI)
        fixture=self.ui_fixture(); source=sorted(candidate.SOURCES)[0]
        fixture[5][fixture[1]/"panorama"/source]=b"different mirror"
        with self.assertRaises(ValueError): self.capture_ui(fixture)
        for mutation in (lambda r:r.update(original_102_bytes_preserved=False), lambda r:r["records"].__setitem__(1,deepcopy(r["records"][0])),
                         lambda r:r["records"][0].update(compiled="panorama/foreign.vjs_c")):
            fixture=self.ui_fixture(); mutation(fixture[4])
            with self.assertRaises(ValueError): self.capture_ui(fixture)
        fixture=self.ui_fixture(); row=next(row for row in fixture[4]["records"] if row["source"].endswith(".js"))
        raw=resource(b"wrong JS DATA"); row.update(compiled_sha256=candidate.web.sha(raw),compiled_bytes=len(raw))
        fixture[5][fixture[0]/row["compiled"]]=raw
        with self.assertRaisesRegex(ValueError,"DATA"): self.capture_ui(fixture)
        fixture=self.ui_fixture(); fixture[5][Path(fixture[4]["records"][0]["log"])]=b"1 compiled, 1 failed, 0 skipped"
        with self.assertRaises(ValueError): self.capture_ui(fixture)

    def test_replacement_wallet_receipt_requires_one_exact_new_log_and_keeps_other_eleven(self):
        fixture=self.ui_fixture(); source="scripts/custom_game/commerce_wallet.js"
        row=next(row for row in fixture[4]["records"] if row["source"]=="panorama/src/"+source)
        previous=Path(row["log"]); replacement=fixture[0]/"output/wallet_compile_v02/commerce_wallet.js.log"
        fixture[5][replacement]=fixture[5].pop(previous);row["log"]=str(replacement)
        with self.assertRaisesRegex(ValueError,"association"): self.capture_ui(fixture)
        self.assertEqual(set(self.capture_ui(fixture,{source:replacement})),candidate.UI)
        other="scripts/custom_game/common/purple_shell.js"
        with self.assertRaisesRegex(ValueError,"Only the replacement wallet"):
            self.capture_ui(fixture,{source:replacement,other:replacement})
        with patch.object(candidate,"COMPILE_REPORT_SHA",None), patch.object(candidate,"read_input",side_effect=AssertionError("unreviewed IO")):
            with self.assertRaisesRegex(ValueError,"has not been reviewed"):candidate.capture_ui({})

    def test_signed_helper_rows_cannot_be_substituted_with_current_source(self):
        protected=[]; fake={name:b"current worktree replacement" for name in candidate.helper.ALLOWLIST}
        with patch.object(candidate.helper,"audit_changes"), patch.object(candidate,"read_input",side_effect=lambda path,snapshots:fake[path.as_posix().removeprefix("payment/")]), self.assertRaisesRegex(ValueError,"twelve payment"):
            candidate.capture_payment(Path("base"),{},Path("payment"),{},protected,{})

    def test_overlay_staging_writes_only_changed_bytes_and_never_copies_unchanged(self):
        files,common,_=self.fixture(); before=manifest(files)
        patches=candidate.variant_patches(common,"native"); after=candidate.project(before,patches)
        with tempfile.TemporaryDirectory(prefix="ws4-thin-fixture-") as temporary:
            target=Path(temporary)/"overlay"
            with patch.object(candidate.shutil,"copyfile",side_effect=AssertionError("full copy")),patch.object(candidate.os,"link",side_effect=AssertionError("hardlink")):
                changed=candidate.stage_thin(target,before,after,patches)
            actual={path.relative_to(target).as_posix() for path in target.rglob("*") if path.is_file()}
            self.assertEqual(actual,changed); self.assertEqual(len(actual),39)
            self.assertFalse(candidate.REMOVE & actual)
            self.assertNotIn(candidate.helper.WEB_CONFIG,actual); self.assertNotIn(candidate.helper.SESSION_CONFIG,actual)
            for name in actual: self.assertEqual((target/name).read_bytes(),patches[name])
            with self.assertRaises(ValueError): candidate.stage_thin(target,before,after,patches)

    def signed_fixture(self, temporary):
        root=Path(temporary).resolve(); base=root/"base"; target=root/"overlay"; trusted=root/"trusted"
        public_name="tools/release_security/trusted_public_key.pem"; policy_name="tools/release_security/protection_policy.json"
        gate="scripts/gate.lua"; original={gate:b"old gate", "materials/unchanged.vmat_c":b"same frozen resource"}
        final=dict(original); final[gate]=b"new gate"; final["styles/new.vcss_c"]=b"new resource"
        before,after=manifest(original),manifest(final)
        for name,raw in original.items(): candidate.write_new(base/name,raw)
        for name in (gate,"styles/new.vcss_c"): candidate.write_new(target/name,final[name])
        key=Ed25519PrivateKey.generate(); public=key.public_key().public_bytes(serialization.Encoding.PEM,serialization.PublicFormat.SubjectPublicKeyInfo)
        key_id=candidate.pack.protect_data.public_id(key.public_key()); sequence=2026102705
        candidate.write_new(trusted/gate,final[gate]); candidate.write_new(trusted/public_name,public); candidate.write_new(trusted/policy_name,b"fixture policy")
        policy={"integrity":{"minimum_release_sequence":sequence,"trusted_key_id":key_id}}
        document=dict(schema=2,algorithm="Ed25519",key_id=key_id,release_sequence=sequence,content_sha256=after["content_sha256"],
                      signature=base64.b64encode(key.sign(candidate.pack.protect_data.DOMAIN+struct.pack(">Q",sequence)+candidate.pack.runtime.manifest_payload(after))).decode())
        candidate.write_new(target/candidate.pack.handoff.MANIFEST,candidate.pack.runtime.canonical_bytes(after)+b"\n")
        candidate.write_new(target/candidate.pack.handoff.SIGNATURE,json.dumps(document).encode())
        return base,target,trusted,before,after,sequence,key_id,policy,public_name,(gate,policy_name,public_name)

    def test_complete_merged_bytes_and_ed25519_signature_reject_tampering_and_extra_files(self):
        for fault in (None,"base","overlay","signature","gate","extra"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory(prefix="ws4-sign-fixture-") as temporary:
                base,target,trusted,before,after,sequence,key_id,policy,public_name,names=self.signed_fixture(temporary)
                if fault=="base": (base/"materials/unchanged.vmat_c").write_bytes(b"changed unchanged payload")
                if fault=="overlay": (target/"styles/new.vcss_c").write_bytes(b"changed overlay payload")
                if fault=="signature":
                    signature=target/candidate.pack.handoff.SIGNATURE; value=json.loads(signature.read_bytes()); value["signature"]=base64.b64encode(b"x"*64).decode(); signature.write_text(json.dumps(value))
                if fault=="gate": (trusted/"scripts/gate.lua").write_bytes(b"wrong reviewed gate")
                if fault=="extra": candidate.write_new(target/"unreviewed.txt",b"extra")
                with patch.object(candidate.pack.handoff,"trusted_policy",return_value=(policy,trusted/public_name)),patch.object(candidate.helper.previous,"trust_names",return_value=names):
                    if fault is None: self.assertTrue(candidate.verify_merged(base,target,before,after,trusted,sequence,key_id)["signature_valid"])
                    else:
                        with self.assertRaises(Exception): candidate.verify_merged(base,target,before,after,trusted,sequence,key_id)

    def test_private_key_or_literal_secret_cannot_enter_runtime(self):
        for raw in (b"-----BEGIN PRIVATE KEY-----",b"Bearer "+b"x"*30,b'access_token = "'+b"x"*30+b'"'):
            with self.assertRaises(ValueError): candidate.no_credentials({candidate.POLICY:raw})
        with self.assertRaises(ValueError): candidate.no_credentials({"../foreign.lua":b"bad"})

    def test_plan_does_not_read_key_write_sign_link_package_or_install(self):
        files,common,protected=self.fixture(); before=manifest(files)
        with ExitStack() as stack:
            stack.enter_context(patch.object(candidate,"authenticate_inputs",return_value=(Path("base"),before,{"key_id":"same"},{},Path("helper"),{},{})))
            stack.enter_context(patch.object(candidate,"capture_common",return_value=({},common,{})))
            stack.enter_context(patch.object(candidate.helper,"protected_paths",return_value=protected))
            stack.enter_context(patch.object(candidate.helper,"check_lua")); stack.enter_context(patch.object(candidate.helper,"require_unchanged"))
            stack.enter_context(patch.object(candidate.pack,"inventory_unchanged")); stack.enter_context(patch.object(candidate.web,"git",return_value=b"same-head\n"))
            for owner,name in ((candidate,"stage_thin"),(candidate,"write_new"),(candidate.web,"output_paths"),(candidate.pack.protect_data,"sign_manifest"),(candidate.pack,"package"),(candidate.os,"link")):
                stack.enter_context(patch.object(owner,name,side_effect=AssertionError("unexpected mutation or key access")))
            stack.enter_context(patch.object(Path,"mkdir",side_effect=AssertionError("mkdir")))
            result=candidate.build(candidate.parser().parse_args(["--key","NEVER-READ.pem"]))
        self.assertEqual(result["status"],"READ_ONLY_PLAN"); self.assertEqual(result["expected_files"],6655)
        self.assertFalse(result["private_key_copied"]); self.assertFalse(result["vpk_packaged"])
        self.assertFalse(result["external_full_candidate_created"]); self.assertFalse(result["human_wave_architecture_backported"])


if __name__ == "__main__": unittest.main(verbosity=2)
