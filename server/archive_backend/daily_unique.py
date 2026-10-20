"""Exact daily contribution repair and immutable database ownership boundary."""
from __future__ import annotations
import copy
from decimal import Decimal
import hashlib
import json
import re
import uuid
from .unique_points import MAX_INTEGER, integer, catalog as lottery_catalog

MIGRATION='20261019_unique_daily_points_v1'


def encode(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False)


def number(value):
    if isinstance(value,bool) or not isinstance(value,(int,float,Decimal)):
        raise ValueError('daily_unique_stat_invalid')
    result=Decimal(str(value))
    if not result.is_finite() or abs(result)>MAX_INTEGER:
        raise ValueError('daily_unique_stat_invalid')
    return result


def plain(value):
    return int(value) if value==value.to_integral_value() else float(value)


def catalog(bundle):
    rows=[r for r in bundle.configs['archive_daily_items']['rows'] if r.get('enabled') is not False]
    if len(rows)!=12 or len({r['item_id'] for r in rows})!=12:
        raise ValueError('daily_unique_catalog_invalid')
    rates={}
    for row in bundle.configs['lottery_item_definitions']['rows']:
        if row.get('enabled') is False or row.get('item_type')!='积分道具':continue
        quality=row['quality'].lower();rate=integer(row['duplicate_points'])
        if rate<=0 or quality in rates and rates[quality]!=rate:
            raise ValueError('daily_duplicate_rate_conflict')
        rates[quality]=rate
    for row in rows:
        if row['quality'].lower() not in rates or len(row['effect_ids'])!=len(row['effect_values']):
            raise ValueError('daily_unique_catalog_invalid')
    return rows,rates


def preview(profile,bundle):
    rows,rates=catalog(bundle)
    archive=copy.deepcopy(profile['save'].get('archive',{}))
    stats=copy.deepcopy(profile['save'].get('gameplay_stats',{}))
    if not isinstance(archive,dict) or not isinstance(stats,dict):
        raise ValueError('daily_unique_state_invalid')
    inventory=profile['save'].get('content_inventory',{})
    if not isinstance(inventory,dict):raise ValueError('daily_unique_inventory_invalid')
    for item in rows:
        if integer(inventory.get(item['item_id'],0)):
            raise ValueError('daily_unique_dual_inventory_requires_review')
    lottery,aliases=lottery_catalog(bundle)
    for identity in lottery:
        keys=[key for key in inventory if aliases.get(key,key)==identity]
        for key in keys:
            raw=inventory[key]
            if isinstance(raw,bool) or not isinstance(raw,(int,float)) or raw not in (0,1):
                raise ValueError('daily_unique_lottery_inventory_requires_review')
        if sum(inventory[key] for key in keys)>1:
            raise ValueError('daily_unique_lottery_inventory_requires_review')
    daily=archive.get('daily_rewards')
    if 'daily_rewards' not in archive:
        return {'archive':archive,'gameplay_stats':stats,'deltas':{},'details':[],
                'changed_items':0,'converted_points':0,'converted_currency':'shop_points'}
    if not isinstance(daily,dict) or not isinstance(daily.get('item_counts'),dict):
        raise ValueError('daily_unique_state_invalid')
    counts=daily['item_counts'];totals={};excess={};details=[];converted=0
    definitions=bundle.tables['player_gameplay_stats']
    for item in rows:
        identity=item['item_id'];count=integer(counts.get(identity,0))
        for field,raw in zip(item['effect_ids'],item['effect_values']):
            delta=Decimal(str(raw))
            if not delta.is_finite() or delta<=0:raise ValueError('daily_unique_effect_not_reversible')
            totals[field]=totals.get(field,Decimal(0))+count*delta
            if count>1:excess[field]=excess.get(field,Decimal(0))+(count-1)*delta
        if count>1:
            amount=(count-1)*rates[item['quality'].lower()];converted+=amount
            if converted>MAX_INTEGER:raise ValueError('commerce_wallet_limit')
            details.append({'id':identity,'previous_count':count,'count':1,'extra_copies':count-1,
                            'converted_points':amount})
            counts[identity]=1
        elif identity in counts and (isinstance(counts[identity],str) or counts[identity]!=count):
            counts[identity]=count
            details.append({'id':identity,'previous_count':count,'count':count,'extra_copies':0,'converted_points':0})
    deltas={}
    for field,removed in sorted(excess.items()):
        spec=definitions.get(field)
        # A bounded field may have saturated in the past. Loyalty progress has
        # downstream tier rewards. Neither can be inverted from counts alone.
        if not spec or spec.get('max_value') is not None or field.startswith('starjoy_'):
            raise ValueError('daily_unique_effect_requires_review:'+field)
        before=number(stats.get(field));default=number(spec.get('default_value',0))
        if before-default<totals[field]:raise ValueError('daily_unique_effect_budget_insufficient:'+field)
        after=before-removed
        if spec.get('min_value') is not None and after<number(spec['min_value']):
            raise ValueError('daily_unique_stat_below_min:'+field)
        if spec.get('storage_type')=='integer' and after!=after.to_integral_value():
            raise ValueError('daily_unique_stat_not_integer:'+field)
        stats[field]=plain(after);deltas[field]=plain(-removed)
    if converted:
        commerce=archive.setdefault('commerce',{})
        if not isinstance(commerce,dict):raise ValueError('commerce_wallet_invalid')
        wallet=commerce.setdefault('balances',{})
        if not isinstance(wallet,dict):raise ValueError('commerce_wallet_invalid')
        before=wallet.get('shop_points',0)
        if isinstance(before,str):raise ValueError('commerce_wallet_invalid')
        before=integer(before)
        if before+converted>MAX_INTEGER:raise ValueError('commerce_wallet_limit')
        wallet['shop_points']=before+converted
    return {'archive':archive,'gameplay_stats':stats,'deltas':deltas,'details':details,
            'changed_items':len(details),'converted_points':converted,'converted_currency':'shop_points'}


