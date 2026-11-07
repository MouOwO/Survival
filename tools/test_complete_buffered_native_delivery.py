"""Synthetic evidence-shape rejection tests. No native evidence/transactions."""
from pathlib import Path
from datetime import datetime, timedelta, timezone
from copy import deepcopy
from unittest.mock import patch
import ast, inspect
import unittest

import sys
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from complete_delivery_release_20261103 import native_admission as n

class BufferedGateTests(unittest.TestCase):
    def fixture(self, *, direct_draw=False, preview_return=False, extra=True):
        self.base=datetime(2026,11,7,12,0,0,tzinfo=timezone(timedelta(hours=8)))
        self.process=dict(created_utc='2026-11-07T03:00:00Z')
        self.bounds=(self.base-timedelta(minutes=1),self.base+timedelta(hours=1))
        self.lines=[];self.shots={};self.counter=0
        self.review=dict(lottery_presentation_policy=n.BUFFERED_PRESENTATION_POLICY,decoder_probe=None,
                         lottery_previews={},consecutive_draws=[],buffered_failure_probe=None)
        self.manifest=dict(files=[]);self.original=dict(compiler=dict(outputs={}))
        fingerprint=dict(bytes=100,sha256='a'*64,md5='b'*32)
        for pool in n.POOLS:
            path='panorama/layout/custom_game/lottery_movie_'+pool+'.vxml_c'
            self.manifest['files'].append(dict(path=path,**fingerprint));self.original['compiler']['outputs'][path]=fingerprint.copy()
            self.manifest['files'].append(dict(path='panorama/videos/custom_game/lottery_cinematic_v1/'+pool+'.webm',**fingerprint))
        self.manifest['files'].append(dict(path=n.BUFFERED_BAD_XML,**fingerprint))
        self.original['compiler']['outputs'][n.BUFFERED_BAD_XML]=fingerprint.copy()
        self.manifest['files'].append(dict(path=n.BUFFERED_BAD_MEDIA,bytes=59,sha256=n.BUFFERED_BAD_SHA,md5='c'*32))
        for i,pool in enumerate(n.POOLS):
            self.review['lottery_previews'][pool]=self.add_case(pool,i*20,preview=True,direct=preview_return and i==1)
        for i in range(3):
            self.review['consecutive_draws'].append(self.add_case('map',100+i*20,preview=False,direct=direct_draw and i==0))
        if extra:self.review['buffered_failure_probe']=self.add_case('map',180,preview=True,direct=True,bad=True)
        self.text=''.join(self.lines)

    def log(self,t,body):
        self.lines.append((self.base+timedelta(seconds=t)).strftime('%m/%d %H:%M:%S')+' [PanoramaScript] '+body+'\n')

    def add_case(self,pool,t,*,preview,direct=False,bad=False):
        self.counter+=1;attempt=self.counter
        presentation=('preview_return' if preview else 'results_direct') if direct else 'movie'
        visual=dict.fromkeys(('returned_to_lottery_window','returned_to_preview_origin','no_movie_error_visible',
                'no_secondary_animation','no_automatic_retry','no_draw_inputs','actual_movie_content','animation_progressed',
                'theme_matches_pool','ten_actual_rewards_visible','confirm_button_full_width','owned_text_visible_when_applicable'),True)
        case=dict(pool=pool,presentation=presentation,buffered_attempt=attempt,visual_review=visual,
                  failure_reason='ended_before_initialized' if direct else None,_key=str(attempt))
        if preview:
            case.update(mode='ZERO_CONSUMPTION_BUFFERED_FAILURE_PROBE' if bad else 'NO_CONSUMPTION_PREVIEW',
                        ordinary_client=True,actual_draw_inputs=0,tickets_before=100,tickets_after=100)
        else:
            i=len(self.review['consecutive_draws'])
            case.update(count=10,ticket_kind='ordinary',real_player_transaction=True,skip_animation=False,
                        request_id='request_'+str(i),tickets_before=100-i*10,tickets_after=90-i*10)
            self.log(t+1,'[SURVIVAL_LOTTERY_UI] stage=result_received request='+case['request_id'])
            self.log(t+1,'[SURVIVAL_LOTTERY_UI] result_count=10 server_count=10 guarantee=sr')
            self.log(t+1,'[SURVIVAL_LOTTERY_UI] stage=cards_ready count=10')
        common=' attempt='+str(attempt)+' pool='+pool+' probe='+('true' if bad else 'false')
        self.log(t+1,'[LOTTERY_BUFFERED_PLAYBACK] stage=begin'+common+' loadbehavior=buffer-async source='+('fixed_invalid_media' if bad else 'pool_movie'))
        if direct:
            self.log(t+1,'[LOTTERY_BUFFERED_PLAYBACK] stage=failure'+common+' reason=ended_before_initialized action='+('return_to_preview_idle' if preview else 'return_to_received_results')+' event=VideoPlayerEnded initialized=false')
            self.log(t+1,'[LOTTERY_BUFFERED_PLAYBACK] stage=complete'+common+' outcome=skipped_ended_before_initialized')
        else:
            self.log(t+1,'[LOTTERY_BUFFERED_PLAYBACK] stage=initialized'+common)
            self.log(t+8,'[LOTTERY_BUFFERED_PLAYBACK] stage=ended'+common+' elapsed_ms=7003')
            self.log(t+8,'[LOTTERY_BUFFERED_PLAYBACK] stage=complete'+common+' outcome=native_ended')
        if not preview:self.log(t+1 if not direct else t+2,'[SURVIVAL_LOTTERY_UI] stage=reveal_ready animated='+('false' if direct else 'true'))
        if direct:
            roles=('window_before','window_after') if preview else ('window_before','results','window_after')
            stamps=(0,3) if preview else (0,1.3,3)
        else:
            roles=('window_before','animation_a','animation_b','window_after') if preview else ('window_before','animation_a','animation_b','results','window_after')
            stamps=(0,2,6,10) if preview else (0,2,6,8.3,10)
        self.shots[str(attempt)]=dict(zip(roles,[dict(start=self.base+timedelta(seconds=t+x),end=self.base+timedelta(seconds=t+x+.01),sha256=('%064x'%(attempt*100+i)),hwnd=123,width=1600,height=900) for i,x in enumerate(stamps)]))
        return case

    def run_gate(self):
        def captures(case,roles,*unused):
            actual=self.shots[case['_key']]
            self.assertEqual(tuple(actual),roles)
            return [deepcopy(actual[role]) for role in roles]
        with patch.object(n,'captures',captures):
            return n.buffered_lottery_cases(self.review,self.process,self.bounds,self.text,None,None,
                manifest=self.manifest,original_evidence=self.original)

    def test_all_real_movies_plus_actual_bad_preview_return(self):
        self.fixture();out=self.run_gate()
        self.assertEqual((out['actual_movie_presentations'],out['actual_decoder_returns'],out['ordinary_tickets_consumed']),(7,1,30))
        self.assertFalse(out['additional_buffered_failure_probe']['real_draw_case_replacement'])
    def test_direct_real_results_need_no_second_animation(self):
        self.fixture(direct_draw=True,extra=False);out=self.run_gate()
        self.assertEqual((out['actual_movie_presentations'],out['actual_decoder_returns']),(6,1))
    def test_preview_return_has_no_fake_rewards_and_old_fields_unused(self):
        self.fixture(preview_return=True,extra=False);out=self.run_gate()
        self.assertEqual((out['actual_movie_previews'],out['direct_return_previews']),(3,1))
    def test_setup_and_timeout_are_safe_returns_not_real_decoder_evidence(self):
        for reason in ('setup_error','startup_timeout','completion_timeout'):
            with self.subTest(reason=reason):
                self.fixture();self.review['buffered_failure_probe']['failure_reason']=reason
                self.text=self.text.replace('ended_before_initialized',reason)
                with self.assertRaisesRegex(ValueError,'does_not_prove_decoder_failure'):self.run_gate()
    def test_legacy_css_wrapper_probe_cannot_cover_production(self):
        self.fixture();self.review['decoder_probe']={'mode':'ZERO_CONSUMPTION_NATIVE_DECODER_PROBE'}
        with self.assertRaisesRegex(ValueError,'legacy_wrapper'):self.run_gate()
    def test_reason_without_actual_child_event_is_rejected(self):
        self.fixture();self.text=self.text.replace(' event=VideoPlayerEnded','')
        with self.assertRaisesRegex(ValueError,'real_child_ended'):self.run_gate()
    def test_signed_bad_raw_and_compiled_xml_are_both_required(self):
        for resource in (n.BUFFERED_BAD_MEDIA,n.BUFFERED_BAD_XML):
            with self.subTest(resource=resource):
                self.fixture();self.manifest['files']=[r for r in self.manifest['files'] if r['path']!=resource]
                with self.assertRaisesRegex(ValueError,'signed_resource_missing'):self.run_gate()
        self.fixture();self.original['compiler']['outputs'][n.BUFFERED_BAD_XML]['sha256']='d'*64
        with self.assertRaisesRegex(ValueError,'official_compiler'):self.run_gate()
        self.fixture();next(r for r in self.manifest['files'] if r['path']==n.BUFFERED_BAD_MEDIA)['bytes']=60
        with self.assertRaisesRegex(ValueError,'exact_bad_media'):self.run_gate()
    def test_static_movie_frames_or_wrong_theme_rejected(self):
        self.fixture();case=self.review['lottery_previews']['map'];shots=self.shots[case['_key']]
        shots['animation_b']['sha256']=shots['animation_a']['sha256']
        with self.assertRaisesRegex(ValueError,'actual_movie_frames'):self.run_gate()
        self.fixture();self.review['lottery_previews']['map']['visual_review']['theme_matches_pool']=False
        with self.assertRaisesRegex(ValueError,'actual_movie_frames'):self.run_gate()
    def test_ended_without_init_cannot_claim_actual_movie(self):
        self.fixture();self.text=self.text.replace('[LOTTERY_BUFFERED_PLAYBACK] stage=initialized attempt=1 pool=map probe=false','[OTHER] ignored',1)
        with self.assertRaisesRegex(ValueError,'initialization_and_end'):self.run_gate()
    def test_wrong_native_action_or_complete_outcome_rejected(self):
        for old,new in [('return_to_preview_idle','return_to_received_results'),('outcome=skipped_ended_before_initialized','outcome=native_ended')]:
            with self.subTest(old=old):
                self.fixture();self.text=self.text.replace(old,new)
                with self.assertRaisesRegex(ValueError,'actual_caller'):self.run_gate()
    def test_extra_draw_and_duplicate_request_remain_rejected(self):
        self.fixture();self.text+='11/07 12:04:00 [SURVIVAL_LOTTERY_UI] stage=result_received request=extra\n'
        with self.assertRaisesRegex(ValueError,'additional_draw_ack'):self.run_gate()
        self.fixture();self.review['consecutive_draws'][1]['request_id']='request_0'
        with self.assertRaisesRegex(ValueError,'distinct_actual_draw_request'):self.run_gate()
    def test_ticket_chain_and_zero_ticket_probe_unchanged(self):
        self.fixture();self.review['consecutive_draws'][1]['tickets_after']-=1
        with self.assertRaisesRegex(ValueError,'ticket_debit'):self.run_gate()
        self.fixture();self.review['buffered_failure_probe']['tickets_after']-=1
        with self.assertRaisesRegex(ValueError,'zero_transaction'):self.run_gate()
    def test_animated_false_only_for_direct_results(self):
        self.fixture();self.text=self.text.replace('animated=true','animated=false',1)
        with self.assertRaisesRegex(ValueError,'successful_ten_reward'):self.run_gate()
    def test_old_case_time_and_unfinished_presentation_rejected(self):
        self.fixture();case=self.review['lottery_previews']['map']
        for shot in self.shots[case['_key']].values():
            shot['start']-=timedelta(days=1);shot['end']-=timedelta(days=1)
        with self.assertRaisesRegex(ValueError,'same_case_native'):self.run_gate()
        self.fixture();self.text=self.text.replace('stage=complete attempt=1 ','stage=aborted attempt=1 ',1)
        with self.assertRaisesRegex(ValueError,'finish_in_capture'):self.run_gate()
    def test_free_preview_cannot_replace_real_draw(self):
        self.fixture();self.review['consecutive_draws'][0]['real_player_transaction']=False
        with self.assertRaisesRegex(ValueError,'actual_ordinary_map_ten'):self.run_gate()
    def test_preview_returns_to_original_ui_even_if_lottery_was_closed(self):
        self.fixture();self.review['buffered_failure_probe']['visual_review']['returned_to_lottery_window']=False
        self.assertEqual(self.run_gate()['actual_decoder_returns'],1)
        self.review['buffered_failure_probe']['visual_review']['returned_to_preview_origin']=False
        with self.assertRaisesRegex(ValueError,'zero_transaction'):self.run_gate()
    def test_distinct_native_case_cannot_share_an_attempt_lifecycle(self):
        self.fixture();self.review['consecutive_draws'][0]['buffered_attempt']=1
        with self.assertRaisesRegex(ValueError,'same_case_native'):self.run_gate()
    def test_early_end_needs_actual_initialization_and_bounded_elapsed(self):
        self.fixture()
        old='[LOTTERY_BUFFERED_PLAYBACK] stage=failure attempt=8 pool=map probe=true reason=ended_before_initialized action=return_to_preview_idle event=VideoPlayerEnded initialized=false'
        new='[LOTTERY_BUFFERED_PLAYBACK] stage=initialized attempt=8 pool=map probe=true\n11/07 12:03:01 [PanoramaScript] [LOTTERY_BUFFERED_PLAYBACK] stage=failure attempt=8 pool=map probe=true reason=early_end action=return_to_preview_idle event=VideoPlayerEnded initialized=true elapsed_ms=200'
        self.text=self.text.replace(old,new).replace('outcome=skipped_ended_before_initialized','outcome=skipped_early_end')
        self.review['buffered_failure_probe']['failure_reason']='early_end'
        self.assertEqual(self.run_gate()['actual_decoder_returns'],1)
        self.text=self.text.replace('elapsed_ms=200','elapsed_ms=7003')
        with self.assertRaisesRegex(ValueError,'early_native_end'):self.run_gate()
    def test_0701_and_future_templates_are_empty_and_older_template_unchanged(self):
        report=dict(release_sequence=2026110701,source_revisions={},collection_source_revisions={},operator_revision='0'*40,
                    content_sha256='1'*64,signed_manifest_sha256='2'*64,changed_runtime_paths=[],removed_runtime_paths=[])
        for version in (2026110701,2026110702):
            report['release_sequence']=version
            value=n.review_template(report,'3'*64)
            self.assertEqual(value['lottery_presentation_policy'],n.BUFFERED_PRESENTATION_POLICY)
            self.assertTrue(all(item['buffered_attempt'] is None for item in value['consecutive_draws']))
            self.assertFalse(value['consecutive_draws'][0]['visual_review']['no_secondary_animation'])
        report['release_sequence']=2026110604
        self.assertNotIn('lottery_presentation_policy',n.review_template(report,'3'*64))
    def test_authenticated_validation_dispatch_preserves_old_and_future_policies(self):
        # Evaluate the actual validator expression, without faking its signature,
        # OAuth or process admission prerequisites to reach this narrow branch.
        tree=ast.parse(inspect.getsource(n._validate_native_release))
        expression=next(node.value for node in ast.walk(tree) if isinstance(node,ast.Assign)
                        and any(isinstance(target,ast.Name) and target.id=='lottery_policy' for target in node.targets))
        code=compile(ast.Expression(expression),'<actual validator policy expression>','eval')
        for version,expected in [(2026110604,n.lottery_cases),(2026110701,n.buffered_lottery_cases),(2026110702,n.buffered_lottery_cases)]:
            with self.subTest(version=version):
                self.assertIs(eval(code,n.__dict__,{'report':{'release_sequence':version}}),expected)

if __name__=='__main__':unittest.main()
