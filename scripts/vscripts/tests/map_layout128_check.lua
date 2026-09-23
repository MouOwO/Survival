-- Explicit local check; temporary probe units are removed before returning.
if not IsServer() or not IsInToolsMode() or GetMapName() ~= 'template_map' then return end
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    print('[LAYOUT128] ' .. (ok and 'PASS ' or 'FAIL ') .. name .. ' ' .. tostring(detail or ''))
end
local destination = require('systems/destination_validation_service')
local expected = {{-12992,11904}, {12608,11904}, {-12992,-11904}, {12608,-11904}}
for player_id = 0, 3 do
    local name = 'player_' .. player_id .. '_hero_spawn'
    local e = Entities:FindByName(nil, name)
    local p = e and e:GetAbsOrigin()
    local xy = expected[player_id + 1]
    check(name, p and math.abs(p.x-xy[1])<1 and math.abs(p.y-xy[2])<1)
    if p then
        check(name..'.floor', math.abs(GetGroundHeight(p,nil)-128)<2)
        local unit = CreateUnitByName('npc_dota_creep_goodguys_melee', p, false, nil, nil, DOTA_TEAM_GOODGUYS)
        if unit then
            unit.survival_hero_id = 'layout_validation_probe'
            local ok, err = destination.teleport(unit, p, false)
            check(name..'.teleport', ok and (unit:GetAbsOrigin()-p):Length2D()<32, err)
            UTIL_Remove(unit)
        else check(name..'.probe', false) end
    end
end
for _,row in ipairs({{'rebirth_10_entry',-13100,4096},{'challenge_11_stage_10_entry',12544,5910}}) do
    local e=Entities:FindByName(nil,row[1]); local p=e and e:GetAbsOrigin()
    check(row[1]..'.location',p and math.abs(p.x-row[2])<1 and math.abs(p.y-row[3])<1)
end
for _,id in ipairs({'05','06','09','10_stage_01'}) do
    local entry=Entities:FindByName(nil,'challenge_'..id..'_entry')
    local suffix=id=='10_stage_01' and '_spawn' or '_boss_spawn'
    local target=Entities:FindByName(nil,'challenge_'..id..suffix)
    local p=entry and entry:GetAbsOrigin()
    check('native_'..id..'.entry',p and GridNav:IsTraversable(p) and not GridNav:IsBlocked(p)
        and math.abs(GetGroundHeight(p,nil)-128)<2)
    check('native_'..id..'.path',entry and target and GridNav:CanFindPath(p,target:GetAbsOrigin()))
end
local center=Vector(-1024,4096,16)
for i=0,3 do
    local e=Entities:FindByName(nil,'c6_player_'..i..'_entrance')
    check('central_entrance_'..i,e and GridNav:CanFindPath(center,e:GetAbsOrigin()))
    local b=Entities:FindByName(nil,'player_'..i..'_builder_spawn')
    check('builder_'..i,b and math.abs(GetGroundHeight(b:GetAbsOrigin(),nil)-384)<2)
end
for _,xy in ipairs({{-15000,0},{15000,0},{0,15000},{0,-15000},{-12000,8000},{12000,9000},{0,-7000}}) do
    local p=Vector(xy[1],xy[2],16)
    check('ocean_'..xy[1]..'_'..xy[2],not GridNav:IsTraversable(p) or GridNav:IsBlocked(p))
end
local cfg=require('config/map_layouts/template_map')
local tree=Entities:FindByName(nil,'c6_resource_tree')
check('resource_tree_config',tree and (tree:GetAbsOrigin()-Vector(cfg.resource_tree.x,cfg.resource_tree.y,cfg.resource_tree.z)):Length()<1)
print(string.format('[LAYOUT128] SUMMARY passed=%d failed=%d',passed,failed))