def plans(conn,bundle,accounts=None):
    records=conn.execute('''SELECT p.account_id,p.profile_revision,a.archive,a.content_inventory,
        to_jsonb(s)-'player_id'-'created_at'-'updated_at'
        FROM public.survival_players p JOIN public.player_archive_state a USING(account_id)
        LEFT JOIN public.player_gameplay_stats s ON s.player_id=p.account_id
        WHERE (%s::text[] IS NULL OR p.account_id=ANY(%s::text[])) ORDER BY p.account_id''',(accounts,accounts)).fetchall()
    result=[]
    for account,revision,archive,inventory,stats in records:
        profile={'account_id':account,'revision':revision,'save':{
            'archive':archive,'content_inventory':inventory,'gameplay_stats':stats or {}}}
        projected=preview(profile,bundle)
        if projected['changed_items']:result.append({'before':profile,**projected})
    # Review approves the repair itself, not a frozen account snapshot. A
    # legitimate checkpoint, wallet credit or other-source stat increase can
    # arrive before apply. Re-read and back up that latest state below; retain
    # the exact quantity/conversion/deduction authorization across those writes.
    reviewed=[]
    for plan in result:
        reviewed.append({
            'account_hash':hashlib.sha256(plan['before']['account_id'].encode()).hexdigest(),
            'items':sorted(({key:detail[key] for key in
                ('id','previous_count','count','extra_copies','converted_points')}
                for detail in plan['details']),key=lambda row:row['id']),
            'converted_points':plan['converted_points'],
            'deltas':plan['deltas'],
        })
    reviewed.sort(key=lambda row:row['account_hash'])
    digest=hashlib.sha256(encode({'migration':MIGRATION,'config_hash':bundle.hash,
                                'repairs':reviewed}).encode()).hexdigest()
    return result,digest


