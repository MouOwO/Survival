"""Immutable S2 generator replay and fail-closed provenance tests; no runtime writes."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "generator_binding", ROOT / "tools/complete_delivery_release_20261103/generator_binding.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
S2 = "9ee4a3c411b42c84d4afe712e0eea9383a271457"
C2 = "e5c1b70d8ad2370389c87a0d645a6fccbe0d4178"


class MemorySource:
    def __init__(self, revision, values):
        self.revision, self.values = revision, values.copy()

    def read(self, name):
        if name not in self.values:
            raise subprocess.CalledProcessError(128, "immutable missing blob")
        return self.values[name]

    def fact(self, name):
        import hashlib
        raw = self.read(name)
        return {"commit": self.revision, "git_oid": hashlib.sha1(
            b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest(), **m.fingerprint(raw)}


class GeneratorBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        game = m.GitSource(ROOT, S2)
        content = m.GitSource(m.CONTENT, C2)
        operator = m.GitSource(ROOT, S2)
        cls.game_values = {p: game.read(p) for p in (*m.INPUTS, *m.OUTPUTS)}
        cls.content_values = {m.content_path(p): content.read(m.content_path(p))
                              for p in m.OUTPUTS if p != m.LUA}
        cls.operator_values = {m.GENERATOR: operator.read(m.GENERATOR)}

    def sources(self):
        return (MemorySource(S2, self.game_values), MemorySource(C2, self.content_values),
                MemorySource(S2, self.operator_values))

    def run_replay(self, game=None, content=None, operator=None, normalization="LF_TO_CRLF"):
        default = self.sources()
        return m.replay(game or default[0], content or default[1], operator or default[2],
                        {"exact_committed_tool": False, "diagnostic_only": True},
                        json_normalization=normalization)

    def test_real_s2_six_outputs_and_five_mirrors_are_exact(self):
        result = self.run_replay()
        self.assertEqual(result["source_revisions"], dict(game=S2, content=C2, operator=S2))
        self.assertEqual(len(result["outputs"]), 6)
        self.assertEqual(result["outputs"][m.LUA]["sha256"],
                         "e10121e0ee91d5530877b0480281fe8da94133c61e2d33f54b075935da196483")
        self.assertTrue(all(result["checks"].values()))
        self.assertEqual([r["mode"] for r in result["execution"]["commands"]], ["generate", "check"])
        self.assertFalse(result["protected"] or result["compiled"] or result["runtime_files_modified"])
        self.assertIn("BINDING_WRAPPER_NOT_YET_COMMITTED_TO_OPERATOR", result["authority_blockers"])

    def test_identity_input_replay_refuses_historical_crlf_digest(self):
        with self.assertRaisesRegex(ValueError, "generated_output_not_exact_selected_git_bytes"):
            self.run_replay(normalization="IDENTITY_EXACT_GIT_BYTES")

    def test_normalization_is_explicit_and_binds_both_original_and_executed_bytes(self):
        result = self.run_replay()
        normal = result["input_normalizations"]
        self.assertEqual(set(normal), set(m.INPUTS[:2]))
        self.assertEqual(normal[m.INPUTS[0]]["git_sha256"],
                         "0ae2cc392cd0e960be9e3ea1f232ab09b97e3cd66ca3593e23ce08117968bf83")
        self.assertEqual(normal[m.INPUTS[0]]["executed"]["sha256"],
                         "0c5b54163d7741598e414e367be1c5d862257aa78969032f383d22afd681d3fc")
        self.assertEqual(normal[m.INPUTS[1]]["executed"]["sha256"],
                         "efe674d95c2939a90b0545d62018fef81e0551f895b4634939e0052438885f26")
        self.assertEqual(result["executed_operator_inputs"][m.GENERATOR]["normalization"],
                         "IDENTITY_EXACT_GIT_BYTES")

    def test_absent_input_has_no_worktree_or_optional_file_fallback(self):
        game, _, _ = self.sources()
        del game.values[m.INPUTS[1]]
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_replay(game=game)

    def test_changed_expected_runtime_is_not_accepted_by_generator_check(self):
        game, _, _ = self.sources()
        game.values[m.LUA] += b"\n-- selected target tampered\n"
        with self.assertRaisesRegex(ValueError, "generated_output_not_exact_selected_git_bytes"):
            self.run_replay(game=game)

    def test_content_mirror_only_accepts_declared_crlf_transform(self):
        _, content, _ = self.sources()
        path = m.content_path(m.OUTPUTS[0])
        content.values[path] = content.values[path].replace(b"\n", b"\r\n")
        self.assertTrue(self.run_replay(content=content)["checks"]["five_content_mirrors_equal"])
        content.values[path] += b"// changed\n"
        with self.assertRaisesRegex(ValueError, "generated_content_js_mirror_mismatch"):
            self.run_replay(content=content)

    def test_missing_operator_generator_cannot_fall_back_to_current_tool(self):
        _, _, operator = self.sources()
        del operator.values[m.GENERATOR]
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_replay(operator=operator)

    def test_unreviewed_generator_write_is_detected(self):
        _, _, operator = self.sources()
        operator.values[m.GENERATOR] += b'\n(ROOT / "unreviewed.txt").write_text("unexpected")\n'
        with self.assertRaisesRegex(ValueError, "generator_unreviewed_file_write"):
            self.run_replay(operator=operator)

    def test_generator_cannot_mutate_public_input_after_generating(self):
        _, _, operator = self.sources()
        operator.values[m.GENERATOR] += b'\n(ROOT / SOURCE).write_bytes(b"changed")\n'
        with self.assertRaisesRegex(ValueError, "generator_modified_source"):
            self.run_replay(operator=operator)

    def test_invalid_normalization_never_executes(self):
        with self.assertRaisesRegex(ValueError, "explicit_reviewed_json_normalization_required"):
            self.run_replay(normalization="AUTODETECT")

    def test_uncommitted_wrapper_requires_explicit_diagnostic(self):
        _, _, operator = self.sources()
        with self.assertRaisesRegex(ValueError, "binding_tool_not_in_exact_operator_commit"):
            m.tool_identity(operator)
        self.assertFalse(m.tool_identity(operator, allow_diagnostic=True)["exact_committed_tool"])
        operator.values[m.TOOL] = Path(m.__file__).read_bytes()
        self.assertTrue(m.tool_identity(operator)["exact_committed_tool"])
        operator.values[m.TOOL] += b"# another implementation\n"
        with self.assertRaisesRegex(ValueError, "binding_tool_not_in_exact_operator_commit"):
            m.tool_identity(operator)

class LoadedToolTests(unittest.TestCase):
    def test_loaded_wrapper_must_match_disk_even_in_diagnostic_mode(self):
        operator = MemorySource(S2, {})
        with patch.object(m, "EXECUTED_TOOL_LF_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "binding_tool_changed_after_load"):
                m.tool_identity(operator, allow_diagnostic=True)


if __name__ == "__main__":
    unittest.main()
