"""Synthetic release-tool tests. These never admit a real client or spend tickets."""
import base64
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import contextlib
import os
import sys
from contextlib import ExitStack
from datetime import datetime,timedelta,timezone

HERE=Path(__file__).resolve().parent
def load(name, relative):
    spec=importlib.util.spec_from_file_location(name,HERE/"complete_delivery_release_20261103"/relative)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
n=load("complete_native_policy_tests","native_admission.py")
r=load("complete_ordinary_ops_tests","rehearsal.py")
d=load("complete_official_download_tests","verify_download.py")

def package_rows(blobs):
    return [dict(name=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()) for name,raw in blobs.items()]

class NativeProtocolTests(unittest.TestCase):
    def log(self,size=49,data=None,event="cw"):
        if data is None:data=base64.urlsafe_b64encode(b"\x10"+b"\x01"*17).decode().rstrip("=")
        return ('message (%d bits/%d bytes):\nCUserMsg_CustomGameEvent [148]\nevent_name: "%s"\n'
            'data: \\000\\000\\001d\\000%s\\000\\013\\013\n')%(size*8,size,event,data)
    def test_native_layer_budget_accepts_measured_49_bytes(self):
        value=n.network_summary(self.log());self.assertEqual(value["max_native_bytes"],49)
        self.assertFalse(value["native_fps_measured"])
    def test_over_frequent_budget_rejected(self):
        with self.assertRaisesRegex(ValueError,"exceeds_50"):n.network_summary(self.log(51))
    def test_body_budget_cannot_be_hidden_by_small_native_size_label(self):
        with self.assertRaises(ValueError):n.network_summary(self.log(data="A"*25))
    def test_missing_or_extra_native_key_is_not_accepted_as_d(self):
        with self.assertRaises(ValueError):n.network_summary(self.log(data="bad key"))
        with self.assertRaises(ValueError):n.network_summary(self.log().rsplit("data:",1)[0])
    def test_unknown_cold_bulk_has_separate_policy(self):
        value=n.network_summary(self.log()+self.log(923,event="gb"))
        self.assertEqual(value["frames"],1)
    def test_no_frames_cannot_claim_native_success(self):
        with self.assertRaises(ValueError):n.network_summary("a ready marker")
    def test_every_collector_and_package_source_binding_is_required(self):
        report=dict(source_revisions={"game":"a"*40,"content":"b"*40},
            collection_source_revisions={"game":"a"*40,"content":"b"*40,"operator":"c"*40},
            operator_revision="d"*40,content_sha256="e"*64,signed_manifest_sha256="f"*64)
        value=dict(report,package_report_sha256="1"*64)
        self.assertTrue(n.exact_bindings(value,report,"1"*64))
        for key in value:
            bad=deepcopy(value);bad[key]="wrong"
            self.assertFalse(n.exact_bindings(bad,report,"1"*64),key)
    def test_pure_worksheet_is_not_preapproved_native_evidence(self):
        report=dict(release_sequence=2026110302,source_revisions={"game":"a"*40,"content":"b"*40},
            collection_source_revisions={"game":"a"*40,"content":"b"*40,"operator":"c"*40},
            operator_revision="d"*40,content_sha256="e"*64,signed_manifest_sha256="f"*64,
            changed_runtime_paths=["scripts/a.lua"],removed_runtime_paths=["scripts/old.lua"])
        value=n.review_template(report,"1"*64)
        self.assertEqual(value["status"],"TEMPLATE_NOT_NATIVE_EVIDENCE")
        self.assertIsNone(value["synthetic"])
        self.assertFalse(any(value["root_review"].values()))
        self.assertEqual(len(value["consecutive_draws"]),3)
        self.assertTrue(all(item["request_id"] is None for item in value["consecutive_draws"]))

