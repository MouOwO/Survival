-- Offline declaration/lifecycle regression; separate from native FPS captures.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(t) return t end
LinkLuaModifier = function() end
local server, ready = true, true
IsServer = function() return server end
MODIFIER_EVENT_ON_ATTACK_START, MODIFIER_EVENT_ON_ATTACK_LANDED = 1, 2
MODIFIER_EVENT_ON_DEATH, MODIFIER_PROPERTY_ATTACK_RANGE_BONUS = 3, 4
DOTA_UNIT_CAP_MELEE_ATTACK, DOTA_UNIT_CAP_RANGED_ATTACK = 1, 2
package.loaded["systems/enemy_attack_observer"] = { is_ready = function() return ready end }
package.loaded["core/team_alignment"] = {}
package.loaded["systems/wall_navigation_service"] = {}
local ai = require("modifiers/modifier_enemy_wall_ai")
local function unit(skip, formal)
    local u = { survival_wave_skip_contact_range_bonus = skip,
        survival_is_wave_monster = formal, capability = 1, base = 128,
        position = { x = -192, y = 96, z = 0 } }
    function u:IsNull() return false end
    function u:GetAbsOrigin() return self.position end
    function u:GetAttackCapability() return self.capability end
    function u:Script_GetAttackRange()
        return self.base + (self.mod and self.mod.contact_range_delta or 0)
    end
    return u
end
local function modifier(parent)
    local m = setmetatable({ sent = 0 }, { __index = ai })
    function m:GetParent() return parent end
    function m:StartIntervalThink() end
    function m:SetHasCustomTransmitterData(value) self.transmitter = value end
    function m:SendBuffRefreshToClients() self.sent = self.sent + 1 end
    if parent then parent.mod = m end
    return m
end
local function declares_range(m)
    local found, declarations = false, m:DeclareFunctions()
    for _, value in ipairs(declarations) do
        if value == MODIFIER_PROPERTY_ATTACK_RANGE_BONUS then found = true end
    end
    assert(declarations[#declarations - (found and 1 or 0)] == MODIFIER_EVENT_ON_DEATH)
    return found, declarations
end

-- Engine may declare first or create first. Both paths freeze the same policy.
for _, declare_first in ipairs({ true, false }) do
    for _, skip in ipairs({ true, false }) do
        local u = unit(skip, true)
        local m = modifier(u)
        if declare_first then assert(declares_range(m) == not skip) end
        m:OnCreated({ wall_entindex = 90 })
        local enabled, declarations = declares_range(m)
        assert(enabled == not skip and #declarations == (skip and 1 or 2))
        assert(m.contact_range_delta == 0 and m.transmitter == true)
        assert(u.survival_enemy_attack_owner == m)
        u.survival_wave_skip_contact_range_bonus = not skip
        u.capability = u.capability == 1 and 2 or 1
        m:OnRefresh()
        assert(declares_range(m) == enabled, "refresh/capability changes must not drift declarations")
    end
end

-- Only explicit, completed formal spawns opt out. Unknown or challenge callers
-- keep range; an early missing/null parent conservatively freezes it on.
for _, u in ipairs({ unit(nil, true), unit(true, nil), unit(true, false), unit(false, true) }) do
    local m = modifier(u)
    assert(declares_range(m))
    m:OnCreated({})
    assert(declares_range(m))
end
assert(declares_range(modifier(nil)))
local null_parent = unit(true, true)
null_parent.IsNull = function() return true end
assert(declares_range(modifier(null_parent)))
local unknown = modifier(nil)
unknown.GetParent = function() error("parent not available during declaration") end
assert(declares_range(unknown))

-- Legacy instances with no new field retain their original property and delta,
-- including a refresh before DeclareFunctions or stale/new parent metadata.
for _, refresh_first in ipairs({ true, false }) do
    local legacy = modifier(unit(true, true))
    legacy.contact_range_delta, legacy.ai_state, legacy.wall_entindex = 73, "attack", 91
    if refresh_first then legacy:OnRefresh() end
    assert(declares_range(legacy))
    legacy:OnRefresh()
    assert(declares_range(legacy) and legacy.contact_range_delta == 73
        and legacy.ai_state == "attack" and legacy.wall_entindex == 91)
end
ready = false
local fallback = modifier(unit(true, true))
fallback:OnCreated({})
local enabled, declarations = declares_range(fallback)
assert(not enabled and #declarations == 3 and declarations[1] == MODIFIER_EVENT_ON_ATTACK_START
    and declarations[2] == MODIFIER_EVENT_ON_ATTACK_LANDED)
ready = true
assert(#fallback:DeclareFunctions() == 3, "native attack event fallback stays registered")

-- Each of four melee contacts keeps exact center reach, including negative
-- compensation after an external range buff. Zero values are not a criterion
-- for dropping the property: waiting units must still be able to enter contact.
local wall = { GetAbsOrigin = function() return { x = 0, y = 0, z = 0 } end }
for _, y in ipairs({ -96, -32, 32, 96 }) do
    local u = unit(false, true)
    u.position.y = y
    local m = modifier(u)
    m:OnCreated({})
    assert(declares_range(m) and m:GetModifierAttackRangeBonus() == 0)
    m:UpdateContactRange(u, wall)
    local expected = math.ceil(math.sqrt(192 * 192 + y * y) + 8)
    assert(u:Script_GetAttackRange() == expected and m.sent == 1)
    m:UpdateContactRange(u, wall)
    assert(m.sent == 1, "stable contact does not transmit unchanged range")
    u.base = 700
    m:UpdateContactRange(u, wall)
    assert(m:GetModifierAttackRangeBonus() < 0 and u:Script_GetAttackRange() == expected)
    local delta = m:AddCustomTransmitterData().contact_range_delta
    server = false
    local client = modifier(unit(true, true))
    client:OnCreated({})
    assert(declares_range(client), "clients never infer a server-only opt-out")
    client:HandleCustomTransmitterData({ contact_range_delta = delta })
    assert(client:GetModifierAttackRangeBonus() == delta)
    server = true
    m:UpdateContactRange(u, false)
    assert(m:GetModifierAttackRangeBonus() == 0 and declares_range(m))
end

-- A future conversion must explicitly provide a new eligible instance. A
-- changed capability alone cannot safely rewrite an engine-cached declaration.
local converted = unit(true, true)
local old = modifier(converted)
old:OnCreated({})
assert(not declares_range(old))
converted.survival_wave_skip_contact_range_bonus = false
converted.capability = DOTA_UNIT_CAP_MELEE_ATTACK
old:OnRefresh()
assert(not declares_range(old))
local replacement = modifier(converted)
replacement:OnCreated({})
assert(declares_range(replacement))
replacement:UpdateContactRange(converted, wall)
assert(replacement:GetModifierAttackRangeBonus() > 0)
print("ENEMY_RANGE_DECLARATION_PASS frozen spawn policy, legacy/client fallback, four contacts, transmitter, conversion contract")
