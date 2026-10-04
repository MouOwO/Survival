-- Authoritative reducer: wallet debit, ownership and effects commit together.
local catalog=require('config/generated/commerce_catalog')
local definitions=require('config/generated/player_gameplay_stats')
local M={}
local currencies={u_coin='U币',shop_points='积分',shop_gold='金币'}
local function copy(value)
    if type(value)~='table' then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function balance(state,key)
    local value=(state.balances or {})[key] or 0
    assert(type(value)=='number' and value>=0 and value<=9007199254740991 and value==math.floor(value),'commerce_wallet_invalid')
    return value
end
local function blocked(p,inventory,stats,state)
    if not p or not p.enabled then return 'product_unavailable' end
    if p.purchase_limit>0 and (tonumber(inventory[p.item_id]) or 0)>=p.purchase_limit then return 'already_owned' end
    for id,n in pairs(p.grants.items) do
        if (tonumber(inventory[id]) or 0)+n>p.grants.item_limits[id] then return 'component_already_owned' end
    end
    for field,n in pairs(p.effects) do
        local rule=definitions.by_id[field]
        if not rule then return 'commerce_effect_invalid' end
        local value=(tonumber(stats[field]) or tonumber(rule.default_value) or 0)+n
        if rule.max_value and value>rule.max_value then return 'attribute_limit_reached' end
    end
    if balance(state,p.currency)<p.price then return 'commerce_balance_insufficient' end
    return ''
end
function M.snapshot(profile)
    local save=profile.save or {};local state=(save.archive or {}).commerce or {}
    local inventory=save.content_inventory or {};local stats=save.gameplay_stats or {}
    local products={};local wallet={}
    for key in pairs(currencies) do wallet[key]=balance(state,key) end
    for _,p in ipairs(catalog.rows) do
        if p.enabled then
            local reason=blocked(p,inventory,stats,state)
            products[#products+1]={sku=p.sku,title=p.title,description=p.description,category_id=p.category_id,
                product_type=p.product_type,icon=p.icon,price=p.price,currency=p.currency,currency_name=p.currency_name,
                purchase_method='wallet',purchase_limit=p.purchase_limit,owned=tonumber(inventory[p.item_id]) or 0,
                enabled=reason=='',disabled_reason=reason,reward_lines=copy(p.grants.lines),source_id=p.source_id}
        end
    end
    return {ok=true,products=products,balances=wallet,categories={{id='technology',label='科技与服务'},{id='item',label='道具与材料'}}}
end
function M.settle(profile,command)
    if command.kind=='commerce_catalog' then return M.snapshot(profile) end
    if command.kind~='commerce_purchase' then return {ok=false,error='commerce_command_invalid'} end
    local p=catalog.by_id[command.sku]
    local archive=copy(profile.save.archive or {});local inventory=copy(profile.save.content_inventory or {})
    local stats=copy(profile.save.gameplay_stats or {})
    local state=archive.commerce or {balances={}};archive.commerce=state;state.balances=state.balances or {}
    local reason=blocked(p,inventory,stats,state)
    if reason~='' then return {ok=false,error=reason} end
    -- Never accept a price, balance, quantity or reward from the client.
    state.balances[p.currency]=balance(state,p.currency)-p.price
    inventory[p.item_id]=(tonumber(inventory[p.item_id]) or 0)+1
    for id,n in pairs(p.grants.items) do inventory[id]=(tonumber(inventory[id]) or 0)+n end
    for field,n in pairs(p.effects) do
        stats[field]=(tonumber(stats[field]) or tonumber(definitions.by_id[field].default_value) or 0)+n
    end
    return {ok=true,archive=archive,content_inventory=inventory,gameplay_stats=stats,
        response={ok=true,sku=p.sku,title=p.title,currency=p.currency,price=p.price,
            balance=state.balances[p.currency],request_id=command.request_id}}
end
return M
