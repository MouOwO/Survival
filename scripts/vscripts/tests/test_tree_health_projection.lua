package.path = "scripts/vscripts/?.lua;scripts/vscripts/?/init.lua;" .. package.path
local tree_system = require("systems/tree_system")
local projection = require("combat/endless_stat_projection")
local levels = require("config/generated/tree_progression").rows
local tree = {
    SetBaseMaxHealth=function(self,h) assert(h > 0 and h <= 100000000); self.base=h end,
    SetMaxHealth=function(self,h) assert(h > 0 and h <= 100000000); self.max=h end,
    SetHealth=function(self,h) assert(h >= 1 and h <= self.max); self.health=h end,
    SetPhysicalArmorBaseValue=function()end,
}
for _, row in ipairs(levels) do
    tree_system._apply_level_for_test(tree,row.level)
    local logical = tonumber(projection.for_ui(tree, tree.health, "health"))
    assert(math.abs(logical-row.health)/row.health < 1e-12)
    local damage=projection.incoming(tree,row.health*.25)
    assert(math.abs(damage/tree.max-.25)<1e-12)
end
assert(#levels == 100)
class = function(t) return t end
IsServer = function() return true end
local modifier = require("modifiers/modifier_tree_progression")
local level = 1
tree.GetHealth = function(self) return self.health end
tree.survival_tree_depleted_callback = function(self)
    level = math.min(100,level+1)
    tree_system._apply_level_for_test(self,level)
end
local instance = setmetatable({GetParent=function()return tree end},{__index=modifier})
for hit=1,120 do
    tree.health=1
    instance:OnTakeDamage({unit=tree,damage=100000000})
    assert(tree.health==tree.max and tree.health>1)
end
assert(level==100)
print("TREE_HEALTH_PROJECTION_PASS: all 100 levels fit native health and preserve logical health/damage ratios")
