"""Temporary signed thin inputs and aliases; never touch the real helper."""
from contextlib import ExitStack, contextmanager
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import install_refresh_helper as tool
import test_incremental_vpk as signed_fixture

spec = importlib.util.spec_from_file_location("existing_alias_test_fixture",
    HERE.parent / "arcade_payment_link_20261027/test_install_helper.py")
alias_fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alias_fixture)


@contextmanager
def signed_inputs():
    fixture = signed_fixture.IncrementalVPKTests("test_default_is_read_only_and_reports_only_impacted_volumes")
    fixture.setUp()
    try:
        data = fixture.fixture
        removed = "panorama/images/test/empty.vtex_c"
        changes = {"panorama/images/test/spaced binary.vtex_c": b"new signed bytes",
                   "panorama/scripts/custom_game/new_fixture.vjs_c": b"new compiled fixture"}
        fixture.reseal(changes, deleted=(removed,))
        trusted, root = data.base / "refresh-trusted", data.base / "workspace/survival"
        trusted.mkdir(); root.mkdir(parents=True)
        public_name = tool.web.POLICY_FILES[1]
        policy = json.loads((data.source / "policy.json").read_text())
        policy["integrity"]["trusted_public_key"] = public_name
        for folder in (root, trusted):
            for name, raw in ((tool.web.POLICY_FILES[0], tool.engine.canonical(policy)),
                              (public_name, (data.source / "public.pem").read_bytes())):
                path = folder / name
                path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(raw)
        for name in (*tool.pack.handoff.GATE_FILES, tool.pack.handoff.ACCESS_FILE):
            path = trusted / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((data.candidate / name).read_bytes())
        old_metadata = {name: (data.candidate / name).read_bytes() for name in tool.engine.METADATA}
        with ExitStack() as stack:
            for name, value in (("ROOT", root), ("OVERLAY", fixture.overlay), ("TRUSTED", trusted),
                ("NEW_SHA", fixture.manifest["content_sha256"]), ("COUNT", fixture.manifest["file_count"]),
                ("SEQUENCE", 11), ("DELETED_CSS", removed)):
                stack.enter_context(patch.object(tool, name, value))
            stack.enter_context(patch.object(tool, "input_paths"))
            stack.enter_context(patch.object(tool, "old_release", return_value=(fixture.base_manifest, old_metadata, {})))
            # Only production-specific 180-module configuration is outside this
            # small fixture. Real signature, all source hashes, thin inventory,
            # gate equality and manifest difference assembly remain enabled.
            stack.enter_context(patch.object(tool, "helper_guards"))
            stack.enter_context(patch.object(tool.pack.handoff, "ENTRY_GATE_FILES", ()))
            stack.enter_context(patch.object(tool.policy_patch, "unchanged"))
            yield fixture
    finally:
        fixture.doCleanups()


@contextmanager
def transaction_inputs():
    with alias_fixture.fixture() as data, ExitStack() as stack:
        core = alias_fixture.tool
        for name, value in (("engine", core), ("ROOT", data.root), ("TARGET", data.target),
            ("STORE", data.root / "output/arcade_cleanup_20261027/helper04_alias_transactions"),
            ("OLD_SHA", data.old["content_sha256"]), ("OLD_COUNT", data.old["file_count"]),
            ("OLD_SEQUENCE", core.BASE_SEQUENCE), ("NEW_SHA", data.new["content_sha256"]),
            ("COUNT", data.new["file_count"]), ("SEQUENCE", core.RELEASE_SEQUENCE),
            ("OLD_MARKER_SHA", core.web.sha(data.marker)), ("DELETED_CSS", next(iter(data.context["removed"])))):
            stack.enter_context(patch.object(tool, name, value))
        stack.enter_context(patch.object(tool, "releases", side_effect=lambda: dict(data.context)))
        # Restore these independent module entry points after configure retargets
        # this temporary transaction fixture.
        stack.enter_context(patch.object(core, "fixed_paths", core.fixed_paths))
        stack.enter_context(patch.object(core, "releases", core.releases))
        yield data, core


