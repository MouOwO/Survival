"""Adversarial handoff checks with real signatures and temporary addon trees."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

spec = importlib.util.spec_from_file_location("handoff", Path(__file__).with_name("publish_test_release.py"))
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.source, self.candidate, self.install = [self.base / name for name in ("source", "candidate", "dota")]
        self.source.mkdir(); self.candidate.mkdir()
        for tree in ("game", "content"):
            (self.install / tree / "dota_addons").mkdir(parents=True)
        self.testers = [str(handoff.STEAM_BASE + number) for number in (101, 102, 103, 104)]
        self.name = "survival_test_fixture"
        self.write("addoninfo.txt", b'"AddonInfo" { "maps" "template_map" "IsPlayable" "1" "template_map" {"MaxPlayers" "4"} }')
        self.write(handoff.runtime.RELEASE_PROFILE, b'return { channel = "production" }')
        self.write(handoff.ACCESS_FILE, ('return {enabled=true, allowed_steamids={' +
                                       ','.join(json.dumps(sid) for sid in self.testers) + '}}').encode())
        for name in (handoff.runtime.CRITICAL | handoff.runtime.map_files(self.candidate)) - {
                "addoninfo.txt", handoff.runtime.RELEASE_PROFILE}:
            self.write(name, b"return {}" if name.endswith(".lua") else b"native fixture")
        for name in handoff.GATE_FILES:
            raw = handoff.protect_data.source_path(handoff.ROOT, name).read_bytes()
            self.write(name, raw)
            trusted = self.source / name
            trusted.parent.mkdir(parents=True, exist_ok=True)
            trusted.write_bytes(raw)
        self.write("docs/should_not_ship.md", b"private staging metadata fixture")
        self.write("_RELEASE_READY_FOR_NATIVE_SMOKE.json", b'{"ready_for_upload":false}')
        self.key = Ed25519PrivateKey.generate()
        self.private = self.base / "signing.pem"
        self.private.write_bytes(self.key.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        (self.source / "public.pem").write_bytes(self.key.public_key().public_bytes(serialization.Encoding.PEM,
                                         serialization.PublicFormat.SubjectPublicKeyInfo))
        self.policy = json.loads(handoff.POLICY.read_text(encoding="utf-8"))
        self.policy["integrity"].update(trusted_public_key="public.pem",
                                         trusted_key_id=handoff.protect_data.public_id(self.key.public_key()),
                                         minimum_release_sequence=10)
        self.policy_file = self.source / "policy.json"
        self.policy_file.write_text(json.dumps(self.policy), encoding="utf-8")
        self.root_patch = patch.object(handoff, "ROOT", self.source)
        self.root_patch.start(); self.addCleanup(self.root_patch.stop)
        self.seal()

    def write(self, name, contents):
        path = self.candidate / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)

    def seal(self, sequence=10):
        self.manifest = handoff.runtime.manifest(self.candidate)
        (self.candidate / handoff.MANIFEST).write_text(json.dumps(self.manifest), encoding="utf-8")
        signature = self.candidate / handoff.SIGNATURE
        if signature.exists():
            signature.unlink()
        handoff.protect_data.sign_manifest(self.candidate / handoff.MANIFEST, self.private, signature, sequence)

    def prepare(self, **kwargs):
        return handoff.prepare(self.candidate, kwargs.pop("name", self.name), kwargs.pop("testers", self.testers),
                               kwargs.pop("mode", "create"), kwargs.pop("workshop_id", None),
                               install=self.install, policy_path=self.policy_file, **kwargs)

    def assert_uninstalled(self):
        for tree in ("game", "content"):
            self.assertFalse((self.install / tree / "dota_addons" / self.name).exists())

    def test_dry_run_verifies_real_signature_and_hashes_without_installing(self):
        result = self.prepare()
        self.assertEqual(result["status"], "VERIFIED_DRY_RUN")
        self.assertTrue(result["signature_valid"])
        self.assertFalse(result["ready_for_upload"])
        self.assertFalse(result["workshop_upload_performed"])
        self.assert_uninstalled()
        self.assertFalse((self.source / "output").exists())

    def test_apply_copies_only_authenticated_inventory_and_no_metadata_or_editable_content(self):
        result = self.prepare(apply=True)
        target = self.install / "game/dota_addons" / self.name
        files = sorted(p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file())
        self.assertEqual(files, [row["path"] for row in self.manifest["files"]])
        self.assertEqual(list((self.install / "content/dota_addons" / self.name).iterdir()), [])
        self.assertTrue(handoff.runtime.verify(target, self.manifest)["ok"])
        self.assertEqual(result["status"], "INSTALLED_FOR_NATIVE_TEST_ONLY")
        self.assertFalse(result["ready_for_upload"])
        self.assertTrue((Path(result["receipt_directory"]) / "handoff.json").is_file())

    def test_missing_duplicate_invalid_and_mismatched_testers_never_install(self):
        for testers in ([], self.testers[:3], [self.testers[0]] * 4, ["not-steam-id"] * 4,
                        [str(handoff.STEAM_BASE + n) for n in (201, 202, 203, 204)]):
            with self.subTest(testers=testers), self.assertRaises(ValueError):
                self.prepare(testers=testers, apply=True)
            self.assert_uninstalled()

    def test_disabled_or_dynamic_access_configuration_never_installs(self):
        original = (self.candidate / handoff.ACCESS_FILE).read_bytes()
        for raw in (original.replace(b"enabled=true", b"enabled=false"),
                    original + b"; os.execute('anything')", b"return require('other')"):
            self.write(handoff.ACCESS_FILE, raw); self.seal()
            with self.assertRaises(ValueError):
                self.prepare(apply=True)
            self.assert_uninstalled()

    def test_exposing_any_second_map_is_rejected_even_with_valid_signature(self):
        raw = (self.candidate / "addoninfo.txt").read_bytes()
        self.write("addoninfo.txt", raw.replace(b'"maps" "template_map"', b'"maps" "template_map survival_c6"'))
        self.write("maps/survival_c6.vpk", b"other map fixture")
        self.seal()
        with self.assertRaisesRegex(ValueError, "Only template_map"):
            self.prepare(apply=True)
        self.assert_uninstalled()

    def test_tampering_signature_rollback_and_extra_runtime_are_rejected(self):
        original = (self.candidate / handoff.ACCESS_FILE).read_bytes()
        self.write(handoff.ACCESS_FILE, original + b" -- byte changed")
        with self.assertRaisesRegex(ValueError, "full inventory"):
            self.prepare(apply=True)
        self.assert_uninstalled()
        self.write(handoff.ACCESS_FILE, original); self.seal(sequence=9)
        with self.assertRaisesRegex(ValueError, "sequence"):
            self.prepare(apply=True)
        self.seal()
        self.write("scripts/vscripts/unreviewed.lua", b"return {}")
        with self.assertRaisesRegex(ValueError, "full inventory"):
            self.prepare(apply=True)
        self.assert_uninstalled()

    def test_wrong_signature_key_is_rejected(self):
        other = Ed25519PrivateKey.generate()
        self.private.write_bytes(other.private_bytes(serialization.Encoding.PEM,
                                 serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.seal()
        with self.assertRaisesRegex(ValueError, "identity"):
            self.prepare(apply=True)
        self.assert_uninstalled()

    def test_signed_manifest_swap_during_verification_cannot_install_or_forge_receipt(self):
        original_verify = handoff.protect_data.verify_signature

        def swap_signed_inventory(*args, **kwargs):
            other = copy.deepcopy(self.manifest)
            other["files"][0]["sha256"] = "0" * 64
            other["content_sha256"] = hashlib.sha256(handoff.runtime.manifest_payload(other)).hexdigest()
            (self.candidate / handoff.MANIFEST).write_text(json.dumps(other), encoding="utf-8")
            (self.candidate / handoff.SIGNATURE).unlink()
            handoff.protect_data.sign_manifest(self.candidate / handoff.MANIFEST, self.private,
                                               self.candidate / handoff.SIGNATURE, 10)
            return original_verify(*args, **kwargs)

        with patch.object(handoff.protect_data, "verify_signature", side_effect=swap_signed_inventory):
            with self.assertRaisesRegex(ValueError, "changed during signature"):
                self.prepare(apply=True)
        self.assert_uninstalled()
        self.assertFalse((self.source / "output").exists())

    def test_existing_addon_source_name_and_ambiguous_item_operation_are_rejected(self):
        target = self.install / "game/dota_addons" / self.name
        target.mkdir()
        sentinel = target / "keep.txt"; sentinel.write_text("preserve")
        with self.assertRaisesRegex(ValueError, "existing"):
            self.prepare(apply=True)
        self.assertEqual(sentinel.read_text(), "preserve")
        for args in ({"name": "survival"}, {"mode": "update"}, {"mode": "guess"},
                     {"mode": "create", "workshop_id": "123"}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.prepare(**args)

    def test_confirmed_update_records_id_without_uploading(self):
        result = self.prepare(mode="update", workshop_id="123456789")
        self.assertEqual(result["workshop_id"], "123456789")
        self.assertFalse(result["workshop_upload_performed"])

    def test_enabled_whitelist_without_reviewed_enforcement_is_rejected(self):
        self.write(handoff.GATE_FILES[1], b"return {} -- missing admission enforcement")
        self.seal()
        with self.assertRaisesRegex(ValueError, "differs from reviewed source"):
            self.prepare(apply=True)
        self.assert_uninstalled()

    def test_duplicate_kv_or_json_fields_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "Duplicate addoninfo"):
            handoff.kv('"AddonInfo" {"maps" "template_map" "maps" "other"}')
        path = self.base / "ambiguous.json"
        path.write_text('{"steamids":[],"steamids":[]}')
        with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
            handoff.load_json(path)

    def test_source_change_while_copying_never_exposes_completed_addon(self):
        original_copy = handoff.shutil.copyfileobj
        changed = []

        def copy_and_change_source(read, write, length):
            original_copy(read, write, length)
            if not changed:
                changed.append(True)
                self.write(handoff.ACCESS_FILE, (self.candidate / handoff.ACCESS_FILE).read_bytes() + b" -- race")

        with patch.object(handoff.shutil, "copyfileobj", side_effect=copy_and_change_source):
            with self.assertRaisesRegex(ValueError, "verification|changed"):
                self.prepare(apply=True)
        self.assert_uninstalled()

    def test_traversal_and_development_addon_names_cannot_be_destinations(self):
        for name in ("survival", "Survival", "../survival", "survival_test_../survival", "survival_test_bad:name"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "isolated addon name"):
                self.prepare(name=name, apply=True)
        self.assert_uninstalled()


if __name__ == "__main__":
    unittest.main()
