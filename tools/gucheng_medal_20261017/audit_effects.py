"""Read-only V1 medal settlement and real combat-consumer audit; synthetic accounts only."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'output/video_shop_20261015/deps'), str(ROOT / 'server')]
from lupa.lua51 import LuaRuntime
from payment_backend.csv_catalog import build, SOURCES
from payment_backend.commerce_bundles import compile_commerce

package = build(ROOT)
reference = {name: (ROOT / 'data/csv' / name).read_text(encoding='utf-8-sig') for name in SOURCES}
catalog = compile_commerce(package['commerce_tables'], reference, package['tables']['payment_categories'])
lua = LuaRuntime(unpack_returned_tuples=True)

def convert(value):
    if isinstance(value, dict):
        return lua.table_from({k: convert(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([convert(v) for v in value])
    return value

lua.globals().REVIEWED_COMMERCE = convert(dict(rows=catalog['products'], by_id={p['sku']: p for p in catalog['products']}))
# Reuse only the existing engine-double setup, not the unrelated broad audit cases.
bootstrap = (ROOT / 'scripts/vscripts/tests/test_reward_effect_audit.lua').read_text(encoding='utf-8').split("check('resource_per_second'", 1)[0]
specific = (Path(__file__).with_name('audit_effects.lua')).read_text(encoding='utf-8')
lua.execute(bootstrap + '\n' + specific)
results = json.loads(lua.eval('require("core/json_encoder").encode')(lua.globals().GUCHENG_MEDAL_RESULTS))
failed = [r for r in results if not r['ok']]
out = ROOT / 'output/gucheng_medal_20261017'
out.mkdir(parents=True, exist_ok=True)
paths = ['scripts/vscripts/config/generated/archive_vip_rewards.lua',
         'scripts/vscripts/systems/archive_vip_rewards.lua',
         'scripts/vscripts/systems/commerce_settlement.lua',
         'scripts/vscripts/systems/permanent_reward_effect_service.lua',
         'scripts/vscripts/systems/building_upgrade_system.lua',
         'scripts/vscripts/systems/tower_attack_critical.lua',
         'scripts/vscripts/systems/hero_combat_stat_service.lua',
         'scripts/vscripts/modifiers/modifier_weapon_stat_projection.lua',
         'scripts/vscripts/combat/damage_filter_service.lua']
report = dict(status='FAIL' if failed else 'PASS', reward_id='vip_medal_01', results=results,
              scope='Real local Lua 5.1 reducers, formal CSV-compiled commerce catalog, real gameplay consumers; synthetic engine doubles and accounts. No network, deployment or game client.',
              source_sha256={p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths})
(out / 'effect_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(dict(status=report['status'], cases=len(results), failed=[r['name'] for r in failed]), ensure_ascii=False))
raise SystemExit(bool(failed))
