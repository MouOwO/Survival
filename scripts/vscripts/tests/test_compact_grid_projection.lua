package.path='scripts/vscripts/?.lua;'..package.path
local lookup=require('config/generated/ui_static_catalog_lookup')
local wire=require('ui/compact_wire')
local factory=assert(require('ui/compact_grid_projection').new(lookup))
local schema=assert(wire.compile_lookup(lookup,1))
local state=factory.initialize()
local config=lookup.grid.maps.template_map
local profile
for _,p in ipairs(lookup.grid.profiles)do if p.ability_name=='ability_build_arrow_tower'then profile=p end end
assert(profile)
local scope=1
local header={grid_scope_version=scope,layout_ready=1,profiles=lookup.grid.profiles,
 static_grid={bounds=config.grid_display_bounds or config.build_bounds,build_bounds=config.build_bounds,height=config.build_ground_height}}
local initial=assert(state.ingest('ui_grid_placement_profiles',header))
local cells={}
local width,height=profile.grid_footprint_x,profile.grid_footprint_y
for x=-math.floor(width/2),-math.floor(width/2)+width-1 do for y=-math.floor(height/2),-math.floor(height/2)+height-1 do
 cells[#cells+1]={x=(x+0.5)*config.cell_size,y=(y+0.5)*config.cell_size,z=384,ok=1}
end end
local validation={grid_scope_version=scope,session_id=77,request_id=1,ability_name=profile.ability_name,building_id=profile.building_id,
 success=1,error='',request_anchor_x=0,request_anchor_y=0,anchor_x=0,anchor_y=0,
 world_x=0,world_y=0,world_z=384,cells=cells,area='3|64|-2|-2|4|4|384|aaaaaaaa',area_complete=1}
local first=assert(state.ingest('ui_grid_placement_validation',validation))
local full=state.full_ops()
local stable_words=state.inspect().area_words
for _=1,1000 do assert(#assert(state.ingest('ui_grid_placement_validation',validation))==0)end
assert(state.inspect().area_words==stable_words,'same area must not be reparsed on request/heartbeat repeats')
validation.request_id=2;validation.cells[1].ok=0
local delta=assert(state.ingest('ui_grid_placement_validation',validation));assert(#delta==2,'only request sequence and occupancy bitmask changed')
local words_before=state.inspect().area_words
local area_delta=assert(state.ingest('ui_grid_placement_area',{grid_scope_version=scope,session_id=77,ability_name=profile.ability_name,
 area='3|64|-2|-2|4|4|384|9aaaaaaa',complete=1}))
assert(state.inspect().area_words==words_before+1)
local binding={schema=1,schema_sha256=lookup.sha256,session=9,epoch=1,view=4}
local packets,report=assert(wire.encode(schema,binding,1,full,{full=true,value_budget=24}))
local maximum,total=0,0;for _,packet in ipairs(packets)do maximum=math.max(maximum,#packet.d+25);total=total+#packet.d+25 end
assert(maximum<=49)
local changed=assert(wire.encode(schema,binding,2,delta,{value_budget=24}))
local delta_total=0;for _,packet in ipairs(changed)do delta_total=delta_total+#packet.d+25 end
local atlas=assert(lookup.grid.atlases[1])
local static=factory.initialize()
local static_initial=assert(static.ingest('ui_grid_placement_static_area',{area=atlas.area,grid_scope_version=1}))
assert(static.inspect().static_base==1 and static.inspect().static_overrides==0)
local static_packets=assert(wire.encode(schema,{schema=1,schema_sha256=lookup.sha256,session=9,epoch=1,view=6},1,static_initial,{full=true,value_budget=24}))
local static_total=0;for _,packet in ipairs(static_packets)do static_total=static_total+#packet.d+25;assert(#packet.d+25<=49)end
assert(static_total<#atlas.area)
local prefix,digits=atlas.area:match('^(.*|)([^|]+)$')
local digit=tonumber(digits:sub(1,1),16);local low=digit%4;local changed_digit=math.floor(digit/4)*4+(low==1 and 2 or 1)
local changed_area=prefix..string.format('%x',changed_digit)..digits:sub(2)
local static_delta=assert(static.ingest('ui_grid_placement_static_area',{area=changed_area,grid_scope_version=1}))
assert(#static_delta==1 and static.inspect().static_overrides==1,'one live tree/terrain word must override the local candidate')
local static_delta_packets=assert(wire.encode(schema,{schema=1,schema_sha256=lookup.sha256,session=9,epoch=1,view=6},2,static_delta,{value_budget=24}))
local static_delta_total=0;for _,packet in ipairs(static_delta_packets)do static_delta_total=static_delta_total+#packet.d+25 end
local zero_area=prefix..'00000000'..digits:sub(9)
local static_zero=assert(static.ingest('ui_grid_placement_static_area',{area=zero_area,grid_scope_version=1}))
assert(#static_zero==1 and static_zero[1].value==0,'zero override must not mean reuse nonzero local candidate')
local json=require('core/json_encoder')
if arg and arg[1]=='emit'then
 print(json.encode({schema_sha256=lookup.sha256,initial_ops=full,expected=validation,delta_ops=delta,area_ops=area_delta,config=header,
  static_initial_ops=static_initial,static_delta_ops=static_delta,static_zero_ops=static_zero,
  metrics={full_packets=#packets,full_bytes=total,max_native_bytes=maximum,delta_packets=#changed,delta_bytes=delta_total,
   static_legacy_area_bytes=#atlas.area,static_k0_packets=#static_packets,static_k0_bytes=static_total,static_k1_bytes=static_delta_total,static_live_words=atlas.word_count}}))
else print('COMPACT_GRID_PROJECTION_PASS full_packets='..#packets..' full_bytes='..total..' delta_packets='..#changed..' delta_bytes='..delta_total..' max49 stable1000=0 static_K0='..static_total..'B static_K1='..static_delta_total..'B old_area='..#atlas.area..'B')end
