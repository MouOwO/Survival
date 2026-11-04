"""Read-only complete signed-package ordinary-client evidence admission.

No SDK, input or process query runs on import. Explicit validation independently
authenticates the full package, hashes each bounded private evidence file once
and rehashes it at the end: O(evidence bytes + captures + volumes). Screenshots
must come from the same foreground ordinary native window. Old run07/08,
synthetic MovieError classes, logs alone and source tests cannot admit a package.
"""
from __future__ import annotations
import argparse
import base64
from datetime import datetime
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
from types import ModuleType, SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
KIND = "COMPLETE_RUNTIME_NATIVE_REVIEW"
SCOPE = "COMPLETE_RUNTIME_UI_NETWORK_AND_CONSECUTIVE_LOTTERY"
POLICY = "DATA_VOLUMES_USED_INDEX_AUTHENTICATED_NOT_OPEN"
POOLS = ("map","cultivation","dragon_knight","summer")
HELPERS = ROOT/"tools/lottery_hotfix_release_20261102/native_admission.py"
HELPERS_SHA = "935f0958a188dce736baa08282b3b4cd2cd30794767ddb9e8060527600c7a8ab"
_HELPERS = None
_EXECUTED_HELPERS = {}

def need(ok, why):
    if not ok: raise ValueError(why)

def sha(raw): return hashlib.sha256(raw).hexdigest()

def timestamp(value):
    need(isinstance(value,str),"complete_native_timezone_timestamp_required")
    result=datetime.fromisoformat(value.replace("Z","+00:00"))
    need(result.tzinfo is not None,"complete_native_timezone_required")
    return result

def helpers():
    global _HELPERS
    if _HELPERS is None:
        raw=HELPERS.read_bytes()
        need(len(raw)<=128*1024 and sha(raw)==HELPERS_SHA,"complete_frozen_native_pixel_helpers_changed")
        value=ModuleType("complete_private_native_pixel_helpers");value.__file__=str(HELPERS)
        exec(compile(raw,str(HELPERS),"exec"),value.__dict__)
        _EXECUTED_HELPERS[HELPERS.relative_to(ROOT).as_posix()]=sha(raw.replace(b"\r\n",b"\n"))
        _HELPERS=value
    return _HELPERS

def environment():
    from complete_delivery_release_20261103 import pipeline_recipe,rehearsal
    b,p,_=rehearsal.environment()
    return pipeline_recipe,rehearsal,p

def same_process(left,right):
    return helpers().same_process(left,right)

def screenshot(ref,process,reader,origin):
    return helpers().screenshot(ref,process,reader,origin)

def exact_bindings(document, report, expected_sha):
    return (document.get("package_report_sha256")==expected_sha
        and document.get("source_revisions")==report["source_revisions"]
        and document.get("collection_source_revisions")==report["collection_source_revisions"]
        and document.get("operator_revision")==report["operator_revision"]
        and document.get("content_sha256")==report["content_sha256"]
        and document.get("signed_manifest_sha256")==report["signed_manifest_sha256"])

