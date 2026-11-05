"""Synthetic native-format adversarial evidence; no GUI, SDK or transactions."""
import base64
from copy import deepcopy
from datetime import datetime,timedelta
import json
from pathlib import Path
import struct
import sys
import unittest
import zlib
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).resolve().parent))
from complete_delivery_release_20261103 import native_admission as n


def stamp(t):return (datetime(2026,11,5,12)+timedelta(seconds=t)).strftime("%m/%d %H:%M:%S")
def mark(t,text):return stamp(t)+" [VScript] "+text+"\n"
def uint(v):
    out=bytearray()
    while v>=128:out.append((v&127)|128);v>>=7
    out.append(v);return bytes(out)
def kv(values):
    out=bytearray(b"\0\0")
    for key,value in values.items():
        if isinstance(value,str):out+=b"\x01"+key.encode()+b"\0"+value.encode("utf8")+b"\0"
        else:out+=b"\x02"+key.encode()+b"\0"+struct.pack("<i",value)
    out+=b"\x0b\x0b";return b"VBKV"+struct.pack("<I",zlib.crc32(out))+out
def escape(raw):return "".join(chr(v) if 32<=v<127 and v not in (34,92) else "\\%03o"%v for v in raw)
def event(t,name,body,size=148):
    p=stamp(t)+" [Networking] "
    return p+"message (%d bits/%d bytes):\n"%(size*8,size)+p+"CUserMsg_CustomGameEvent [148]\n"+p+'event_name: "'+name+'"\n'+p+'data: "'+escape(body)+'"\n'


FIELDS=dict(known=1,success=9,grid_error=3,grid_scope=20,grid_session=14,grid_profile=7)
COMMIT,VALIDATION,WALL,CITY=999,1000,801,802
ANCHORS={WALL:"synthetic_wall_anchor",CITY:"synthetic_city_anchor"}
PROFILES={WALL:("wall","ability_build_wall","城墙"),CITY:("main_city","ability_build_main_city","主城")}
def catalog():
    data=dict(sha256="a"*64,fields=[dict(id=v,name=k,kind="uint",min=0,max=4294967295)for k,v in FIELDS.items()],
        records=[dict(id=k,key=v,tombstone=False)for k,v in [(COMMIT,"grid:commit"),(VALIDATION,"grid:validation"),(WALL,"grid:profile:ability_build_wall"),(CITY,"grid:profile:ability_build_main_city")]],
        auxiliary=dict(grid=dict(profiles=[dict(building_id=v[0],ability_name=v[1],display_name=v[2])for v in PROFILES.values()])))
    config='M.wall={abilities={"synthetic_wall_anchor"}}\nM.main_city={abilities={"synthetic_city_anchor"}}'
    runtime='keys.grid=4; function binding(){return {schema:1,schema_sha256:C.sha256};}'
    rules='building_id = "wall", build_time = 3\nbuilding_id = "main_city", build_time = 3'
    building='x .. "正在前往建造位置"\nx .. "开始建造"\nx .. "已建造"'
    return n._build_catalog_from_sources(('var data='+json.dumps(data,ensure_ascii=False)+';').encode(),config.encode(),runtime.encode(),rules.encode(),building.encode())


def wire(t,revision,changes=(),full=False,epoch=1,view=4,session=1,drop=None,duplicate=False):
    body=b"".join(uint(record)+uint(FIELDS[field]*2)+uint(value) for record,field,value in changes)
    chunks=[body[i:i+8] for i in range(0,len(body),8)] or [b""]
    out=[]
    for i,chunk in enumerate(chunks,1):
        raw=bytes([17 if full else 16])+b"".join(map(uint,[1,session,epoch,view,revision,i,len(chunks)]))+chunk
        assert len(raw)<=18
        token=base64.urlsafe_b64encode(raw).decode().rstrip("=")
        if i!=drop:out.append(event(t,"cw",kv(dict(d=token)),49))
        if duplicate and i==1:out.append(out[-1])
    return "".join(out)
def boot():
    return mark(0,"[Survival][INFO][Addon] initialized")+wire(0,1,full=True,view=1)+wire(1,1,full=True)+mark(2,"[BUILDER_READY] player=0 slot=east entindex=770 unit=npc_survival_builder_proxy")
