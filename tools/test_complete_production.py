"""Pure transformation guards plus optional real authenticated0104 review/probes."""
from pathlib import Path
import collections
import copy
import importlib.util
import tempfile
import unittest

spec=importlib.util.spec_from_file_location("complete_production",Path(__file__).parent/"complete_delivery_release_20261103/production.py")
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)


def fixtures():
    # Independent small known-shape fixtures. The real policy is additionally
    # tested below when the authenticated external0104 baseline is available.
    parent={path:b"return {enabled=true}\n" for path in m.CONSTANTS}
    source={path:b"return {enabled=false}\n" for path in m.CONSTANTS}
    parent["addoninfo.txt"]=b'"AddonInfo"\n{\n "maps" "ws4_entry"\n "ws4_entry" { "MaxPlayers" "4" }\n "template_map" { "MaxPlayers" "4" }\n}\n'
    source["addoninfo.txt"]=b'"AddonInfo"\n{\n "maps" "template_map"\n "ws4_entry" { "MaxPlayers" "1" }\n "template_map" { "MaxPlayers" "4" }\n "ws4_lobby" { "MaxPlayers" "1" }\n}\n'
    parent["scripts/vscripts/addon_game_mode_client.lua"]=b"-- original native entry suffix\nreturn {}\n"
    source["scripts/vscripts/addon_game_mode_client.lua"]=(b'local lobby=require("systems/hosted_lobby_client")\nActivate=function()lobby.init()end\nActivateClient=Activate\n'+parent["scripts/vscripts/addon_game_mode_client.lua"])
    current='local config = require("config/test_access")\nlocal M={}\nlocal MAX_ALLOWED_ACCOUNTS = 5\nfunction M.init()\n    initialized = true\n    if not M.enabled() then return true end\nend\nfunction M.allowed(player_id)\n    local getter = true\nend\nreturn M\n'
    old=current.replace('local M={}\n','local offline_onboarding = require("debug/offline_onboarding_test")\nlocal M={}\n')
    old=old.replace('    initialized = true\n','    initialized = true\n    -- Latch the explicit preview choice before an online match can mutate a\n    -- server convar. The helper never loads or enables the offline provider.\n    offline_onboarding.requested()\n')
    old=old.replace('    local getter = true\n','    if offline_onboarding.requested() then\n        if not offline_onboarding.is_human(player_id) then\n            return false, "test_access_player_invalid"\n        end\n        return true\n    end\n    local getter = true\n')
    source[m.PROFILE],parent[m.PROFILE]=current.encode(),old.encode()
    access=b'return {enabled=true,allowed_steamids={"76561198000000001","76561198000000002","76561198000000003","76561198000000004","76561198000000005"}}\n'
    source[m.ACCESS]=parent[m.ACCESS]=access
    return source,parent


class ProductionGuards(unittest.TestCase):
    def test_four_constant_configs_preserve_exact_parent_bytes(self):
        source,parent=fixtures();parent[m.CONSTANTS[0]]=parent[m.CONSTANTS[0]].replace(b'\n',b'\r\n')
        target,_=m.transform_overrides(source,parent)
        for path in m.CONSTANTS:self.assertEqual(target[path],parent[path])

    def test_entry_four_players_and_new_lobby_all_survive(self):
        source,parent=fixtures();target,_=m.transform_overrides(source,parent)
        self.assertIn(b'"maps" "ws4_entry"',target['addoninfo.txt'])
        self.assertIn(b'"ws4_entry" { "MaxPlayers" "4" }',target['addoninfo.txt'])
        self.assertIn(b'"ws4_lobby" { "MaxPlayers" "1" }',target['addoninfo.txt'])
        self.assertEqual(target['scripts/vscripts/addon_game_mode_client.lua'],source['scripts/vscripts/addon_game_mode_client.lua'])

    def test_removed_dependency_is_not_resurrected(self):
        source,parent=fixtures();target,_=m.transform_overrides(source,parent)
        self.assertNotIn(b'offline_onboarding',target[m.PROFILE]);self.assertEqual(target[m.PROFILE],source[m.PROFILE])

    def test_unreviewed_admission_change_or_bypass_is_rejected(self):
        for extra in (b'\nfunction M.unrestricted()return true end\n',b'\nlocal preview=true\n'):
            source,parent=fixtures();source[m.PROFILE]+=extra
            with self.assertRaisesRegex(ValueError,'admission_logic_changed'):
                m.transform_overrides(source,parent)

    def test_roster_replacement_or_duplicate_and_unknown_map_fail(self):
        source,parent=fixtures();source[m.ACCESS]=source[m.ACCESS].replace(b'00000005',b'00000006')
        with self.assertRaisesRegex(ValueError,'roster_changed'):m.transform_overrides(source,parent)
        source,parent=fixtures();source['addoninfo.txt']=source['addoninfo.txt'].replace(b'"maps" "template_map"',b'"maps" "other_map"')
        with self.assertRaisesRegex(ValueError,'primary_map'):m.transform_overrides(source,parent)

    def test_old_return_only_client_cannot_overwrite_new_feature(self):
        source,parent=fixtures();source['scripts/vscripts/addon_game_mode_client.lua']=parent['scripts/vscripts/addon_game_mode_client.lua']
        with self.assertRaisesRegex(ValueError,'hosted_lobby'):m.transform_overrides(source,parent)

    def test_sources_are_exact_commits_and_relative_prepare_is_refused(self):
        for value in ('HEAD','main','1f160c3a',None):
            with self.assertRaises(ValueError):m.immutable(value)
        with self.assertRaisesRegex(ValueError,'absolute_external'):
            m.prepare({},Path('relative'),Path('lua'),Path('prometheus'))


class Actual0104Integration(unittest.TestCase):
    def test_authentic_parent_and_actual_immutable_source_behavior(self):
        if not m.pending.PARENT_MANIFEST.is_file():self.skipTest('requires retained authenticated0104 external baseline')
        rev='1f160c3a848e57db81f5b9498cc0d59b733fc501';counts=collections.Counter()
        baseline=m.pending._read_json(m.pending.BASELINE,m.pending.BASELINE_SHA256)
        manifest=m.pending._read_json(m.pending.PARENT_MANIFEST,baseline['parent_manifest_sha256'])
        rows={r['path']:r for r in manifest['files']}
        source={p:m.git_blob(m.ROOT,rev,p,counts) for p in (*m.OVERRIDES,m.ACCESS)}
        parent={p:(m.pending.PARENT_MANIFEST.parent/p).read_bytes() for p in source}
        for path,raw in parent.items():self.assertEqual(m.sha(raw),rows[path]['sha256'])
        target,reviews=m.transform_overrides(source,parent);self.assertEqual(len(reviews),7)
        ctx=dict(source=source,parent=parent,operator=rev,counts=counts)
        with tempfile.TemporaryDirectory(prefix='production-policy-probe-')as folder:
            dest=Path(folder);path=dest/'source_export'/m.PROFILE;path.parent.mkdir(parents=True);path.write_bytes(target[m.PROFILE])
            proof=m.run_probes(ctx,dest,Path('C:/Program Files/lua/bin/lua5.1.exe'))
            self.assertTrue(proof['five_account_engine_io_simulation'])
            self.assertTrue(proof['hosted_lobby_and_original_entry_engine_io_simulation'])
            self.assertFalse(proof['actual_steam_login'])


if __name__=='__main__':unittest.main()
