"""Local sealed-payload scope and Lua settlement tests. No network calls."""
import ast
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path,PurePosixPath
import subprocess
import tarfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'tmp/benefit_revision_20261021/release_candidate'
sha=lambda raw:hashlib.sha256(raw).hexdigest()
canonical=lambda value:json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


class RevisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan=json.loads((OUT/'plan.json').read_bytes());cls.seal=json.loads((OUT/'seal.json').read_bytes())
        cls.stage=OUT/'local_stage';cls.stage.mkdir(parents=True,exist_ok=True)
        with tarfile.open(OUT/'release.tar.gz','r:gz') as archive:
            members=archive.getmembers();assert len(members)==len(cls.seal['files'])
            for member in members:
                name=PurePosixPath(member.name)
                assert member.isfile() and not name.is_absolute() and '..' not in name.parts and member.name in cls.seal['files']
                raw=archive.extractfile(member).read();assert sha(raw)==cls.seal['files'][member.name]
                target=cls.stage/member.name;assert not target.is_symlink();target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(raw)
        cls.old=OUT/'local_parent';directory=cls.old/'addon/server/bundles'/cls.plan['archive_bundle'];directory.mkdir(parents=True,exist_ok=True)
        parent=json.loads((OUT/'parent_bundle.json').read_bytes());(directory/'bundle.json').write_bytes(canonical(parent))
        for name,value in parent['sources'].items():
            target=directory/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(value.encode())
        tree=ast.parse((Path(__file__).with_name('remote_operator.py')).read_text(encoding='utf-8'))
        allowed={'need','safe','scope'}
        code=ast.Module(body=[node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name in allowed],type_ignores=[])
        cls.env=dict(STAGE=cls.stage,OLD=cls.old,P=copy.deepcopy(cls.plan),PurePosixPath=PurePosixPath,copy=copy,json=json,sha=sha)
        exec(compile(code,'local_remote_scope.py','exec'),cls.env)

    def setUp(self):self.env['P']=copy.deepcopy(self.plan)

    def modified(self,edit):
        data=json.loads((OUT/'bundles'/self.plan['bundle']/'bundle.json').read_bytes());edit(data)
        raw=canonical(data);digest=sha(raw);path=self.stage/'overlay/addon/server/bundles'/digest/'bundle.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
        self.env['P']['bundle']=digest

    def claim(self,digest,track,tier,claimed=False):
        directory=(self.old/'addon/server/bundles'/digest) if digest==self.plan['archive_bundle'] else OUT/'bundles'/digest
        data=json.loads((directory/'bundle.json').read_bytes());now=int(time.time());day=str((now+10800)//86400);week=str(((now+10800)//86400+3)//7)
        period=dict(seconds=1080*60,wins=5,claimed={tier:dict(at=now,has_pass=1)} if claimed else {})
        defaults={row['field_id']:row['default_value'] for row in data['configs']['player_gameplay_stats']['rows']}
        profile=dict(save=dict(archive=dict(benefits=dict(version=1,days={day:copy.deepcopy(period)},weeks={week:copy.deepcopy(period)})),content_inventory={},gameplay_stats=defaults))
        payload=dict(configs=data['configs'],profile=profile,command=dict(id='revision_local_memory',kind='benefit_claim',track=track,tier_id=tier,event_at=now),has_pass=True,server_time=now,seed=1)
        lua=os.environ.get('LUA_EXECUTABLE','C:/Program Files/lua/bin/lua5.1.exe')
        result=subprocess.run([lua,'worker.lua'],cwd=directory,input=canonical(payload),capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,'local Lua worker must finish')
        return json.loads(result.stdout)

    def test_exact_config_only_scope(self):
        self.assertEqual(set(self.env['scope']()),{'bundle','rollback_bundle'})
        parent=json.loads((OUT/'parent_bundle.json').read_bytes());new=json.loads((OUT/'bundles'/self.plan['bundle']/'bundle.json').read_bytes())
        self.assertEqual(new['sources'],parent['sources'],'Every Lua source stays byte-identical')
        self.assertEqual(new['configs']['archive_daily_limits'],parent['configs']['archive_daily_limits'])
        self.assertNotIn('benefit_claim',new['compatible_config_hashes'][self.plan['archive_bundle']]['commands'])

    def test_modified_quota_rejected_even_with_rehashed_bundle(self):
        self.modified(lambda data:data['configs']['archive_daily_limits']['rows'][0].update(limit=999))
        with self.assertRaisesRegex(RuntimeError,'unrelated_bundle_configuration_or_source_changed'):self.env['scope']()

    def test_cross_hash_new_benefit_claim_cannot_be_admitted(self):
        self.modified(lambda data:data['compatible_config_hashes'][self.plan['archive_bundle']]['commands'].append('benefit_claim'))
        with self.assertRaisesRegex(RuntimeError,'unrelated_bundle_configuration_or_source_changed'):self.env['scope']()

    def test_migration_rejected(self):
        self.env['P']['migrations']=['unapproved.sql']
        with self.assertRaisesRegex(RuntimeError,'unexpected_migration'):self.env['scope']()

    def test_revised_rewards_with_real_lua(self):
        cases=[('daily_time','daily_time_150',4,1),('daily_wins','daily_win_3',2,1),('daily_wins','daily_win_4',1,0),('weekly_time','weekly_time_120',4,0),('weekly_time','weekly_time_840',10,1)]
        for track,tier,ordinary,gold in cases:
            with self.subTest(tier=tier):
                result=self.claim(self.plan['bundle'],track,tier);self.assertTrue(result['ok']);inventory=result['content_inventory']
                self.assertEqual(inventory.get('lottery_ticket',0),ordinary);self.assertEqual(inventory.get('special_lottery_ticket',0),gold)

    def test_parent_pending_intent_keeps_original_reward(self):
        result=self.claim(self.plan['archive_bundle'],'daily_time','daily_time_150')
        self.assertTrue(result['ok']);self.assertEqual(result['content_inventory']['special_lottery_ticket'],2)

    def test_claimed_tiers_stay_claimed(self):
        self.assertFalse(self.claim(self.plan['bundle'],'daily_time','daily_time_150',True)['ok'])

    def test_safe_disabled_bundle_blocks_new_claim(self):
        self.assertFalse(self.claim(self.plan['rollback_bundle'],'daily_time','daily_time_150')['ok'])


if __name__=='__main__':unittest.main()
