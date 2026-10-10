'use strict';
// Observe existing combat for two seconds, then restore the filter and pause.
// No test attacks, units, hero values or orders are created.
const fs = require('node:fs');
const { connect } = require('./map_c6/console-session.cjs');
(async () => {
  const session = await connect({ port: 29001, timeoutMs: 10000, historyTimeoutMs: 15000 });
  let installed = false;
  const setup = `
assert(IsInToolsMode() and IsServer(),"requires Tools server")
assert(not _G.survival_native_hero_observation,"observer already installed")
local original=assert(package.loaded["combat/damage_filter_service"])
local original_pause=GameRules:IsGamePaused()
local hero=assert(require("core/event_bus").request("hero.summon.get.request",{player_id=0}).unit)
local mode=GameRules:GetGameModeEntity()
local count=0
_G.survival_native_hero_observation={restore=function()
  mode:SetDamageFilter(original._filter_for_test,original)
  PauseGame(original_pause)
  _G.survival_native_hero_observation=nil
  print("HERO_NATIVE_OBSERVATION_RESTORED")
end}
mode:SetDamageFilter(function(context,keys)
  local input=keys.damage
  local observed=tonumber(keys.entindex_attacker_const)==hero:entindex() and count<6
  local accepted=original._filter_for_test(context,keys)
  if observed then
    count=count+1
    print("[CURRENT_HERO_NATIVE_DAMAGE] sample="..count.." input="..tostring(input).." filtered="..tostring(keys.damage).." accepted="..tostring(accepted).." category="..tostring(keys.damage_category_const).." inflictor="..tostring(keys.entindex_inflictor_const).." native_average="..tostring(hero:GetAverageTrueAttackDamage(nil)).." scale="..tostring(hero.survival_endless_attack_scale or 1))
  end
  return accepted
end,original)
PauseGame(false)
print("HERO_NATIVE_OBSERVATION_READY")`;
  try {
    installed = true;
    await session.send([{ name: 'dota_run_lua', arguments: { code: setup } }], 'HERO_NATIVE_OBSERVATION_READY');
    await new Promise(resolve => setTimeout(resolve, 2000));
  } finally {
    if (installed) await session.send([{ name: 'dota_run_lua', arguments: { code: 'if _G.survival_native_hero_observation then _G.survival_native_hero_observation.restore() else print("HERO_NATIVE_OBSERVATION_RESTORED") end' } }], 'HERO_NATIVE_OBSERVATION_RESTORED');
    fs.writeFileSync('output/current_hero_native_damage.log', session.rawOutput);
    console.log(session.rawOutput.split(/\r?\n/).filter(line => /CURRENT_HERO_NATIVE_DAMAGE|HERO_NATIVE_OBSERVATION_RESTORED/.test(line)).join('\n'));
    await session.close();
  }
})().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