class RefreshHelperTests(unittest.TestCase):
    def test_not_pinned_refuses_before_old_or_target_io(self):
        self.assertIsNot(tool.engine, tool.policy_patch.install)
        with patch.object(tool, "NEW_SHA", None), patch.object(tool, "old_release", side_effect=AssertionError("IO")):
            with self.assertRaisesRegex(RuntimeError, "not_pinned"):
                tool.releases()

    def test_real_signature_thin_sources_and_deletion_are_verified_without_view(self):
        with signed_inputs() as data:
            before = {p: p.read_bytes() for p in data.overlay.rglob("*") if p.is_file()}
            result = tool.releases()
            self.assertEqual(result["removed"], {tool.DELETED_CSS})
            self.assertEqual(set(result["patches"]), result["modified"] | result["added"])
            self.assertEqual(result["new"]["content_sha256"], tool.NEW_SHA)
            self.assertFalse(data.view.exists())
            self.assertEqual(before, {p: p.read_bytes() for p in data.overlay.rglob("*") if p.is_file()})

    def test_tampered_signature_fallback_overlay_or_foreign_file_refuses(self):
        for kind in ("signature", "fallback", "overlay", "extra"):
            with self.subTest(kind=kind), signed_inputs() as data:
                if kind == "signature":
                    path = data.overlay / tool.pack.handoff.SIGNATURE
                    document = json.loads(path.read_bytes()); document["signature"] = "A" * 88
                    path.write_bytes(tool.engine.canonical(document))
                elif kind == "fallback":
                    (data.fixture.candidate / "addoninfo.txt").write_bytes(b"tampered base")
                elif kind == "overlay":
                    (data.overlay / "panorama/images/test/spaced binary.vtex_c").write_bytes(b"tampered")
                else:
                    (data.overlay / "foreign.txt").write_bytes(b"foreign")
                with self.assertRaises(Exception): tool.releases()
                self.assertFalse(data.view.exists())

    def test_real_transaction_apply_removes_old_css_and_strict_rollback_restores_it(self):
        with transaction_inputs() as (data, core):
            before = alias_fixture.images(data.target)
            audit = tool.run()
            self.assertTrue(audit["dry_run"])
            self.assertFalse(tool.STORE.exists())
            installed = tool.run(apply=True)
            self.assertTrue(installed["ok"])
            self.assertFalse((data.target / tool.DELETED_CSS).exists())
            self.assertEqual(alias_fixture.images(data.target)[next(iter(data.context["added"]))],
                             data.new_files[next(iter(data.context["added"]))])
            self.assertFalse(any((data.target / name).exists() for name in core.METADATA))
            self.assertTrue(tool.run(restore=True)["ok"])
            self.assertEqual(before, alias_fixture.images(data.target))

    def test_dota_or_foreign_runtime_blocks_before_transaction(self):
        for kind in ("dota", "foreign"):
            with self.subTest(kind=kind), transaction_inputs() as (data, core):
                if kind == "foreign": (data.target / "user.txt").write_bytes(b"keep me")
                before = alias_fixture.images(data.target)
                with patch.object(core, "dota_pids", return_value=[42] if kind == "dota" else []):
                    with self.assertRaises(RuntimeError): tool.run(apply=True)
                self.assertEqual(before, alias_fixture.images(data.target))
                self.assertFalse(tool.STORE.exists())

    def test_partial_failure_restores_only_owned_postimages(self):
        for foreign in (False, True):
            with self.subTest(foreign=foreign), transaction_inputs() as (data, core):
                before = alias_fixture.images(data.target)
                original, fired = core.cas_change, False
                modified = data.target / "scripts/vscripts/addon_game_mode.lua"
                def fail(*args, **kwargs):
                    nonlocal fired
                    original(*args, **kwargs)
                    if not fired:
                        fired = True
                        if foreign: modified.write_bytes(b"concurrent user bytes")
                        raise OSError("injected_failure")
                with patch.object(core, "cas_change", side_effect=fail), self.assertRaises(core.TransactionFailure) as caught:
                    tool.run(apply=True)
                if foreign:
                    self.assertFalse(caught.exception.report["recovery"]["ok"])
                    self.assertEqual(modified.read_bytes(), b"concurrent user bytes")
                else:
                    self.assertTrue(caught.exception.report["recovery"]["ok"])
                    self.assertEqual(before, alias_fixture.images(data.target))


if __name__ == "__main__": unittest.main()
