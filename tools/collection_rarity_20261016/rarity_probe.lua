-- Authoritative social collection odds, boundaries and retry invariants.
package.path = "scripts/vscripts/?.lua;" .. package.path
local social = require("systems/archive_social_rewards")
local items = require("config/generated/archive_social_items")
local rules = require("config/generated/archive_social_rules")
local qualities = {"N", "R", "SR", "SSR", "UR"}
local base = {N=.6, R=.25, SR=.1, SSR=.045, UR=.005}
local calls = 0
RandomInt = function(a, b) calls=calls+1; return math.floor((a+b)/2) end
local function equal(a, b, message)
    assert(math.abs(a-b)<1e-10, (message or "probability differs") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function save_for(pool)
    return {social_counts={}, social_tickets={[rules.by_id[pool].currency_id]=100000}, social_unlocks={}, daily={}}
end
local function index(rows)
    local result={};for _,row in ipairs(rows) do result[row.id]=row end;return result
end
local function draw(save, pool, roll, command)
    local effects=0
    command=command or {id="rarity-test", kind="social_draw", pool_id=pool, roll=roll}
    local ok, err=social.apply(command, save, {}, function(_, item)
        effects=effects+1;assert(item.draw_enabled~=false,"pending effect was applied")
    end)
    assert(ok, err)
    assert(effects==1,"a draw applies effects exactly once")
    local drawn
    for _,item in ipairs(items.rows) do
        if item.display_name==save.social_last_draw.name and item.pool_id==pool then drawn=item;break end
    end
    return assert(drawn), command
end
local expected_count={N=5,R=10,SR=12,SSR=10,UR=3}
for _,pool in ipairs({"ex","friend","wife","beast"}) do
    local save=save_for(pool)
    local rows=social.rows(save,pool)
    assert(#rows==40)
    local counts, sum={},0
    local info=social.info(save,pool)
    for _,q in ipairs(qualities) do
        equal(info.rarity_probabilities[q],base[q],pool.." group probability "..q)
        equal(info.rarity_base_probabilities[q],base[q])
    end
    for _,row in ipairs(rows) do
        counts[row.quality]=(counts[row.quality] or 0)+1
        local item=items.by_id[row.id]
        assert(row.count==0 and row.target==item.max_owned,"projection must preserve counts and caps")
        equal(row.draw_probability,row.initial_draw_probability)
        if row.draw_enabled==0 then
            equal(row.draw_probability,0)
            assert(pool=="wife" and (row.id=="wife_31" or row.id=="wife_39"))
        else
            equal(row.quality_draw_probability,base[row.quality])
        end
        sum=sum+row.draw_probability
    end
    equal(sum,1,pool.." item probabilities sum")
    for _,q in ipairs(qualities) do assert(counts[q]==expected_count[q],"five-tier classification "..pool..q) end
    for _,probe in ipairs({{0,"N"},{.6,"R"},{.85,"SR"},{.95,"SSR"},{.995,"UR"},{1-1e-12,"UR"},{1-2^-53,"UR"}}) do
        assert(draw(save_for(pool),pool,probe[1]).quality==probe[2],"quality interval boundary "..pool..probe[1])
    end
end
-- Exactly stratified samples exercise the real settlement rather than a second
-- probability implementation. Each draw starts with the same empty inventory.
local observed={N=0,R=0,SR=0,SSR=0,UR=0}
for n=0,9999 do
    local item=draw(save_for("wife"),"wife",(n+.5)/10000)
    observed[item.quality]=observed[item.quality]+1
end
assert(observed.N==6000 and observed.R==2500 and observed.SR==1000 and observed.SSR==450 and observed.UR==50,
    "real settlement must produce configured quality intervals")
-- A quality boundary and an item boundary share one half-open random fraction.
assert(draw(save_for("wife"),"wife",.6).item_id=="wife_06")
assert(draw(save_for("wife"),"wife",.625).item_id=="wife_07")

local save=save_for("wife")
save.social_counts.wife_06=3
local rows=index(social.rows(save,"wife"))
equal(rows.wife_06.draw_probability / rows.wife_07.draw_probability,.5,"within-quality remaining-copy weights")
equal(social.info(save,"wife").rarity_probabilities.R,.25,"partial ownership does not change quality weight")
equal(rows.wife_06.initial_draw_probability,.025,"initial odds do not depend on current save")
save.social_counts.wife_06=6
rows=index(social.rows(save,"wife"))
equal(rows.wife_06.draw_probability,0,"full character excluded")
assert(draw(copy(save),"wife",.6).item_id=="wife_07","full first character cannot be chosen")

save=save_for("wife")
for _,item in ipairs(items.rows) do if item.pool_id=="wife" and item.quality=="UR" then save.social_counts[item.item_id]=item.max_owned end end
local info=social.info(save,"wife")
equal(info.rarity_probabilities.UR,0)
equal(info.rarity_probabilities.N,.6/.995,"empty quality renormalizes")
equal(info.rarity_probabilities.SSR,.045/.995)
assert(draw(copy(save),"wife",1-1e-12).quality=="SSR","last eligible quality receives the tail interval")

save=save_for("wife")
for _,item in ipairs(items.rows) do if item.pool_id=="wife" then save.social_counts[item.item_id]=item.max_owned end end
save.social_counts.wife_40=0
info=social.info(save,"wife")
equal(info.rarity_probabilities.UR,1)
equal(index(social.rows(save,"wife")).wife_40.draw_probability,1)
assert(draw(save,"wife",0).item_id=="wife_40","last unowned character is guaranteed")
local before_tickets=save.social_tickets.rose
local before_calls=calls
local ok,err=social.apply({kind="social_draw",pool_id="wife"},save,{},function()error("full pool effect")end)
assert(not ok and err=="本奖池已全部集满")
assert(save.social_tickets.rose==before_tickets and calls==before_calls,"full pool neither charges nor rolls")
info=social.info(save,"wife")
for _,q in ipairs(qualities) do equal(info.rarity_probabilities[q],0) end

-- A persistence failure discards the staged save but retains the queued
-- command. Reapplying it must use the original random fraction and reward.
local original=save_for("wife")
local first,command=draw(copy(original),"wife",nil)
before_calls=calls
local second=draw(copy(original),"wife",nil,command)
assert(first.item_id==second.item_id and calls==before_calls,"retry must reuse the command random fraction")
assert(type(command.roll)=="number" and command.roll>=0 and command.roll<1)
assert(original.social_tickets.rose==100000 and not next(original.social_counts),"staged retries do not touch original save")
print("collection rarity: four pools, exact five-tier intervals, published odds, ownership/caps, pending exclusion, renormalization and deterministic retries PASS")
