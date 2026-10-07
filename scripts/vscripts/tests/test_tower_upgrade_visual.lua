local source=assert(io.open("scripts/vscripts/systems/building_upgrade_system.lua","r")):read("*a")
local body=assert(source:match("local function play_upgrade_sound%((.-)\nend"))
local sound,created,released=0,0,0
local env={building_sound={upgrade_completed=function()sound=sound+1 end},tower_routes={current=function(s)return s end,model_for=function(s)return s.model end},PATTACH_ABSORIGIN_FOLLOW=1,pcall=pcall,print=function()end}
env.ParticleManager={CreateParticle=function(_,path,attach,unit)assert(path=="particles/generic_hero_status/hero_levelup.vpcf" and attach==1 and unit);created=created+1;return 99 end,ReleaseParticleIndex=function(_,id)assert(id==99);released=released+1 end}
local fn=assert(loadstring("return function("..body.."\nend"));setfenv(fn,env);local play=fn()
play({building_id="arrow_tower",model="models/survival_buildings/tower.vmdl",unit={}});assert(sound==1 and created==0)
play({building_id="arrow_tower",model="models/heroes/zuus/zuus.vmdl",unit={}});assert(sound==2 and created==1 and released==1)
play({building_id="wall",model="models/heroes/zuus/zuus.vmdl",unit={}});assert(created==1)
env.ParticleManager.CreateParticle=function()error("unavailable")end
assert(pcall(play,{building_id="arrow_tower",model="models/heroes/zuus/zuus.vmdl",unit={}}),"cosmetics never cancel completed upgrade")
print("TOWER_UPGRADE_VISUAL_PASS: original particle, hero-only tower, sound retained, release and failure isolation")
