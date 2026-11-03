local file=assert(io.open("scripts/vscripts/tests/test_archive_ui_wire_budget.lua","rb"));local text=file:read("*a");file:close()
local prefix=assert(text:match("^(.-)\nreset%(%)\nlocal before_timers"))
local body=[=[
reset()
local lookup=assert(loadfile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"))()
local handlers,published,snapshots={}, {},0
local accepted_nonce
local transport={register_view=function(id,h)assert(not handlers[id]);handlers[id]=h end,publish=function(id,view,ops,options) published[#published+1]={id=id,view=view,ops=copy(ops),full=options and options.full} end}
local bridge=require("ui/compact_archive_views").new({lookup=lookup,transport=transport,
 snapshot=function(player,category)snapshots=snapshots+1;return archive.snapshot(player,category)end,
 header=function(player,category,current,h)h.revision=current.revision;return h end,
 profile=function()return profile end,
 intent=function(player,kind,id,level,nonce)accepted_nonce=nonce;if kind=="social" then return {ok=true,pending=true} end;return {ok=false,error="synthetic denied",terminal=true}end})
local count=0;for _ in pairs(handlers) do count=count+1 end;assert(count==20 and snapshots==0 and #published==0)
local clear=bridge.view("clear");assert(clear==101)
assert(handlers[clear].open(0));assert(snapshots==1)
bridge.changed(0,profile,{content_inventory={}});assert(snapshots==1 and #published==0,"stable source does no work")
handlers[clear].close(0);profile.revision=2;bridge.changed(0,profile,{replace=true});assert(snapshots==1 and #published==0,"closed source does no work")
local commerce=bridge.view("commerce_goods");assert(commerce==120)
assert(handlers[commerce].open(0));local opened=snapshots
local item=require("config/generated/archive_commerce_goods").rows[1]
profile.revision=3;profile.save.content_inventory[item.ownership_id]=3
local change=bridge.changed(0,profile,{content_inventory={item.ownership_id}})
assert(change.rows==1 and snapshots==opened and #published==1 and not published[1].full,"one inventory source uses one authoritative project_one, not full snapshot")
local standalone=require("systems/archive_commerce_goods").project_one(profile,item.id)
local full=require("systems/archive_commerce_goods").project(profile)
assert(encode(standalone)==encode(full[1]),"single item and existing full authority must agree")
bridge.changed(0,profile,{content_inventory={item.ownership_id}});assert(#published==1 and snapshots==opened)
bridge.changed(0,profile,{pending_changed=true});assert(snapshots==opened,"pending metadata never rebuilds rows")
profile.revision=4;bridge.changed(0,profile,{replace=true});assert(snapshots==opened+1 and published[#published].full)
local before=#published
local denied=handlers[commerce].intent
local okay=pcall(denied,0,"archive_title",{arg_a=lookup.by_key["archive:titles:peak_perfection"],request_token=1});assert(not okay,"cross-category intent must reject")
assert(#published==before)
handlers[commerce].close(0);bridge.changed(0,profile,{replace=true});assert(snapshots==opened+1)
local metric=bridge.inspect();assert(metric.changed_rows==1 and metric.full_rebuilds==1)
local friend=bridge.view("friend");assert(handlers[friend].open(0))
handlers[friend].intent(0,"archive_action",{arg_a=lookup.by_key["archive:category:friend"],request_token=7})
assert(accepted_nonce and published[#published].ops)
handlers[friend].close(0);local closed=#published
profile.revision=5;profile.save.archive.social_counts={friend_01=1}
assert(bridge.complete(0,"friend",accepted_nonce,{ok=true,terminal=true}))
assert(#published==closed,"closed completion retains ACK without sending a page")
local snapshot_count=snapshots;handlers[friend].probe(0);assert(snapshots==snapshot_count,"pending intent probe reads no catalogue")
local response=published[#published];assert(response.full);local ack={}
for _,op in ipairs(response.ops) do ack[lookup.fields[op.field].name]=op.value end
assert(ack.request_token==7 and ack.success==1 and ack.terminal==1 and ack.arg_a==5)
local repeats=#published;assert(bridge.complete(0,"friend",accepted_nonce,{ok=true,terminal=true}));assert(#published==repeats,"duplicate terminal ACK emits nothing")
assert(handlers[friend].open(0));local unknown,error_message=bridge.complete(0,"friend","unknown_nonce",{ok=true,terminal=true});assert(unknown==nil and error_message=="archive_intent_unknown")
raw_print(encode({pass=true,views=20,closed_snapshots=0,stable_snapshots=0,one_item_rows=change.rows,one_item_full_snapshots=0,pending_full_snapshots=0,explicit_replacement_full=1,metrics=metric}))
]=]
assert(loadstring(prefix.."\n"..body,"@real_compact_archive_views"))()
