package.path="scripts/vscripts/?.lua;"..package.path
local time,shots=0,{}
GameRules={GetGameTime=function() return time end}
ProjectileManager={CreateTrackingProjectile=function(_,shot) shots[#shots+1]=shot end}
local service=require("systems/tower_projectile_visual")
local a,b,c={},{},{}
local fallback="particles/units/heroes/hero_drow/drow_base_attack.vpcf"
a.survival_projectile_model=""
assert(service.resolve(a,fallback)==fallback,"laser suppression blank must not hide split arrows")
a.survival_projectile_model="configured"
assert(service.resolve(a,fallback)=="configured")
for _,row in ipairs(require("config/generated/tower_class_machine_gun").rows) do
    a.survival_model_asset_id=row.model_asset_id
    assert(service.resolve(a,fallback)==row.projectile_model,"every gun tier retains its native costume bullet")
end
for i=1,100 do service.emit(a,b,fallback,2000,1) end
assert(#shots==1,"same frame/trajectory duplicates must merge")
service.emit(a,c,fallback,2000,1)
service.emit(a,b,"different",2000,1)
service.emit(a,b,"different",2500,1)
service.emit(a,b,"different",2500,2)
assert(#shots==5,"target/effect/speed/socket differences retained")
time=0.03;service.emit(a,b,"different",2500,2)
assert(#shots==6,"next frame never loses its bullet")
service.clear(a);service.emit(a,b,"different",2500,2)
assert(#shots==7,"relocation/upgrade starts a fresh visual frame")
for _,shot in ipairs(shots) do assert(shot.bIsAttack==false and shot.Ability==nil) end
local projection=require("systems/tower_rank_projection")
for _,building in ipairs({"arrow_tower","ultimate_tower","city"}) do
    for level=-2,29 do
        local r=projection.project({building_id=building,level=level})
        assert(projection.rarity(building,level)==(r and r.rarity),"fast rarity disagrees with full projection")
    end
end
print("TOWER_PROJECTILE_VISUAL_PASS: blank fallback, all gun skins, same-frame overlap, different trajectories and next frames, rarity parity")
