"""Offline contract tests: no live release reads, Steam, download or writes."""
import ctypes as C
from contextlib import nullcontext, redirect_stdout
import copy
import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import verify_download as subject


class SafetyTests(unittest.TestCase):
    def inputs(self):
        return dict(total=1000, report={}, state={}, snapshots={}, success=True, expected_manifest=None)

    def remote(self):
        return dict(id=subject.ITEM, result=1, file_type=0, creator_app_id=570,
            consumer_app_id=570, owner=subject.api.OWNER, visibility=3, total_files_bytes=1000,
            cached=False, max_cache_age_seconds=0, banned=False, tags_truncated=False,
            time_updated=subject.MINIMUM_REMOTE_UPDATED + 1, tags="Custom Game")

    def test_fixed_new_release_has_no_historical_manifest_pin(self):
        self.assertEqual((subject.ITEM, subject.SEQUENCE, subject.FILE_COUNT), ("3824360109", 2026102705, 6655))
        self.assertEqual(subject.CONTENT, "8a01a5b66603804c683b879043c220e4f9496d7cca75f304ac5d9da210794cf6")
        self.assertEqual(subject.CANDIDATE.name, "20261027_ws4_refresh_native_v02_view")
        self.assertEqual(subject.TRUSTED.name, "20261027_ws4_refresh_native_v02_overlay_trusted_source")
        self.assertEqual(subject.VPK.parent.name, "20261027_ws4_refresh_native_v02")
        self.assertEqual(subject.REPORT.name, "native_package_build_v02.json")
        self.assertEqual(subject.OUTPUT.name, "download_evidence_v02")
        self.assertEqual(len(subject.EXPECTED_NAMES), 5)
        self.assertFalse(hasattr(subject, "EXPECTED_STEAM_MANIFEST"))

    def test_current_journal_manifest_must_be_uint64_string_and_never_comes_from_history(self):
        self.assertIsNone(subject.journal_manifest(dict(previous_release={"download_manifest": "123"},
                                                       release_history=[{"steam_manifest": "456"}])))
        for value in (0, 123, True, "0", "01", "-1", "", "１２３", str(2**64)):
            with self.subTest(value=value), self.assertRaises(subject.callbacks.Refused):
                subject.journal_manifest({"download_manifest": value})
        self.assertEqual(subject.journal_manifest({"steam_manifest": "123", "download_manifest": "123"}), "123")
        with self.assertRaisesRegex(subject.callbacks.Refused, "conflicting"):
            subject.journal_manifest({"steam_manifest": "123", "download_manifest": "456"})

    def test_default_plan_does_not_initialize_steam_lock_or_write_and_needs_no_manifest_pin(self):
        with patch.object(subject, "local_inputs", return_value=self.inputs()) as local, \
                patch.object(subject.shutil, "disk_usage", return_value=SimpleNamespace(free=2**40)), \
                patch.object(subject.api.Steam, "__enter__", side_effect=AssertionError("Steam forbidden")), \
                patch.object(subject.api, "publication_lock", side_effect=AssertionError("lock write forbidden")), \
                patch.object(subject.callbacks, "write_exclusive", side_effect=AssertionError("write forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main([]), 0)
        local.assert_called_once_with(False)
        self.assertIn("READ_ONLY_REFRESH_NATIVE_DOWNLOAD_PLAN", output.getvalue())
        self.assertIn('"steam_initialized": false', output.getvalue())
        self.assertIn('"journal_manifest": null', output.getvalue())

    def test_insufficient_space_and_changed_inputs_refuse_before_sdk_or_download(self):
        with patch.object(subject, "local_inputs", return_value=self.inputs()), \
                patch.object(subject.shutil, "disk_usage", return_value=SimpleNamespace(free=0)), \
                patch.object(subject.api, "publication_lock", side_effect=AssertionError("lock forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main(["--download"]), 1)
        self.assertIn("insufficient_full_package", output.getvalue())
        with patch.object(subject, "local_inputs", return_value=self.inputs()), \
                patch.object(subject.shutil, "disk_usage", return_value=SimpleNamespace(free=2**40)), \
                patch.object(subject.api, "publication_lock", return_value=nullcontext()), \
                patch.object(subject, "unchanged", side_effect=subject.callbacks.Refused("changed")), \
                patch.object(subject, "download_once", side_effect=AssertionError("download forbidden")), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(subject.main(["--download"]), 1)

    def test_full_locked_revalidation_must_match_initial_snapshots_before_download(self):
        initial, changed = self.inputs(), self.inputs()
        changed["snapshots"] = {Path("fake"): b"changed"}
        with patch.object(subject, "local_inputs", side_effect=[initial, changed]) as local, \
                patch.object(subject.shutil, "disk_usage", return_value=SimpleNamespace(free=2**40)), \
                patch.object(subject.api, "publication_lock", return_value=nullcontext()), \
                patch.object(subject, "unchanged"), \
                patch.object(subject, "download_once", side_effect=AssertionError("download forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(subject.main(["--download"]), 1)
        self.assertEqual(local.call_args_list[1].kwargs, {"full": True})
        self.assertIn("inputs_changed_before_download", output.getvalue())

    def test_remote_details_must_match_same_owner_item_size_visibility_and_freshness(self):
        valid = self.remote()
        subject.validate_remote(valid, 1000)
        for key, value in dict(id="1", result=True, owner="1", visibility=0, cached=True,
                max_cache_age_seconds=1, banned=True, tags_truncated=True, total_files_bytes=999,
                time_updated=subject.MINIMUM_REMOTE_UPDATED, consumer_app_id=571, tags="Other").items():
            with self.subTest(key=key), self.assertRaises(subject.callbacks.Refused):
                subject.validate_remote({**valid, key: value}, 1000)

    def test_download_api_allowlist_forbids_publication_and_unsubscribe(self):
        steam = subject.RefreshSteam(1000)
        for name in ("CreateItem", "StartItemUpdate", "SubmitItemUpdate", "SetItemContent", "UnsubscribeItem"):
            with self.subTest(name=name), self.assertRaises(subject.callbacks.Refused):
                steam.ug(name, C.c_bool, [])

    def test_existing_subscription_requires_matching_real_1313_once(self):
        steam, calls = self.subscription()
        result = steam.refresh_subscription_once()
        self.assertEqual(result["callback"]["callback_id"], 1313)
        self.assertEqual(calls.count("SubscribeItem"), 1)
        self.assertNotIn("DownloadItem", calls)
        for options in ({"result": 2}, {"item": "1"}, {"after": 29}):
            steam, calls = self.subscription(**options)
            with self.subTest(options=options), self.assertRaises(subject.callbacks.Refused):
                steam.refresh_subscription_once()
            self.assertNotIn("DownloadItem", calls)

    def subscription(self, *, result=1, item=None, after=13):
        steam = subject.RefreshSteam(1000)
        calls, scheduled = [], [False]
        completed = subject.callbacks.CallCompleted(99, 1313, C.sizeof(subject.verify.Subscribed))
        message = SimpleNamespace(callback=703, size=C.sizeof(completed), data=C.addressof(completed))
        def ug(name, unused_result, unused_types, *unused_args):
            calls.append(name)
            if name == "GetItemState":
                return after if scheduled[0] else 5
            self.assertEqual(name, "SubscribeItem")
            scheduled[0] = True
            return 99
        def poll(handler):
            if scheduled[0]:
                handler(message)
        def read_result(pipe, call, pointer, size, callback, failed):
            record = C.cast(pointer, C.POINTER(subject.verify.Subscribed)).contents
            record.result, record.item = result, int(subject.ITEM if item is None else item)
            return True
        steam.ug = ug
        steam.dispatch = SimpleNamespace(pipe=7, poll=poll, result=read_result)
        return steam, calls

    def test_download_requires_real_3406_one_request_and_same_install_folder_and_size(self):
        with tempfile.TemporaryDirectory() as folder:
            installed = Path(folder).resolve()
            steam = subject.RefreshSteam(1000)
            calls, states = [], iter([13, 5])
            def ug(name, unused_result, unused_types, *args):
                calls.append(name)
                if name == "GetItemState":
                    return next(states)
                if name == "DownloadItem":
                    self.assertEqual(args, (int(subject.ITEM), True))
                    return True
                self.assertEqual(name, "GetItemInstallInfo")
                C.cast(args[1], C.POINTER(C.c_uint64)).contents.value = 1000
                args[2].value = str(installed).encode("utf8")
                C.cast(args[4], C.POINTER(C.c_uint32)).contents.value = subject.MINIMUM_REMOTE_UPDATED + 1
                return True
            def download(request):
                self.assertTrue(request())
                return dict(callback_id=3406, app_id=570, workshop_id=subject.ITEM, result=1)
            steam.ug, steam.dispatch = ug, SimpleNamespace(download=download)
            with patch.object(subject, "INSTALLED", installed):
                result = steam.download_installed()
            self.assertEqual(calls.count("DownloadItem"), 1)
            self.assertEqual(result["callback"]["callback_id"], 3406)
            self.assertIsNone(result["journal_manifest"])
            self.assertNotIn("expected_manifest", result)

    def acf(self, *, manifest="123456", size="1000", stamp=None):
        stamp = str(subject.MINIMUM_REMOTE_UPDATED + 1) if stamp is None else stamp
        return ('"AppWorkshop" { "appid" "570" "WorkshopItemsInstalled" { "' + subject.ITEM +
                '" { "manifest" "' + manifest + '" "size" "' + size + '" "timeupdated" "' + stamp + '" } } }').encode()

    def test_dynamic_manifest_from_real_install_is_bound_to_fresh_query_not_old_pin(self):
        manifest, row = subject.acf_manifest(self.acf(), self.remote(), 1000)
        self.assertEqual(manifest, "123456")
        self.assertIsInstance(manifest, str)
        self.assertEqual(subject.acf_manifest(self.acf(), self.remote(), 1000, "123456")[0], "123456")
        for raw, pin in ((self.acf(manifest="0"), None), (self.acf(size="999"), None),
                         (self.acf(stamp="1"), None), (self.acf(), "old123")):
            with self.subTest(raw=raw, pin=pin), self.assertRaises(subject.callbacks.Refused):
                subject.acf_manifest(raw, self.remote(), 1000, pin)

    def test_snapshot_change_and_wrong_protected_count_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder).resolve() / "input.json"
            path.write_bytes(b"expected")
            subject.unchanged({path: b"expected"})
            path.write_bytes(b"changed")
            with self.assertRaisesRegex(subject.callbacks.Refused, "local_input_changed"):
                subject.unchanged({path: b"expected"})
        with patch.object(subject.protect_runtime_lua, "check_policy"), \
                patch.object(subject.protect_runtime_lua, "selected_files", return_value=[{"path": "x"}]), \
                self.assertRaisesRegex(subject.callbacks.Refused, "180"):
            subject.protected_inventory({"files": []}, {})


if __name__ == "__main__":
    unittest.main()