def lifecycle(review,origin,report,expected_sha,reader,b,ops,p):
    refs=review["rehearsal"]
    tx,tx_path=reader.document(refs["transaction"],origin);folder=tx_path.parent
    process,process_path=reader.document(refs["process"],origin)
    need(tx_path.name=="transaction.json" and folder.parent==ops.STORE
        and process_path==folder/"process.json" and tx.get("schema")==1 and tx.get("kind")==ops.KIND
        and tx.get("transaction_id")==folder.name and tx.get("installed")==str(p.INSTALLED)
        and tx.get("candidate_files")==report["package_files"] and tx.get("code_pins")==ops.own_code_pins()
        and exact_bindings(tx,report,expected_sha),"complete_native_transaction_differs")
    need(exact_bindings(process,report,expected_sha) and process.get("kind")==ops.KIND
        and process.get("code_pins")==tx["code_pins"] and process.get("tools") is False
        and process.get("offline_logic_requested") is False and process.get("cheats_requested") is False
        and process.get("owned_launch") is True and process.get("launch_route") in ops.LAUNCH_ROUTES
        and process.get("argv")==ops.arguments(Path(process["log_file"]),process["launch_route"])
        and process.get("log_origin")=="DIRECT_NATIVE_CON_LOGFILE_MOUNTED_OUTPUT"
        and process.get("log_file")==str(ops.expected_log_path(folder))
        and process.get("port")==ops.PORT and process.get("workshop_id")==b.ITEM,
        "complete_native_owned_ordinary_process_required")
    need(Path(process["executable"]).resolve()==p.EXE.resolve()
        and process.get("command_line_sha256")==sha(subprocess.list2cmdline([str(p.EXE),*process["argv"]]).encode())
        and type(process.get("native_created_filetime")) is int
        and process["native_created_filetime"]//10==p.utc_ticks(process["created_utc"])//10
        and same_process(review["process"],process),"complete_native_actual_executable_generation_differs")
    names=ops.names(report["package_files"]);held=process.get("held_files",[])
    need(len(held)==len(names) and [v["name"] for v in held]==names
        and [v["path"] for v in held]==[str(p.INSTALLED/name) for name in names]
        and [v["bytes"] for v in held]==[v["bytes"] for v in report["package_files"]]
        and len({(v["volume_serial"],v["file_index"]) for v in held})==len(names)
        and process.get("file_hold_mode")=="GENERIC_READ_FILE_SHARE_READ_ONLY"
        and not (folder/"hold_failed.json").exists(),"complete_native_continuous_exact_file_holds_required")
    refs_inspect=refs["inspections"];need(len(refs_inspect)==2,"complete_native_two_bracketing_inspections_required")
    times=[]
    for ref in refs_inspect:
        value,path=reader.document(ref,origin);rows=value.get("file_use",[])
        need(path.parent==folder/"inspections" and exact_bindings(value,report,expected_sha)
            and same_process(value["process"],process) and value.get("keeper")==process["keeper"]
            and value.get("held_files")==held and value.get("candidate_files")==report["package_files"]
            and [v.get("name") for v in rows]==names
            and all(v.get("owned_keeper_uses_file") is True for v in rows)
            and all(v.get("owned_dota_uses_file") is True for v in rows[1:])
            and type(rows[0].get("owned_dota_uses_file")) is bool
            and value.get("index_owned_dota_use_observed") is rows[0]["owned_dota_uses_file"]
            and value.get("external_signed_manifest_binding") is True
            and value.get("external_signed_resources_verified")==report["files"]
            and value.get("external_protected_modules_verified")==report["protected_modules_verified"],
            "complete_native_same_process_data_volume_use_required")
        times.append(timestamp(value["observed_utc"]))
    documents={}
    for name in ("close_intent","close_requested","hold_end","restored"):
        document,path=reader.document(refs[name],origin)
        need(path==folder/(name+".json") and exact_bindings(document,report,expected_sha),
            "complete_native_exact_lifecycle_receipt_required")
        documents[name]=document
    intent,close,end,restored=[documents[k] for k in ("close_intent","close_requested","hold_end","restored")]
    need(intent.get("status")=="ONE_OWNED_WM_CLOSE_INTENT" and same_process(intent,process)
        and close.get("status")=="WM_CLOSE_REQUESTED_NOT_EXIT_VERIFIED" and same_process(close,process)
        and close.get("queued") is True and close.get("force_stop") is False
        and intent.get("console_connections")==close.get("console_connections")==0,
        "complete_native_one_normal_owned_close_required")
    life=end.get("process_lifetime",{})
    need(end.get("status")=="OWNED_DOTA_EXITED_HOLDS_COMPLETED" and same_process(end,process)
        and end.get("held_files")==held and end.get("end_no_dota_check_deferred_to_restore") is True
        and life.get("exit_observed") is True and life.get("executable_verified_while_alive") is True
        and life.get("exit_identity_method")=="SAME_RETAINED_HANDLE_GETPROCESSTIMES"
        and life.get("created_filetime")==process["native_created_filetime"]
        and type(life.get("exit_filetime")) is int and life["exit_filetime"]>life["created_filetime"],
        "complete_native_same_retained_handle_exit_required")
    parent,parent_manifest=b.baseline(full=True,require_current_journal=False)
    need(restored.get("status")=="ORIGINAL0104_COMPLETE_SET_FULLY_RESTORED"
        and restored.get("original_files")==tx.get("original_files")==parent["package_files"]
        and restored.get("original_content_sha256")==parent["content_sha256"]
        and restored.get("acf_written") is False and restored.get("canonical_journal_written") is False
        and restored.get("backups_preserved") is True and restored.get("candidate_preserved") is True,
        "complete_native_original_exact_restore_required")
    need(timestamp(process["created_utc"])<=times[0]<times[1]
        <=timestamp(close["observed_utc"])<=timestamp(end["ended_utc"])<=timestamp(restored["observed_utc"])
        <=timestamp(review["reviewed_utc"]),"complete_native_lifecycle_chronology_invalid")
    log=reader.file(refs["engine_log_final"],origin)
    need(log==ops.expected_log_path(folder),"complete_native_actual_launch_log_required")
    raw=log.read_bytes();need(len(raw)<=64*1024*1024,"complete_native_log_budget")
    text=raw.decode("utf-8","replace")
    need("[WS4-NATIVE-HANDOFF-01]" in text and "[Survival][INFO][Addon] initialized" in text,
        "complete_native_actual_handoff_and_addon_start_required")
    need(re.search(r"Script Runtime Error|VScript Error|SCRIPT ERROR|ScriptException|stack traceback:|"
        r"NETWORK_DISCONNECT_SNAPSHOTERROR|Failed\s+to\s+serialize\s+(?:CUserMsg_)?CustomGameEvent|"
        r"SendData[^\r\n]*reliable\s+data\s+too\s+big|VPK directory corrupt",text,re.I) is None,
        "complete_native_script_network_package_fatal")
    ops.require_rows(p.INSTALLED,parent["package_files"]);ops.full_vpk(p.INSTALLED,parent_manifest)
    ops.require_rows(folder/"backup",parent["package_files"])
    ops.require_rows(folder/"retained_candidate",report["package_files"])
    return process,times,text

