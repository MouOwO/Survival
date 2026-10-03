-- Real sound-service routing and limits with a recording engine emitter.
package.path = "scripts/vscripts/?.lua;" .. package.path
local service = require("core/sound_service")
local skills = require("config/generated/tower_skill_definitions")
local cues = require("config/generated/tower_skill_sound_definitions")
local now, played = 0, {}
GameRules = { GetGameTime = function() return now end }
local function unit(id)
    return {entindex=function() return id end, IsNull=function() return false end,
        EmitSound=function(_, event) played[#played+1]=event end}
end
local first, second = unit(1), unit(2)
-- Use the real asset catalog: every tier must keep its configured skin bullet,
-- despite the engine's default attack projectile being hidden by the modifier.
local feedback = require("systems/tower_machine_gun_feedback")
local machine_rows = require("config/generated/tower_class_machine_gun")
local shot
ProjectileManager = { CreateTrackingProjectile = function(_, options) shot=options end }
first.GetProjectileSpeed = function() return 1800 end
for _, row in ipairs(machine_rows.rows) do
    service.reset()
    first.survival_model_asset_id = row.model_asset_id
    feedback.shot(first, second)
    assert(shot.EffectName == row.projectile_model, "machine gun lost configured tier projectile")
    assert(shot.Source == first and shot.Target == second and shot.iMoveSpeed == 1800)
    assert(shot.bIsAttack == false and shot.Ability == nil, "cosmetic projectile gained gameplay")
end
for _, speed in ipairs({0, 100}) do
    for level=1,5 do
        service.reset()
        now, played = 0, {}
        local skill = skills.by_id[string.format("machine_gun_lv%02d", level)]
        for hit=1,skill.max_targets do
            now = (hit-1)*skill.barrage_interval/(1+speed/100)
            assert(service.play("tower_machine_gun", {source=first, unit=first}), "configured burst muted a gunshot")
        end
        assert(#played == skill.max_targets)
        for _, event in ipairs(played) do assert(event == "Hero_Sniper.Attack.DT20") end
    end
end
service.reset()
now, played = 0, {}
local function coins(tower)
    return service.play("tower_bounty_machine_gun", {
        source=tower, unit=tower, limiter_scope="tower_gold_player:0",
    })
end
assert(coins(first))
assert(not coins(second), "same player's tower coins must not overlap")
now=0.81
assert(not coins(second), "native coin sample must finish before replay")
now=1.61
assert(coins(second))
assert(#played==2 and played[1]=="Survival.Tower.Coins")
local precached={}
PrecacheResource=function(kind, resource, context)
    assert(kind=="soundfile" and context==42)
    precached[resource]=true
end
service.precache(42)
for _, row in ipairs(cues.rows) do
    if row.enabled then assert(precached[row.sound_resource], "missing sound precache: "..row.cue_id) end
end
print("TOWER_ATTACK_AUDIO_PASS: configured gunshots at two speeds, shared coin limiter, every enabled tower sound precached")
