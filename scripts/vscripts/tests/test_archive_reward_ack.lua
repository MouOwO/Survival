-- Execute the real archive queue/reducer: notification follows persisted ACK,
-- never the kill intent, and retries retain one operation and one message.
package.path = "scripts/vscripts/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local result={};for key,child in pairs(value) do result[key]=copy(child) end;return result
end
local bus,events=require("core/event_bus"),require("core/events")
local schema=require("config/generated/player_gameplay_stats")
local profiles,writes,fail_write={},0,false
local tasks={}
package.loaded["core/scheduler"]={
    every=function(_,fn,key) tasks[key]=fn end, after=function(_,fn,key) tasks[key]=fn end,
    cancel=function(key) tasks[key]=nil end,
}
package.loaded["systems/player_profile_service"]={
    get_profile=function(id) return copy(profiles[id]) end,
    get_account_profile=function(id) return copy(profiles[id]) end,
    get_provider=function() return {persist_save=function() end} end,
    update_save_sections=function(id,sections)
        if fail_write then return {ok=false,error="disk_failed"} end
        for key,value in pairs(sections) do profiles[id].save[key]=copy(value) end
        writes=writes+1;profiles[id].revision=profiles[id].revision+1
        return {ok=true}
    end,
}
local function profile()
    local p={revision=1,save={archive={},gameplay_stats={},content_inventory={}},entitlements={}}
    for _,row in ipairs(schema.rows) do p.save.gameplay_stats[row.field_id]=row.default_value end
    return p
end
profiles[0],profiles[1]=profile(),profile()
GameRules={GetGameTime=function() return 0 end,IsCheatMode=function() return false end}
RandomInt=function(a) return a end
PlayerResource={GetPlayer=function(_,id) return id end,IsValidPlayerID=function(_,id) return id==0 or id==1 end}
CustomGameEventManager={RegisterListener=function() end,Send_ServerToPlayer=function() end}
local archive=require("systems/archive_service")
archive.init();archive.set_clock(function() return 1700000000 end)
local notifications={}
bus.subscribe(events.UI_NOTIFICATION,function(packet) notifications[#notifications+1]=copy(packet) end)
local function reward_messages()
    local found={};for _,packet in ipairs(notifications) do
        if packet.kind=="archive_reward" then found[#found+1]=packet end
    end;return found
end
local function challenge(id,key,sequence)
    return archive.record_challenge(id,key,sequence,"N10")
end
assert(challenge(0,"hunt_01",1).ok)
local rewards=reward_messages()
assert(#rewards==1 and writes==1 and profiles[0].revision==2)
assert(rewards[1].player_id==0 and rewards[1].rich_text==true)
assert(rewards[1].message:find('<font color="#',1,true) and not rewards[1].message:find('<br>',1,true))
assert(profiles[0].save.archive.fragment_counts.fragment_01>0,"real persistent fragment mutation precedes message")

fail_write=true
local failed=challenge(0,"hunt_02",2)
assert(not failed.ok and failed.error=="disk_failed")
assert(archive.has_pending(0) and #reward_messages()==1 and writes==1,"failed save cannot announce success")
fail_write=false;archive._test.flush(0)
assert(not archive.has_pending(0) and #reward_messages()==2 and writes==2)

local submissions={}
archive.set_provider({submit=function(id,command,done)
    submissions[#submissions+1]={id=id,command=copy(command),done=done}
end})
assert(challenge(1,"hunt_03",3).ok)
assert(#submissions==1 and #reward_messages()==2,"accepted kill intent waits for remote commit")
assert(tasks["archive_remote_timeout:1"]);tasks["archive_remote_timeout:1"]()
archive._test.flush(1)
assert(#submissions==2 and submissions[1].command.id==submissions[2].command.id)
local reducer=require("systems/archive_settlement")
local settled=reducer.settle(copy(profiles[1]),submissions[2].command,false)
assert(settled.ok and settled.response and settled.response.awarded>0)
profiles[1].save.archive,profiles[1].save.gameplay_stats=settled.archive,settled.gameplay_stats
profiles[1].revision=profiles[1].revision+1
submissions[1].done({ok=true,response=settled.response})
assert(#reward_messages()==2 and archive.has_pending(1),"stale callback cannot announce or clear new attempt")
submissions[2].done({ok=true,duplicate=true,response=settled.response})
assert(#reward_messages()==3 and not archive.has_pending(1),"recovered committed receipt is announced once")
submissions[2].done({ok=true,duplicate=true,response=settled.response})
assert(#reward_messages()==3,"duplicate callback cannot replay reward toast")
assert(reward_messages()[3].player_id==1,"recipient identity is not the source player")
assert(challenge(1,"hunt_03",3).ok)
submissions[3].done({ok=true,duplicate=true,response=settled.response})
assert(#reward_messages()==3,"re-enqueued durable receipt cannot replay an already announced reward")

assert(challenge(1,"hunt_04",4).ok)
submissions[4].done({ok=false,terminal=true,error="backend_rejected"})
assert(#reward_messages()==3 and not archive.has_pending(1),"rejected operation never reports reward")
assert(challenge(1,"hunt_05",5).ok)
submissions[5].done({ok=true,response={awarded=0,skipped_reason="今日获取次数已达上限"}})
assert(#reward_messages()==3 and not archive.has_pending(1))
assert(notifications[#notifications].message:find("未获得奖励",1,true),"zero reward has readable reason")
assert(challenge(1,"hunt_06",6).ok)
submissions[6].done({ok=true,duplicate=true})
assert(#reward_messages()==3,"legacy receipt without reward detail never invents a grant")
print("ARCHIVE_REWARD_ACK_PASS: real persistence, failed writes, lost responses, stale callbacks, retry identity, recipient isolation, caps and legacy receipts")