def captures(case,roles,process,bounds,reader,origin):
    refs=case.get("captures",{})
    need(set(refs)==set(roles),"complete_native_exact_capture_roles_required")
    shots=[screenshot(refs[role],process,reader,origin) for role in roles]
    need(all(a["end"]<z["start"] for a,z in zip(shots,shots[1:]))
        and bounds[0]<=shots[0]["start"]<=shots[-1]["end"]<=bounds[1],
        "complete_native_capture_chronology_invalid")
    need(case.get("visual_review",{}).get("reviewed_png_sha256")==[shot["sha256"] for shot in shots],
        "complete_native_root_pixel_review_requires_exact_sha")
    return shots

def ui_cases(review,process,bounds,reader,origin):
    required=("n1_gameplay","archive","hud_selection","grid","production","vip","payment","public_beta")
    cases=review.get("ui_cases",{});need(set(cases)==set(required),"complete_native_runtime_ui_cases_required")
    windows=set();count=0
    for name in required:
        case=cases[name];shots=captures(case,("visible",),process,bounds,reader,origin)
        visual=case.get("visual_review",{})
        need(visual.get("actual_data_visible") is True and visual.get("normal_ui_open") is True
            and visual.get("not_loading_or_placeholder") is True and visual.get("no_stall") is True,
            "complete_native_actual_runtime_ui_pixels_required:"+name)
        windows.update((s["hwnd"],s["width"],s["height"]) for s in shots);count+=len(shots)
    need(len(windows)==1,"complete_native_ui_cases_must_share_window")
    return dict(cases=list(required),captures=count,ordinary_native_pixels_reviewed=True,
        all_gameplay_paths_verified=False,no_purchase_or_claim_required=True)

