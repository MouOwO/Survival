-- Welfare claims share the existing revision-checked inventory transaction.
-- Existing operation IDs, command bodies, hashes and completed receipts remain
-- unchanged. Only new operations use Beijing 05:00 daily reset.
begin;

do $migration$
declare definition text; updated text; signature text;
begin
 -- Change the day-index offset, not the actual timezone/clock. This covers
 -- newly prepared archive claims/caps, the online outbox and fishing grants.
 foreach signature in array array[
  'public.archive_prepare(text,text,text,text,jsonb)',
  'public.archive_online_pending(text,text)',
  'public.archive_fishing_daily_limit(text)'
 ] loop
  select pg_get_functiondef(signature::regprocedure) into definition;
  if position('28800' in definition)>0 then
   execute replace(definition,'28800','10800');
  elsif position('10800' in definition)=0 then
   raise exception 'benefit_reset_unexpected_definition: %',signature;
  end if;
 end loop;

 -- The checkpoint updates this session before inserting its idempotency
 -- receipt (which fires archive_capture_online). Use that exact interval end,
 -- rather than the later trigger-processing clock, for newly created outbox
 -- rows. Existing outbox rows and all replayed receipts remain untouched.
 select pg_get_functiondef('public.archive_capture_online()'::regprocedure) into definition;
 if position('stamp timestamptz:=(select last_checkpoint_at' in definition)=0 then
  updated:=regexp_replace(definition,
   $$stamp\s+timestamptz\s*:=\s*clock_timestamp\(\)$$,
   $$stamp timestamptz:=(select last_checkpoint_at from public.online_time_sessions where account_id=new.account_id)$$);
  if updated=definition then raise exception 'benefit_capture_unexpected_definition'; end if;
  execute updated;
 end if;

 -- Return the immutable event time separately, so no caller can supply or
 -- rewrite it and no historical receipt fingerprint is changed. Retrying a
 -- claim after 05:00 therefore uses its original day and month-card status.
 select pg_get_functiondef('public.archive_resume(text,text)'::regprocedure) into definition;
 if position('''event_at''' in definition)=0 then
  updated:=regexp_replace(definition,
   $$('command'\s*,\s*op\.command)$$,
   $$\1, 'event_at', floor(extract(epoch from op.event_at))::bigint$$);
  if updated=definition then raise exception 'benefit_resume_unexpected_definition'; end if;
  execute updated;
 end if;

 -- Preserve the existing security-definer owner, pinned search_path and
 -- role grants. Only the explicit allowed-command list is extended.
 select pg_get_functiondef('public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)'::regprocedure)
 into definition;
 if position('''benefit_claim''' in definition)=0 then
  if position('''commerce_purchase'')' in definition)=0 then
   raise exception 'benefit_commit_unexpected_definition';
  end if;
  execute replace(definition,'''commerce_purchase'')','''commerce_purchase'',''benefit_claim'')');
 end if;
end;
$migration$;

commit;