def backup_ddl():
    return '''CREATE TABLE IF NOT EXISTS public.archive_daily_unique_backups (
        run_id uuid NOT NULL,account_id text NOT NULL REFERENCES public.survival_players(account_id),
        migration_id text NOT NULL CHECK(migration_id='20261019_unique_daily_points_v1'),
        config_hash text NOT NULL CHECK(config_hash ~ '^[0-9a-f]{64}$'),
        before_revision bigint NOT NULL,after_revision bigint NOT NULL CHECK(after_revision=before_revision+1),
        before_archive jsonb NOT NULL,after_archive jsonb NOT NULL,
        before_stats jsonb NOT NULL,after_stats jsonb NOT NULL,inventory jsonb NOT NULL,
        converted_points bigint NOT NULL CHECK(converted_points BETWEEN 0 AND 9007199254740991),
        details jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),rolled_back_at timestamptz,
        PRIMARY KEY(run_id,account_id));
        ALTER TABLE public.archive_daily_unique_backups ENABLE ROW LEVEL SECURITY;
        REVOKE ALL ON public.archive_daily_unique_backups FROM PUBLIC,anon,authenticated,service_role,goufayu_app;'''


def _write_stats(conn,account,stats,fields):
    for field in sorted(fields):
        if not re.fullmatch('[a-z][a-z0-9_]*',field):raise ValueError('daily_unique_field_invalid')
        conn.execute('UPDATE public.player_gameplay_stats SET "'+field+'"=%s WHERE player_id=%s',(stats[field],account))


def repair(conn,bundle,expected_digest,accounts=None):
    candidates,digest=plans(conn,bundle,accounts)
    if digest!=expected_digest:raise ValueError('daily_unique_plan_changed_preview_again')
    run=str(uuid.uuid4())
    for plan in candidates:
        before=plan['before'];account=before['account_id'];saved=before['save']
        actual=conn.execute("SELECT to_jsonb(s)-'player_id'-'created_at'-'updated_at' FROM public.player_gameplay_stats s WHERE player_id=%s FOR UPDATE",(account,)).fetchone()
        revision=conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s FOR UPDATE',(account,)).fetchone()
        state=conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s FOR UPDATE',(account,)).fetchone()
        if actual!=(saved['gameplay_stats'],) or revision!=(before['revision'],) or state!=(saved['archive'],saved['content_inventory']):
            raise ValueError('daily_unique_state_changed_preview_again')
        conn.execute('''INSERT INTO public.archive_daily_unique_backups
            (run_id,account_id,migration_id,config_hash,before_revision,after_revision,before_archive,after_archive,
             before_stats,after_stats,inventory,converted_points,details)
            VALUES(%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s::jsonb,%s::jsonb,%s,%s::jsonb)''',
            (run,account,MIGRATION,bundle.hash,before['revision'],before['revision']+1,
             encode(saved['archive']),encode(plan['archive']),encode(saved['gameplay_stats']),encode(plan['gameplay_stats']),
             encode(saved['content_inventory']),plan['converted_points'],encode(plan['details'])))
        _write_stats(conn,account,plan['gameplay_stats'],plan['deltas'])
        conn.execute('UPDATE public.player_archive_state SET archive=%s::jsonb WHERE account_id=%s',(encode(plan['archive']),account))
        conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=%s',(account,))
    return {'run_id':run,'changed_accounts':len(candidates),'changed_items':sum(p['changed_items'] for p in candidates),
            'converted_points':sum(p['converted_points'] for p in candidates),'plan_digest':digest}