def lottery_cases(review,process,bounds,text,reader,origin):
    previews=review.get("lottery_previews",{})
    need(set(previews)==set(POOLS),"complete_native_four_pool_previews_required")
    actual_movie=0;native_fallback=0;windows=set()
    for pool in POOLS:
        case=previews[pool];need(case.get("pool")==pool and case.get("mode")=="NO_CONSUMPTION_PREVIEW",
            "complete_native_pool_preview_required")
        shots=captures(case,("window_before","animation_a","animation_b","window_after"),process,bounds,reader,origin)
        visual=case.get("visual_review",{})
        need(shots[1]["sha256"]!=shots[2]["sha256"]
            and all(visual.get(key) is True for key in ("theme_matches_pool","animation_progressed",
                "returned_to_lottery_window","no_movie_error_visible_after_fallback","no_draw_inputs")),
            "complete_native_real_moving_pool_pixels_required")
        start="[LOTTERY_CINEMATIC] stage=preview pool="+pool
        left=text.find(start);right=text.find("[LOTTERY_CINEMATIC] stage=complete pool="+pool+" preview=true",left+len(start))
        need(left>=0 and right>left,"complete_native_preview_lifecycle_missing")
        if case.get("presentation")=="movie":
            need(visual.get("actual_movie_content") is True,"complete_native_movie_is_distinct_from_fallback")
            actual_movie+=1
        else:
            reason=case.get("fallback_reason")
            need(case.get("presentation")=="fallback" and reason in ("native_error","sync_error")
                and "[LOTTERY_CINEMATIC] stage=fallback pool="+pool+" reason="+reason in text[left:right],
                "complete_native_real_decoder_failure_fallback_required")
            native_fallback+=1
        need(type(case.get("tickets_before")) is int and case["tickets_before"]==case.get("tickets_after"),
            "complete_native_preview_ticket_balance_changed")
        windows.update((s["hwnd"],s["width"],s["height"]) for s in shots)
    preview_movies,preview_fallbacks=actual_movie,native_fallback
    draws=review.get("consecutive_draws",[])
    need(len(draws)==3,"complete_native_three_authorized_consecutive_ten_draws_required")
    previous=None;previous_end=None;requests=set();total=0
    for case in draws:
        need(case.get("pool")=="map" and case.get("count")==10 and case.get("ticket_kind")=="ordinary"
            and case.get("real_player_transaction") is True and case.get("skip_animation") is False,
            "complete_native_actual_ordinary_map_ten_draw_required")
        request=case.get("request_id")
        need(isinstance(request,str) and 1<=len(request)<=128 and request not in requests
            and re.fullmatch("[A-Za-z0-9_:-]+",request),"complete_native_distinct_actual_draw_request_required")
        requests.add(request)
        before,after=case.get("tickets_before"),case.get("tickets_after")
        need(type(before) is int and type(after) is int and before>=10 and after>=0 and before-after==10
            and (previous is None or before==previous),"complete_native_exact_authorized_ticket_debit_required")
        total+=before-after;previous=after
        shots=captures(case,("window_before","animation_a","animation_b","results","window_after"),process,bounds,reader,origin)
        need(previous_end is None or previous_end < shots[0]["start"], "complete_native_draws_must_be_observed_consecutively")
        previous_end = shots[-1]["end"]
        visual=case.get("visual_review",{})
        need(shots[1]["sha256"]!=shots[2]["sha256"] and all(visual.get(key) is True for key in
            ("animation_progressed","ten_actual_rewards_visible",
             "confirm_button_full_width","owned_text_visible_when_applicable","returned_to_lottery_window")),
            "complete_native_each_draw_requires_actual_movie_rewards_and_return")
        marker="[SURVIVAL_LOTTERY_UI] stage=result_received request="+request
        need(text.count(marker)==1,"complete_native_exact_actual_draw_ack_missing_or_duplicated")
        left=text.index(marker);next_ack=text.find("[SURVIVAL_LOTTERY_UI] stage=result_received request=",left+len(marker))
        segment=text[left:next_ack if next_ack>=0 else len(text)]
        need(re.search(r"\[SURVIVAL_LOTTERY_UI\] result_count=10 server_count=10\b",segment)
            and "[SURVIVAL_LOTTERY_UI] stage=cards_ready count=10" in segment
            and "[SURVIVAL_LOTTERY_UI] stage=reveal_ready animated=true" in segment,
            "complete_native_successful_ten_reward_native_ack_required")
        if case.get("presentation")=="movie":
            need(visual.get("actual_movie_content") is True,
                "complete_native_draw_movie_must_be_distinct_from_fallback")
            actual_movie+=1
        else:
            reason=case.get("fallback_reason")
            marker=("[LOTTERY_CINEMATIC] native playback failed; using themed presentation" if reason=="native_error"
                else "[LOTTERY_CINEMATIC] playback unavailable; using themed presentation")
            need(case.get("presentation")=="fallback" and reason in ("native_error","sync_error")
                and visual.get("fallback_animation_content") is True and marker in segment,
                "complete_native_draw_fallback_requires_real_decoder_evidence")
            native_fallback+=1
        windows.update((s["hwnd"],s["width"],s["height"]) for s in shots)
    need(total==30 and len(windows)==1,"complete_native_authorized_30_ticket_single_window_required")
    observed_requests=re.findall(r"\[SURVIVAL_LOTTERY_UI\] stage=result_received request=([A-Za-z0-9_:-]+)",text)
    need(len(observed_requests)==3 and set(observed_requests)==requests,
        "complete_native_unexpected_additional_draw_ack_exceeds_review_scope")
    need(actual_movie>0 and native_fallback>0,
        "complete_native_both_actual_movie_and_decoder_fallback_must_be_observed")
    return dict(pools=list(POOLS),actual_movie_previews=preview_movies,decoder_fallback_previews=preview_fallbacks,
        actual_movie_presentations=actual_movie,actual_decoder_fallbacks=native_fallback,
        same_pool_consecutive_real_ten_draws=3,ordinary_tickets_consumed=total,
        real_player_transaction_performed=True,synthetic_results=False)

