from pathlib import Path
import hashlib,json,sys,subprocess,datetime
root=Path.cwd(); out=root/'output/purchase_refresh_20261015';out.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(root/'output/video_shop_20261015/deps'))
from lupa.lua51 import LuaRuntime
lua_tests=[
 'tools/test_payment_reward_refresh_chain.lua',
 'tools/test_payment_profile_refresh.lua',
 'tools/test_lottery_purchase_refresh.lua',
 'tools/test_purchase_inventory_refresh.lua',
 'scripts/vscripts/tests/test_payment_service.lua',
 'scripts/vscripts/tests/test_lottery_http_service.lua',
 'scripts/vscripts/tests/test_player_profile_load_retry.lua',
 'scripts/vscripts/tests/test_player_profile_modes.lua',
 'scripts/vscripts/tests/test_profile_commerce_reads.lua',
 'scripts/vscripts/tests/test_match_inventory.lua',
 'scripts/vscripts/tests/test_payment_stat_projection.lua',
 'scripts/vscripts/tests/test_resource_opening_wood.lua']
js_tests=[
 ['node','tools/test_payment_closed_refresh.cjs'],
 ['node','tools/test_payment_original_shell.cjs'],
 ['node','tools/test_payment_ui.cjs'],
 ['node','tools/test_payment_catalog_cache.cjs'],
 ['node','tools/test_monthly_pass_checkout.cjs'],
 ['node','--test','tools/tests/ucoin_checkout.test.cjs'],
 ['node','tools/test_commerce_wallet.cjs'],
 ['node','tools/purple_ui_10h/checkout_verify.cjs']]
records=[]
for path in lua_tests:
 logs=[]
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.globals().print=lambda *args:logs.append(' '.join(map(str,args)))
 text=(root/path).read_text(encoding='utf-8-sig')
 lua.execute(text)
 unexpected=[line for line in logs if '[EventBus] handler error' in line
   and 'expected_writer_failure' not in line and 'expected_failure_after_commit' not in line]
 assert not unexpected,(path,unexpected)
 records.append(dict(path=path,passed=True,sha256=hashlib.sha256((root/path).read_bytes()).hexdigest(),log=logs))
 print('PASS '+path,flush=True)
for command in js_tests:
 run=subprocess.run(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
 log=run.stdout.decode('utf8',errors='replace')
 assert run.returncode==0,(command,log)
 records.append(dict(command=command,passed=True,log=log.splitlines()))
 print('PASS '+' '.join(command),flush=True)
sources=['panorama/src/scripts/custom_game/payment_test.js',
 'scripts/vscripts/systems/lottery_http_service.lua','scripts/vscripts/systems/payment_service.lua',
 'scripts/vscripts/systems/player_profile_service.lua','scripts/vscripts/systems/content_inventory_service.lua']
report=dict(at=datetime.datetime.now(datetime.timezone.utc).isoformat(),passed=True,
 scope='Production controllers and real Lua service modules; engine/transports are isolated fixtures; no real payment/account/network requests.',
 checks=records,sources={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in sources})
(out/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('PURCHASE_REFRESH_VALIDATION_PASS '+str(len(records)),flush=True)
