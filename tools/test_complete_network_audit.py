"""Synthetic engine-format fixtures; zero native/network/credential operations."""
import base64
from datetime import datetime, timedelta
import importlib.util
import json
from pathlib import Path
import struct
import sys
import unittest
import zlib

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from complete_delivery_release_20261103 import native_admission as native
from types import SimpleNamespace
import ast,math,re,subprocess
original=subprocess.check_output(["git","--no-replace-objects","show","8034c5d5a379bbd7882102f4752d16b9c73525f7:tools/complete_delivery_release_20261103/native_admission.py"])
tree=ast.parse(original);function=next(v for v in tree.body if isinstance(v,ast.FunctionDef) and v.name=="network_summary")
def need(ok,code):
    if not ok:raise ValueError(code)
namespace=dict(need=need,math=math,re=re,base64=base64)
exec(compile(ast.Module(body=[function],type_ignores=[]),"<immutable_S13_network_function>","exec"),namespace)
old=SimpleNamespace(network_summary=namespace["network_summary"])
def audited(text,**kwargs):
    if kwargs.get("explicit_snapshot_budget") and "explicit_snapshot_windows" not in kwargs:
        kwargs["explicit_snapshot_windows"]=((native._time(stamp(0)),native._time(stamp(20))),)
    return native._all_custom_event_audit(text,**kwargs)
draft=SimpleNamespace(AUTH=native.AUTH,network_summary=audited)


def stamp(seconds):
    return (datetime(2026,11,4,12)+timedelta(seconds=seconds)).strftime("%m/%d %H:%M:%S")


def kv(values):
    raw = bytearray(b"\0\0")
    for key, value in values.items():
        if isinstance(value, str): raw += b"\x01"+key.encode()+b"\0"+value.encode()+b"\0"
        else: raw += b"\x02"+key.encode()+b"\0"+struct.pack("<i",value)
    body = bytes(raw)+b"\x0b\x0b"
    return b"VBKV"+struct.pack("<I",zlib.crc32(body))+body


def escape(raw):
    return "".join(chr(v) if 32 <= v < 127 and v not in (34,92) else "\\%03o" % v for v in raw)


def event(seconds, name, raw, size):
    prefix = stamp(seconds)+" [Networking] "
    return (prefix+"message (%d bits/%d bytes):\n"%(size*8,size)
        +prefix+"CUserMsg_CustomGameEvent [148]\n"+prefix+'event_name: "'+name+'"\n'
        +prefix+'data: "'+escape(raw)+'"\n')


def cw(seconds=0):
    body = bytes([17])+bytes([1]*7)+bytes([1]*10)
    return event(seconds,"cw",kv({"d":base64.urlsafe_b64encode(body).decode().rstrip("=")}),49)


def world(seconds=0):
    return stamp(seconds)+" [Survival][INFO][Addon] initialized V1.6\n"


def auth(seconds=0, status="pending", expires=60,player_id=0):
    # Deliberately fake fixture identities. Never read from a real auth record.
    values = dict(session_id="SYNTHETIC_ONLY_NOT_REAL",player_id=player_id,status=status,error="",
        user_code="SYNTHETIC_ONLY_CODE",verification_uri="https://example.invalid/SYNTHETIC_ONLY_URI",
        expires_in=expires,diagnostic_revision="",diagnostic_phase="",diagnostic_stage="",diagnostic_status=0)
    return event(seconds,draft.AUTH,kv(values),376)


def marker(seconds=0, reason="explicit_snapshot", status="pending"):
    return stamp(seconds)+" [PLAYER_WEB_AUTH_PUBLIC] reason="+reason+" status="+status+"\n"


def accepted_request(seconds=0,slot=0,mode="explicit_snapshot"):
    return stamp(seconds)+" [PLAYER_WEB_AUTH_REQUEST] accepted=1 generation=1 slot="+str(slot)+" mode="+mode+"\n"


