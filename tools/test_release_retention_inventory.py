import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from release_retention_inventory import produce_inventory, scan_inventory
from release_retention import plan_retirement


def identity(sequence=2026110302, digest="a"):
    return dict(workshop_id="3824360109", release_sequence=sequence, content_sha256=digest*64)


def record(name, version):
    files=[dict(name="3824360109.vpk",bytes=10,sha256="c"*64)]
    files += [dict(name="3824360109_%03d.vpk"%n,bytes=20+n,sha256="d"*64) for n in range(4)]
    document=dict(version,candidate="D:/Survival_发布候选/"+name,output="D:/Survival_工坊输出/"+name+"/3824360109.vpk",package_files=files)
    digest=hashlib.sha256(json.dumps(document,sort_keys=True).encode()).hexdigest()
    return dict(path="C:/repo/output/"+name+"/package.json",sha256=digest,document=document)


def control(document):
    raw=json.dumps(document,sort_keys=True).encode()
    return dict(document=document,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())


def fixture():
    current=record("current",identity());old=record("old",identity(2026102301,"b"))
    journal=dict(identity(),uploaded=True,package=current["document"]["output"],previous_release=copy.deepcopy(old["document"]),release_history=[copy.deepcopy(old["document"])])
    view=dict(path="D:/Survival_发布候选/old",root_reparse_point=False,scan_errors=[],entries=[dict(name="materials",kind="directory",bytes=None)],controls={
        "_release_manifest.json":control(dict(content_sha256="b"*64,bytes=100,file_count=1)),
        "_release_signature.json":control(dict(content_sha256="b"*64,release_sequence=2026102301))})
    build=dict(path="D:/Survival_工坊输出/old",root_reparse_point=False,scan_errors=[],controls={},entries=[dict(name=f["name"],kind="file",bytes=f["bytes"]) for f in old["document"]["package_files"]])
    return [view,build],[current,old],current,journal


def observed(snapshots):
    return {s["path"]:dict(active=False,in_use=False,reparse_point=False) for s in snapshots}


def confirmed(result):
    return {row["path"]:dict(preserved=True,identity={k:row[k] for k in ("workshop_id","release_sequence","content_sha256")},
                inventory_fingerprint=row["inventory_fingerprint"],evidence_paths=["D:/Survival_清理归档/retention/receipts.json"]) for row in result["inventory"]}


