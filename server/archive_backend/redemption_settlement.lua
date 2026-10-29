-- Reuse the installed purchase reducer with trusted zero-price definitions.
-- No recharge/VIP progression or payment order is created by a redemption.
local commerce = require("systems/commerce_settlement")
local aliases = require("config/content_id_aliases")
local M = {}
local function copy(v)
    if type(v)~="table" then return v end
    local out={};for k,n in pairs(v)do out[k]=copy(n)end;return out
end
local function count(inventory,id)
    local total=0;id=aliases.canonical(id)
    for raw,n in pairs(inventory)do if aliases.canonical(raw)==id then total=total+(tonumber(n)or 0)end end
    return total
end
function M.settle(profile,command)
    assert(command.kind=="redemption_redeem")
    local rewards=assert(command.rewards)
    local current=copy(profile);local granted,skipped=0,0
    for _,product in ipairs(rewards.products)do
        local g=product.grants
        assert(product.price==0 and product.currency=="u_coin" and product.enabled==true)
        assert((g.required_vip_level or 0)==0 and #(g.vip_claims or {})==0)
        assert(#(g.entitlements or {})==0 and not next(g.vip_claim_effects or {}))
        assert(not product.item_id:match("^vip") and not product.sku:find("vip",1,true))
        for field in pairs(product.effects or {})do assert(not field:find("vip",1,true))end
        for id in pairs(g.items or {})do assert(not id:find("vip",1,true))end
        local owned=count(current.save.content_inventory or {},product.item_id)
        if product.purchase_limit>0 and owned>=product.purchase_limit then
            skipped=skipped+1
        else
            local result=commerce.settle(current,{kind="commerce_purchase",id=command.id,
                sku=product.sku,request_id=command.request_id})
            if result.ok then
                current.save.archive=result.archive
                current.save.content_inventory=result.content_inventory
                current.save.gameplay_stats=result.gameplay_stats
                granted=granted+1
            elseif result.error=="already_owned" or result.error=="component_already_owned" then
                skipped=skipped+1
            else return {ok=false,error="redeem_rewards_pending"} end
        end
    end
    local inventory=current.save.content_inventory or {}
    -- Bundle ownership markers are separate from the deduplicated leaf rewards.
    for _,marker in ipairs(rewards.markers or {})do
        assert(type(marker)=="string" and not marker:find("vip",1,true))
        if count(inventory,marker)==0 then inventory[marker]=1 end
    end
    local archive=current.save.archive or {}
    archive.commerce=archive.commerce or {};archive.commerce.balances=archive.commerce.balances or {}
    for currency,amount in pairs(rewards.wallet or {})do
        assert(currency=="u_coin" and type(amount)=="number" and amount>0 and amount==math.floor(amount))
        local n=(archive.commerce.balances[currency]or 0)+amount
        assert(n<=9007199254740991);archive.commerce.balances[currency]=n
    end
    return {ok=true,archive=archive,content_inventory=inventory,gameplay_stats=current.save.gameplay_stats,
        response={ok=true,title=command.label,granted=granted,skipped=skipped}}
end
return M
