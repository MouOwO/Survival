"""Offline native-cloud adapter and unchanged real callback ABI contracts."""
from __future__ import annotations

from contextlib import redirect_stdout
import copy
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load("map2802_official_download_under_test", HERE / "verify_map_resources_download.py")
legacy = load("map2802_original_protocol_tests", HERE.parent / "arcade_cleanup_20261027/test_verify_download.py")


class NativeCloudProtocolContracts(legacy.SafetyTests):
    """Run all existing callback/freshness/ACF tests against our private instance."""
    def setUp(self):
        context = patch.object(legacy, "subject", tool.protocol)
        context.start()
        self.addCleanup(context.stop)

    def test_fixed_new_release_has_no_historical_manifest_pin(self):
        p = tool.protocol
        self.assertEqual((p.ITEM, p.SEQUENCE, p.FILE_COUNT), ("3824360109", 2026102802, 6658))
        self.assertEqual(p.CONTENT, tool.CONTENT)
        self.assertEqual(p.CANDIDATE.name, "20261028_ws4_map_resources_v01_view")
        self.assertEqual(p.TRUSTED.name, "20261028_ws4_map_resources_v01_overlay_trusted_source")
        self.assertEqual(p.VPK.parent.name, "20261028_ws4_map_resources_v01")
        self.assertEqual(p.REPORT.name, "package.json")
        self.assertEqual(p.OUTPUT.name, "download_evidence")
        self.assertEqual(p.MINIMUM_REMOTE_UPDATED, 1793146417)
        self.assertFalse(hasattr(p, "EXPECTED_STEAM_MANIFEST"))