def begin(t,profile=WALL):return mark(t,"[SURVIVAL_CAST][CLIENT] POINT_TARGET_BEGIN unit=770 ability=773 name="+PROFILES[profile][1])
def submit(t):return mark(t,"[SURVIVAL_CAST][CLIENT] POINT_TARGET_CANCEL reason=grid_submitted")
def notice(t,phase,profile=WALL,player=0,extra=None):
    value=dict(audience="player",kind="message",level="info",message=PROFILES[profile][2]+dict(approach="正在前往建造位置",start="开始建造",complete="已建造")[phase],player_id=player,rich_text=0)
    if extra:value.update(extra)
    return event(t,"ui_notification",kv(value))
def anchor(t,unit=806,profile=WALL,missing_begin=False):
    name=ANCHORS[profile]
    return ("" if missing_begin else mark(t,f"[BuildingAbility] add begin unit={unit} ability={name}"))+mark(t,f"[BuildingAbility] AddAbility OK unit={unit} ability={name} index=0")
def accepted(t=11,token=101,revision=2,profile=WALL,success=1,epoch=1,drop=None,duplicate=False):
    validation=[(VALIDATION,"known",1),(VALIDATION,"success",1),(VALIDATION,"grid_error",0),(VALIDATION,"grid_scope",1),(VALIDATION,"grid_session",token),(VALIDATION,"grid_profile",profile)]
    commit=[(COMMIT,"known",1),(COMMIT,"success",success),(COMMIT,"grid_error",0),(COMMIT,"grid_scope",1),(COMMIT,"grid_session",token)]
    return wire(t,revision,validation,epoch=epoch)+wire(t,revision+1,commit,epoch=epoch,drop=drop,duplicate=duplicate)
def operation(t=10,token=101,revision=2,profile=WALL,unit=806):
    return begin(t,profile)+notice(t+1,"approach",profile)+accepted(t+1,token,revision,profile)+submit(t+1)+anchor(t+2,unit,profile)+notice(t+2,"start",profile)+anchor(t+5,unit,profile)+notice(t+5,"complete",profile)
def audit(text,**kwargs):return n._all_custom_event_audit(text,build_catalog=catalog(),**kwargs)


