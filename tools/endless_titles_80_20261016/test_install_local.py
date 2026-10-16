"""Exercise local pointer installation entirely inside temporary fixtures."""
from __future__ import annotations

from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


TOOL_DIRECTORY = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("endless_titles_install_fixture", TOOL_DIRECTORY / "install_local.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True).encode("utf-8")


class InstallLocalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="title-local-install-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.release = self.root / "fixture-release"
        self.report = self.root / "fixture-report"
        self.report.mkdir()
        self.base = digest(b"synthetic previous bundle")
        bundle = encoded({"synthetic": "title installer fixture"})
        self.candidate = digest(bundle)
        payload = self.release / "payload"
        self.write(payload / "bundle" / self.candidate / "bundle.json", bundle)
        self.write(payload / "bundle" / self.candidate / "worker.lua", b"-- synthetic worker\n")
        self.write(self.root / "data/title_fixture.csv", b"title_id,required_wave\nfixture,1\n")
        self.write(self.root / "server/bundles" / self.base / "bundle.json", b"old fixture retained\n")
        self.json_pointer = self.root / "server/bundles/current.json"
        self.lua_pointer = self.root / "scripts/vscripts/config/generated/archive_http_bundle.lua"
        self.write(self.json_pointer, encoded({"protocol": 1, "hash": self.base}) + b"\n")
        self.write(self.lua_pointer, ('-- original fixture\nreturn { protocol = 1, hash = "' + self.base + '" }\n').encode())
        plan = {
            "candidate": self.candidate, "base": self.base, "target_release": "fixture-title-release",
            "files": {p.relative_to(payload).as_posix(): digest(p.read_bytes())
                      for p in payload.rglob("*") if p.is_file()},
            "input_hashes": {"data/title_fixture.csv": digest((self.root / "data/title_fixture.csv").read_bytes())},
        }
        plan_raw = encoded(plan)
        self.write(self.release / "release_plan.json", plan_raw)
        # Tool source hashes are allowed; no actual server/output data is read.
        evidence = {
            "archive_bundle": self.candidate, "archive_release": plan["target_release"],
            "plan_sha256": digest(plan_raw),
            "operator_sha256": digest((TOOL_DIRECTORY / "deploy_remote.py").read_bytes()),
        }
        for filename, status in (("activate.json", "DEPLOYED"), ("verify.json", "VERIFIED")):
            self.write(self.report / filename, encoded({**evidence, "status": status}))
        self.patch = mock.patch.multiple(INSTALLER, ROOT=self.root, RELEASE=self.release, REPORT=self.report)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    @staticmethod
    def write(path, raw):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)

    def pointers(self):
        return self.json_pointer.read_bytes(), self.lua_pointer.read_bytes()

    def install(self):
        with redirect_stdout(io.StringIO()):
            INSTALLER.main()

    def assert_failed_pointers_unchanged(self, before):
        self.assertEqual(self.pointers(), before)
        self.assertFalse((self.report / "local_activation.json").exists())
        self.assertEqual(list(self.root.rglob("*.endless-titles-next")), [])

    def test_normal_install_and_idempotence(self):
        before = self.pointers()
        self.install()
        after = self.pointers()
        self.assertNotEqual(after, before)
        self.assertEqual(json.loads(after[0]), {"protocol": 1, "hash": self.candidate})
        self.assertEqual(INSTALLER.pointer_hash(self.lua_pointer.name, after[1]), self.candidate)
        backup = self.report / "local_pointer_backup"
        self.assertEqual((backup / self.json_pointer.name).read_bytes(), before[0])
        self.assertEqual((backup / self.lua_pointer.name).read_bytes(), before[1])
        self.assertEqual((self.root / "server/bundles" / self.candidate / "bundle.json").read_bytes(),
                         (self.release / "payload/bundle" / self.candidate / "bundle.json").read_bytes())
        first = json.loads((self.report / "local_activation.json").read_bytes())
        self.assertEqual(first["status"], "LOCAL_GAME_HASH_UPDATED")
        self.assertEqual(len(first["pointers"]), 2)
        self.assertTrue(first["old_bundle_retained"])
        with mock.patch.object(INSTALLER.os, "replace", side_effect=AssertionError("idempotent install rewrote a pointer")):
            self.install()
        self.assertEqual(self.pointers(), after)
        self.assertEqual(json.loads((self.report / "local_activation.json").read_bytes())["pointers"], {})
        self.assertEqual((backup / self.json_pointer.name).read_bytes(), before[0])
        self.assertEqual((backup / self.lua_pointer.name).read_bytes(), before[1])

    def test_extra_payload_is_rejected_without_pointer_changes(self):
        before = self.pointers()
        self.write(self.release / "payload/unreviewed.txt", b"not listed in release plan\n")
        with self.assertRaises(AssertionError):
            self.install()
        self.assert_failed_pointers_unchanged(before)

    def test_base_hash_in_lua_comment_cannot_authorize_other_pointer(self):
        other = digest(b"another synthetic deployment")
        self.write(self.lua_pointer, ('-- old BASE was ' + self.base + '\nreturn { protocol = 1, hash = "' + other + '" }\n').encode())
        before = self.pointers()
        with self.assertRaisesRegex(AssertionError, "local_pointer_changed:"):
            self.install()
        self.assert_failed_pointers_unchanged(before)

    def test_second_replace_failure_restores_both_pointer_bytes(self):
        before = self.pointers()
        real_replace = INSTALLER.os.replace
        destinations = []

        def fail_second(source, destination):
            destinations.append(Path(destination))
            if len(destinations) == 2:
                self.assertEqual(Path(destination), self.lua_pointer)
                self.assertEqual(json.loads(self.json_pointer.read_bytes())["hash"], self.candidate)
                self.assertEqual(self.lua_pointer.read_bytes(), before[1])
                raise OSError("synthetic second-pointer replace failure")
            return real_replace(source, destination)

        with mock.patch.object(INSTALLER.os, "replace", side_effect=fail_second):
            with self.assertRaisesRegex(OSError, "synthetic second-pointer"):
                self.install()
        self.assertEqual(destinations, [self.json_pointer, self.lua_pointer, self.json_pointer])
        self.assert_failed_pointers_unchanged(before)
        backup = self.report / "local_pointer_backup"
        self.assertEqual((backup / self.json_pointer.name).read_bytes(), before[0])
        self.assertEqual((backup / self.lua_pointer.name).read_bytes(), before[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
