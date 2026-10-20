"""Reviewed repair semantics survive legitimate progress; fresh writes remain locked."""
import copy
import json
from pathlib import Path
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'server'))
from archive_backend.bundle import Bundle
from archive_backend.daily_unique import plans,repair


class Result:
    def __init__(self,rows=()):self.rows=rows
    def fetchall(self):return copy.deepcopy(self.rows)
    def fetchone(self):return copy.deepcopy(self.rows[0]) if self.rows else None


class Connection:
    """Adapter that exposes latest snapshots and records guarded writes."""
    def __init__(self,profiles):
        self.profiles=copy.deepcopy(profiles);self.backups=[];self.writes=[];self.on_lock=None
    def execute(self,sql,params=()):
        if 'FROM public.survival_players p JOIN public.player_archive_state a' in sql:
            selected=params[0]
            return Result([(identity,row['revision'],row['save']['archive'],row['save']['content_inventory'],row['save']['gameplay_stats'])
                for identity,row in sorted(self.profiles.items()) if selected is None or identity in selected])
        if "SELECT to_jsonb(s)-'player_id'" in sql:
            if self.on_lock:
                callback=self.on_lock;self.on_lock=None;callback(self.profiles[params[0]])
            return Result([(self.profiles[params[0]]['save']['gameplay_stats'],)])
        if 'SELECT profile_revision' in sql:return Result([(self.profiles[params[0]]['revision'],)])
        if 'SELECT archive,content_inventory' in sql:
            save=self.profiles[params[0]]['save'];return Result([(save['archive'],save['content_inventory'])])
        if 'INSERT INTO public.archive_daily_unique_backups' in sql:
            self.backups.append(copy.deepcopy(params));self.writes.append(sql);return Result()
        if 'UPDATE public.player_gameplay_stats' in sql:
            field=re.search(r'SET "([a-z0-9_]+)"',sql).group(1)
            self.profiles[params[1]]['save']['gameplay_stats'][field]=params[0]
            self.writes.append(sql);return Result()
        if 'UPDATE public.player_archive_state' in sql:
            self.profiles[params[1]]['save']['archive']=json.loads(params[0]);self.writes.append(sql);return Result()
        if 'UPDATE public.survival_players' in sql:
            self.profiles[params[0]]['revision']+=1;self.writes.append(sql);return Result()
        raise AssertionError(sql)


class DailyPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base=ROOT/'server/bundles'
        cls.bundle=Bundle(base/json.loads((base/'current.json').read_text('utf-8'))['hash'])

    def setUp(self):
        self.identity='private-synthetic-account-a'
        self.conn=Connection({self.identity:{'account_id':self.identity,'revision':5,'save':{
            'archive':{'daily_rewards':{'first_day':20000,'claimed':{'20000':True},'count':1,
                'item_counts':{'daily_growth_gem':3}},'commerce':{'balances':{'shop_points':100,'u_coin':9}},
                'online':{'cursors':{'test-session':60}}},
            'content_inventory':{'material_synthesis_gem':7},
            'gameplay_stats':{'hero_attack_per_second':10,'initial_gold':17}}}})

    def test_new_progress_and_other_source_growth_keep_authorization_and_latest_full_backup(self):
        _,approved=plans(self.conn,self.bundle)
        latest=self.conn.profiles[self.identity];latest['revision']+=3
        save=latest['save'];save['archive']['online']['cursors']['test-session']=120
        save['archive']['endless_score']=321
        save['archive']['commerce']['balances']['shop_points']+=11
        save['gameplay_stats']['hero_attack_per_second']+=5
        save['gameplay_stats']['initial_gold']+=8
        save['content_inventory']['material_synthesis_gem']+=2
        before=copy.deepcopy(latest)
        _,current=plans(self.conn,self.bundle)
        self.assertEqual(current,approved)
        result=repair(self.conn,self.bundle,approved)
        self.assertEqual(result['converted_points'],50)
        saved=self.conn.profiles[self.identity]
        self.assertEqual(saved['revision'],before['revision']+1)
        self.assertEqual(saved['save']['gameplay_stats'],{'hero_attack_per_second':13,'initial_gold':25})
        self.assertEqual(saved['save']['archive']['commerce']['balances'],{'shop_points':161,'u_coin':9})
        self.assertEqual(saved['save']['archive']['online'],before['save']['archive']['online'])
        self.assertEqual(saved['save']['archive']['endless_score'],321)
        self.assertEqual(saved['save']['content_inventory'],before['save']['content_inventory'])
        self.assertEqual(json.loads(self.conn.backups[0][6]),before['save']['archive'])
        self.assertEqual(json.loads(self.conn.backups[0][8]),before['save']['gameplay_stats'])

    def test_review_changes_for_quantity_effect_rate_rules_or_account_and_old_plan_is_refused(self):
        for kind in ('quantity','effect','rate','rules','account'):
            with self.subTest(kind=kind):
                conn=Connection(self.conn.profiles);bundle=copy.deepcopy(self.bundle)
                _,approved=plans(conn,bundle)
                if kind=='quantity':
                    conn.profiles[self.identity]['save']['archive']['daily_rewards']['item_counts']['daily_growth_gem']=4
                elif kind=='effect':
                    row=next(row for row in bundle.configs['archive_daily_items']['rows'] if row['item_id']=='daily_growth_gem')
                    row['effect_values']=['2']
                elif kind=='rate':
                    for row in bundle.configs['lottery_item_definitions']['rows']:
                        if row.get('item_type')=='积分道具' and row.get('quality','').lower()=='r':row['duplicate_points']=30
                elif kind=='rules':bundle.hash='f'*64
                else:
                    conn.profiles['private-synthetic-account-b']=conn.profiles.pop(self.identity)
                    conn.profiles['private-synthetic-account-b']['account_id']='private-synthetic-account-b'
                _,changed=plans(conn,bundle)
                self.assertNotEqual(changed,approved)
                before=copy.deepcopy(conn.profiles)
                with self.assertRaisesRegex(ValueError,'daily_unique_plan_changed_preview_again'):
                    repair(conn,bundle,approved)
                self.assertFalse(conn.writes);self.assertFalse(conn.backups);self.assertEqual(conn.profiles,before)

    def test_concurrent_change_after_latest_read_still_aborts_before_any_repair_write(self):
        _,approved=plans(self.conn,self.bundle)
        def change(profile):
            profile['revision']+=1;profile['save']['gameplay_stats']['hero_attack_per_second']+=1
        self.conn.on_lock=change
        with self.assertRaisesRegex(ValueError,'daily_unique_state_changed_preview_again'):
            repair(self.conn,self.bundle,approved)
        self.assertFalse(self.conn.writes);self.assertFalse(self.conn.backups)
        self.assertEqual(self.conn.profiles[self.identity]['save']['gameplay_stats']['hero_attack_per_second'],11)

    def test_progress_cannot_bypass_budget_or_wallet_bounds(self):
        for invalid in ('budget','wallet'):
            with self.subTest(invalid=invalid):
                conn=Connection(self.conn.profiles);_,approved=plans(conn,self.bundle)
                if invalid=='budget':conn.profiles[self.identity]['save']['gameplay_stats']['hero_attack_per_second']=2
                else:conn.profiles[self.identity]['save']['archive']['commerce']['balances']['shop_points']=9007199254740990
                with self.assertRaises(ValueError):repair(conn,self.bundle,approved)
                self.assertFalse(conn.writes)


if __name__=='__main__':unittest.main(verbosity=2)
