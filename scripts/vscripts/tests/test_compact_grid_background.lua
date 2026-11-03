package.path='scripts/vscripts/?.lua;'..package.path
local L=require('config/generated/ui_static_catalog_lookup')
local lookup={};for key,value in pairs(L)do lookup[key]=value end
lookup.grid={};for key,value in pairs(L.grid)do lookup.grid[key]=value end;lookup.grid.atlases={}
local wire=require('ui/compact_wire');local schema=assert(wire.compile_lookup(L,1))
local tasks,handlers,published={},{},{}
local opened={[4]=true,[6]=true};local busy=false;local channel
local scheduler={after=function(_,fn,key)tasks[key]=fn end,cancel=function(key)tasks[key]=nil end}
local transport={register_view=function(id,handler)handlers[id]=handler end,is_bound=function()return true end,
 is_open=function(_,view)return opened[view]end,queue_depth=function()return busy and 1 or 0 end,
 publish=function(id,view,ops,options)published[#published+1]={id=id,view=view,ops=ops,options=options};return true end}
channel=require('ui/compact_grid_views').new({lookup=lookup,transport=transport,scheduler=scheduler,
 bootstrap=function()end,bootstrap_static=function(id)channel.send(id,'ui_grid_placement_static_area',{area=L.grid.atlases[1].area,grid_scope_version=1})end,
 dispatch=function()return true end})
handlers[4].open(0)
local initial=handlers[6].open(0)
for _,op in ipairs(initial)do assert(lookup.records[op.record].kind~='static_word')end
local step=assert(tasks['grid_static_delivery:0'])
busy=true;assert(step()==0.05 and #published==0,'background must wait for its previous short transaction')
busy=false
local arguments={grid_session=9,grid_request=1,grid_actor=10,grid_ability=20,grid_profile=L.by_key['grid:profile:ability_build_arrow_tower']}
for axis,value in pairs({x=-1024,y=4096,z=384})do local p=assert(wire.float64_words(value));arguments['grid_'..axis..'_hi']=p.hi;arguments['grid_'..axis..'_lo']=p.lo end
handlers[4].input(0,2,arguments,2)
local packets,total,maximum,batches=0,0,0,0
for revision=1,1000 do
 local delay=step();batches=batches+1
 if #published>0 then
  local result=published[#published];assert(result.view==6 and result.options.priority==false and #result.ops<=4)
  if revision==1 then assert(tonumber(lookup.records[result.ops[1].record].business_id)>1,'first batch must prioritize the cursor ROI over the beginning of the whole map')end
  local encoded=assert(wire.encode(schema,{schema=1,schema_sha256=L.sha256,session=7,epoch=1,view=6},revision,result.ops,{full=revision==1,value_budget=24}))
  for _,p in ipairs(encoded)do packets=packets+1;total=total+#p.d+25;maximum=math.max(maximum,#p.d+25)end
 end
 if not delay then break end
 assert(revision<999)
end
assert(maximum<=49 and batches>100)
handlers[6].open(0);step=assert(tasks['grid_static_delivery:0'])
local before=#published;handlers[6].close(0);assert(tasks['grid_static_delivery:0']==nil);step();assert(#published==before,'close cancels pending atlas work and old callback')
print('COMPACT_GRID_BACKGROUND_PASS absent_candidate=576words batch<=4 ROI_first close_cancel max='..maximum..' total_bytes='..total..' frames='..packets..' batches='..batches..' (synthetic_not_native)')
