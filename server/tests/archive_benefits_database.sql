-- Run only inside the release verifier's outer transaction, after both new
-- migrations and exact-hash config registration; the caller MUST ROLLBACK.
-- Replace __CONFIG_HASH__ with the reviewed candidate bundle hash.
do $probe$
declare
 account text:=encode(sha256(convert_to('benefit-rollback-probe:'||clock_timestamp()::text,'UTF8')),'hex');
 candidate_hash text:='__CONFIG_HASH__'; defaults jsonb; first jsonb; second jsonb; stale jsonb;
 operation text:='benefit-probe:atomic'; stale_id text:='benefit-probe:stale';
 inventory jsonb:='{"lottery_ticket":1,"lottery_ember_of_legacy":2,"welfare_zongzi":150}';
 archive jsonb; response jsonb:='{"ok":true,"tier_id":"daily_time_150"}'; revision bigint; event_stamp bigint;
 boundary timestamptz; measured_end timestamptz; outbox_stamp timestamptz; measured_seconds bigint;
 clock_receipt text:='benefit-probe-clock:'||account;
begin
 select jsonb_object_agg(entry->>'field_id',entry->'default_value') into defaults
 from public.archive_config_sets cfg,
  lateral jsonb_array_elements(cfg.config->'configs'->'player_gameplay_stats'->'rows') entry
 where cfg.config_hash=candidate_hash;
 if defaults is null then raise exception 'benefit_probe_config_missing'; end if;
 perform public.ensure_player_gameplay_stats(account,defaults);
 first:=public.archive_prepare(account,operation,candidate_hash,'benefit-probe:atomic',
  jsonb_build_object('id',operation,'kind','benefit_claim','track','daily_time','tier_id','daily_time_150'));
 if not (first->>'ok')::boolean then raise exception 'benefit_probe_prepare_failed'; end if;
 event_stamp:=(first->>'event_at')::bigint;
 if event_stamp is null or abs(event_stamp-extract(epoch from clock_timestamp()))>5 then
  raise exception 'benefit_probe_event_time_missing';
 end if;
 if first->'command'->>'day_key'<>floor((event_stamp+10800)/86400.0)::bigint::text then
  raise exception 'benefit_probe_daily_reset_wrong';
 end if;
 second:=public.archive_resume(account,operation);
 if second->>'event_at'<>first->>'event_at' then raise exception 'benefit_probe_event_time_changed'; end if;
 revision:=(first->'profile'->>'revision')::bigint;
 stale:=public.archive_prepare(account,stale_id,candidate_hash,'benefit-probe:stale',
  jsonb_build_object('id',stale_id,'kind','benefit_claim','track','daily_time','tier_id','daily_time_30'));
 archive:=jsonb_build_object('benefits',jsonb_build_object('days',jsonb_build_object(
  first->'command'->>'day_key',jsonb_build_object('seconds',9000,'wins',0,
   'claimed',jsonb_build_object('daily_time_150',jsonb_build_object('at',event_stamp,'has_pass',0))))));
 first:=public.archive_commit_lottery(account,operation,revision,archive,'{}',null,inventory,response);
 if not (first->>'ok')::boolean or not (first->>'done')::boolean
  or first->'profile'->'save'->'content_inventory'<>inventory or first->'response'<>response then
  raise exception 'benefit_probe_atomic_inventory_commit_failed';
 end if;
 second:=public.archive_commit_lottery(account,operation,revision,archive,'{}',null,inventory,response);
 if second->'profile'<>first->'profile' or second->'response'<>response then
  raise exception 'benefit_probe_replay_double_grant';
 end if;
 stale:=public.archive_commit_lottery(account,stale_id,revision,archive,'{}',null,'{}','{}');
 if stale->>'error'<>'archive_revision_conflict' then raise exception 'benefit_probe_conflict_missing'; end if;
 second:=public.get_fishing_profile(account);
 if second->'save'->'content_inventory'<>inventory then raise exception 'benefit_probe_conflict_destroyed_inventory'; end if;

 -- Simulate an already-computed checkpoint whose actual interval straddles
 -- 05:00. Trigger processing happens at the current clock; outbox attribution
 -- must still use the session's exact checkpoint end (30 seconds after reset).
 boundary:=to_timestamp(floor((extract(epoch from clock_timestamp())+10800)/86400)*86400-10800);
 measured_end:=boundary+interval '30 seconds';
 insert into public.online_time_sessions(account_id,session_id,last_checkpoint_at)
  values(account,'benefit-probe-session',measured_end)
  on conflict(account_id) do update set session_id=excluded.session_id,last_checkpoint_at=excluded.last_checkpoint_at;
 insert into public.online_time_idempotency(request_id,account_id,response)
  values(clock_receipt,account,jsonb_build_object('ok',true,'elapsed_seconds',60,'online_seconds_total',60,'grants','[]'::jsonb));
 select created_at,elapsed into outbox_stamp,measured_seconds from public.archive_online_outbox
  where account_id=account and request_id=clock_receipt;
 if outbox_stamp is distinct from measured_end or measured_seconds is distinct from 60::bigint then
  raise exception 'benefit_probe_outbox_interval_end_drift';
 end if;
 if extract(epoch from (boundary-(outbox_stamp-measured_seconds*interval '1 second')))<>30
  or extract(epoch from (outbox_stamp-boundary))<>30 then
  raise exception 'benefit_probe_outbox_five_am_split_wrong';
 end if;
end;
$probe$;
