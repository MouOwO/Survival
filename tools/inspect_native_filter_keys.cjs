'use strict';
// Explicit synchronous, paused Tools probe. The original native filter is
// restored before the command returns; no gameplay unit or service is replaced.
const fs = require('node:fs');
const { connect } = require('./map_c6/console-session.cjs');
(async () => {
  const session = await connect({ port: 29001, timeoutMs: 10000, historyTimeoutMs: 15000 });
  const code = `
assert(IsInToolsMode() and GameRules:IsGamePaused(), "native filter observation requires paused Tools match")
local original=assert(package.loaded["combat/damage_filter_service"])
local mode=GameRules:GetGameModeEntity()
mode:SetDamageFilter(function(context,keys)
  local attacker=EntIndexToHScript(tonumber(keys.entindex_attacker_const) or -1)
  if attacker and attacker.survival_large_attack_native_capture then
    local names={} for name in pairs(keys) do names[#names+1]=tostring(name) end table.sort(names)
    print("[NATIVE_FILTER_RAW] category_const="..tostring(keys.damage_category_const).." category="..tostring(keys.damage_category).." inflictor="..tostring(keys.entindex_inflictor_const).." damage="..tostring(keys.damage).." keys="..table.concat(names,","))
  end
  return original._filter_for_test(context,keys)
end,original)
local ok,result=pcall(function()
  package.loaded["tests/manual_large_attack_native"]=nil
  return require("tests/manual_large_attack_native").run()
end)
mode:SetDamageFilter(original._filter_for_test,original)
print("[NATIVE_FILTER_OBSERVER] restored=true ok="..tostring(ok).." result="..tostring(result))
print("NATIVE_FILTER_OBSERVATION_COMPLETE")`;
  try {
    await session.send([{ name: 'dota_run_lua', arguments: { code } }], 'NATIVE_FILTER_OBSERVATION_COMPLETE');
    fs.writeFileSync('output/native_filter_keys_live.log', session.rawOutput);
    console.log(session.rawOutput.split(/\r?\n/).filter(line => /NATIVE_FILTER_RAW|NATIVE_FILTER_OBSERVER|LARGE_ATTACK_NATIVE_DONE/.test(line)).join('\n'));
  } finally { await session.close(); }
})().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
