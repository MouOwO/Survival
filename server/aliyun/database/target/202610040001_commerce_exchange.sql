-- Reuse the existing atomic inventory commit without changing its privileges,
-- pinned search_path, revision checks or existing lottery behavior.
begin;
do $$
declare definition text;
begin
 select pg_get_functiondef('public.archive_commit_lottery(text,text,bigint,jsonb,jsonb,text,jsonb,jsonb)'::regprocedure)
 into definition;
 if position('''commerce_purchase''' in definition)>0 then return; end if;
 if position('(''lottery_draw'',''lottery_exchange'',''lottery_read'')' in definition)=0 then
  raise exception 'commerce_commit_unexpected_definition';
 end if;
 execute replace(definition,
  '(''lottery_draw'',''lottery_exchange'',''lottery_read'')',
  '(''lottery_draw'',''lottery_exchange'',''lottery_read'',''commerce_purchase'')');
end; $$;
commit;
