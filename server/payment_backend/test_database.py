"""Real PostgreSQL payment tests. All fixture writes roll back, including grants."""
import json
from pathlib import Path
import unittest

ACCOUNT='f7'*32
OTHER='f8'*32
ORDER='WX'+'1'*30


def run_checks(conn,defaults):
    # Caller controls one transaction and MUST roll it back on success/failure.
    assert not conn.execute('SELECT 1 FROM public.survival_players WHERE account_id IN (%s,%s)',(ACCOUNT,OTHER)).fetchone()
    for account in (ACCOUNT,OTHER):
        conn.execute('SELECT public.ensure_player_gameplay_stats(%s,%s::jsonb)',(account,json.dumps(defaults)))
        conn.execute('SELECT public.match_profile_login(%s,%s,%s,%s::jsonb)',(account,'payment_fixture_session','standard',json.dumps(defaults)))
    conn.execute("INSERT INTO public.player_archive_state(account_id,archive,content_inventory) VALUES(%s,'{\"keep_archive\":123}','{\"keep_item\":3}')",(ACCOUNT,))
    call=lambda name,args=():conn.execute('SELECT payments.'+name+'('+','.join(['%s']*len(args))+')',args).fetchone()[0]
    assert call('create_order',(ACCOUNT,'missing_session',ORDER))['error']=='match_session_missing'
    first=call('create_order',(ACCOUNT,'payment_fixture_session',ORDER))
    second=call('create_order',(ACCOUNT,'payment_fixture_session','WX'+'2'*30))
    assert first['order_id']==second['order_id']==ORDER
    assert call('create_order',(OTHER,'payment_fixture_session','WX'+'3'*30))['account_id']==OTHER
    before=conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s',(ACCOUNT,)).fetchone()[0]
    with conn.transaction(force_rollback=True):
        try:call('deliver',(ORDER,'4200000000000000000000000001',1,'wx164e25a570fb636a','1117928493'))
        except Exception:pass
        else:raise AssertionError('wrong amount accepted')
    assert call('get_order',(ORDER,))['state']=='created'
    args=(ORDER,'4200000000000000000000000001',10,'wx164e25a570fb636a','1117928493')
    assert call('deliver',args)['state']=='delivered'
    assert call('deliver',args)['state']=='delivered'
    saved=conn.execute('SELECT content_inventory,archive FROM public.player_archive_state WHERE account_id=%s',(ACCOUNT,)).fetchone()
    assert saved==({'lottery_monkey_king':1,'keep_item':3},{'keep_archive':123})
    after=conn.execute('SELECT profile_revision FROM public.survival_players WHERE account_id=%s',(ACCOUNT,)).fetchone()[0]
    assert after==before+1
    stats=conn.execute('SELECT to_jsonb(s) FROM public.player_gameplay_stats s WHERE player_id=%s',(ACCOUNT,)).fetchone()[0]
    expected={'hero_attack_armor_reduction':10,'hero_basic_attack_growth':10,'hero_attribute_growth':20,
        'hero_attack_bonus_pct':10,'hero_final_damage_bonus_pct':10,'map_level':1,
        'wall_initial_health':100,'wall_health_regen_per_second':5}
    for key,delta in expected.items():assert stats[key]==defaults[key]+delta,(key,stats[key])
    assert call('create_order',(ACCOUNT,'payment_fixture_session','WX'+'4'*30))['error']=='already_owned'
    conn.execute("INSERT INTO public.player_archive_state(account_id,content_inventory) VALUES(%s,'{\"lottery_monkey_king\":1}')",(OTHER,))
    review=call('deliver',('WX'+'3'*30,'4200000000000000000000000002',10,'wx164e25a570fb636a','1117928493'))
    assert review['state']=='paid_review' and review['granted_at'] is None
    assert conn.execute('SELECT map_level FROM public.player_gameplay_stats WHERE player_id=%s',(OTHER,)).fetchone()[0]==defaults['map_level']
    for role in ('goufayu_app','goufayu_payment'):
        assert not conn.execute("SELECT has_table_privilege(%s,'payments.orders','SELECT,INSERT,UPDATE,DELETE')",(role,)).fetchone()[0]
    assert not conn.execute("SELECT has_schema_privilege('goufayu_app','payments','USAGE')").fetchone()[0]
    return {'passed':True,'checks':12,'fixture_writes':'rolled_back_by_caller'}