def rollback(conn,run):
    rows=conn.execute('''SELECT account_id,after_revision,before_archive,after_archive,before_stats,after_stats,inventory
        FROM public.archive_daily_unique_backups WHERE run_id=%s AND migration_id=%s AND rolled_back_at IS NULL ORDER BY account_id''',(run,MIGRATION)).fetchall()
    for account,revision,before_archive,after_archive,before_stats,after_stats,inventory in rows:
        actual=conn.execute("SELECT to_jsonb(s)-'player_id'-'created_at'-'updated_at' FROM public.player_gameplay_stats s WHERE player_id=%s FOR UPDATE",(account,)).fetchone()
        rev=conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s FOR UPDATE',(account,)).fetchone()
        state=conn.execute('SELECT archive,content_inventory FROM public.player_archive_state WHERE account_id=%s FOR UPDATE',(account,)).fetchone()
        if actual!=(after_stats,) or rev!=(revision,) or state!=(after_archive,inventory):
            raise ValueError('daily_unique_rollback_refused_account_changed')
        fields={k for k in before_stats if before_stats[k]!=after_stats.get(k)}
        _write_stats(conn,account,before_stats,fields)
        conn.execute('UPDATE public.player_archive_state SET archive=%s::jsonb WHERE account_id=%s',(encode(before_archive),account))
        conn.execute('UPDATE public.survival_players SET profile_revision=profile_revision+1,updated_at=now() WHERE account_id=%s',(account,))
        conn.execute('UPDATE public.archive_daily_unique_backups SET rolled_back_at=now() WHERE run_id=%s AND account_id=%s',(run,account))
    return {'run_id':run,'rolled_back_accounts':len(rows)}


def render_constraint_sql(bundle):
    daily,_=catalog(bundle);lottery,aliases=lottery_catalog(bundle)
    groups={identity:sorted([identity]+[key for key,target in aliases.items() if target==identity]) for identity in lottery}
    payload=encode({'daily':sorted(r['item_id'] for r in daily),'lottery':groups})
    # The known IDs come only from the reviewed immutable bundle, not a caller.
    if "'" in payload:raise ValueError('daily_unique_constraint_id_invalid')
    return "-- Unique points CHECK whitelist from bundle "+bundle.hash+"\n"+'''
CREATE OR REPLACE FUNCTION public.archive_unique_points_20261019_valid(p_archive jsonb,p_inventory jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public,pg_temp AS $function$
DECLARE rules constant jsonb := 'PAYLOAD'::jsonb;
 counts jsonb;identity text;group_row record;raw jsonb;total numeric;
BEGIN
 IF jsonb_typeof(p_archive) IS DISTINCT FROM 'object' OR jsonb_typeof(p_inventory) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 IF p_archive ? 'daily_rewards' AND jsonb_typeof(p_archive->'daily_rewards') IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 counts:=coalesce(p_archive->'daily_rewards'->'item_counts','{}'::jsonb);
 IF jsonb_typeof(counts) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 FOR identity IN SELECT jsonb_array_elements_text(rules->'daily') LOOP
  raw:=counts->identity;
  IF raw IS NOT NULL THEN
   IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
   IF (raw#>>'{}')::numeric NOT IN (0,1) THEN RETURN false; END IF;
  END IF;
  -- Daily effects are granted only from archive.daily_rewards.item_counts.
  -- A second positive copy in content_inventory has no legitimate writer.
  raw:=p_inventory->identity;
  IF raw IS NOT NULL THEN
   IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
   IF (raw#>>'{}')::numeric<>0 THEN RETURN false; END IF;
  END IF;
 END LOOP;
 FOR group_row IN SELECT * FROM jsonb_each(rules->'lottery') LOOP
  total:=0;
  FOR identity IN SELECT jsonb_array_elements_text(group_row.value) LOOP
   raw:=p_inventory->identity;
   IF raw IS NOT NULL THEN
    IF jsonb_typeof(raw)<>'number' THEN RETURN false; END IF;
    IF (raw#>>'{}')::numeric NOT IN (0,1) THEN RETURN false; END IF;
    total:=total+(raw#>>'{}')::numeric;
   END IF;
  END LOOP;
  IF total>1 THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END;
$function$;
REVOKE ALL ON FUNCTION public.archive_unique_points_20261019_valid(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role,goufayu_app;
ALTER TABLE public.player_archive_state DROP CONSTRAINT IF EXISTS archive_unique_points_20261019_check;
ALTER TABLE public.player_archive_state ADD CONSTRAINT archive_unique_points_20261019_check
 CHECK(public.archive_unique_points_20261019_valid(archive,content_inventory)) NOT VALID;
ALTER TABLE public.player_archive_state VALIDATE CONSTRAINT archive_unique_points_20261019_check;
'''.replace('PAYLOAD',payload)