class NetworkAuditTests(unittest.TestCase):
    def test_old_gate_passes_clock_only_auth_loop_new_gate_reports_all_events_and_blocks(self):
        log = world()+cw()+"".join(auth(t,expires=60-t) for t in (1,6,11,16,21))
        self.assertEqual(old.network_summary(log)["max_native_bytes"],49)
        result = draft.network_summary(log)
        self.assertFalse(result["accepted"])
        auth_stats = result["worlds"][0]["auth"]
        self.assertEqual(auth_stats["clock_only_duplicates"],4)
        self.assertEqual(result["worlds"][0]["events"][draft.AUTH]["count"],5)
        self.assertEqual(result["blockers"]["auth_repeated_semantic_state_without_bounded_request"],4)

    def test_unknown_large_loop_after_protocol_ready_cannot_hide_behind_good_cw(self):
        log = world()+cw()+"".join(event(t,"future_unknown_legacy",kv({"n":t}),400) for t in (1,6,11,16))
        self.assertEqual(old.network_summary(log)["frames"],1)
        result = draft.network_summary(log)
        self.assertIn("unexplained_repeated_large_event:future_unknown_legacy",result["blockers"])
        stats = result["worlds"][0]["events"]["future_unknown_legacy"]
        self.assertEqual(stats["phases"]["protocol_ready"],4)
        self.assertEqual(stats["large_count"],4)

    def test_unknown_same_body_rapid_loop_is_detected_without_any_event_whitelist(self):
        log = world()+cw()+"".join(event(t,"brand_new_event",kv({"n":1}),400) for t in (1,2,3))
        self.assertIn("unexplained_repeated_large_event:brand_new_event",draft.network_summary(log)["blockers"])

    def test_necessary_cold_responses_are_bound_one_per_real_transaction_window(self):
        times=(1,6,11)
        windows=tuple((native._time(stamp(t))-1,native._time(stamp(t))+1) for t in times)
        response=lambda t:event(t,"unknown_paid_response",kv({"n":1}),400)
        log=world()+cw()+"".join(response(t) for t in times)
        self.assertFalse(draft.network_summary(log)["accepted"])
        value=native.network_summary(log,cold_response_windows=windows)
        self.assertEqual(value["worlds"][0]["events"]["unknown_paid_response"]["validated_transaction_responses"],3)
        self.assertFalse(draft.network_summary(log+response(1),cold_response_windows=windows)["accepted"])

    def test_paid_response_windows_never_exempt_auth_clock_repeats(self):
        times=(1,6,11)
        windows=tuple((native._time(stamp(t))-1,native._time(stamp(t))+1) for t in times)
        log=world()+cw()+"".join(auth(t,expires=60-t) for t in times)
        self.assertFalse(draft.network_summary(log,cold_response_windows=windows)["accepted"])

    def test_one_cold_88kb_qr_and_distinct_bounded_cold_fragments_are_allowed(self):
        cold = event(1,"survival_payment_result",b"Q"*88600,88626)
        cold += "".join(event(2,"future_cold_chunks",kv({"n":i}),923) for i in range(12))
        result = draft.network_summary(world()+cw()+cold)
        self.assertTrue(result["accepted"],result["blockers"])
        self.assertEqual(result["worlds"][0]["events"]["survival_payment_result"]["max_bytes"],88626)
        self.assertGreater(result["worlds"][0]["large_total_bytes"],88626)

    def test_genuine_requesting_pending_approved_transitions_are_allowed(self):
        log = world()+auth(1,"requesting")+auth(2,"pending")+auth(3,"approved")+cw(4)
        result = draft.network_summary(log)
        self.assertTrue(result["accepted"],result["blockers"])
        self.assertEqual(result["worlds"][0]["auth"]["semantic_changes"],3)
        self.assertTrue(result["worlds"][0]["authorization_observed"])
        self.assertFalse(result["worlds"][0]["profile_ready_proven"])

    def test_one_reviewed_late_listener_snapshot_needs_marker_and_explicit_budget(self):
        log = world()+accepted_request(0,mode="state_change")+auth(0,"requesting")+auth(1)+cw(2)+accepted_request(3)+marker(3)+auth(3,expires=58)
        self.assertFalse(draft.network_summary(log)["accepted"])
        self.assertTrue(draft.network_summary(log,explicit_snapshot_budget=1)["accepted"])
        result = draft.network_summary(log+accepted_request(4)+marker(4)+auth(4,expires=57),explicit_snapshot_budget=1)
        self.assertFalse(result["accepted"])
        self.assertEqual(result["worlds"][0]["auth"]["reviewed_late_listener_snapshots"],1)

    def test_first_actual_ui_request_gets_only_one_cold_listener_bootstrap(self):
        log=world()+auth(1)+cw(2)+accepted_request(3)+marker(3)+auth(3,expires=58)
        value=draft.network_summary(log)
        self.assertTrue(value["accepted"],value["blockers"])
        self.assertEqual(value["worlds"][0]["auth"]["cold_listener_bootstraps"],1)
        self.assertFalse(draft.network_summary(log+accepted_request(4)+marker(4)+auth(4,expires=57))["accepted"])

    def test_state_change_input_logged_after_its_send_consumes_first_input(self):
        log=world()+marker(1,reason="state_change")+auth(1)+accepted_request(1,mode="state_change")+cw(2)
        log+=accepted_request(3)+marker(3)+auth(3,expires=58)
        self.assertFalse(draft.network_summary(log)["accepted"])
        value=draft.network_summary(log,explicit_snapshot_budget=1)
        self.assertTrue(value["accepted"],value["blockers"])
        self.assertEqual(value["worlds"][0]["auth"].get("cold_listener_bootstraps",0),0)
        self.assertEqual(value["worlds"][0]["auth"]["reviewed_late_listener_snapshots"],1)

    def test_state_change_mode_never_grants_a_following_explicit_send_permit(self):
        log=world()+auth(1)+cw(2)+accepted_request(3,mode="state_change")+marker(3)+auth(3,expires=58)
        self.assertFalse(draft.network_summary(log,explicit_snapshot_budget=1)["accepted"])

    def test_state_change_ordinal_and_cold_bootstrap_are_indexed_per_slot(self):
        log=world()+auth(1,player_id=0)+accepted_request(1,slot=0,mode="state_change")
        log+=auth(1,player_id=1)+cw(2)+accepted_request(3,slot=1)+marker(3)+auth(3,expires=58,player_id=1)
        value=draft.network_summary(log)
        self.assertTrue(value["accepted"],value["blockers"])
        self.assertEqual(value["worlds"][0]["auth"]["cold_listener_bootstraps"],1)
        self.assertFalse(draft.network_summary(log+accepted_request(4,slot=0)+marker(4)+auth(4,expires=57,player_id=0))["accepted"])

    def test_other_slots_state_change_does_not_destroy_an_inflight_explicit_pair(self):
        log=world()+auth(1,player_id=0)+auth(1,player_id=1)+cw(2)
        log+=accepted_request(3,slot=0)+marker(3)
        log+=marker(3,reason="state_change",status="approved")+auth(3,status="approved",player_id=1)
        log+=accepted_request(3,slot=1,mode="state_change")+auth(3,expires=58,player_id=0)
        value=draft.network_summary(log)
        self.assertTrue(value["accepted"],value["blockers"])
        self.assertEqual(value["worlds"][0]["auth"]["cold_listener_bootstraps"],1)

    def test_untyped_accepted_marker_cannot_silently_reenable_first_input(self):
        log=world()+cw()+auth(1)+accepted_request(2).replace(" mode=explicit_snapshot","")
        value=draft.network_summary(log)
        self.assertIn("native_auth_accepted_request_mode_missing_or_invalid",value["blockers"])

    def test_alternating_recipient_states_cannot_hide_each_others_repeat(self):
        log=world()+cw()+auth(1,player_id=0)+auth(2,player_id=1)+auth(6,expires=55,player_id=0)+auth(7,expires=55,player_id=1)
        value=draft.network_summary(log)
        self.assertFalse(value["accepted"])
        self.assertEqual(value["worlds"][0]["auth"]["clock_only_duplicates"],2)

    def test_positive_review_budget_without_actual_capture_window_is_rejected(self):
        with self.assertRaisesRegex(ValueError,"case_window_required"):
            native._all_custom_event_audit(world()+cw(),explicit_snapshot_budget=1)

    def test_formal_summary_blocks_loop_even_when_unchanged_s13_function_passes(self):
        log=world()+cw()+auth(1)+auth(6,expires=55)
        self.assertEqual(old.network_summary(log)["max_native_bytes"],49)
        with self.assertRaisesRegex(ValueError,"all_custom_event_network_gate"):
            native.network_summary(log)

    def test_state_change_marker_or_stale_marker_cannot_excuse_same_semantic_body(self):
        for reason, delay in (("state_change",0),("explicit_snapshot",2)):
            log = world()+auth(1)+cw(2)+accepted_request(3)+marker(3,reason)+auth(3+delay,expires=58)
            self.assertFalse(draft.network_summary(log,explicit_snapshot_budget=1)["accepted"])

    def test_send_marker_alone_cannot_manufacture_an_explicit_ui_request(self):
        log = world()+auth(1)+cw(2)+marker(3)+auth(3,expires=58)
        self.assertFalse(draft.network_summary(log,explicit_snapshot_budget=1)["accepted"])

    def test_other_player_request_cannot_excuse_a_duplicate_snapshot(self):
        log = world()+auth(1)+cw(2)+accepted_request(3,slot=1)+marker(3)+auth(3,expires=58)
        self.assertFalse(draft.network_summary(log,explicit_snapshot_budget=1)["accepted"])

    def test_each_world_restarts_cold_auth_and_cw_protocol_counters(self):
        log = world()+auth(1)+cw(2)+world(30)+auth(31)+cw(32)
        result = draft.network_summary(log)
        self.assertTrue(result["accepted"],result["blockers"])
        self.assertEqual(len(result["worlds"]),2)
        self.assertTrue(all(w["auth"]["semantic_changes"]==1 for w in result["worlds"]))

    def test_report_never_discloses_body_session_code_uri_or_payload_hash(self):
        result = draft.network_summary(world()+cw()+auth(1)+auth(6,expires=55))
        output = json.dumps(result)
        for forbidden in ("SYNTHETIC_ONLY", "example.invalid", "verification_uri", "session_id", "expires_in"):
            self.assertNotIn(forbidden,output)
        self.assertFalse(result["payload_hashes_disclosed"])
        self.assertFalse(result["event_body_or_identity_disclosed"])

    def test_incomplete_native_event_or_bad_cw_stays_blocking(self):
        result = draft.network_summary(world()+cw().rsplit("data:",1)[0])
        self.assertFalse(result["accepted"])
        result = draft.network_summary(world()+event(1,"cw",kv({"d":"bad key"}),49))
        self.assertFalse(result["accepted"])


if __name__ == "__main__": unittest.main()
