"""Synthetic native-format adversarial cases; no native/SDK/paid actions."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import test_complete_build_operation_gate as b
from complete_delivery_release_20261103 import native_admission as n


def source_catalog():
    c = b.catalog()
    paths = ('scripts/vscripts/config/generated/training_definitions.lua',
             'scripts/vscripts/systems/worker_system.lua',
             'scripts/vscripts/systems/worker_training_queue_service.lua',
             'scripts/vscripts/ui/compact_production_views.lua',
             'scripts/vscripts/ui/production_ui_service.lua')
    c.training = n._TrainingCatalog(n._TRAINING_CATALOG_SEAL,
        *[(SOURCE_ROOT/path if (SOURCE_ROOT/path).exists() else ROOT/path).read_text(encoding='utf8') for path in paths])
    return c


SOURCE_ROOT = ROOT
def trace(t,phase,job=1,token=None,owner=1,queue=1,world=1,player=0,source=10,adapter=1,
          started=10.,finish=11.,now=None,training='train_lumberjack_01',action=8,unit=100):
    token = job if token is None else token
    if phase=='enqueue': started,finish,unit,now = 0.,0.,0,10. if now is None else now
    if phase=='start': unit=0
    now = (started if phase=='start' else finish) if now is None else now
    return b.mark(t,f'[WORKER_TRAINING_TRACE] v=1 phase={phase} world={world} queue={queue} job={job} player={player} source={source} adapter={adapter} owner={owner} token={token} selection=1 action={action} training={training} duration=1.000000 started={started:.6f} finish={finish:.6f} now={now:.6f} unit={unit}')


def notice(t,player=0,message='伐木工LV1训练完成',**extra):
    value=dict(audience='player',kind='message',level='info',message=message,player_id=player,rich_text=0)
    value.update(extra)
    return b.event(t,'ui_notification',b.kv(value),142)


def job(t=10,job=1,**kw):
    return trace(t,'enqueue',job,**kw)+trace(t,'start',job,**kw)+notice(t+1,kw.get('player',0))+trace(t+1,'complete',job,**kw)


def audit(text):return n._all_custom_event_audit(b.boot()+text,build_catalog=source_catalog())
def world(value):return next(row for row in value['worlds'] if row['events'].get('cw'))


class TrainingOperationGateTests(unittest.TestCase):
    def ok(self,text):
        value=audit(text);self.assertTrue(value['accepted'],value['blockers']);return world(value)
    def blocked(self,text):
        value=audit(text);self.assertFalse(value['accepted']);return value
    def test_five_distinct_jobs_preserve_raw_wire_counts(self):
        w=self.ok(''.join(job(10+i,i+1) for i in range(5)))
        self.assertEqual(w['training_operations']['successful_jobs'],5)
        self.assertEqual(w['training_operations']['matched_notifications'],5)
        s=w['events']['ui_notification']
        self.assertEqual((s['count'],s['total_bytes'],s['max_bytes']),(5,710,142))
        self.assertEqual(s['validated_training_operation_notifications'],5)
        self.assertEqual(s['validated_transaction_responses'],0)
    def test_sixth_notice_is_blocked_even_below_generic_repeat_threshold(self):
        v=self.blocked(''.join(job(10+i,i+1) for i in range(5))+notice(15))
        self.assertEqual(v['blockers']['unproven_training_operation_notification'],1)
    def test_one_job_cannot_erase_five_duplicate_notices(self):
        v=self.blocked(job()+notice(11)*4)
        self.assertEqual(v['blockers']['unproven_training_operation_notification'],4)
        self.assertIn('unexplained_repeated_large_event:ui_notification',v['blockers'])
    def test_marker_absent_or_missing_phase_gets_no_credit(self):
        for text in (notice(11),trace(10,'enqueue')+notice(11),
                     trace(10,'enqueue')+trace(10,'start')+notice(11),
                     trace(10,'enqueue')+trace(11,'complete')+notice(11)):
            with self.subTest(text=text[:40]):self.blocked(text)
    def test_duplicate_lifecycle_invalidates_job(self):
        v=self.blocked(job()+trace(11,'complete'))
        self.assertIn('invalid_training_lifecycle',v['blockers'])
        self.assertEqual(world(v)['training_operations']['matched_notifications'],0)
    def test_action_token_replay_across_queue_and_selection_is_not_new_input(self):
        text=job()+job(12,2,token=1,queue=2)
        self.assertIn('invalid_training_lifecycle',self.blocked(text)['blockers'])
    def test_invalid_origin_cannot_be_cold_response_budget(self):
        for action in (0,9,10):
            self.blocked(job(action=action))
    def test_wrong_recipient_or_notification_shape_has_no_credit(self):
        prefix=trace(10,'enqueue')+trace(10,'start')+trace(11,'complete')
        for text in (notice(11,1),notice(11,level='error'),notice(11,code='fake'),notice(11,kind='wave_overflow_tip')):
            self.blocked(prefix+text)
    def test_changed_source_or_training_rejected(self):
        prefix=trace(10,'enqueue')+trace(10,'start')
        self.blocked(prefix+notice(11)+trace(11,'complete',source=11))
        self.blocked(prefix+notice(11)+trace(11,'complete',training='train_lumberjack_02'))
    def test_early_completion_rejected_actual_game_clock_required(self):
        self.blocked(trace(10,'enqueue')+trace(10,'start')+notice(11)+trace(11,'complete',now=10.5))
    def test_missing_created_worker_rejected(self):
        self.blocked(trace(10,'enqueue')+trace(10,'start')+notice(11)+trace(11,'complete',unit=0))
    def test_notice_can_precede_finish_return_but_not_enqueue(self):
        self.ok(job())
        self.blocked(notice(10)+trace(10,'enqueue')+trace(10,'start')+trace(11,'complete'))
    def test_delayed_unrelated_notice_not_consumed(self):
        self.blocked(trace(10,'enqueue')+trace(10,'start')+trace(11,'complete')+notice(14))
    def test_pause_changes_wall_duration_not_game_duration(self):
        self.ok(trace(10,'enqueue')+trace(10,'start')+notice(500)+trace(500,'complete'))
    def test_actual_new_owner_and_queue_allow_reused_local_numbers(self):
        self.ok(job()+job(12,1,owner=2,queue=2))
        self.ok(job()+job(12,1,adapter=2,queue=2))
    def test_new_world_cannot_borrow_old_lifecycle(self):
        self.blocked(trace(10,'enqueue')+trace(10,'start')+
                     b.mark(11,'[Survival][INFO][Addon] initialized')+notice(11)+trace(11,'complete'))
    def test_unknown_definition_is_not_whitelisted(self):
        self.blocked(job(training='train_lumberjack_99'))
    def test_overflow_and_build_gate_remain_active(self):
        text=''.join(notice(t,message='overflow',kind='wave_overflow_tip') for t in (10,11,12))
        self.assertIn('unexplained_repeated_large_event:ui_notification',self.blocked(text)['blockers'])
        self.assertTrue(audit(b.operation())['accepted'])
    def test_dense_completion_matching_is_linear(self):
        count=1000
        text=''.join(trace(10,'enqueue',i+1)+trace(10,'start',i+1) for i in range(count))
        text+=''.join(trace(11,'complete',i+1) for i in range(count))
        text+=notice(11)*count
        w=self.ok(text);m=w['training_operations']['work']
        self.assertEqual(m['marker_lines'],count*3)
        self.assertEqual(m['job_lookups'],count*3)
        self.assertEqual(m['notification_checks'],count)
        self.assertEqual(w['training_operations']['matched_notifications'],count)


if __name__=='__main__': unittest.main()