class LotteryAdmissionCaseTests(unittest.TestCase):
    """Synthetic pixels/SDK are explicitly mocked; only policy branches tested."""
    def fixture(self,draw_fallback=True,preview_fallback=True,movies=True):
        tick=datetime(2026,11,4,tzinfo=timezone.utc);serial=0
        def shots(case,roles,*args):
            nonlocal serial
            result=[]
            for role in roles:
                serial+=1
                result.append(dict(start=tick+timedelta(seconds=serial*2),
                    end=tick+timedelta(seconds=serial*2+1),sha256=hashlib.sha256(str(serial).encode()).hexdigest(),
                    hwnd=7,width=1280,height=720))
            return result
        previews={};lines=[]
        for pool in n.POOLS:
            fallback=(not movies) or (preview_fallback and pool=="cultivation")
            visual=dict.fromkeys(("theme_matches_pool","animation_progressed","returned_to_lottery_window",
                "no_movie_error_visible_after_fallback","no_draw_inputs","actual_movie_content"),True)
            previews[pool]=dict(pool=pool,mode="NO_CONSUMPTION_PREVIEW",presentation="fallback" if fallback else "movie",
                fallback_reason="native_error" if fallback else None,visual_review=visual,tickets_before=100,tickets_after=100)
            lines.append("[LOTTERY_CINEMATIC] stage=preview pool="+pool)
            if fallback:lines.append("[LOTTERY_CINEMATIC] stage=fallback pool="+pool+" reason=native_error preview=true")
            lines.append("[LOTTERY_CINEMATIC] stage=complete pool="+pool+" preview=true")
        draws=[]
        for index in range(3):
            fallback=(not movies) or draw_fallback
            visual=dict.fromkeys(("actual_movie_content","fallback_animation_content","animation_progressed",
                "ten_actual_rewards_visible","confirm_button_full_width","owned_text_visible_when_applicable",
                "returned_to_lottery_window"),True)
            request="lottery_123456789_"+str(index+1)
            draws.append(dict(pool="map",count=10,ticket_kind="ordinary",real_player_transaction=True,
                skip_animation=False,request_id=request,tickets_before=100-index*10,tickets_after=90-index*10,
                presentation="fallback" if fallback else "movie",fallback_reason="native_error" if fallback else None,
                visual_review=visual))
            lines.extend(["[SURVIVAL_LOTTERY_UI] stage=result_received request="+request,
                "[SURVIVAL_LOTTERY_UI] result_count=10 server_count=10 guarantee=sr satisfied=true",
                "[SURVIVAL_LOTTERY_UI] stage=cards_ready count=10",
                "[SURVIVAL_LOTTERY_UI] stage=reveal_ready animated=true"])
            if fallback:lines.append("[LOTTERY_CINEMATIC] native playback failed; using themed presentation")
        return dict(lottery_previews=previews,consecutive_draws=draws),"\n".join(lines),shots,
    def run_case(self,review,text,shots):
        start=datetime(2026,11,4,tzinfo=timezone.utc)
        with patch.object(n,"captures",side_effect=shots):
            return n.lottery_cases(review,{},[start,start+timedelta(hours=1)],text,None,None)
    def test_three_real_fallback_draws_allowed_when_real_video_also_observed(self):
        review,text,shots=self.fixture()
        value=self.run_case(review,text,shots)
        self.assertEqual(value["same_pool_consecutive_real_ten_draws"],3)
        self.assertEqual(value["ordinary_tickets_consumed"],30)
        self.assertGreater(value["actual_movie_presentations"],0)
    def test_only_fallback_never_claims_real_video(self):
        review,text,shots=self.fixture(movies=False)
        with self.assertRaisesRegex(ValueError,"both_actual_movie"):self.run_case(review,text,shots)
    def test_only_movies_does_not_invent_decoder_failure_coverage(self):
        review,text,shots=self.fixture(draw_fallback=False,preview_fallback=False)
        with self.assertRaisesRegex(ValueError,"both_actual_movie"):self.run_case(review,text,shots)
    def test_mock_or_class_only_error_is_not_decoder_evidence(self):
        review,text,shots=self.fixture()
        text=text.replace("native playback failed; using themed presentation","MovieError class added manually")
        with self.assertRaisesRegex(ValueError,"real_decoder_evidence"):self.run_case(review,text,shots)
    def test_unreviewed_fourth_ack_is_rejected_even_when_three_cases_look_good(self):
        review,text,shots=self.fixture()
        text+="\n[SURVIVAL_LOTTERY_UI] stage=result_received request=unauthorized_fourth"
        with self.assertRaisesRegex(ValueError,"unexpected_additional_draw"):self.run_case(review,text,shots)
    def test_ten_reward_pictures_cannot_replace_a_successful_ten_ack(self):
        review,text,shots=self.fixture()
        text=text.replace("result_count=10 server_count=10","result_count=10 server_count=1",1)
        with self.assertRaisesRegex(ValueError,"ten_reward_native_ack"):self.run_case(review,text,shots)

