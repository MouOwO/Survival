import copy
import unittest

from release_retention import plan_retirement


def delivered():
    identity=dict(workshop_id="3824360109",release_sequence=2026110302,content_sha256="a"*64)
    return dict(status="WORKSHOP_SYNCED",workshop_synchronized=True,source_binding_state="DUAL_SOURCE_BOUND",
                target_source_revisions=dict(game="c"*40,content="d"*40),
                upload_evidence_matches_target=True,official_download_evidence_matches_target=True,blockers=[],
                pending_resource_changes=[],pending_source_changes=[],local_version=identity,
                uploaded_version=copy.deepcopy(identity),downloaded_version=copy.deepcopy(identity))


def artifact(name="20261023_old",kind="build",**fields):
    row=dict(path="D:/Survival_工坊输出/"+name,kind=kind,bytes=100,active=False,in_use=False,reparse_point=False,
             referenced_by=[],evidence_preserved=True,workshop_id="3824360109",release_sequence=2026102301,content_sha256="b"*64)
    row.update(fields);return row


class RetentionTests(unittest.TestCase):
    def test_verified_delivery_allows_only_old_explicit_unreferenced_artifacts(self):
        rows=[artifact(),artifact("older_view",kind="view"),artifact("unsigned",kind="unsigned"),artifact("temp",kind="temp")]
        before=copy.deepcopy(rows);state=delivered();before_state=copy.deepcopy(state)
        result=plan_retirement(rows,[],state)
        self.assertEqual(result["status"],"RETIREMENT_PLAN_READY")
        self.assertEqual(result["retire_bytes"],400)
        self.assertEqual(len(result["retire"]),4)
        self.assertEqual(result["filesystem_actions"],0)
        self.assertTrue(result["execution_revalidation_required"])
        self.assertEqual(rows,before);self.assertEqual(state,before_state)

    def test_local_git_push_signature_stage_and_upload_without_download_cannot_retire(self):
        for status in ("LOCAL_ONLY","UPLOADED_PENDING_DOWNLOAD_VERIFICATION","BUILT_SIGNED","STAGED","WORKSHOP_SYNCED"):
            with self.subTest(status=status):
                state=delivered();state["status"]=status;state["git_pushed"]=True
                if status=="WORKSHOP_SYNCED":state["official_download_evidence_matches_target"]=False
                result=plan_retirement([artifact()],[],state)
                self.assertEqual(result["retire"],[])
                self.assertIn("new_target_not_fully_workshop_synced",result["blockers"])

    def test_exact_verified_identity_and_empty_pending_required(self):
        changes=(lambda v:v["downloaded_version"].update(content_sha256="c"*64),
                 lambda v:v["uploaded_version"].update(release_sequence=2026110104),
                 lambda v:v.update(pending_source_changes=["game:x.lua"]),
                 lambda v:v.update(pending_resource_changes=[dict(path="x.lua",change="modified")]),
                 lambda v:v.update(source_binding_state="LEGACY_MIXED_BASELINE"),
                 lambda v:v.update(blockers=["missing_actual_download"]))
        for change in changes:
            with self.subTest(change=change):
                state=delivered();change(state)
                self.assertEqual(plan_retirement([artifact()],[],state)["retire"],[])

    def test_protected_path_itself_ancestor_and_descendant_are_blocked(self):
        row=artifact("old/sub")
        for path in (row["path"],"d:\\survival_工坊输出\\OLD",row["path"]+"/keep/receipt.json","D:/"):
            with self.subTest(path=path):
                result=plan_retirement([row],[path],delivered())
                self.assertEqual(result["retire"],[])
                self.assertIn("protected_path_ancestor_or_descendant",result["blocked"][0]["reasons"])

    def test_current_install_upload_baseline_pending_restore_and_unreferenced_future_are_kept(self):
        for flag in ("current_upload","current_install","parent_baseline","pending_restore","backend","user_backup","keys"):
            with self.subTest(flag=flag):
                result=plan_retirement([artifact(**{flag:True})],[],delivered())
                self.assertIn("protected_artifact_role",result["blocked"][0]["reasons"])
        target=artifact(**delivered()["local_version"])
        self.assertIn("current_release_identity",plan_retirement([target],[],delivered())["blocked"][0]["reasons"])
        self.assertEqual(plan_retirement([artifact(release_sequence=2099010101)],[],delivered())["retire"],[])

    def test_backup_lab_key_backend_or_unknown_kind_never_retire(self):
        for kind in ("backup","rehearsal","key","backend","user_backup","unknown",None):
            with self.subTest(kind=kind):
                self.assertEqual(plan_retirement([artifact(kind=kind)],[],delivered())["retire"],[])
        for name in ("keys/old","old/backend","user_backup","真实排演","玩家备份"):
            with self.subTest(name=name):
                self.assertEqual(plan_retirement([artifact(name)],[],delivered())["retire"],[])

    def test_only_explicit_external_roots_no_drive_root_addon_maps_traversal_or_unc(self):
        paths=("D:/","D:/Survival_工坊输出","D:/other/old","D:/SteamLibrary/game/dota_addons/survival/maps/x.vpk",
               "D:/Survival_工坊输出/../backup","D:/Survival_工坊输出/old/./x",r"\\server\share\old",
               r"\\?\D:\Survival_工坊输出\old","D:old","D:/Survival_工坊输出/old:stream","D:/Survival_工坊输出/NUL")
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(plan_retirement([artifact(path=path)],[],delivered())["retire"],[])
        self.assertEqual(len(plan_retirement([artifact(path="D:/Survival_发布候选/old")],[],delivered())["retire"]),1)

    def test_duplicate_and_nested_targets_block_both(self):
        for second in (artifact(path="d:\\survival_工坊输出\\OLD"),artifact("old/child")):
            result=plan_retirement([artifact("old"),second],[],delivered())
            self.assertEqual(result["retire"],[])
            self.assertEqual(len(result["blocked"]),2)

    def test_unknown_reference_occupancy_or_reparse_state_blocked(self):
        for field in ("active","in_use","reparse_point","referenced_by","evidence_preserved"):
            with self.subTest(field=field):
                row=artifact();row.pop(field)
                self.assertEqual(plan_retirement([row],[],delivered())["retire"],[])
        for field,value in (("active",True),("in_use",True),("reparse_point",True),("referenced_by",["current-builder"]),("roles",["parent_baseline"])):
            with self.subTest(field=field):
                self.assertEqual(plan_retirement([artifact(**{field:value})],[],delivered())["retire"],[])

    def test_evidence_inside_target_and_conflicting_or_foreign_package_identity_kept(self):
        row=artifact();row["evidence_paths"]=[row["path"]+"/receipt.json"]
        self.assertEqual(plan_retirement([row],[],delivered())["retire"],[])
        row=artifact();row["evidence_paths"]=["D:/Survival_知识库/old_receipt.json"]
        self.assertEqual(len(plan_retirement([row],[],delivered())["retire"]),1)
        self.assertEqual(plan_retirement([artifact(workshop_id="42")],[],delivered())["retire"],[])
        row=artifact(package=dict(workshop_id="42",release_sequence=2026102301,content_sha256="b"*64))
        self.assertIn("conflicting_package_identity",plan_retirement([row],[],delivered())["blocked"][0]["reasons"])

    def test_unknown_inventory_or_protection_input_blocks_conservatively(self):
        for inventory in (None,{},[None],[artifact(kind=[])]):
            with self.subTest(inventory=inventory):
                self.assertEqual(plan_retirement(inventory,[],delivered())["retire"],[])
        self.assertEqual(plan_retirement([artifact()],["not-an-absolute-protection"],delivered())["retire"],[])

    def test_incomplete_target_source_binding_is_not_verified_delivery(self):
        state=delivered();state.pop("target_source_revisions")
        self.assertEqual(plan_retirement([artifact()],[],state)["retire"],[])


if __name__=="__main__":unittest.main()
