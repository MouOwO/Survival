'use strict';
const fs=require('fs');
// Local Tools test setup via the same validated building requests as ability_build_wall.
const code=`local bus=require('core/event_bus');local e=require('core/events');local state=bus.request(e.BUILDER_GET_REQUEST,{player_id=0});local builder=state and state.builder
if not builder then print('[SHOP_WALL_TEST] no_builder');return end
local origin=builder:GetAbsOrigin();local ability=builder:FindAbilityByName('ability_build_wall');local errors={}
for radius=128,1536,128 do for _,v in ipairs({Vector(radius,0,0),Vector(-radius,0,0),Vector(0,radius,0),Vector(0,-radius,0)}) do
local pos=GetGroundPosition(origin+v,builder);local payload={caster=builder,building_id='wall',position=pos,source_ability=ability}
local can=bus.request(e.BUILD_CAN_PLACE_REQUEST,payload)
if can and can.ok then local result=bus.request(e.BUILD_REQUEST,payload);print('[SHOP_WALL_TEST] request '..tostring(result and result.ok)..' '..tostring(result and result.error));return else errors[tostring(can and can.error)]=true end
end end
for err in pairs(errors) do print('[SHOP_WALL_TEST] blocked '..err) end`;
fs.writeFileSync('design_refs/shop_ui_12h/work/native_build_wall_request.json',JSON.stringify([{name:'dota_run_lua',arguments:{code}}]));console.log('NORMAL_BUILD_REQUEST_FIXTURE_READY');