def network_summary(text):
    header=None;event=None;count=0;maximum=0;total=0;payloads=0
    for line in text.splitlines():
        found=re.search(r"\((\d+) bits/(\d+) bytes\):",line)
        if found:
            header=tuple(map(int,found.groups()));event=None
        elif "CUserMsg_CustomGameEvent [148]" in line:event=""
        elif event is not None and "event_name:" in line:
            found=re.search(r'event_name: "([A-Za-z0-9_]+)"',line)
            if found and header:
                event=found[1]
                if event=="cw":
                    bits,size=header;need(math.ceil(bits/8)==size and 0<size<=50,"complete_native_frequent_event_exceeds_50_bytes")
                    count+=1;maximum=max(maximum,size);total+=size
        elif event=="cw" and "data:" in line:
            found=re.search(r"\\000\\000\\001d\\000([A-Za-z0-9_-]+)\\000\\013\\013",line)
            need(found is not None and len(found[1])<=24,"complete_native_cw_single_bounded_d_key_required")
            raw=base64.urlsafe_b64decode(found[1]+"="*(-len(found[1])%4))
            need(0<len(raw)<=18,"complete_native_cw_raw_body_limit");payloads+=1
    need(count>0 and payloads==count,"complete_native_current_ordinary_cw_measurements_required")
    return dict(layer="CUserMsg_CustomGameEvent; excludes UDP/IP/Steam headers",frames=count,
        max_native_bytes=maximum,total_native_bytes=total,frequent_limit_bytes=50,
        cold_bulk_uses_separate_total_traffic_policy=True,raw_payloads_disclosed=False,native_fps_measured=False)

def validate_native_release(request,report,manifest,signed):
    b,ops,p=environment();expected=request.get("report_sha256")
    actual,actual_manifest,actual_signed=b.load_package(expected,full=True)
    need((actual,actual_manifest,actual_signed)==(report,manifest,signed),"complete_native_authenticated_package_objects_differ")
    ops.source_binding(report,expected)
    ref=dict(path=request.get("production_evidence_path"),sha256=request.get("production_evidence_sha256"))
    reader=helpers().Evidence(b,SimpleNamespace(p=SimpleNamespace(STORE=ops.STORE)))
    review,origin=reader.document(ref,ROOT/"output/complete_native_review_origin.json")
    need(review.get("schema")==1 and review.get("kind")==KIND and review.get("scope")==SCOPE
        and review.get("release_sequence")==report["release_sequence"] and exact_bindings(review,report,expected)
        and review.get("runtime_paths")==report["changed_runtime_paths"]
        and review.get("removed_runtime_paths")==report["removed_runtime_paths"]
        and review.get("native_file_use_policy")==POLICY,"complete_native_exact_complete_scope_review_required")
    need(review.get("synthetic") is False and review.get("tools") is False
        and review.get("offline_logic_test") is False and review.get("cheats") is False
        and review.get("http_enabled") is True and all(review.get("root_review",{}).get(key) is True for key in
        ("normal_oauth_approved","no_synthetic_profile","no_runtime_script_injection","no_mock_movie_error_class",
         "no_crash_or_hang","normal_exit_without_force","keeper_held_continuously_reviewed")),
         "complete_native_real_authenticated_ordinary_scope_required")
    need(same_process(request["native_process_generation"],review["process"]),"complete_native_request_generation_differs")
    process,bounds,text=lifecycle(review,origin,report,expected,reader,b,ops,p)
    ui=ui_cases(review,process,bounds,reader,origin)
    lottery=lottery_cases(review,process,bounds,text,reader,origin)
    network=network_summary(text)
    reader.unchanged()
    b.verify_operator_paths(dict(_EXECUTED_HELPERS),report["operator_revision"])
    return dict(ordinary_production_acceptance=True,scope=SCOPE,release_sequence=report["release_sequence"],
        content_sha256=report["content_sha256"],source_revisions=report["source_revisions"],
        production_evidence_sha256=ref["sha256"],native_process_generation=request["native_process_generation"],
        ui_cases=ui,lottery=lottery,network=network,original0104_fully_restored=True,
        native_file_use_policy=POLICY,all_gameplay_paths_verified=False,native_fps_measured=False,
        official_download=False,post_upload_arcade_verified=False,sdk_initialized=False,updates_submitted=0)