class NativeCloudAdditionalGuards(unittest.TestCase):
    def package_inputs(self):
        return dict(report=dict(status="BUILT_SIGNED_MAP2802_REQUIRES_NATIVE_MAP_TEST",
            vpk_sha256="a"*64, full_view_canonical_guard="PASS", canonical_single_map=True,
            canonical_reviewed_gate=True, immutable_base_unchanged=True,
            qr_fix_preserved=True, layout_fix_preserved=True, authentication_payment_gameplay_code_preserved=True,
            base_release_sequence=2026102801,
            base_content_sha256="f20c64b00da4e9d9f1a93bd7fca23163aa3f8b203e9ae354de5f60d9a8c75503",
            changed_runtime_paths=[tool.MAP_TARGET], deleted_runtime_paths=[], added_runtime_paths=[],
            source_sha256=tool.MAP_SOURCE_SHA, compile_log_sha256=tool.COMPILE_LOG_SHA,
            source_crc32=tool.MAP_SOURCE_CRC, map_package_verification_sha256=tool.MAP_VERIFICATION_SHA,
            map_package_crc_entries_verified=tool.MAP_CRC_ENTRIES, map_compiled_source_crc_verified=True,
            trusted_gate_files=14, trusted_review_files=16,
            protected_modules_preserved=180, protected_modules_rebuilt=0),
            report_sha256="b"*64, total=1000, snapshots={}, manifest={"files":[
                dict(path=tool.MAP_TARGET,sha256=tool.MAP_COMPILED_SHA,bytes=tool.MAP_COMPILED_BYTES),
                dict(path=tool.ENTRY_TARGET,sha256=tool.ENTRY_SHA)]})

    def package_pins(self):
        values = dict(REPORT_SHA="b"*64, INDEX_SHA="a"*64, TOTAL_BYTES=1000, CONTENT="c"*64,
            MAP_COMPILED_SHA="d"*64, MAP_COMPILED_BYTES=1234, COMPILE_LOG_SHA="e"*64,
            MAP_VERIFICATION_SHA="f"*64)
        for name,value in values.items():
            context=patch.object(tool,name,value);context.start();self.addCleanup(context.stop)

    def test_pending_pins_refuse_before_release_reads_lock_or_sdk(self):
        with patch.object(tool, "REPORT_SHA", None), \
                patch.object(tool, "_verified_local_inputs", side_effect=AssertionError("release reads forbidden")), \
                patch.object(tool.api.Steam, "__enter__", side_effect=AssertionError("SDK forbidden")), \
                patch.object(tool.api, "publication_lock", side_effect=AssertionError("lock forbidden")), \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(tool.main([]), 1)
            self.assertEqual(tool.main(["--download"]), 1)
        self.assertEqual(output.getvalue().count("map_resources_completed_package_pins_not_yet_finalized"), 2)

    def test_completed_real_package_hash_size_and_canonical_results_are_mandatory(self):
        self.package_pins()
        tool.require_package_pins()
        original = self.package_inputs()
        tool.verify_completed_report(original)
        for key,value in (("status","NOT_BUILT"),("full_view_canonical_guard","NOT_RUN"),
                ("canonical_single_map",False),("canonical_reviewed_gate",False),("immutable_base_unchanged",False),
                ("protected_modules_preserved",179),("protected_modules_rebuilt",1),
                ("qr_fix_preserved",False),("layout_fix_preserved",False),
                ("authentication_payment_gameplay_code_preserved",False),("base_release_sequence",2026102709),
                ("base_content_sha256","0"*64),("changed_runtime_paths",[tool.LAYOUT_TARGET]),
                ("source_sha256","0"*64),("compile_log_sha256","0"*64),
                ("trusted_gate_files",13),("trusted_review_files",15),
                ("deleted_runtime_paths",["other"]),("added_runtime_paths",["other"]),("vpk_sha256","0"*64)):
            d = copy.deepcopy(original); d["report"][key] = value
            with self.subTest(key=key), self.assertRaises(tool.callbacks.Refused): tool.verify_completed_report(d)
        for key, value in (("report_sha256", "c" * 64), ("total", 999)):
            d = copy.deepcopy(original); d[key] = value
            with self.subTest(key=key), self.assertRaises(tool.callbacks.Refused): tool.verify_completed_report(d)

    def test_full_locked_verification_forwards_to_frozen_canonical_protocol(self):
        self.package_pins()
        values = self.package_inputs()
        with patch.object(tool, "_verified_local_inputs", return_value=values) as base, \
                patch.object(tool, "verify_review_sources") as reviews, \
                patch.object(tool,"verify_map_compile_evidence") as map_proof:
            self.assertIs(tool.local_inputs(True, full=True), values)
        base.assert_called_once_with(True, full=True)
        reviews.assert_called_once_with(values)
        map_proof.assert_called_once_with(values)

    def test_exact_sixteen_review_sources_bind_native_modules_checkout_and_reject_foreign_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            values = self.package_inputs()
            for relative in tool.TRUST_NAMES:
                raw = ("reviewed fixture " + relative).encode()
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
                if relative.startswith("scripts/"):
                    values["manifest"]["files"].append(dict(path=relative, sha256=hashlib.sha256(raw).hexdigest()))
            qr = root/tool.QR_SOURCE_REL
            qr.parent.mkdir(parents=True,exist_ok=True)
            qr.write_bytes(b"reviewed original QR source")
            values["manifest"]["files"].append(dict(path=tool.QR_TARGET,sha256=tool.QR_COMPILED_SHA))
            source = root/tool.LAYOUT_SOURCE_REL
            source.parent.mkdir(parents=True,exist_ok=True)
            source.write_bytes(b"reviewed QR09 checkout source fixture")
            values["manifest"]["files"].append(dict(path=tool.LAYOUT_TARGET,sha256=tool.LAYOUT_COMPILED_SHA))
            with patch.object(tool, "TRUSTED", root), patch.object(tool,"LAYOUT_SOURCE_SHA",hashlib.sha256(source.read_bytes()).hexdigest()), patch.object(tool,"QR_SOURCE_SHA",hashlib.sha256(qr.read_bytes()).hexdigest()):
                tool.verify_review_sources(values)
                self.assertEqual(len(values["snapshots"]), 19)  # 16 reviewed + publisher/protocol/profile parser.
                target = root / "scripts/vscripts/systems/native_cloud_roster.lua"
                raw = target.read_bytes(); target.write_bytes(raw + b"tampered")
                with self.assertRaisesRegex(tool.callbacks.Refused, "review_source_differs"): tool.verify_review_sources(values)
                target.write_bytes(raw)
                qr_raw=qr.read_bytes(); qr.write_bytes(qr_raw+b"tamper")
                with self.assertRaisesRegex(tool.callbacks.Refused,"previous_qr_fix_changed"):tool.verify_review_sources(values)
                qr.write_bytes(qr_raw)
                source_raw=source.read_bytes(); source.write_bytes(source_raw+b"tamper")
                with self.assertRaisesRegex(tool.callbacks.Refused,"checkout_source_changed"):tool.verify_review_sources(values)
                source.write_bytes(source_raw)
                values["manifest"]["files"].append(dict(path=tool.LAYOUT_SOURCE_REL,sha256="a"*64))
                with self.assertRaisesRegex(tool.callbacks.Refused,"source_exclusion_changed"):tool.verify_review_sources(values)
                values["manifest"]["files"].pop()
                (root / "foreign.txt").write_bytes(b"not reviewed")
                with self.assertRaisesRegex(tool.callbacks.Refused, "inventory_changed"): tool.verify_review_sources(values)

    def map_proof(self):
        return dict(status="PASS",compiled_verified=True,
            source=dict(sha256=tool.MAP_SOURCE_SHA,raw_crc32=tool.MAP_SOURCE_CRC,converted=False),
            package=dict(sha256=tool.MAP_COMPILED_SHA,bytes=tool.MAP_COMPILED_BYTES,version=2,
                         crc_entries=tool.MAP_CRC_ENTRIES,
                         entries=[dict(crc_matches=True,expected_crc32=77,actual_crc32=77)
                                  for _ in range(tool.MAP_CRC_ENTRIES)]),
            source_match=dict(source_name="maps/template_map.vmap",matches=True,
                              raw_source_crc32=tool.MAP_SOURCE_CRC,compiled_source_crc32=tool.MAP_SOURCE_CRC),
            compiled_map=dict(path="maps/template_map.vmap_c"))

    def test_actual_map_crc_source_match_and_raw_proof_pin_are_required(self):
        import json
        self.package_pins()
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/"package_verification.json"
            proof=self.map_proof();raw=json.dumps(proof).encode();path.write_bytes(raw)
            with patch.object(tool,"MAP_VERIFICATION",path),patch.object(tool,"MAP_VERIFICATION_SHA",hashlib.sha256(raw).hexdigest()):
                values=self.package_inputs();tool.verify_map_compile_evidence(values)
                self.assertIn(path.resolve(),values["snapshots"])
                path.write_bytes(raw+b" ")
                with self.assertRaisesRegex(tool.callbacks.Refused,"crc_evidence_changed"):
                    tool.verify_map_compile_evidence(self.package_inputs())
            def bad_crc_row(row):
                entries=copy.deepcopy(proof["package"]["entries"])
                entries[-1]=row
                return entries
            cases=[("status","FAIL"),("compiled_verified",False),
                   ("source.converted",True),("source.sha256","0"*64),("source.raw_crc32",123),
                   ("package.sha256","0"*64),("package.bytes",1),("package.version",1),
                   ("package.crc_entries",2),("package.entries",bad_crc_row(dict(crc_matches=True,expected_crc32=77,actual_crc32=88))),
                   ("package.entries",bad_crc_row(dict(crc_matches=True))),
                   ("package.entries",bad_crc_row(dict(crc_matches=True,expected_crc32=True,actual_crc32=True))),
                   ("source_match.matches",False),("source_match.compiled_source_crc32",736803486),
                   ("source_match.raw_source_crc32",0),("source_match.source_name","maps/ws4_entry.vmap"),
                   ("compiled_map.path","maps/other.vmap_c")]
            for field,value in cases:
                bad=copy.deepcopy(proof);target=bad
                parts=field.split(".")
                for part in parts[:-1]:target=target[part]
                target[parts[-1]]=value;data=json.dumps(bad).encode();path.write_bytes(data)
                with self.subTest(field=field),patch.object(tool,"MAP_VERIFICATION",path), \
                        patch.object(tool,"MAP_VERIFICATION_SHA",hashlib.sha256(data).hexdigest()), \
                        self.assertRaisesRegex(tool.callbacks.Refused,"actual_map_crc_and_source_match"):
                    tool.verify_map_compile_evidence(self.package_inputs())

    def test_signed_map_and_unchanged_entry_are_bound_independently_of_report_flags(self):
        self.package_pins()
        for path,field,value in ((tool.MAP_TARGET,"sha256","0"*64),(tool.MAP_TARGET,"bytes",0),(tool.ENTRY_TARGET,"sha256","0"*64)):
            values=self.package_inputs();next(row for row in values["manifest"]["files"]if row["path"]==path)[field]=value
            with self.subTest(path=path,field=field),self.assertRaisesRegex(tool.callbacks.Refused,"signed_map_entry_or_source_scope"):
                tool.verify_completed_report(values)
        values=self.package_inputs();values["manifest"]["files"].append(dict(path="maps/template_map.vmap",sha256="0"*64))
        with self.assertRaisesRegex(tool.callbacks.Refused,"signed_map_entry_or_source_scope"):
            tool.verify_completed_report(values)

    def test_builder_map_crc_proof_fields_refuse_bad_hash_flags_or_legacy_alias_before_evidence_or_sdk(self):
        self.package_pins()
        fields = {"map_package_verification_sha256":"0"*64,
                  "map_compiled_source_crc_verified":False,
                  "map_package_crc_entries_verified":306,"source_crc32":736803486}
        for field,value in fields.items():
            for missing in (False,True):
                values=self.package_inputs()
                if missing:
                    values["report"].pop(field)
                    if field=="map_package_verification_sha256":
                        values["report"]["map_verification_sha256"]=tool.MAP_VERIFICATION_SHA
                else:values["report"][field]=value
                with self.subTest(field=field,missing=missing), \
                        patch.object(tool,"_verified_local_inputs",return_value=values), \
                        patch.object(tool,"verify_review_sources",side_effect=AssertionError("review reads forbidden")), \
                        patch.object(tool,"verify_map_compile_evidence",side_effect=AssertionError("evidence reads forbidden")), \
                        patch.object(tool.api.Steam,"__enter__",side_effect=AssertionError("SDK forbidden")), \
                        self.assertRaisesRegex(tool.callbacks.Refused,"complete_view_canonical_and_protection"):
                    tool.local_inputs(True,full=True)

    def test_frozen_original_protocol_file_is_unchanged(self):
        self.assertEqual(hashlib.sha256(tool.PROTOCOL_FILE.read_bytes().replace(b"\r\n", b"\n")).hexdigest(),
                         tool.PROTOCOL_LF_SHA)
        self.assertIsNot(legacy.subject, tool.protocol)
        self.assertEqual((legacy.subject.SEQUENCE, legacy.subject.FILE_COUNT), (2026102705, 6655))
        self.assertEqual(legacy.subject.REPORT.name, "native_package_build_v02.json")


if __name__ == "__main__":
    unittest.main()
