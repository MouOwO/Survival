-- Stackable permanent rewards are derived from inventory, never added again
-- to saved combat stats on login, refresh, purchase or a repeated claim.
local rules = require('config/generated/archive_stackable_items')
local aliases = require('config/content_id_aliases')
local M = { MAX_INTEGER = 9007199254740991 }
local definitions = {}
for _, row in ipairs(rules.rows) do
    if row.enabled ~= false then
        local item = definitions[row.item_id]
        if not item then
            item = {id=row.item_id,name=row.display_name,max_owned=row.max_owned,
                quality=row.quality,description=row.description or '',rules={}}
            definitions[row.item_id] = item
        end
        assert(item.max_owned==row.max_owned,'stackable_limit_conflict')
        item.rules[#item.rules+1] = row
        if row.description and row.description~='' then item.description=row.description end
    end
end
local function integer(value)
    local n=tonumber(value)
    assert(n and n==n and n>=0 and n<=M.MAX_INTEGER and n==math.floor(n),'stackable_count_invalid')
    return n
end
function M.definition(id) return definitions[aliases.canonical(id)] end
function M.count(save,id)
    local total=0;id=aliases.canonical(id)
    for raw,value in pairs((save or {}).content_inventory or {}) do
        if aliases.canonical(raw)==id then
            local n=integer(value)
            assert(n<=M.MAX_INTEGER-total,'stackable_count_limit')
            total=total+n
        end
    end
    return total
end
local function legacy_ember_growth(save,archive,stats)
    local state=archive and archive.stackable_items
    if state and state.legacy_ember_growth~=nil then
        local n=tonumber(state.legacy_ember_growth)
        assert(n and n>=0 and n<=.1,'stackable_legacy_marker_invalid')
        return n
    end
    -- Only an existing effect receipt proves that the first copy already
    -- applied 0.1. Unattributed saved stats are preserved without guessing
    -- their origin, including historical bulk purchases.
    local markers=(save or {}).lottery_applied_item_effects or {}
    return markers.lottery_ember_of_legacy==true and .1 or 0
end
function M.grant(save,archive,stats,id,amount)
    id=aliases.canonical(id)
    local item=assert(definitions[id],'stackable_item_unknown')
    local requested=integer(amount);local before=M.count(save,id)
    local cap=item.max_owned>0 and item.max_owned or M.MAX_INTEGER
    local accepted=math.min(requested,math.max(0,cap-before))
    archive.stackable_items=archive.stackable_items or {}
    if id=='lottery_ember_of_legacy' and archive.stackable_items.legacy_ember_growth==nil then
        archive.stackable_items.legacy_ember_growth=legacy_ember_growth(save,archive,stats)
    end
    save.content_inventory=save.content_inventory or {}
    for raw in pairs(save.content_inventory) do
        if raw~=id and aliases.canonical(raw)==id then save.content_inventory[raw]=nil end
    end
    save.content_inventory[id]=before+accepted
    return accepted,requested-accepted
end
function M.project(save,base)
    save=save or {};base=base or save.gameplay_stats or {}
    if save.stackable_projection_applied==true then return {} end
    local result={}
    for id,item in pairs(definitions) do
        local count=M.count(save,id)
        if item.max_owned>0 then count=math.min(item.max_owned,count) end
        local contribution={}
        local highest={}
        for _,row in ipairs(item.rules) do
            if row.mode=='per_copy' then
                contribution[row.effect_id]=(contribution[row.effect_id] or 0)+count*row.effect_value
            elseif count>row.threshold then
                local previous=highest[row.effect_id]
                if not previous or row.threshold>previous.threshold then highest[row.effect_id]=row end
            end
        end
        for field,row in pairs(highest) do contribution[field]=(contribution[field] or 0)+row.effect_value end
        if id=='lottery_ember_of_legacy' then
            contribution.hero_basic_attack_growth=math.max(0,(contribution.hero_basic_attack_growth or 0)
                -legacy_ember_growth(save,save.archive,base))
        end
        for field,n in pairs(contribution) do
            if n~=0 then result[field]=(result[field] or 0)+n end
        end
    end
    return result
end
return M
