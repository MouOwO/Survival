"""Synthetic control/evidence-shape tests, not native acceptance or screenshots."""
from copy import deepcopy
from datetime import datetime,timedelta,timezone
from pathlib import Path
import sys
import unittest

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from complete_delivery_release_20261103 import native_admission as native
import release_compile_scope as compiler
from types import SimpleNamespace
gate=SimpleNamespace(RESOURCE=native.DECODER_PROBE_RESOURCE,URI="file://{resources}/styles/custom_game/lottery_cinematic_v1.vcss_c",decoder_probe=native._decoder_probe_case)



class GateTests(unittest.TestCase):
    def setUp(self):
        self.t=datetime(2026,11,4,12,tzinfo=timezone(timedelta(hours=8)))
        self.case=dict(mode="ZERO_CONSUMPTION_NATIVE_DECODER_PROBE",pool="map",resource=gate.RESOURCE,
            presentation="fallback",fallback_reason="native_error",probe_id=1,tickets_before=141,tickets_after=141,
            actual_draw_inputs=0,ordinary_client=True,visual_review=dict.fromkeys(("fallback_animation_content",
            "animation_progressed","returned_to_lottery_window","no_movie_error_visible_after_fallback","no_draw_inputs"),True))
        self.fingerprint=dict(bytes=7839,sha256="1"*64,md5="2"*32)
        self.manifest=dict(files=[dict(path=gate.RESOURCE,**self.fingerprint)])
        self.original=dict(compiler=dict(outputs={gate.RESOURCE:self.fingerprint.copy()}))
        self.shots=[dict(start=self.t+timedelta(seconds=a),end=self.t+timedelta(seconds=a+.01),
            sha256=str(i)*64,hwnd=9,width=1280,height=720) for i,a in enumerate((0,2.1,3.1,6))]
        self.text="".join("11/04 12:00:%02d [Panorama] [LOTTERY_DECODER_PROBE] stage=%s probe=1 pool=map %s\n"%row for row in (
            (1,"begin","resource="+gate.RESOURCE+" no_consumption=true"),(1,"set_movie","resource="+gate.RESOURCE),
            (2,"error","cause=native_error native_class=MovieError"),(2,"fallback","reason=native_error"),(5,"complete","outcome=native_error")))
    def run_gate(self):
        return gate.decoder_probe(self.case,dict(created_utc="2026-11-04T03:00:00Z"),(self.t-timedelta(seconds=2),self.t+timedelta(seconds=8)),
            self.text,None,None,lambda *args:deepcopy(self.shots),self.manifest,self.original)
    def test_fixed_vcss_uri_maps_to_its_real_content_css_author(self):
        raw=(HERE.parent/"panorama/src/scripts/custom_game/lottery_cinematic_v1.js").read_bytes()
        source,engine=compiler.dependencies("panorama/scripts/custom_game/lottery_cinematic_v1.js",raw)
        self.assertEqual(source,["panorama/styles/custom_game/lottery_cinematic_v1.css"])
        self.assertEqual(engine,[])
        self.assertEqual(compiler.artifact_for(source[0]),gate.RESOURCE)
        with self.assertRaises(ValueError):
            compiler.dependencies("panorama/scripts/custom_game/lottery_cinematic_v1.js",raw.replace(gate.URI.encode(),b"file://{resources}/missing.bin"))
    def test_additional_probe_counts_zero_movies_zero_tickets_but_one_real_error_shape(self):
        result=self.run_gate()
        self.assertEqual((result["ordinary_tickets_consumed"],result["actual_movie_presentations"],result["actual_decoder_fallbacks"]),(0,0,1))
        self.assertFalse(result["real_draw_case_replacement"])
    def test_missing_or_unproven_candidate_resource_is_rejected(self):
        self.manifest["files"]=[]
        with self.assertRaisesRegex(ValueError,"real_signed_compiler_output"):self.run_gate()
    def test_silent_watchdog_or_manually_selected_fallback_cannot_satisfy_real_error(self):
        for outcome in ("inconclusive","tools_preview"):
            before=self.text;self.text=self.text.replace("outcome=native_error","outcome="+outcome)
            with self.assertRaises(ValueError):self.run_gate()
            self.text=before
        self.text=self.text.replace("stage=error","stage=anything_else")
        with self.assertRaises(ValueError):self.run_gate()
    def test_setup_exception_cannot_be_claimed_as_media_api_failure(self):
        self.case["fallback_reason"]="sync_error"
        self.text=self.text.replace("cause=native_error native_class=MovieError","cause=sync_error api=CreatePanel").replace("reason=native_error","reason=sync_error").replace("outcome=native_error","outcome=sync_error")
        with self.assertRaisesRegex(ValueError,"media_api_exception"):self.run_gate()
        self.text=self.text.replace("api=CreatePanel","api=SetMovie")
        self.assertEqual(self.run_gate()["actual_decoder_fallbacks"],1)
    def test_old_or_static_captures_and_any_ticket_debit_fail(self):
        self.shots[2]["sha256"]=self.shots[1]["sha256"]
        with self.assertRaisesRegex(ValueError,"actual_native_pixels"):self.run_gate()
        self.shots[2]["sha256"]="9"*64;self.shots[2]["end"]+=timedelta(hours=1)
        with self.assertRaisesRegex(ValueError,"lifecycle_must_match"):self.run_gate()
        self.case["tickets_after"]-=1
        with self.assertRaisesRegex(ValueError,"cannot_consume"):self.run_gate()



if __name__=="__main__":unittest.main()
