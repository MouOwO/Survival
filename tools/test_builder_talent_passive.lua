-- Execute the real Lua ability and runtime builder with engine lookup/transport
-- substituted. Talent selection must control behavior independently per player.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(value) return value end
DOTA_ABILITY_BEHAVIOR_PASSIVE = 2
DOTA_ABILITY_BEHAVIOR_NO_TARGET = 4
DOTA_ABILITY_BEHAVIOR_IMMEDIATE = 2048
local snapshots, opens = {}, {}
CustomNetTables = {GetTableValue = function(_, name, key)
    assert(name == "survival_rogue_reward")
    return snapshots[key]
end}
local bus, events = require("core/event_bus"), require("core/events")
bus.reset()
bus.handle_request(events.ROGUE_REWARD_OPEN_REQUEST, function(payload)
    opens[#opens + 1] = payload
    return {ok = true}
end)
local native = require("abilities/ability_survival_rogue_reward")
local builder = require("ui/ability_runtime_builder")
local function fixture(player_id, id)
    local caster = {}
    function caster:IsNull() return false end
    function caster:GetPlayerOwnerID() return player_id end
    function caster:entindex() return id end
    local ability = setmetatable({}, {__index = native})
    function ability:GetCaster() return caster end
    local function runtime()
        return builder.build("ability_survival_rogue_reward", {player_id = player_id, unit = caster}, {})
    end
    return ability, caster, runtime
end
local ability, caster, runtime = fixture(0, 100)
local other, _, other_runtime = fixture(1, 101)
local active_behavior = DOTA_ABILITY_BEHAVIOR_NO_TARGET + DOTA_ABILITY_BEHAVIOR_IMMEDIATE
assert(ability:GetBehavior() == active_behavior and other:GetBehavior() == active_behavior,
    "a player without a selected talent can still open three choices")
assert(ability:GetAbilityTextureName() == "ogre_magi_multicast")
local pending = runtime()
assert(pending.passive == 0 and pending.talent_pending == 1 and pending.available == 1)
assert(pending.fields[1].label == "快捷键" and pending.fields[1].value == "G")
ability:OnSpellStart()
assert(#opens == 1 and opens[1].player_id == 0 and opens[1].source == "builder",
    "pending native casts reach the actual opening request")

snapshots["0"] = {active = 0, talent_pending = 0, builder_talent = {
    card_id = "wall_recovery", name = "Wall Recovery", description = "Passive recovery",
    icon_name = "survival/native/talent_wall_recovery",
}}
assert(ability:GetBehavior() == DOTA_ABILITY_BEHAVIOR_PASSIVE,
    "successful selection turns the same native ability into a passive")
assert(ability:GetAbilityTextureName() == snapshots["0"].builder_talent.icon_name)
local chosen = runtime()
assert(chosen.passive == 1 and chosen.talent_pending == 0 and #chosen.fields == 0,
    "selected runtime exposes a passive without a tooltip shortcut")
assert(chosen.available == 1 and chosen.can_afford == 1,
    "selected passives retain their visible hoverable presentation")
assert(chosen.icon_name == snapshots["0"].builder_talent.icon_name
    and chosen.upgrade_description == snapshots["0"].builder_talent.description)
ability:OnSpellStart()
assert(#opens == 1, "an already selected native talent cannot reopen the choice flow")
assert(other:GetBehavior() == active_behavior and other_runtime().passive == 0,
    "another player keeps an active selection entrance")
assert(other:GetAbilityTextureName() == "ogre_magi_multicast",
    "another player's icon cannot leak into an unselected talent")
other:OnSpellStart()
assert(#opens == 2 and opens[2].player_id == 1)
snapshots["1"] = {builder_talent = {card_id = "instant_wood", name = "Instant Wood",
    description = "Starting wood", icon_name = "survival/native/talent_instant_wood"}}
assert(other:GetBehavior() == DOTA_ABILITY_BEHAVIOR_PASSIVE)
assert(other:GetAbilityTextureName() == snapshots["1"].builder_talent.icon_name
    and ability:GetAbilityTextureName() == snapshots["0"].builder_talent.icon_name,
    "two selected players retain their own native talent textures")
assert(other_runtime().icon_name == snapshots["1"].builder_talent.icon_name)
local owned_ability, owned_caster = fixture(1, 102)
owned_caster.survival_player_id = 0
assert(owned_ability:GetBehavior() == DOTA_ABILITY_BEHAVIOR_PASSIVE
    and owned_ability:GetAbilityTextureName() == snapshots["0"].builder_talent.icon_name,
    "native behavior and texture resolve the same survival owner as cast requests")

-- A different offer may replace the outer snapshot; the chosen builder talent
-- is the persistent selection marker, independent from the current offer UI.
snapshots["0"].active, snapshots["0"].reward_type = 1, "boss"
assert(ability:GetBehavior() == DOTA_ABILITY_BEHAVIOR_PASSIVE and runtime().passive == 1)
ability:OnSpellStart()
assert(#opens == 2, "boss offers do not make the opening talent clickable again")
snapshots["1"] = {talent_pending = 0, builder_talent = {card_id = ""}}
assert(other:GetBehavior() == active_behavior and other_runtime().passive == 0,
    "an empty card identifier does not represent a completed selection")
print("BUILDER_TALENT_PASSIVE_PASS: native active-to-passive behavior, guarded cast, icon/runtime player isolation, no chosen shortcut and persistent selection")
