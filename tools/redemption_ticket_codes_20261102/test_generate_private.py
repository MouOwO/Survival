"""Only temp directories, fixed synthetic entropy and no server connection."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from contextlib import redirect_stdout
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ticket_private_generator", HERE / "generate_private.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class PrivateGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic-ticket-workbook-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.private = root / "output/redemption_ticket_codes_20261102/private"
        for name, value in (("ROOT", root), ("PRIVATE", self.private)):
            p = patch.object(generator, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.tokens = [f"{n:024X}" for n in (1, 2, 3, 4)]

    def create(self):
        with patch.object(generator.secrets, "token_hex", side_effect=self.tokens) as entropy:
            result = generator.generate()
        self.assertEqual(entropy.call_count, 4)
        self.assertTrue(all(call.args == (12,) for call in entropy.call_args_list))
        return result

    def test_default_zero_effects_without_dependency_catalog_or_entropy(self):
        with patch.object(generator, "compiler", side_effect=AssertionError("Static only")), \
                patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No entropy")), \
                redirect_stdout(io.StringIO()) as out:
            self.assertEqual(generator.main([]), 0)
        value = json.loads(out.getvalue())
        self.assertEqual((value["plaintext_codes_created"], value["files_written"], value["server_connections"]), (0, 0, 0))
        self.assertFalse(self.private.exists())

    def test_four_codes_only_in_private_chinese_workbook_hashes_match_registry(self):
        result = self.create()
        self.assertEqual(result["codes"], 4)
        self.assertEqual(set(p.name for p in self.private.iterdir()), set(generator.TARGETS))
        module = generator.compiler()
        hashes = generator.hashes_from_workbook(module)
        self.assertEqual(json.loads((self.private / generator.HASHES).read_bytes()), hashes)
        registry = json.loads((self.private / generator.REGISTRY).read_bytes())
        self.assertEqual(registry, module.compile_definitions(hashes))
        for path in self.private.iterdir():
            if path.suffix == ".json":
                raw = path.read_bytes()
                for quantity, token in zip((10, 50, 100, 200), self.tokens):
                    self.assertNotIn(f"GFCJ{quantity}-{token}".encode(), raw)
        self.assertNotIn("GFCJ", json.dumps(result))
        manifest = json.loads((self.private / generator.MANIFEST).read_bytes())
        self.assertEqual(manifest["registration_status"], "待登记")
        self.assertFalse(manifest["registered"])

    def test_existing_batch_never_takes_fresh_entropy_or_overwrites(self):
        self.create()
        before = {p.name: p.read_bytes() for p in self.private.iterdir()}
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No regeneration")):
            with self.assertRaisesRegex(ValueError, "existing_generation_target"):
                generator.generate()
        self.assertEqual({p.name: p.read_bytes() for p in self.private.iterdir()}, before)

    def test_existing_old_target_refuses_without_entropy(self):
        self.private.mkdir(parents=True)
        old = self.private / generator.WORKBOOK
        old.write_bytes(b"unrelated old workbook; do not touch")
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No regeneration")):
            with self.assertRaisesRegex(ValueError, "existing_generation_target"):
                generator.generate()
        self.assertEqual(old.read_bytes(), b"unrelated old workbook; do not touch")

    def test_entropy_failure_preserves_intent_and_refuses_regeneration(self):
        with patch.object(generator.secrets, "token_hex", side_effect=RuntimeError("synthetic entropy failure")):
            with self.assertRaises(RuntimeError):
                generator.generate()
        self.assertTrue((self.private / generator.INTENT).is_file())
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No regeneration")):
            with self.assertRaisesRegex(ValueError, "existing_generation_target"):
                generator.generate()

    def test_resume_after_workbook_write_recovers_same_codes_without_entropy(self):
        with patch.object(generator.secrets, "token_hex", side_effect=self.tokens), \
                patch.object(generator, "same_or_new", side_effect=OSError("synthetic disk failure")):
            with self.assertRaises(OSError):
                generator.generate()
        self.assertTrue((self.private / generator.WORKBOOK).is_file())
        before = (self.private / generator.WORKBOOK).read_bytes()
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("Resume has no entropy")):
            result = generator.finish_same_batch(generator.compiler())
        self.assertEqual(result["codes"], 4)
        self.assertEqual((self.private / generator.WORKBOOK).read_bytes(), before)
        self.assertTrue((self.private / generator.MANIFEST).is_file())

    def test_completed_batch_resume_idempotent_and_zero_entropy(self):
        self.create()
        before = {p.name: p.read_bytes() for p in self.private.iterdir()}
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No regeneration")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(generator.main(["--resume"]), 0)
        self.assertNotIn("GFCJ", output.getvalue())
        self.assertEqual({p.name: p.read_bytes() for p in self.private.iterdir()}, before)

    def test_unknown_existing_registry_never_overwritten(self):
        self.create()
        path = self.private / generator.REGISTRY
        path.write_bytes(b'{"foreign":"preserve"}\n')
        with self.assertRaisesRegex(ValueError, "existing_private_artifact_differs"):
            generator.finish_same_batch(generator.compiler())
        self.assertEqual(path.read_bytes(), b'{"foreign":"preserve"}\n')

    def test_changed_pending_hashes_refused(self):
        self.create()
        path = self.private / generator.PENDING
        value = json.loads(path.read_bytes())
        value["hashes"]["10"] = "a" * 64
        path.write_text(json.dumps(value), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "workbook_hash_differs_from_pending"):
            generator.finish_same_batch(generator.compiler())

    def test_changed_operator_source_pins_refused(self):
        self.create()
        with patch.object(generator, "source_pins", return_value={"foreign": "x"}):
            with self.assertRaisesRegex(ValueError, "generation_source_changed"):
                generator.finish_same_batch(generator.compiler())

    def test_partial_workbook_preserved_without_regeneration(self):
        self.create()
        path = self.private / generator.WORKBOOK
        path.write_bytes(b"synthetic truncated xlsx")
        with patch.object(generator.secrets, "token_hex", side_effect=AssertionError("No regeneration")):
            with self.assertRaisesRegex(ValueError, "intact_original_workbook_required"):
                generator.finish_same_batch(generator.compiler())
        self.assertEqual(path.read_bytes(), b"synthetic truncated xlsx")

    def test_wrong_output_root_or_directory_reparse_refused(self):
        with patch.object(generator, "PRIVATE", Path(self.temporary.name) / "old128"):
            with self.assertRaisesRegex(ValueError, "fixed_private_directory_required"):
                generator.private_directory()
        import stat
        from types import SimpleNamespace
        with patch.object(Path, "lstat", return_value=SimpleNamespace(st_mode=stat.S_IFDIR, st_file_attributes=0x400)):
            with self.assertRaisesRegex(ValueError, "private_reparse"):
                generator.private_directory()


if __name__ == "__main__":
    unittest.main()
