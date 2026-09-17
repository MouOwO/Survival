package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path

LUA_MODIFIER_MOTION_NONE = 0
LinkLuaModifier = function() end

local created = {}
local removed = {}
local fail_sync = false
local fail_wearable = false
local next_entindex = 900

UTIL_Remove = function(entity)
    entity.removed = true
    removed[#removed + 1] = entity
end

local function carrier(unit_name, position, team, model)
    next_entindex = next_entindex + 1
    local entity = {
        unit_name = unit_name,
        class_name = unit_name == "dota_item_wearable"
            and "dota_item_wearable" or "npc_dota_creature",
        body_model = model or "models/test/default.vmdl",
        position = position,
        team = team,
        hidden = false,
        removed = false,
        gestures = {},
    }
    function entity:IsNull() return self.removed end
    function entity:entindex() return self.entity_entindex end
    function entity:GetUnitName() return self.unit_name end
    function entity:GetClassname() return self.class_name end
    function entity:SetModel(model_path) self.body_model = model_path end
    function entity:SetOriginalModel(model_path) self.body_model = model_path end
    function entity:GetModelName() return self.body_model end
    function entity:AddNoDraw() self.hidden = true end
    function entity:RemoveNoDraw() self.hidden = false end
    function entity:SetOwner(owner) self.owner = owner end
    function entity:GetOwner() return self.owner end
    function entity:FollowEntity(owner, bone_merge)
        self.follow_owner = owner
        self.bone_merge = bone_merge
    end
    function entity:SetSolid(solid) self.solid = solid end
    function entity:SetAbsOrigin(position)
        if fail_sync then error("simulated position sync failure") end
        self.position = position
    end
    function entity:SetAngles(pitch, yaw, roll)
        if fail_sync then error("simulated angle sync failure") end
        self.angles = { x = pitch, y = yaw, z = roll }
    end
    function entity:SetForwardVector(forward)
        if fail_sync then error("simulated forward sync failure") end
        self.forward = forward
    end
    function entity:SetControllableByPlayer(player_id, enabled)
        self.control_player = player_id
        self.controllable = enabled
    end
    function entity:AddNewModifier(_, _, name)
        self.modifier = name
        return { name = name }
    end
    function entity:StartGesture(activity)
        self.gestures[#self.gestures + 1] = { activity = activity }
    end
    function entity:StartGestureWithPlaybackRate(activity, playback_rate)
        self.gestures[#self.gestures + 1] = {
            activity = activity,
            playback_rate = playback_rate,
        }
    end
    created[#created + 1] = entity
    entity.entity_entindex = next_entindex
    return entity
end

CreateUnitByName = function(unit_name, position, find_clear_space, owner,
        unit_owner, team)
    assert(find_clear_space == false,
        "visual carrier unexpectedly requested clear-space movement")
    assert(owner == unit_owner, "visual carrier owner arguments diverged")
    return carrier(unit_name, position, team)
end

SpawnEntityFromTableSynchronous = function(class_name, data)
    assert(class_name == "dota_item_wearable",
        "native carrier spawned an unexpected child class: " .. tostring(class_name))
    if fail_wearable then error("simulated wearable creation failure") end
    return carrier(class_name, data and data.origin, 0, data and data.model)
end

Entities = {}
function Entities:FindAllByClassname(class_name)
    local result = {}
    for _, entity in ipairs(created) do
        if not entity.removed and entity.class_name == class_name then
            result[#result + 1] = entity
        end
    end
    return result
end

local unit = {
    hidden = false,
    render_alpha = 192,
    position = { x = 10, y = 20, z = 30 },
    angles = { x = 0, y = 90, z = 0 },
}
function unit:IsNull() return false end
function unit:entindex() return 77 end
function unit:GetAbsOrigin() return self.position end
function unit:GetAngles() return self.angles end
function unit:GetForwardVector() return { x = 0, y = 1, z = 0 } end
function unit:GetTeamNumber() return 2 end
function unit:GetPlayerOwnerID() return 4 end
function unit:AddNoDraw() self.hidden = true end
function unit:RemoveNoDraw() self.hidden = false end
function unit:GetRenderAlpha() return self.render_alpha end
function unit:SetRenderAlpha(alpha) self.render_alpha = alpha end

local function asset(asset_id, unit_name, item_def)
    return {
        asset_id = asset_id,
        async_unit_name = unit_name,
        primary_model = "models/test/default.vmdl",
        native_wearables = {
            {
                wearable_key = asset_id .. "_wearable",
                item_def = item_def,
                model_path = "models/test/default.vmdl",
                entity_class = "dota_item_wearable",
                attach_mode = "bone_merge",
            },
        },
    }
end

package.loaded["visual/native_wearable_carrier_service"] = nil
local service = require("visual/native_wearable_carrier_service")
local first = asset("tower_stage_one", "asset_proxy_tower_stage_one", "101")
local second = asset("tower_stage_two", "asset_proxy_tower_stage_two", "102")
local catalog = require("config/asset_catalog")
catalog.by_id[first.asset_id] = first
catalog.by_id[second.asset_id] = second

unit.hidden = true
service.Clear(unit)
assert(unit.hidden and unit.render_alpha == 192,
    "clearing an unmanaged unit changed visibility owned by another system")
unit.hidden = false

local ok, status, first_carrier = service.Apply(unit, first)
assert(ok and status == first.asset_id and #created == 2,
    "native wearable carrier was not created")
assert(unit.render_alpha == 0 and not unit.hidden and not first_carrier.hidden
        and service._wearable_count_for_test(unit) == 1,
    "native wearable carrier did not atomically replace building rendering")
local first_wearable = created[2]
assert(first_wearable.class_name == "dota_item_wearable"
        and first_wearable.body_model == "models/test/default.vmdl"
        and first_wearable.owner == first_carrier
        and first_wearable.follow_owner == first_carrier
        and first_wearable.bone_merge == true
        and not first_wearable.hidden,
    "native wearable was not explicitly bone-merged to the carrier")
assert(first_carrier.follow_owner == nil and first_carrier.bone_merge == nil
        and first_carrier.position == unit.position
        and first_carrier.angles.x == 0
        and first_carrier.angles.y == 90
        and first_carrier.angles.z == 0,
    "native wearable body was not initialized with an independent transform")
assert(first_carrier.owner == unit and first_carrier.team == 2
        and first_carrier.control_player == 4
        and first_carrier.controllable == false,
    "native wearable carrier changed ownership or control semantics")
assert(first_carrier.modifier == "modifier_native_wearable_visual_carrier",
    "native wearable carrier safety modifier was not applied")
assert(service.Sync(unit),
    "native wearable carrier explicit transform sync did not succeed")

ok, status = service.Refresh(unit, first)
assert(ok and status == first.asset_id and #created == 2,
    "same-stage refresh duplicated the native wearable carrier")
assert(unit.render_alpha == 0,
    "same-stage refresh did not keep the building renderer hidden")

unit.position = { x = 110, y = 120, z = 130 }
unit.angles = { x = 5, y = 180, z = 2 }
ok, status = service.Refresh(unit, first)
assert(ok and status == first.asset_id and #created == 2
        and first_carrier.position == unit.position
        and first_carrier.angles.x == 5
        and first_carrier.angles.y == 180
        and first_carrier.angles.z == 2,
    "same-stage refresh did not synchronize the independent carrier transform")

UTIL_Remove(first_wearable)
ok, status, first_carrier = service.Refresh(unit, first)
assert(ok and status == first.asset_id and #created == 4
        and service.Matches(unit, first)
        and service._wearable_count_for_test(unit) == 1
        and first_carrier ~= created[1]
        and created[1].removed,
    "missing committed wearable did not trigger a complete carrier rebuild")
first_wearable = created[4]
assert(not first_wearable.removed and first_wearable.owner == first_carrier
        and first_wearable.bone_merge == true,
    "carrier rebuild did not restore the explicit wearable attachment")

service.StartGesture(unit, 9001, 2)
assert(#first_carrier.gestures == 1
        and first_carrier.gestures[1].activity == 9001
        and first_carrier.gestures[1].playback_rate == 2,
    "native wearable carrier did not mirror the attack playback rate")

fail_sync = true
ok, status = service.Refresh(unit, first)
assert(not ok and status == "carrier_sync_failed"
        and service.Matches(unit, first)
        and not first_carrier.removed,
    "failed transform synchronization did not preserve the previous carrier")
fail_sync = false

fail_sync = true
ok, status = service.Refresh(unit, second)
assert(not ok and status == "carrier_attach_failed",
    "failed stage replacement did not report attachment failure")
assert(service.Matches(unit, first) and not first_carrier.removed
        and unit.render_alpha == 0,
    "failed stage replacement discarded the previous valid carrier")

fail_sync = false
fail_wearable = true
ok, status = service.Refresh(unit, second)
assert(not ok and status == "wearable_create_failed"
        and service.Matches(unit, first)
        and not first_carrier.removed
        and not first_wearable.removed,
    "failed wearable creation did not preserve the previous complete carrier")
fail_wearable = false

ok, status, second_carrier = service.Refresh(unit, second)
assert(ok and status == second.asset_id and #created == 8,
    "stage upgrade did not create its replacement carrier")
assert(first_carrier.removed and not second_carrier.removed
        and first_wearable.removed
        and service.Matches(unit, second)
        and service._wearable_count_for_test(unit) == 1,
    "stage upgrade did not atomically replace the old carrier")
assert(second_carrier.position == unit.position
        and second_carrier.angles.y == unit.angles.y,
    "upgraded carrier did not preserve the independent transform")

service.Clear(unit)
assert(second_carrier.removed and unit.render_alpha == 192 and not unit.hidden
        and service._count_for_test() == 0,
    "carrier cleanup did not restore the original building alpha or visual state")

local recovered_carrier
ok, status, recovered_carrier = service.Apply(unit, first)
assert(ok and status == first.asset_id and service._count_for_test() == 1,
    "recovery setup did not create a live carrier")
local recovered_wearable = created[#created]
recovered_wearable.survival_is_native_wearable = nil
recovered_wearable.survival_native_wearable_owner_entindex = nil
recovered_wearable.survival_native_wearable_carrier_entindex = nil
package.loaded["visual/native_wearable_carrier_service"] = nil
local reloaded_service = require("visual/native_wearable_carrier_service")
assert(reloaded_service.Sync(unit)
        and reloaded_service.Has(unit)
        and reloaded_service.Matches(unit, first)
        and reloaded_service._wearable_count_for_test(unit) == 1
        and reloaded_service._live_carrier_count_for_test(unit) == 1
        and recovered_wearable.survival_is_native_wearable == true
        and not recovered_carrier.removed
        and not recovered_wearable.removed,
    "service reload did not recover the existing carrier and legacy wearable")
local created_before_reload_refresh = #created
ok, status, recovered_carrier = reloaded_service.Refresh(unit, first)
assert(ok and status == first.asset_id and #created == created_before_reload_refresh,
    "service reload refresh created a second carrier")

local duplicate_carrier = CreateUnitByName(
    first.async_unit_name,
    unit.position,
    false,
    unit,
    unit,
    unit:GetTeamNumber()
)
duplicate_carrier:SetModel(first.primary_model)
duplicate_carrier:SetOriginalModel(first.primary_model)
duplicate_carrier:SetOwner(unit)
duplicate_carrier.survival_is_native_wearable_visual = true
duplicate_carrier.survival_native_wearable_owner_entindex = unit:entindex()
duplicate_carrier.survival_model_asset_id = first.asset_id
local duplicate_wearable = SpawnEntityFromTableSynchronous(
    "dota_item_wearable",
    { model = first.native_wearables[1].model_path }
)
duplicate_wearable:SetModel(first.native_wearables[1].model_path)
duplicate_wearable:SetOwner(duplicate_carrier)
duplicate_wearable:FollowEntity(duplicate_carrier, true)
duplicate_wearable.survival_is_native_wearable = true
duplicate_wearable.survival_native_wearable_owner_entindex = unit:entindex()
duplicate_wearable.survival_native_wearable_carrier_entindex
    = duplicate_carrier:entindex()
duplicate_wearable.survival_native_wearable_key
    = first.native_wearables[1].wearable_key
duplicate_wearable.survival_native_wearable_item_def
    = tostring(first.native_wearables[1].item_def)
assert(reloaded_service.Has(unit)
        and duplicate_carrier.removed
        and duplicate_wearable.removed
        and reloaded_service._count_for_test() == 1
        and reloaded_service._live_carrier_count_for_test(unit) == 1,
    "duplicate live carrier was not reduced to one complete carrier")

local other_unit = setmetatable({
    position = { x = 70, y = 80, z = 90 },
}, { __index = unit })
other_unit.entindex = function() return 88 end
local invalid_carrier = CreateUnitByName(
    first.async_unit_name,
    other_unit.position,
    false,
    other_unit,
    other_unit,
    other_unit:GetTeamNumber()
)
invalid_carrier:SetModel(first.primary_model)
invalid_carrier:SetOriginalModel(first.primary_model)
invalid_carrier:SetOwner(other_unit)
invalid_carrier.survival_is_native_wearable_visual = true
invalid_carrier.survival_native_wearable_owner_entindex = unit:entindex()
invalid_carrier.survival_model_asset_id = first.asset_id
assert(reloaded_service.Has(unit) and invalid_carrier.removed,
    "carrier with mismatched owner metadata was adopted or left stale")

local stale_wearable = SpawnEntityFromTableSynchronous(
    "dota_item_wearable",
    { model = first.native_wearables[1].model_path }
)
stale_wearable:SetOwner(recovered_carrier)
stale_wearable:FollowEntity(recovered_carrier, true)
stale_wearable.survival_is_native_wearable = true
stale_wearable.survival_native_wearable_owner_entindex = unit:entindex()
stale_wearable.survival_native_wearable_carrier_entindex
    = recovered_carrier:entindex()
stale_wearable.survival_native_wearable_key =
    first.native_wearables[1].wearable_key
stale_wearable.survival_native_wearable_item_def =
    tostring(first.native_wearables[1].item_def)
assert(reloaded_service.Has(unit)
        and stale_wearable.removed
        and reloaded_service._wearable_count_for_test(unit) == 1
        and reloaded_service._live_carrier_count_for_test(unit) == 1,
    "duplicate wearable was not cleaned during carrier reconciliation")

reloaded_service.Clear(unit)
assert(recovered_carrier.removed and recovered_wearable.removed
        and reloaded_service._count_for_test() == 0
        and reloaded_service._live_carrier_count_for_test(unit) == 0,
    "live carrier cleanup did not remove recovered entities")

local reused_unit = setmetatable({
    hidden = false,
    render_alpha = 144,
    position = { x = 40, y = 50, z = 60 },
}, { __index = unit })
reused_unit.GetAngles = function() return nil end
ok, status, first_carrier = service.Apply(unit, first)
assert(ok and status == first.asset_id, "reuse setup did not create the old carrier")
ok, status, second_carrier = service.Apply(reused_unit, second)
assert(ok and status == second.asset_id and first_carrier.removed
        and service.Matches(reused_unit, second)
        and second_carrier.forward.x == 0
        and second_carrier.forward.y == 1,
    "reused entindex retained a carrier owned by the previous entity")
service.Clear(unit)
assert(not second_carrier.removed and service.Matches(reused_unit, second),
    "late cleanup from the old entity removed the reused entity's carrier")
service.Clear(reused_unit)
assert(second_carrier.removed and reused_unit.render_alpha == 144,
    "reused entity cleanup did not restore its own render state")

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local carrier_source = read_all(
    "scripts/vscripts/visual/native_wearable_carrier_service.lua"
)
assert(carrier_source:find("function M.Sync(unit)", 1, true)
        and not carrier_source:find("FollowEntity(unit, false)", 1, true),
    "carrier transform service still relies on parent following")
assert(carrier_source:find("expected_unit=", 1, true)
        and carrier_source:find("actual_body=", 1, true)
        and carrier_source:find("item_defs=", 1, true)
        and carrier_source:find("SpawnEntityFromTableSynchronous", 1, true)
        and carrier_source:find('"dota_item_wearable"', 1, true)
        and carrier_source:find('"FollowEntity",', 1, true)
        and carrier_source:find("true", 1, true)
        and not carrier_source:find("AttachWearables", 1, true),
    "carrier diagnostics do not expose the runtime identity contract")
local relocation_source = read_all(
    "scripts/vscripts/systems/building_relocation.lua"
)
local blink_source = read_all(
    "scripts/vscripts/modifiers/modifier_building_blink_move.lua"
)
local stationary_source = read_all(
    "scripts/vscripts/modifiers/modifier_building_stationary.lua"
)
local attack_source = read_all(
    "scripts/vscripts/modifiers/modifier_tower_attack_effects.lua"
)
assert(not relocation_source:find("native_wearable_carrier", 1, true)
        and not blink_source:find("native_wearable_carrier", 1, true)
        and not stationary_source:find("native_wearable_carrier", 1, true)
        and not attack_source:find("native_wearable_carrier", 1, true),
    "production movement or attack paths still reference the retired carrier")

print("NATIVE_WEARABLE_CARRIER_SERVICE_PASS")