class PackageSetTests(unittest.TestCase):
    def test_volume_count_is_from_complete_rows(self):
        blobs={"3824360109.vpk":b"index"}
        blobs.update({"3824360109_%03d.vpk"%i:b"data"+bytes([i]) for i in range(6)})
        self.assertEqual(r.names(package_rows(blobs)),list(blobs))
    def test_gaps_duplicate_and_path_traversal_are_rejected(self):
        rows=package_rows({"3824360109.vpk":b"index","3824360109_000.vpk":b"data"})
        for name in ("3824360109_001.vpk","3824360109.vpk","../3824360109_000.vpk"):
            bad=deepcopy(rows);bad[1]["name"]=name
            with self.assertRaises(ValueError):r.names(bad)
    def test_boolean_size_is_not_a_byte_count(self):
        rows=package_rows({"3824360109.vpk":b"index","3824360109_000.vpk":b"data"})
        rows[1]["bytes"]=True
        with self.assertRaises(ValueError):r.names(rows)

class DirectorySwitchTests(unittest.TestCase):
    """Real files verify deletion propagation and retained originals, no VPK SDK."""
    def fixture(self,base):
        installed,ready,retained=[base/name for name in ("installed","ready","retained")]
        old={"3824360109.vpk":b"oldindex","3824360109_000.vpk":b"olddata",
             "3824360109_001.vpk":b"oldtrailing"}
        new={"3824360109.vpk":b"newindex","3824360109_000.vpk":b"newdata"}
        for folder,blobs in ((installed,old),(ready,new)):
            folder.mkdir()
            for name,raw in blobs.items():(folder/name).write_bytes(raw)
        calls=[]
        def row(path):
            path=Path(path);raw=path.read_bytes()
            return dict(name=path.name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
        p=SimpleNamespace(regular=lambda value,**kw:Path(value).absolute(),row=row,
            no_clients=lambda:calls.append("strict_no_clients"))
        return installed,ready,retained,package_rows(old),package_rows(new),p,calls
    def test_complete_switch_removes_trailing_old_volume_and_preserves_all_old_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            installed,ready,retained,old,new,p,calls=self.fixture(Path(temp))
            with patch.object(r,"environment",return_value=(None,p,None)):
                r.switch_directory(installed,ready,retained,old,new)
                r.require_rows(installed,new);r.require_rows(retained,old)
            self.assertFalse(ready.exists())
            self.assertFalse((installed/"3824360109_001.vpk").exists())
            self.assertEqual(len(calls),2)
    def test_second_rename_failure_keeps_both_full_images_for_explicit_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            installed,ready,retained,old,new,p,calls=self.fixture(Path(temp))
            original=os.rename;count=0
            def rename(source,target):
                nonlocal count
                count+=1
                if count==2:raise OSError("simulated sharing violation")
                original(source,target)
            with patch.object(r,"environment",return_value=(None,p,None)),patch.object(r.os,"rename",side_effect=rename):
                with self.assertRaises(OSError):r.switch_directory(installed,ready,retained,old,new)
                r.require_rows(ready,new);r.require_rows(retained,old)
            self.assertFalse(installed.exists())
    def test_client_query_failure_prevents_the_first_move(self):
        with tempfile.TemporaryDirectory() as temp:
            installed,ready,retained,old,new,p,calls=self.fixture(Path(temp))
            p.no_clients=lambda:(_ for _ in ()).throw(PermissionError("CIM denied"))
            with patch.object(r,"environment",return_value=(None,p,None)):
                with self.assertRaises(PermissionError):r.switch_directory(installed,ready,retained,old,new)
                r.require_rows(installed,old);r.require_rows(ready,new)
            self.assertFalse(retained.exists())

class DownloadIdentityTests(unittest.TestCase):
    def fixture(self):
        report=dict(release_sequence=2026110302,content_sha256="a"*64,vpk_sha256="b"*64,
            package_files=package_rows({"3824360109.vpk":b"index","3824360109_000.vpk":b"data"}))
        state=dict(uploaded=True,status="SUBMITTED_UNLISTED_PENDING_DOWNLOAD_AND_NATIVE_TEST",
            owner=123,app_id=570,workshop_id="3824360109",visibility_requested=3,
            release_sequence=report["release_sequence"],content_sha256=report["content_sha256"],
            vpk_sha256=report["vpk_sha256"],vpk_bytes=report["package_files"][0]["bytes"],
            package_files=deepcopy(report["package_files"]),legal_agreement_required=False)
        return report,state
    def test_current_successful_upload_matches_every_actual_volume(self):
        report,state=self.fixture()
        with patch.object(d,"protocol",return_value=SimpleNamespace(api=SimpleNamespace(OWNER=123,APP=570))),\
             patch.object(d,"recipe",return_value=SimpleNamespace(ITEM="3824360109")):
            self.assertTrue(d.current_upload(state,report))
            state["package_files"][1]["sha256"]="c"*64
            self.assertFalse(d.current_upload(state,report))
    def test_old_success_hidden_in_history_is_not_current_success(self):
        report,state=self.fixture();old=deepcopy(state)
        state.update(uploaded=False,previous_release=old,release_history=[old])
        with patch.object(d,"protocol",return_value=SimpleNamespace(api=SimpleNamespace(OWNER=123,APP=570))),\
             patch.object(d,"recipe",return_value=SimpleNamespace(ITEM="3824360109")):
            self.assertFalse(d.current_upload(state,report))
    def test_actual_frozen_callback_protocol_loads_with_only_exact_counter_adaptation(self):
        # Importing ctypes/ABI declarations is not Steam initialization.
        p=d.protocol()
        self.assertEqual(p.C.sizeof(p.callbacks.DownloadResult),24)
        self.assertIs(p.RefreshSteam.__mro__[1],p.previous.SHOP02Steam)
        self.assertTrue(callable(p.RefreshSteam.download_installed))

    def dynamic_download(self,base,missing=False):
        """Execute the real frozen verifier with fake SDK/crypto, never Steam.

        Five data volumes deliberately exceed the historical fixed four. Real
        folder membership is checked by the frozen function before the mocked
        CRC verifier. This verifies only adapter control flow, no native proof.
        """
        base=base.resolve()
        p=d.protocol();installed=base/"installed";installed.mkdir()
        blobs={"3824360109.vpk":b"index"}
        blobs.update({"3824360109_%03d.vpk"%i:b"volume"+bytes([i]) for i in range(5)})
        for name,raw in blobs.items():(installed/name).write_bytes(raw)
        rows=package_rows(blobs);index=installed/rows[0]["name"]
        if missing:(installed/rows[-1]["name"]).unlink()
        acf=base/"test.acf";acf.write_bytes(b"test-only-acf")
        report=dict(package_files=rows,vpk_sha256=rows[0]["sha256"],release_sequence=2026110302)
        checks=dict.fromkeys(p.callbacks.CHECKS,True)
        verified=dict(signature_valid=True,vpk_sha256=rows[0]["sha256"],package_files=rows,
            verification=dict(files=7031,archive_count=5,**checks),vpk=str(index))
        query=dict(time_updated=1234,total_files_bytes=sum(v["bytes"] for v in rows))
        saved=[]
        class SteamFake:
            def __init__(self,*args):pass
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def fresh_item(self):return dict(query)
            def refresh_subscription_once(self):return {"callback":1313,"result":1}
            def download_installed(self):return {"install_folder":str(installed),"callback":3406}
        inputs=dict(report=report,state={},total=query["total_files_bytes"],expected_manifest=None,
            snapshots={},report_sha256="a"*64,state_sha256="b"*64,protected_modules=186)
        with ExitStack() as stack:
            stack.enter_context(patch.dict(sys.modules,{"test_entry":SimpleNamespace(
                process_inventory=lambda:dict(steam_running=True,dota_pids=[]))}))
            stack.enter_context(patch.multiple(p,RefreshSteam=SteamFake,INSTALLED=installed,ACF=acf,
                ITEM="3824360109",SEQUENCE=2026110302,CONTENT="c"*64,FILE_COUNT=7031,
                EXPECTED_NAMES=list(blobs),CANDIDATE=base/"candidate"))
            stack.enter_context(patch.object(p.verify,"verify_installed",return_value=verified))
            def paths(target):
                wanted=[installed/name for name in blobs]
                self.assertEqual(set(installed.iterdir()),set(wanted))
                return wanted
            def actual_rows(target):
                self.assertEqual(rows,report["package_files"])
                return rows
            stack.enter_context(patch.object(p.api.pack,"package_paths",side_effect=paths))
            stack.enter_context(patch.object(p.api.pack,"package_inventory",side_effect=actual_rows))
            stack.enter_context(patch.object(p,"acf_manifest",return_value=("123456789",{})))
            stack.enter_context(patch.object(p,"save_evidence",side_effect=lambda value:saved.append(value) or base/"verification.json"))
            value=p.download_once(inputs)
        return value,saved

    def test_real_download_function_checks_dynamic_five_data_volumes_and_186_modules(self):
        with tempfile.TemporaryDirectory() as temp:
            value,saved=self.dynamic_download(Path(temp))
            self.assertEqual(value["archive_count"],5)
            self.assertEqual(value["protected_modules_verified"],186)
            self.assertEqual(saved[0]["signed_resources_verified"],7031)
            self.assertEqual(saved[0]["protected_modules_verified"],186)

    def test_real_download_function_rejects_missing_trailing_volume(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(Exception):self.dynamic_download(Path(temp),missing=True)

class StaticPlanTests(unittest.TestCase):
    def test_both_owned_launch_routes_collect_actual_native_event_sizes_without_cheats(self):
        log=Path("D:/Survival_本地排演/test-only-engine.log")
        for route in r.LAUNCH_ROUTES:
            with self.subTest(route=route):
                arguments=r.arguments(log,route)
                self.assertEqual(arguments[arguments.index("+sv_cheats")+1],"0")
                self.assertEqual(arguments[arguments.index("+net_showmsg")+1],"CUserMsg_CustomGameEvent")
                self.assertEqual(arguments[arguments.index("+net_restrict_showmsg_socket")+1],"client")
                self.assertEqual(arguments[arguments.index("-con_logfile")+1],str(log))
                self.assertEqual("+dota_launch_custom_game" in arguments,route=="direct")
    def test_all_three_default_plans_do_not_load_packages_or_native_helpers(self):
        for module,blocked in ((n,"environment"),(r,"environment"),(d,"recipe")):
            with self.subTest(module=module.__name__),patch.object(module,blocked,side_effect=AssertionError("action")):
                out=io.StringIO()
                with contextlib.redirect_stdout(out):self.assertEqual(module.main([]),0)
                self.assertEqual(json.loads(out.getvalue())["sdk_initialized"],False)

if __name__=="__main__":unittest.main()
