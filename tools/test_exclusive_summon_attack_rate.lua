-- Test the production fixed-rate modifier and its server/client transmission.
-- Engine attack animations and actual cadence require an in-game check.
package.path = "scripts/vscripts/?.lua;" .. package.path
class = function(definition) return definition end
MODIFIER_PROPERTY_FIXED_ATTACK_RATE = 30
local server = true
IsServer = function() return server end
local name = "modifier_hero_exclusive_summon_attack_rate"
local definition = require("modifiers/" .. name)
assert(_G[name] == definition)

local function new_modifier(params)
    local modifier = setmetatable({sent = {}, enabled = 0, native_refreshes = 0}, {__index = definition})
    function modifier:SetHasCustomTransmitterData(enabled)
        assert(server and enabled == true)
        self.enabled = self.enabled + 1
    end
    function modifier:SendBuffRefreshToClients()
        assert(server and self.enabled == 1, "enable transmission before sending data")
        self.sent[#self.sent + 1] = self:AddCustomTransmitterData()
    end
    function modifier:ForceRefresh()
        assert(server)
        self.native_refreshes = self.native_refreshes + 1
        self:OnRefresh(params or {}) -- Even replayed creation params cannot revert rate.
    end
    modifier:OnCreated(params)
    return modifier
end

local function expect(modifier, interval)
    assert(math.abs(modifier:GetModifierFixedAttackRate() - interval) < 0.000000001)
    assert(modifier:AddCustomTransmitterData().attack_interval == modifier:GetModifierFixedAttackRate())
end

local source = new_modifier({attack_interval = 0.1})
assert(source:IsHidden() and not source:IsPurgable() and not source:RemoveOnDeath())
local properties = source:DeclareFunctions()
assert(#properties == 1 and properties[1] == MODIFIER_PROPERTY_FIXED_ATTACK_RATE,
    "inherit the final interval without applying another additive attack-speed bonus")
expect(source, 0.1)
assert(#source.sent == 1 and source.enabled == 1)
assert(source:SetAttackInterval(0.1) and #source.sent == 1,
    "unchanged 0.1-second polling must not continuously retransmit")
assert(source.native_refreshes == 0, "stable polling leaves native attack state alone")
source:OnRefresh({attack_interval = "0.23567"})
expect(source, 0.23567)
assert(#source.sent == 2 and source.sent[1].attack_interval == 0.1,
    "updates must preserve fractional seconds and previous immutable packets")
assert(source.native_refreshes == 1, "changing frequency invalidates the native property cache")
assert(source:SetAttackInterval(0.00001))
expect(source, 0.01)
assert(source:SetAttackInterval(0.7))
expect(source, 0.7)

local invalid = {false, "missing", 0, -1, 0 / 0, math.huge, -math.huge, "1e309"}
local sent_before = #source.sent
assert(source:SetAttackInterval(nil) == false)
source:OnRefresh(nil)
source:OnRefresh({})
for _, value in ipairs(invalid) do
    assert(source:SetAttackInterval(value) == false)
    source:OnRefresh({attack_interval = value})
    expect(source, 0.7)
    local fallback = new_modifier({attack_interval = value})
    expect(fallback, 1)
    assert(fallback.enabled == 1 and #fallback.sent == 1)
end
expect(new_modifier(), 1)
assert(#source.sent == sent_before, "invalid updates preserve the last valid interval without broadcasting")
source:HandleCustomTransmitterData({attack_interval = 0.5})
expect(source, 0.7)

server = false
local client = new_modifier({attack_interval = 0.2})
expect(client, 0.2)
assert(client.enabled == 0 and #client.sent == 0)
assert(client:SetAttackInterval(0.3) == false)
client:OnRefresh({attack_interval = 0.3})
expect(client, 0.2)
for _, packet in ipairs(source.sent) do
    client:HandleCustomTransmitterData(packet)
    expect(client, packet.attack_interval)
end
for _, value in ipairs(invalid) do
    client:HandleCustomTransmitterData({attack_interval = value})
    expect(client, 0.7)
end
client:HandleCustomTransmitterData(nil)
expect(client, 0.7)
client:HandleCustomTransmitterData({attack_interval = 0.00001})
expect(client, 0.01)
expect(new_modifier(), 1)
assert(client.enabled == 0 and #client.sent == 0, "client getters never issue server updates")

-- Cached require must still expose the class in a separate engine script scope.
local bridge = assert(loadfile("scripts/vscripts/modifier_bindings/" .. name .. ".lua"))
local engine_scope = setmetatable({}, {__index = _G})
setfenv(bridge, engine_scope)
assert(bridge() == definition and rawget(engine_scope, name) == definition)
local registry_file = assert(io.open("scripts/vscripts/core/modifier_registry.lua", "rb"))
local registry = registry_file:read("*a"); registry_file:close()
local _, registrations = registry:gsub('name%s*=%s*"' .. name .. '"%s*,%s*path%s*=%s*"modifiers/' .. name .. '"', "")
assert(registrations == 1, "dedicated production modifier must register exactly once")

print("EXCLUSIVE_SUMMON_ATTACK_RATE_PASS: fixed interval, server/client transmission, refresh, finite validation, minimum 0.01, no redundant broadcasts and cached binding")
