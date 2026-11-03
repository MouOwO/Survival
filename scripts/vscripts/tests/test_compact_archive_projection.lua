-- Reuse the existing real 945-row fixture boot environment, not copied mock
-- rows. No game engine, persistence, HTTP, SDK or player data is contacted.
local file=assert(io.open("scripts/vscripts/tests/test_archive_ui_wire_budget.lua","rb"));local text=file:read("*a");file:close()
local prefix=assert(text:match("^(.-)\nreset%(%)\nlocal before_timers"),"real archive fixture boundary changed")
local body=[=[
reset()
local lookup=assert(loadfile("scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"))()
local wire=require("ui/compact_wire")
local factory=assert(require("ui/compact_archive_projection").new(lookup))
local schema=assert(wire.compile_lookup(lookup,1))
local pages=expected_pages();local result={schema=lookup.sha256,pages={},variants={},rows=0,full_packets=0,full_bytes=0,max_native_bytes=0,stable_ops=0,delta_ops=0,delta_packets=0}
local function float_words(value,path,out)
 if type(value)=="table" then for key,child in pairs(value) do local p=copy(path);p[#p+1]=key;float_words(child,p,out) end
 elseif type(value)=="number" and value~=math.floor(value) then local words=assert(wire.float64_words(value));out[#out+1]={path=path,hi=words.hi,lo=words.lo} end
end
for category,snapshot in pairs(pages) do
 local instance,ops=factory.initialize(snapshot);assert(instance,category..":"..tostring(ops))
 local empty,metrics=instance.update(nil,{});assert(#empty==0 and metrics.row_visits==0 and metrics.header_visits==0)
 local binding={schema=1,schema_sha256=lookup.sha256,session=1,epoch=1,view=101}
 local packets,report=assert(wire.encode(schema,binding,1,ops,{full=true}))
 for _,packet in ipairs(packets) do assert(#packet.d<=24);result.max_native_bytes=math.max(result.max_native_bytes,25+#packet.d) end
 local floats={};float_words(snapshot,{},floats)
 result.pages[category]={expected=snapshot,ops=ops,packets=packets,floats=floats}
 result.rows=result.rows+#snapshot.rows;result.full_packets=result.full_packets+#packets;result.full_bytes=result.full_bytes+report.ascii_bytes+25*#packets
 if category=="commerce_goods" then
  local changed=copy(snapshot.rows[1]);changed.count=3;changed.owned=1;changed.unlocked=1;changed.completed=1
  local changes,m=assert(instance.update(nil,{changed}));assert(m.row_visits==1 and m.registry_scans==0)
  local delta=assert(wire.encode(schema,binding,2,changes));result.delta_ops=#changes;result.delta_packets=#delta
  result.pages[category].delta={ops=changes,packets=delta,expected=changed}
  local duplicate,dm=instance.update(nil,{changed});assert(#duplicate==0 and dm.row_visits==1)
  local bad=copy(changed);bad.name="unregistered display string"
  local rejected,reason=instance.update(nil,{bad});assert(rejected==nil and reason:find("archive_unmapped_row",1,true))
 elseif category=="friend" then
  profile.save.archive.social_counts={[snapshot.rows[1].id]=1}
  local changed=archive.snapshot(0,"friend");changed.daily_limits=nil
  local ops,m=assert(instance.update(changed,{changed.rows[1]}));assert(m.row_visits==1)
  local packets=assert(wire.encode(schema,binding,2,ops));local floats={};float_words(changed,{},floats)
  result.pages[category].social_delta={expected=changed,packets=packets,floats=floats}
  profile.save.archive.social_counts=nil
 end
end
assert(result.rows==945 and result.max_native_bytes<=49)
-- Real projector variants: pass changes boss targets; manual title selection,
-- fragment totals and distinct level/count; owned materials, building/work,
-- loaded fishing and a social quality becoming exhausted.
profile.revision=2;profile.entitlements.archive_pass={active=true}
local saved=profile.save.archive
saved.buildings={faith=100000,levels={},earned_by_day={}}
for _,row in ipairs(require("config/generated/archive_building_items").rows) do saved.buildings.levels[row.item_id]=row.max_level end
saved.online={actual_seconds=6000,map_seconds=12000,coins=10000,map_level=2,work_levels={},cursors={}}
for _,row in ipairs(require("config/generated/archive_work_items").rows) do saved.online.work_levels[row.item_id]=row.max_level end
saved.fragment_counts={fragment_01=37};saved.fragment_totals={fragment_01=145};saved.fragment_levels={fragment_01=7}
saved.shadow_counts={shadow_01=3};saved.cage_counts={cage_01=4}
saved.title_selection_manual=true;saved.equipped_title="peak_perfection";saved.endless_best_wave=200;saved.boss_kills=30
profile.save.fishing_inventory={}
for _,row in ipairs(require("config/generated/archive_fishing_items").rows) do profile.save.fishing_inventory[row.reward_id]=2 end
saved.social_counts={}
for _,row in ipairs(require("config/generated/archive_social_items").rows) do if row.pool_id=="friend" and row.quality=="N" then saved.social_counts[row.item_id]=row.max_owned end end
saved.social_last_draw={pool_id="friend",name=require("config/generated/archive_social_items").rows[1].display_name,id="internal-guid-not-rendered",effects={hero_initial_attack=3}}
local changed_pages=expected_pages()
for category,page in pairs(changed_pages) do
 local instance,ops=factory.initialize(page);assert(instance,category..":"..tostring(ops))
 local expected=copy(page);expected.last_draw={pool_id=page.last_draw.pool_id,name=page.last_draw.name}
 local floats={};float_words(expected,{},floats);result.variants[category]={expected=expected,ops=ops,floats=floats}
end
saved.social_counts={};saved.social_tickets={};saved.social_last_draw=nil;profile.revision=10
local rule=require("config/generated/archive_social_rules").by_id.friend
saved.social_tickets[rule.currency_id]=3
local before=archive.snapshot(0,"friend");before.daily_limits=nil
local instance,ops=factory.initialize(before);assert(instance,ops)
local item=before.rows[1];saved.social_counts[item.id]=1;saved.social_tickets[rule.currency_id]=2;profile.revision=11
saved.social_last_draw={pool_id="friend",name=item.name,id="synthetic:social_draw:typed-token",effects={}}
local after=archive.snapshot(0,"friend");after.daily_limits=nil
local delta=assert(instance.update(after,{after.rows[1]}));local floats={};float_words(after,{},floats)
local expected=copy(after);expected.last_draw={pool_id="friend",name=item.name}
result.collection={before=before,initial_ops=ops,delta_ops=delta,after=expected,floats=floats,item_id=item.id}
-- A real partial inventory is unknown, not silently zero-owned.
profile.save.content_inventory=nil;profile.save.gameplay_stats=nil;profile.save.archive=nil
local unknown=archive.snapshot(0,"commerce_goods");unknown.daily_limits=nil
local unknown_instance,unknown_ops=factory.initialize(unknown);assert(unknown_instance,tostring(unknown_ops));assert(unknown_instance.inspect().known==0)
result.unknown={expected=unknown,ops=unknown_ops}
raw_print((arg and arg[1]=="emit") and encode(result) or encode({pass=true,rows=result.rows,full_packets=result.full_packets,full_native_bytes=result.full_bytes,max_native_bytes=result.max_native_bytes,delta_ops=result.delta_ops,delta_packets=result.delta_packets,stable_ops=0}))
]=]
assert(loadstring(prefix.."\n"..body,"@real_compact_archive_fixture"))()