class BuildOperationGateTests(unittest.TestCase):
    def passed(self,text):
        value=audit(text);self.assertTrue(value['accepted'],value['blockers']);return value
    def blocked(self,text):
        value=audit(text);self.assertFalse(value['accepted']);return value
    def test_real_operation_tokens_allow_finite_notifications_keep_all_raw_counts(self):
        log=boot()+operation()+operation(20,102,4,CITY,834)
        self.assertFalse(n._all_custom_event_audit(log)['accepted'])
        value=self.passed(log);world=value['worlds'][0];stats=world['events']['ui_notification']
        self.assertEqual(stats['count'],6);self.assertEqual(stats['total_bytes'],6*148)
        self.assertEqual(stats['validated_build_operation_notifications'],6)
        self.assertEqual(world['build_operations']['accepted_operations'],2)
    def test_canceled_approach_is_bound_to_its_own_successful_commit(self):
        log=boot()+begin(5)+notice(6,'approach')+accepted(6,100,2)+submit(6)+operation(10,101,4)
        self.assertEqual(self.passed(log)['worlds'][0]['events']['ui_notification']['validated_build_operation_notifications'],4)
    def test_same_phase_duplicate_does_not_get_second_permit(self):
        self.blocked(boot()+operation()+notice(15,'complete'))
    def test_text_and_client_markers_without_authoritative_ack_never_authorize(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+submit(11)+anchor(12)+notice(12,'start')+anchor(15)+notice(15,'complete'))
    def test_success_zero_cannot_authorize(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted(success=0)+submit(11))
    def test_missing_real_submit_cannot_authorize(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted())
    def test_wrong_recipient_cannot_borrow_local_builder_operation(self):
        self.blocked(boot()+begin(10)+notice(11,'approach',player=1)+accepted()+submit(11)
            +anchor(12)+notice(12,'start',player=1)+anchor(15)+notice(15,'complete',player=1))
    def test_wrong_profile_or_lifecycle_anchor_cannot_authorize(self):
        self.blocked(boot()+operation().replace('synthetic_wall_anchor','synthetic_city_anchor'))
    def test_missing_start_anchor_begin_or_early_completion_fails(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted()+submit(11)+anchor(12,missing_begin=True)+notice(12,'start')+anchor(15)+notice(15,'complete'))
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted()+submit(11)+anchor(12)+notice(12,'start')+anchor(12)+notice(12,'complete'))
    def test_incomplete_or_conflicting_fragment_cannot_authorize(self):
        for mode in ('drop','duplicate'):
            options=dict(drop=1)if mode=='drop'else dict(duplicate=True)
            self.blocked(boot()+begin(10)+notice(11,'approach')+accepted(**options)+submit(11))
    def test_epoch_change_delta_and_revision_gap_cannot_authorize(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted(epoch=2)+submit(11))
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted(revision=7)+submit(11))
    def test_full_snapshot_replay_is_not_a_new_accepted_operation(self):
        fields=[(VALIDATION,'known',1),(VALIDATION,'success',1),(VALIDATION,'grid_scope',1),
            (VALIDATION,'grid_session',101),(VALIDATION,'grid_profile',WALL),
            (COMMIT,'known',1),(COMMIT,'success',1),(COMMIT,'grid_error',0),
            (COMMIT,'grid_scope',1),(COMMIT,'grid_session',101)]
        self.blocked(boot()+begin(10)+notice(11,'approach')+wire(11,1,fields,full=True,epoch=2)+submit(11))
    def test_mismatching_scope_and_validation_session_cannot_authorize(self):
        for field,value in (('grid_scope',2),('grid_session',55)):
            validation=[(VALIDATION,'known',1),(VALIDATION,'success',1),(VALIDATION,'grid_scope',1),
                (VALIDATION,'grid_session',101),(VALIDATION,'grid_profile',WALL)]
            commit=[(COMMIT,'known',1),(COMMIT,'success',1),(COMMIT,'grid_error',0),
                (COMMIT,'grid_scope',1),(COMMIT,'grid_session',101)]
            commit=[(r,f,value if f==field else v)for r,f,v in commit]
            self.blocked(boot()+begin(10)+notice(11,'approach')+wire(11,2,validation)+wire(11,3,commit)+submit(11))
    def test_missing_scope_or_failed_validation_error_never_authorizes(self):
        for scope,error in ((0,0),(1,1)):
            validation=[(VALIDATION,'known',1),(VALIDATION,'success',1),(VALIDATION,'grid_error',error),
                (VALIDATION,'grid_session',101),(VALIDATION,'grid_profile',WALL)]
            commit=[(COMMIT,'known',1),(COMMIT,'success',1),(COMMIT,'grid_error',0),(COMMIT,'grid_session',101)]
            if scope:validation.append((VALIDATION,'grid_scope',scope));commit.append((COMMIT,'grid_scope',scope))
            self.blocked(boot()+begin(10)+notice(11,'approach')+wire(11,2,validation)+wire(11,3,commit)+submit(11))
    def test_rejected_profile_does_not_borrow_successful_other_building_token(self):
        self.blocked(boot()+begin(10,CITY)+notice(11,'approach',CITY)+accepted(profile=WALL)+submit(11))
    def test_old_world_operation_cannot_authorize_new_world_notice(self):
        self.blocked(boot()+begin(10)+notice(11,'approach')+accepted()+submit(11)+mark(12,'[Survival][INFO][Addon] initialized')+wire(12,1,full=True,view=1)+notice(13,'start'))
    def test_catalog_boolean_is_not_an_exemption_switch(self):
        with self.assertRaisesRegex(ValueError,'internal_source_bound'):n._all_custom_event_audit(boot(),build_catalog=True)
    def test_unknown_persistent_packets_and_high_frequency_limit_unchanged(self):
        extras=''.join(event(t,'future_unknown',kv(dict(n=t)),400)for t in (30,36,42))
        result=self.blocked(boot()+operation()+extras)
        self.assertIn('unexplained_repeated_large_event:future_unknown',result['blockers'])
        bad=wire(30,4).replace('392 bits/49 bytes','408 bits/51 bytes')
        self.blocked(boot()+operation()+bad)
    def test_shape_extra_field_and_broadcast_cannot_borrow_local_permit(self):
        for extra in (dict(fake='anything'),dict(audience='all'),dict(kind='reward')):
            self.blocked(boot()+begin(10)+notice(11,'approach',extra=extra)+accepted()+submit(11))
    def test_native_unknown_notification_subtype_keeps_original_loop_gate(self):
        items=''.join(event(t,'ui_notification',kv(dict(audience='player',kind='wave_overflow_tip',
            level='warning',message='Synthetic countdown '+str(t),player_id=0,rich_text=0)))for t in (30,36,42))
        self.assertIn('unexplained_repeated_large_event:ui_notification',self.blocked(boot()+operation()+items)['blockers'])
    def test_unrelated_cold_unique_events_minutes_apart_are_not_persistent(self):
        cold=''.join(event(t,'ui_notification',kv(dict(kind=kind,message=kind)))for t,kind in
            ((60,'reward'),(240,'fishing_reward'),(420,'message')))
        value=self.passed(boot()+cold)
        self.assertEqual(value['worlds'][0]['events']['ui_notification']['unresolved_large_count'],3)
    def test_unknown_consecutive_bins_and_bounded_identical_body_still_block(self):
        self.blocked(boot()+''.join(event(t,'ui_notification',kv(dict(message=str(t))))for t in (10,15,20)))
        self.blocked(boot()+''.join(event(t,'ui_notification',kv(dict(message='same')))for t in (60,67,75)))
    def test_same_cold_body_minutes_apart_keeps_lifetime_statistics_without_loop_claim(self):
        value=self.passed(boot()+''.join(event(t,'ui_notification',kv(dict(message='same')))for t in (60,240,420)))
        stats=value['worlds'][0]['events']['ui_notification']
        self.assertEqual(stats['unresolved_identical_lifetime_peak'],3)
        self.assertEqual(stats['unresolved_identical_15s_peak'],1)
    def test_auth_semantic_repetition_remains_whole_world_even_minutes_apart(self):
        value={key:''for key in n.AUTH_KEYS};value.update(player_id=0,diagnostic_status=0,expires_in=1000,
            status='pending',session_id='SYNTHETIC_ONLY_NOT_REAL',user_code='SYNTHETIC_ONLY',
            verification_uri='https://example.invalid/SYNTHETIC_ONLY')
        result=self.blocked(boot()+''.join(event(t,n.AUTH,kv(value),376)for t in (60,240,420)))
        self.assertEqual(result['blockers']['auth_repeated_semantic_state_without_bounded_request'],2)
    def test_external_claimed_operation_credit_dictionary_is_not_trusted(self):
        with self.assertRaisesRegex(ValueError,'internal_source_bound'):
            n._all_custom_event_audit(boot(),build_catalog=dict(accepted_operations=True,credits=1000))
    def test_build_draw_and_unrelated_cold_message_credits_are_per_packet(self):
        times=(30,35,40); windows=tuple((n._time(stamp(t))-1,n._time(stamp(t))+1)for t in times)
        responses=''.join(event(t,'ui_notification',kv(dict(kind='actual_draw_response',message='realresponse')))for t in times)
        cold=event(180,'ui_notification',kv(dict(kind='unrelated_cold',message='single')))
        value=audit(boot()+operation()+responses+cold,cold_response_windows=windows)
        self.assertTrue(value['accepted'],value['blockers'])
        stats=value['worlds'][0]['events']['ui_notification']
        self.assertEqual(stats['count'],7);self.assertEqual(stats['validated_build_operation_notifications'],3)
        self.assertEqual(stats['validated_transaction_responses'],3);self.assertEqual(stats['unresolved_large_count'],1)
        extra=event(30,'ui_notification',kv(dict(kind='actual_draw_response',message='realresponse')))
        self.assertFalse(audit(boot()+operation()+responses+extra+cold,cold_response_windows=windows)['accepted'])
        self.assertFalse(audit(boot()+operation()+responses+cold)['accepted'])
    def test_actual_immutable_catalog_derives_all_native_build_profiles(self):
        import subprocess,release_pending_inventory as pending
        revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
        builder=SimpleNamespace(dependencies=lambda:SimpleNamespace(package=SimpleNamespace(pending=pending)))
        value=n._load_build_catalog(builder,dict(source_revisions=dict(game=revision)))
        names={p['building_id'] for p in value.profiles.values()}
        self.assertTrue({'arrow_tower','wall','main_city','building_research_lab','building_advanced_research_lab','hero_altar'}<=names)
        self.assertGreaterEqual(len(value.profiles),9)
        self.assertEqual(len(value.profiles),len(value.anchors))
    def test_replaying_same_token_does_not_mint_another_operation(self):
        self.blocked(boot()+operation()+begin(20)+notice(21,'approach')+accepted(21,101,4)+submit(21))
        self.blocked(boot()+operation()+begin(20)+notice(21,'approach')+accepted(21,99,4)+submit(21))
    def test_indexes_have_linear_work_counter_over_500_operations(self):
        text=boot()+''.join(operation(10+10*i,101+i,2+2*i,WALL,806+i)for i in range(500))
        value=self.passed(text);info=value['worlds'][0]['build_operations']
        self.assertEqual(info['accepted_operations'],500)
        self.assertEqual(info['matched_notifications'],1500)
        self.assertLessEqual(info['work']['phase_clock_probes'],4500)
        self.assertLessEqual(info['work']['retired_permits'],1500)


if __name__=='__main__':unittest.main()
