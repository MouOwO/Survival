package.path='scripts/vscripts/?.lua;'..package.path
local listeners,packets,ready={},{},false
local players={[0]={id=0},[1]={id=1}}
DOTA_MAX_TEAM_PLAYERS=2
PlayerResource={IsValidPlayerID=function(_,id)return players[id]~=nil end,GetPlayer=function(_,id)return players[id]end}
CustomGameEventManager={RegisterListener=function(_,name,fn)listeners[name]=fn end,
    Send_ServerToPlayer=function(_,player,name,payload)packets[#packets+1]={player=player.id,name=name,payload=payload}end}
package.loaded['systems/startup_loading_service']={is_player_ready=function()return ready end}
for _,name in ipairs({'systems/building_system','ui/weapon_synthesis_snapshot_service','ui/combat_stat_projection',
    'config/asset_catalog','systems/hero_summon_projection','systems/building_batch_upgrade_service',
    'systems/gold_mine_batch_upgrade_service'})do package.loaded[name]={}end
package.loaded['config/tree_config']={unit_name='enemy_tree'}
local bus,events=require('core/event_bus'),require('core/events')
bus.reset()
local document=string.rep('a',8100)
local catalog={ok=true,catalog_md5=string.rep('c',32),config_hash=string.rep('b',64),catalog_sequence=7,
    session_id='trusted_catalog_session',catalog_json=document}
local requests,draws,resyncs,reads=0,0,0,0
bus.handle_request(events.LOTTERY_CATALOG_REQUEST,function(payload)
    assert(payload.player_id==0 and (payload.md5=='local_md5' or payload.md5==''))
    requests=requests+1;payload.complete(catalog);return {pending=true}
end)
bus.handle_request(events.LOTTERY_DRAW_REQUEST,function(payload)
    assert(payload.expected_config_hash==catalog.config_hash);draws=draws+1;return {ok=true}
end)
bus.handle_request(events.LOTTERY_EXCHANGE_REQUEST,function(payload)
    assert(payload.expected_config_hash==catalog.config_hash);return {ok=true}
end)
bus.handle_request(events.LOTTERY_CACHE_RESYNC_REQUEST,function(payload)
    assert(payload.player_id==0);resyncs=resyncs+1;return {pending=true}
end)
bus.handle_request(events.LOTTERY_READ_ACK_REQUEST,function(payload)
    assert(payload.player_id==0 and payload.read_action=='details' and payload.revision=='r1')
    reads=reads+1;payload.complete({ok=true,snapshot={selected_pool_id='map',account_id='123',
        session_id='match',profile_mode='standard',config_hash=catalog.config_hash}});return {pending=true}
end)
require('ui/ui_request_router').init()
listeners.ui_lottery_catalog_sync(nil,{PlayerID=0,player_id=1,md5='local_md5'})
assert(requests==1 and #packets==3,'public catalog can warm during initial admission')
local rebuilt={}
for index,packet in ipairs(packets) do
    local value=packet.payload
    assert(packet.player==0 and packet.name=='ui_lottery_catalog')
    assert(#value.catalog_chunk<=3500 and value.chunk==index and value.chunks==3)
    assert(value.catalog_sequence==7 and value.transfer_id==1 and value.config_hash==catalog.config_hash)
    assert(value.session_id=='trusted_catalog_session')
    rebuilt[#rebuilt+1]=value.catalog_chunk
end
assert(table.concat(rebuilt)==document,'ASCII chunks reconstruct the exact MD5 document')
local count=#packets
listeners.ui_lottery_draw_request(nil,{PlayerID=0,pool_id='map',request_id='not_ready'})
listeners.ui_lottery_cache_resync(nil,{PlayerID=0})
assert(draws==0 and resyncs==0,'catalog admission must not admit transactions or private requests')
assert(requests==2,'catalog missing-chunk recovery is available during admission')
count=#packets
bus.emit(events.LOTTERY_CHANGED,{player_id=0,snapshot={account_id='123',tickets=5}})
assert(#packets==count+1 and packets[#packets].name=='ui_lottery_snapshot','trusted profile push warms before UI admission')
packets={}
bus.emit(events.LOTTERY_CATALOG_CHANGED,{catalog=catalog})
assert(#packets==6 and packets[1].player==0 and packets[4].player==1,'hot update broadcasts only public content to every client')
catalog.unchanged=true;packets={}
listeners.ui_lottery_catalog_sync(nil,{PlayerID=0,md5='local_md5'})
assert(#packets==1 and packets[1].payload.unchanged==1 and not packets[1].payload.catalog_chunk)
assert(packets[1].payload.catalog_sequence==7,'same-version handshake preserves the room sequence')
assert(packets[1].payload.session_id=='trusted_catalog_session')
ready=true
package.loaded['systems/player_context_service']={is_defeated=function()return false end}
listeners.ui_lottery_cache_resync(nil,{PlayerID=0,player_id=1})
listeners.ui_lottery_read_ack(nil,{PlayerID=0,player_id=1,pool_id='map',read_action='details',revision='r1'})
assert(resyncs==1 and reads==1)
assert(packets[#packets].payload.snapshot_scope=='read' and packets[#packets].payload.account_id=='123')
listeners.ui_lottery_draw_request(nil,{PlayerID=0,pool_id='map',expected_config_hash=catalog.config_hash})
listeners.ui_lottery_exchange_request(nil,{PlayerID=0,pool_id='map',expected_config_hash=catalog.config_hash})
assert(draws==1,'ready draw and exchange preserve the expected-version precondition')
local before=requests
listeners.ui_lottery_catalog_sync(nil,{PlayerID=99,player_id=0,md5='local_md5'})
assert(requests==before,'forged player fields cannot impersonate a connected slot')
print('LOTTERY_CATALOG_ROUTER_PASS: startup/chunks/broadcast/sequence/private-push/gates/source-identity/read-ack')
