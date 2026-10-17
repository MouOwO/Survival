-- Exercise the production access check with authenticated, mode-filtered
-- profile responses. No account data, saved inventory, or hero balance edits.
package.path = "scripts/vscripts/?.lua;" .. package.path
local bus = require("core/event_bus")
local events = require("core/events")
local access = require("systems/hero_summon_access")
local definitions = require("config/generated/hero_definitions")
local profiles = {}
bus.reset()
bus.handle_request(events.PLAYER_PROFILE_GET_REQUEST, function(payload)
    local profile = profiles[payload.player_id]
    return {ok=profile ~= nil, profile=profile}
end)
local monkey = assert(definitions.by_id.hero_monkey_king)
assert(monkey.enabled ~= false and monkey.vip_required == true)
local function context(id, vip)
    return access.context(id, {vip=vip and 1 or 0})
end
local function allowed(id, vip)
    return access.check(monkey, context(id, vip))
end
local groups = 0
local function check(name, run)
    run(); groups=groups+1; print("MONKEY_OWNERSHIP_PASS " .. name)
end
check("locked_without_ownership_or_vip", function()
    profiles[0]={save={content_inventory={}}}
    assert(allowed(0, false)==false)
end)
check("shared_lottery_identity_unlocks_own_monkey", function()
    profiles[0].save.content_inventory.lottery_monkey_king=1
    assert(allowed(0, false)==true)
end)
check("no_global_vip_or_other_hero_grant", function()
    local blade=assert(definitions.by_id.hero_blademaster)
    assert(access.check(blade, context(0, false))==false)
    assert(context(0,false).vip==false)
end)
check("player_inventory_isolation", function()
    profiles[1]={save={content_inventory={}}}
    assert(allowed(1,false)==false)
    assert(allowed(0,false)==true)
end)
check("mode_filtered_inventory_is_authority", function()
    profiles[2]={mode="pure",save={content_inventory={}},
        account_save={content_inventory={lottery_monkey_king=1}}}
    assert(allowed(2,false)==false)
end)
check("no_parallel_new_purchase_identity", function()
    profiles[3]={save={content_inventory={commerce_p079=1}}}
    assert(allowed(3,false)==false)
end)
check("invalid_or_zero_quantity_cannot_unlock", function()
    for _,quantity in ipairs({0,-1,0.5,math.huge,"1",false}) do
        profiles[4]={save={content_inventory={lottery_monkey_king=quantity}}}
        assert(allowed(4,false)==false, tostring(quantity))
    end
end)
check("normal_vip_and_free_heroes_unchanged", function()
    assert(allowed(1,true)==true)
    assert(access.check({enabled=true,hero_id="free",vip_required=false},context(1,false)))
end)
check("disabled_hero_rejected_even_for_vip", function()
    assert(access.check({enabled=false,hero_id="hero_monkey_king",vip_required=true},context(0,true))==false)
end)
print("MONKEY_OWNERSHIP_ALL_PASS groups=" .. groups)
