'use strict';
// Explicit native validation against a fresh filter in a paused Tools match.
// Reuse dependencies by identity without init/resetting live services or tree
// attack records. Restore the original callback synchronously before returning.
const fs = require('node:fs');
const { connect } = require('./map_c6/console-session.cjs');
(async () => {
  const session = await connect({ port: 29001, timeoutMs: 10000, historyTimeoutMs: 15000 });
  const code = `
assert(IsInToolsMode() and GameRules:IsGamePaused(), "isolated filter validation requires paused Tools match")
local original=assert(package.loaded["combat/damage_filter_service"])
local fresh=dofile("combat/damage_filter_service")
assert(fresh~=original and package.loaded["combat/damage_filter_service"]==original,"filter must remain isolated")
local original_projection=package.loaded["combat/endless_stat_projection"]
local fresh_projection=dofile("combat/endless_stat_projection")
assert(fresh_projection~=original_projection and type(fresh_projection.is_finite)=="function","projection must remain isolated")
local wanted={event_bus=true,events=true,repository=true,config=true}
local dependencies={} local dependency_count=0 local projection_count=0
for index=1,100 do
  local name,value=debug.getupvalue(original._filter_for_test,index)
  if not name then break end
  if wanted[name] then dependencies[name]=assert(value,"live dependency missing: "..name) end
end
for index=1,100 do
  local name=debug.getupvalue(fresh._filter_for_test,index)
  if not name then break end
  if wanted[name] then
    assert(dependencies[name],"dependency identity missing: "..name)
    debug.setupvalue(fresh._filter_for_test,index,dependencies[name])
    dependency_count=dependency_count+1
  elseif name=="endless_projection" then
    debug.setupvalue(fresh._filter_for_test,index,fresh_projection)
    projection_count=projection_count+1
  end
end
assert(dependency_count==4,"expected exactly four isolated filter dependencies")
assert(projection_count==1,"expected one isolated projection helper")
local mode=GameRules:GetGameModeEntity()
mode:SetDamageFilter(fresh._filter_for_test,fresh)
local ok,result=pcall(function()
  package.loaded["tests/manual_large_attack_native"]=nil
  return require("tests/manual_large_attack_native").run({external_isolated_filter=true})
end)
mode:SetDamageFilter(original._filter_for_test,original)
print("[NATIVE_FILTER_VALIDATION] restored=true isolated=true initialized=false cache_unchanged="..tostring(package.loaded["combat/damage_filter_service"]==original and package.loaded["combat/endless_stat_projection"]==original_projection).." ok="..tostring(ok).." status="..tostring(type(result)=="table" and result.status or result))
print("NATIVE_FILTER_VALIDATION_COMPLETE")`;
  try {
    await session.send([{ name: 'dota_run_lua', arguments: { code } }], 'NATIVE_FILTER_VALIDATION_COMPLETE');
    fs.writeFileSync('output/native_projection_filter_live.log', session.rawOutput);
    console.log(session.rawOutput.split(/\r?\n/).filter(line => /LARGE_ATTACK_NATIVE\]|LARGE_ATTACK_NATIVE_DONE|NATIVE_FILTER_VALIDATION\]/.test(line)).join('\n'));
    if (!session.rawOutput.includes('result=PASS cases=12/12')
        || !session.rawOutput.includes('[NATIVE_FILTER_VALIDATION] restored=true isolated=true initialized=false cache_unchanged=true ok=true status=pass')) {
      throw new Error('Native projection/filter validation failed; original callback restoration and case results are in the artifact');
    }
  } finally { await session.close(); }
})().catch(error => { console.error(error.stack || error); process.exitCode = 1; });
