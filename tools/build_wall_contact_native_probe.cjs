'use strict';
// Build a local Tools payload without connecting a console or running gameplay.
// Executing it uses a private module cache and only installs the dedicated
// SURVIVAL_NATIVE_WALL_PROBE handle and acceptance modifier adapter; formal
// gameplay module caches and modifier classes are not replaced.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const output=path.join(root,'output/wall_contact_native_probe');
fs.mkdirSync(output,{recursive:true});
const modules=[
 ['systems/wall_navigation_geometry','scripts/vscripts/systems/wall_navigation_geometry.lua'],
 ['systems/wall_navigation_service','scripts/vscripts/systems/wall_navigation_service.lua'],
 ['systems/wall_melee_contact','scripts/vscripts/systems/wall_melee_contact.lua'],
 ['modifiers/modifier_enemy_wall_ai','scripts/vscripts/modifiers/modifier_enemy_wall_ai.lua'],
 ['tests/wall_native_attack_record_lifecycle','scripts/vscripts/tests/wall_native_attack_record_lifecycle.lua'],
 ['tests/modifier_wall_native_attack_record_audit','scripts/vscripts/tests/modifier_wall_native_attack_record_audit.lua'],
 ['tests/wall_native_redesign_probe','scripts/vscripts/tests/wall_native_redesign_probe.lua'],
];
function luaString(text){let n=0;while(text.includes(']'+ '='.repeat(n)+']'))n++;return '['+'='.repeat(n)+'['+text+']'+'='.repeat(n)+']';}
const hashes={},sources={};
const adapter=fs.readFileSync(path.join(root,'scripts/vscripts/tests/wall_native_redesign_ai.lua'),'utf8');
for(const [name,file] of modules){
 const source=fs.readFileSync(path.join(root,file),'utf8').replace(/^\uFEFF/,'');
 hashes[file]=crypto.createHash('sha256').update(source).digest('hex');
 // Count coordinate repairs without monkeypatching any native engine method.
 sources[name]=name==='tests/wall_native_redesign_probe'?source:
   source.replace(/\b([A-Za-z_]\w*):SetAbsOrigin\(/g,'__native_probe_set_origin($1,')
     .replace(/\b([A-Za-z_]\w*):Stop\(\)/g,'__native_probe_stop($1)');
 if(name==='modifiers/modifier_enemy_wall_ai'){
  const missing=[...source.matchAll(/function M:([A-Za-z_]\w*)\(/g)].map(m=>m[1]).filter(method=>!adapter.includes(method));
  if(missing.length)throw Error('Native adapter must forward new production methods: '+missing.join(', '));
 }
}
const definitions=Object.entries(sources).map(([name,source])=>`sources[ ${luaString(name)} ]=${luaString(source)}`).join('\n');
const hashLua='{'+Object.entries(hashes).map(([name,hash])=>`[ ${luaString(name)} ]=${luaString(hash)}`).join(',')+'}';
const payload=`assert(IsServer() and IsInToolsMode(),'Tools server only')
local real=_G
assert(not real.SURVIVAL_NATIVE_WALL_PROBE or not real.SURVIVAL_NATIVE_WALL_PROBE.is_active(),'stop previous native probe before replacing payload')
local cache,sources={},{}
local metrics={active=false,values={},path_buckets={}}
local scope=setmetatable({_G=false,package={loaded=cache},__native_probe_metrics=metrics},{__index=real})
scope._G=scope
scope.LinkLuaModifier=function() end
local function add(name)
 if metrics.active then metrics.values[name]=(metrics.values[name] or 0)+1 end
end
scope.__native_probe_set_origin=function(unit,point)
 add('position_writes');return unit:SetAbsOrigin(point)
end
scope.__native_probe_stop=function(unit)
 add('stops');return unit:Stop()
end
scope.ExecuteOrderFromTable=function(order)
 add('orders');add(order.OrderType==DOTA_UNIT_ORDER_ATTACK_TARGET and 'attack_orders' or 'move_orders')
 return real.ExecuteOrderFromTable(order)
end
scope.GridNav=setmetatable({},{__index=function(_,name)
 local fn=real.GridNav[name]
 if type(fn)~='function' then return fn end
 return function(_, ...)
  add('nav_'..name)
  if metrics.active and name=='FindPathLength' then
   local bucket=math.floor(GameRules:GetGameTime()*2)
   metrics.path_buckets[bucket]=(metrics.path_buckets[bucket] or 0)+1
   metrics.max_path_bucket=math.max(metrics.max_path_bucket or 0,metrics.path_buckets[bucket])
  end
  return fn(real.GridNav,...)
 end
end})
cache['systems/enemy_attack_observer']={is_ready=function() return false end,can_route_death=function() return false end}
cache['systems/wall_target_service']={}
cache['systems/enemy_ranged_stationary']={owns_root=function() return false end}
${definitions}
scope.require=function(name)
 if cache[name]~=nil then return cache[name] end
 if not sources[name] then return real.require(name) end
 local chunk=assert(loadstring(sources[name],'native_probe/'..name))
 setfenv(chunk,scope)
 local value=chunk()
 cache[name]=value or true
 return cache[name]
end
real.LinkLuaModifier('modifier_wall_native_redesign_ai','tests/wall_native_redesign_ai',LUA_MODIFIER_MOTION_NONE)
real.LinkLuaModifier('modifier_wall_native_attack_record_audit','tests/modifier_wall_native_attack_record_audit',LUA_MODIFIER_MOTION_NONE)
local probe=scope.require('tests/wall_native_redesign_probe')
probe.source_hashes=${hashLua}
real.SURVIVAL_NATIVE_WALL_PROBE=probe
print('WALL_NATIVE_PAYLOAD_READY')
`;
const dest=path.join(output,'payload.lua');
fs.writeFileSync(dest,payload,'utf8');
fs.writeFileSync(path.join(output,'source_hashes.json'),JSON.stringify(hashes,null,2)+'\n');
console.log(JSON.stringify({payload:dest,bytes:Buffer.byteLength(payload),hashes}));