def review_template(report,report_sha256):
    """Pure private worksheet, deliberately unable to satisfy this gate.

    The operator fills references only after real captures and checks; no TRUE
    review, PID, decoder outcome, request ID or ticket balance is manufactured.
    """
    def file_ref():return dict(path="",sha256="")
    def case(roles,flags):
        return dict(captures={role:dict(png=file_ref(),metadata=file_ref()) for role in roles},
            visual_review={**dict.fromkeys(flags,False),"reviewed_png_sha256":[]})
    value=dict(schema=1,kind=KIND,scope=SCOPE,status="TEMPLATE_NOT_NATIVE_EVIDENCE",
        release_sequence=report["release_sequence"],package_report_sha256=report_sha256,
        source_revisions=report["source_revisions"],collection_source_revisions=report["collection_source_revisions"],
        operator_revision=report["operator_revision"],content_sha256=report["content_sha256"],
        signed_manifest_sha256=report["signed_manifest_sha256"],runtime_paths=report["changed_runtime_paths"],
        removed_runtime_paths=report["removed_runtime_paths"],native_file_use_policy=POLICY,
        synthetic=None,tools=None,offline_logic_test=None,cheats=None,http_enabled=None,
        process=dict(pid=None,created_utc=None,native_created_filetime=None),reviewed_utc=None,
        root_review=dict.fromkeys(("normal_oauth_approved","no_synthetic_profile","no_runtime_script_injection",
            "no_mock_movie_error_class","no_crash_or_hang","normal_exit_without_force",
            "keeper_held_continuously_reviewed"),False))
    value["rehearsal"]={name:file_ref() for name in
        ("transaction","process","close_intent","close_requested","hold_end","restored","engine_log_final")}
    value["rehearsal"]["inspections"]=[file_ref(),file_ref()]
    value["ui_cases"]={name:case(("visible",),("actual_data_visible","normal_ui_open",
        "not_loading_or_placeholder","no_stall")) for name in
        ("n1_gameplay","archive","hud_selection","grid","production","vip","payment","public_beta")}
    value["lottery_previews"]={}
    for pool in POOLS:
        item=case(("window_before","animation_a","animation_b","window_after"),
            ("theme_matches_pool","animation_progressed","returned_to_lottery_window",
             "no_movie_error_visible_after_fallback","no_draw_inputs","actual_movie_content"))
        item.update(pool=pool,mode="NO_CONSUMPTION_PREVIEW",presentation=None,fallback_reason=None,
            tickets_before=None,tickets_after=None)
        value["lottery_previews"][pool]=item
    value["consecutive_draws"]=[]
    for unused in range(3):
        item=case(("window_before","animation_a","animation_b","results","window_after"),
            ("actual_movie_content","fallback_animation_content","animation_progressed",
             "ten_actual_rewards_visible","confirm_button_full_width","owned_text_visible_when_applicable",
             "returned_to_lottery_window"))
        item.update(pool="map",count=10,ticket_kind="ordinary",real_player_transaction=None,
            skip_animation=None,request_id=None,tickets_before=None,tickets_after=None,
            presentation=None,fallback_reason=None)
        value["consecutive_draws"].append(item)
    return value

def main(argv=None):
    argparse.ArgumentParser(description=__doc__).parse_args(argv)
    print(json.dumps(dict(status="STATIC_COMPLETE_NATIVE_ADMISSION_PLAN_NO_EFFECTS",scope=SCOPE,
        ordinary_client=True,native_actions=0,sdk_initialized=False,ready_for_upload=False)))
    return 0

if __name__=="__main__":raise SystemExit(main())
