package.path = "scripts/vscripts/?.lua;" .. package.path
Vector = function(x,y,z) return {x=x,y=y,z=z} end
PATTACH_WORLDORIGIN=0
DOTA_UNIT_TARGET_TEAM_ENEMY,DOTA_UNIT_TARGET_HERO,DOTA_UNIT_TARGET_BASIC=1,2,4
DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES,FIND_CLOSEST=8,0
local clock=0
GameRules={GetGameTime=function()return clock end}
local function unit(id,x)
    return {IsNull=function()return false end,entindex=function()return id end,
        GetAbsOrigin=function()return Vector(x,400,32)end,GetTeamNumber=function()return 2 end}
end
local attacker,target,inside,outside=unit(1,0),unit(2,100),unit(3,349),unit(4,351)
local radius_seen,position_seen
FindUnitsInRadius=function(_,position,_,radius)
    radius_seen,position_seen=radius,position
    local found={}
    for _,candidate in ipairs({target,inside,outside})do
        if math.abs(candidate:GetAbsOrigin().x-position.x)<=radius then found[#found+1]=candidate end
    end
    return found
end
local particles,fail_create,fail_control={},false,false
ParticleManager={
    CreateParticle=function(_,path,attach,owner)
        if fail_create then error("optional renderer failure")end
        assert(attach==PATTACH_WORLDORIGIN and owner==nil,"burst must survive target death")
        particles[#particles+1]={path=path,controls={}};return #particles
    end,
    SetParticleControl=function(_,id,cp,point)
        if fail_control then error("optional CP failure")end
        particles[id].controls[cp]=point
    end,
    DestroyParticle=function(_,id)particles[id].destroyed=true end,
    ReleaseParticleIndex=function(_,id)
        assert(not particles[id].released,"particle released twice")
        particles[id].released=true
    end,
}
local visual=require("systems/keeper_blinding_light_visual")
local service=require("systems/hero_exclusive_passive_service")
local definition=require("config/hero_passive_skill_definitions").by_id.skill_shadow_fiend_raze
local calls,sounds={},{}
service.sound_service={play=function(cue) sounds[#sounds+1]=cue end}
service.init({deal_group=function(context,targets,multiplier)
    calls[#calls+1]={targets=targets,multiplier=multiplier}
end})
assert(definition.trigger_chance[1]==0.10 and definition.radius[1]==250)
local context={attacker=attacker,target=target,level=1,skill_id=definition.skill_id}
for _,expected in ipairs({27.5,30,32.5,35,37.5,37.5})do
    assert(service.runners.skill_shadow_fiend_raze(context,definition))
    local result=calls[#calls];assert(math.abs(result.multiplier-expected)<0.0000001)
    assert(#result.targets==2 and result.targets[1]==target and result.targets[2]==inside,
        "damage includes radius 249 and excludes radius 251")
    local p=particles[#particles]
    assert(p.path==visual.PARTICLE and p.controls[2].x==radius_seen and radius_seen==250)
    assert(p.controls[0].x==100 and p.controls[1].x==position_seen.x)
    assert(p.released and not p.destroyed,"native finite impact must retain its tail")
end
clock=3
service.runners.skill_shadow_fiend_raze(context,definition)
assert(math.abs(calls[#calls].multiplier-27.5)<0.0000001,"expired layers must preserve the original reset")
fail_create=true
service.runners.skill_shadow_fiend_raze(context,definition)
assert(calls[#calls].multiplier==30,"optional particle creation cannot swallow damage")
fail_create=false;fail_control=true
service.runners.skill_shadow_fiend_raze(context,definition)
assert(calls[#calls].multiplier==32.5 and particles[#particles].destroyed and particles[#particles].released)
assert(#sounds==#calls,"one sound per proc, not per victim")
local cues=require("config/generated/hero_skill_sound_definitions")
assert(cues.by_id.hero_shadow_raze_impact.sound_event=="Hero_KeeperOfTheLight.BlindingLight")
print("KOTL_BLINDING_LIGHT_PASS: native AoE CP0/1/2, 250 radius boundary, original layers/multipliers/expiry, lethal residue, visual failure isolation")
