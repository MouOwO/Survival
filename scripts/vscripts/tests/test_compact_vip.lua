package.path='scripts/vscripts/?.lua;'..package.path
local module=require('ui/compact_vip_view')
local rewards=require('systems/archive_vip_rewards')
local level_calls,handler,sends=0,nil,{}
local handles,profiles,bound,open={},{},{},{}
local subscriptions={}
local T={register_view=function(id,h)assert(id==8);handler=h end,
 is_open=function(id)return open[id]end,is_bound=function(id)return bound[id]end,
 publish=function(id,view,ops)sends[#sends+1]={id=id,ops=ops};return true end}
local current=true
local api=module.new({lookup={by_key={['vip:state']=10},field_by_name={known=1,count=2}},transport=T,
 player=function(id)return handles[id]end,profile=function(id)return profiles[id]end,
 current=function()return current end,subscribe=function(id,on)subscriptions[id]=on end,
 rewards={recharge_total=rewards.recharge_total,level=function(p)level_calls=level_calls+1;return rewards.level(p)end}})
for id=0,3 do handles[id]={};bound[id]=true;open[id]=true
 local ops=handler.open(id);assert(ops[1].value==0 and ops[2].remove)
 profiles[id]={save={gameplay_stats={vip_recharge_total_fen=5000*(id+1)}}}
 assert(api.changed(id));assert(sends[#sends].id==id)
end
local count,calls=#sends,level_calls
for n=1,1000 do for id=0,3 do assert(api.changed(id).unchanged)end end
assert(#sends==count and level_calls==calls,'stable changes never rebuild catalogue or rescan levels')
profiles[1].save.gameplay_stats.vip_recharge_total_fen=100000
assert(api.changed(1));assert(level_calls==calls+1 and sends[#sends].ops[2].value==5)
profiles[1]=nil;assert(api.changed(1));assert(sends[#sends].ops[1].value==0 and sends[#sends].ops[2].remove)
handles[1]={};profiles[1]={save={gameplay_stats={vip_recharge_total_fen=5000}}}
assert(api.changed(1));assert(sends[#sends].ops[2].value==1,'slot reuse cannot retain another owner grade')
handler.close(1);open[1]=false;assert(subscriptions[1]==false);local previous=#sends
profiles[1].save.gameplay_stats.vip_recharge_total_fen=10000;assert(api.changed(1));assert(#sends==previous)
api.reset();assert(subscriptions[0]and subscriptions[2]and subscriptions[3])
current=false;assert(not api.changed(0));assert(handler.snapshot(0)==nil)
api.dispose();assert(not api.changed(0))
print('COMPACT_VIP_PASS original grade rules,4 owners,1000 stable0 sends/grade scans,unknown/close/reset/world guards; synthetic not FPS')