class InventoryTests(unittest.TestCase):
    def test_no_false_safe_occupancy_reparse_or_evidence_defaults(self):
        snapshots,reports,current,journal=fixture();result=produce_inventory(snapshots,reports,current,journal,[],set())
        for row in result["inventory"]:
            self.assertIsNone(row["active"]);self.assertIsNone(row["in_use"]);self.assertIsNone(row["reparse_point"])
            self.assertFalse(row["evidence_preserved"]);self.assertEqual(row["inventory_status"],"BLOCKED")
        self.assertEqual(result["metrics"]["payload_bytes_read"],0)
        self.assertEqual(result["deletion_actions"],0)

    def test_historical_references_do_not_protect_old_unreferenced_artifacts(self):
        snapshots,reports,current,journal=fixture();before=copy.deepcopy((snapshots,reports,current,journal))
        first=produce_inventory(snapshots,reports,current,journal,[],set(),observations=observed(snapshots))
        result=produce_inventory(snapshots,reports,current,journal,[],set(),observations=observed(snapshots),evidence_confirmations=confirmed(first))
        self.assertTrue(all(row["inventory_status"]=="OBSERVED_UNREFERENCED_ARTIFACT" for row in result["inventory"]))
        self.assertTrue(all(not row["referenced_by"] for row in result["inventory"]))
        self.assertFalse(any(path.casefold().endswith("\\old") for path in result["protected_paths"]))
        self.assertEqual((snapshots,reports,current,journal),before)

    def test_current_package_current_journal_explicit_baseline_and_pending_reports_protect(self):
        snapshots,reports,current,journal=fixture();old=reports[1]
        cases=(dict(registered_report=old),dict(canonical_journal=old["document"]),dict(active_baseline_paths=[snapshots[1]["path"]+"/3824360109.vpk"]),dict(pending_report_sha256s={old["sha256"]}))
        for changes in cases:
            args=dict(directory_snapshots=snapshots,report_records=reports,registered_report=current,canonical_journal=journal,active_baseline_paths=[],pending_report_sha256s=set());args.update(changes)
            result=produce_inventory(**args)
            self.assertTrue(any(row["active"] is True for row in result["inventory"]))
            self.assertTrue(result["protected_paths"])

    def test_unknown_pending_binding_blocks_all_candidates(self):
        snapshots,reports,current,journal=fixture();result=produce_inventory(snapshots,reports,current,journal,[],{"f"*64})
        self.assertIn("pending_report_binding_unresolved",result["blockers"])
        self.assertTrue(all(row["referenced_by"] for row in result["inventory"]))

    def test_conflicting_manifest_report_and_unknown_directory_cannot_be_identified(self):
        snapshots,reports,current,journal=fixture();snapshots[0]["controls"]["_release_manifest.json"]=control(dict(content_sha256="f"*64,bytes=100))
        snapshots.append(dict(path="D:/Survival_发布候选/unregistered",entries=[],controls={}))
        result=produce_inventory(snapshots,reports,current,journal,[],set())
        for row in (result["inventory"][0],result["inventory"][2]):
            self.assertIn("artifact_identity_not_uniquely_bound",row["inventory_blockers"])

    def test_extra_or_missing_build_volume_is_blocked_without_reading_payload(self):
        snapshots,reports,current,journal=fixture();snapshots[1]["entries"].append(dict(name="stale_009.vpk",kind="file",bytes=10))
        result=produce_inventory(snapshots,reports,current,journal,[],set())
        self.assertIn("build_file_set_not_uniquely_bound_to_report",result["inventory"][1]["inventory_blockers"])

    def test_stale_archive_confirmation_or_evidence_inside_release_roots_is_refused(self):
        snapshots,reports,current,journal=fixture();first=produce_inventory(snapshots,reports,current,journal,[],set())
        for change in (lambda v:v.update(inventory_fingerprint="f"*64),lambda v:v.update(evidence_paths=["D:/Survival_工坊输出/old/receipt.json"])):
            evidence=confirmed(first)
            for value in evidence.values():change(value)
            result=produce_inventory(snapshots,reports,current,journal,[],set(),observations=observed(snapshots),evidence_confirmations=evidence)
            self.assertTrue(all(not row["evidence_preserved"] for row in result["inventory"]))

    def test_known_root_reparse_cannot_be_overridden_by_caller_false(self):
        snapshots,reports,current,journal=fixture();snapshots[0]["root_reparse_point"]=True
        result=produce_inventory(snapshots,reports,current,journal,[],set(),observations=observed(snapshots))
        self.assertTrue(result["inventory"][0]["reparse_point"])

    def test_filesystem_adapter_reads_only_control_json_and_one_level_entries(self):
        snapshots,reports,current,journal=fixture()
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);candidate=base/"candidate";output=base/"packages";candidate.mkdir();output.mkdir();repo=base/"repo";(repo/"output").mkdir(parents=True)
            for item in reports:
                folder=repo/"output"/Path(item["path"].replace("\\","/")).parent.name;folder.mkdir()
                (folder/"package.json").write_text(json.dumps(item["document"]),encoding="utf8")
            registered=repo/"output/current/package.json";journal_path=base/"journal.json";journal_path.write_text(json.dumps(journal),encoding="utf8")
            view=candidate/"old";view.mkdir();(view/"materials").mkdir();(view/"materials"/"do_not_read.vpk").write_bytes(b"unread")
            for name,value in snapshots[0]["controls"].items():(view/name).write_text(json.dumps(value["document"]),encoding="utf8")
            build=output/"old";build.mkdir()
            for file in reports[1]["document"]["package_files"]:(build/file["name"]).write_bytes(b"x"*file["bytes"])
            nested=repo/"output/ignored/nested";nested.mkdir(parents=True);(nested/"package.json").write_text("{}",encoding="utf8")
            original=Path.open
            def guarded(path,*args,**kwargs):
                if path.suffix==".vpk":raise AssertionError("payload content was read")
                return original(path,*args,**kwargs)
            with patch.object(Path,"open",guarded),patch.object(Path,"rglob",side_effect=AssertionError("recursive traversal")):
                result=scan_inventory(repo,registered,journal_path,[],set(),root_map={"D:/Survival_发布候选":candidate,"D:/Survival_工坊输出":output})
            self.assertEqual(len(result["inventory"]),2)
            self.assertEqual(result["metrics"]["large_volume_files_hashed"],0)
            self.assertEqual(result["metrics"]["json_reads"],6)
            self.assertTrue(all(row["inventory_status"]=="BLOCKED" for row in result["inventory"]))


if __name__=="__main__":unittest.main()
