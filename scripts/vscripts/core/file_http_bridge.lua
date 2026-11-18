-- Native KeyValues transport only: no console execution, profile provider, grant, or Lua
-- evaluation. The helper forwards HTTPS to one fixed backend. Native HTTP wins.
-- Initialization is O(allowlist), once/world. Idle work=0. Active waits are O(1)
-- plus indexed deadline removals O(k log N), N<=16. Body work is incremental
-- O(bytes): <=2 outbound 1KiB chunks and <=1 native KV read per think.
-- Each reply block contains <=16*192 bytes. No server console command or RPC.
local config = require("config/file_http_bridge")
local encoder = require("core/json_encoder")
local Queue = require("core/deadline_queue")
local M, state = {}, nil
local PREFIX = "[SFB1] "
local DIRECTORY = "cfg/survival_ws4_http_bridge/"
local BOOTSTRAP = "cfg/survival_ws4_http_bridge_bootstrap.txt"
local CURSOR = "cfg/survival_ws4_http_bridge_cursor.txt"
local POST = {}
for _, name in ipairs({"player-auth/start", "player-auth/poll", "session/authenticate",
    "session/login", "profile", "lottery/catalog", "lottery/snapshot", "archive/config",
    "archive/command", "archive/endless-batch", "archive/endless-leaderboard", "online-time/checkpoint",
    "payments/catalog", "payments/create", "payments/status", "payments/cancel"}) do
    POST["/v1/" .. name] = true
end
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local inverse = {}
for index = 1, #alphabet do inverse[alphabet:sub(index,index)] = index - 1 end

local function encode64(value)
    local out = {}
    for index=1,#value,3 do
        local a,b,c=value:byte(index,index+2)
        local n=a*65536+(b or 0)*256+(c or 0)
        out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
            ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
            ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "=")
            ..(c and alphabet:sub(n%64+1,n%64+1) or "=")
    end
    return table.concat(out)
end
local function decode64(value)
    if type(value)~="string" or #value>256 or #value%4~=0 then return nil end
    local out={}
    for index=1,#value,4 do
        local a,b,c,d=value:sub(index,index),value:sub(index+1,index+1),value:sub(index+2,index+2),value:sub(index+3,index+3)
        local x,y,z,w=inverse[a],inverse[b],inverse[c],inverse[d]
        if not x or not y or (not z and c~="=") or (not w and d~="=")
            or (c=="=" and d~="=") or ((c=="=" or d=="=") and index+3~=#value) then return nil end
        local n=x*262144+y*4096+(z or 0)*64+(w or 0)
        out[#out+1]=string.char(math.floor(n/65536)%256)
            ..(z and string.char(math.floor(n/256)%256) or "")..(w and string.char(n%256) or "")
    end
    return table.concat(out)
end
local function integer(value,low,high)
    local number=tonumber(value)
    return number and number==math.floor(number) and number>=low and number<=high and number or nil
end
local function clock()
    local value=type(Time)=="function" and Time() or nil
    return type(value)=="number" and value==value and value>=0 and value<math.huge and value or nil
end
local function current(run)
    return state==run and type(GetMapName)=="function" and GetMapName()=="template_map"
        and GameRules and GameRules:GetGameModeEntity()==run.world
end
local function emit(run,value)
    value.epoch,value.nonce=run.epoch,run.nonce
    print(PREFIX..encoder.encode(value))
end
local function finish(run,job,status,body)
    if run.pending[job.id]~=job then return end
    run.pending[job.id]=nil;run.count=run.count-1;run.deadlines:remove(job.id)
    if run.incoming and run.incoming.id==job.id then run.incoming=nil end
    if run.count==0 then run.outgoing={};run.first,run.last=1,0 end
    if status==0 then
        print('[SFB_STATUS] timeout ticks='..tostring(run.tick_count)..' reads='..tostring(run.read_count)
            ..' armed='..tostring(run.nonce~=nil)..' seconds='..tostring((clock() or job.started)-job.started))
    end
    if current(run) then pcall(job.callback,{StatusCode=status,Body=body or ""}) end
end
local function readkv(run,path,kind)
    run.read_count=run.read_count+1
    local ok,value=pcall(function() local data=LoadKeyValues(path);return data end)
    if not ok or type(value)~="table" or integer(value.protocol,2,2)~=2 or value.kind~=kind then return nil end
    return value
end
local function bootstrap(run)
    local value=readkv(run,BOOTSTRAP,"bootstrap")
    local nonce=value and value.nonce
    if type(nonce)~="string" or #nonce~=33 or not nonce:match('^n[a-f0-9]+$') then return end
    run.nonce=nonce
    emit(run,{event="ready",protocol=2,tools=false})
end
local function cursor(run)
    local value=readkv(run,CURSOR,"reply")
    if not value or value.nonce~=run.nonce or value.epoch~=run.epoch then return end
    local serial,id,status=integer(value.serial,1,999999999),integer(value.id,1,9999999),integer(value.status,0,599)
    local bytes,chunks,blocks=integer(value.bytes,0,config.maximum_response_bytes),integer(value.chunks,0,43691),integer(value.blocks,1,2731)
    if not serial or not id or not status or not bytes or not chunks or not blocks
        or serial<=run.last_reply or not run.pending[id]
        or chunks~=math.ceil(bytes/config.inbound_chunk_bytes)
        or blocks~=math.max(1,math.ceil(chunks/config.inbound_block_chunks)) then return end
    run.last_reply=serial
    run.incoming={serial=serial,id=id,status=status,bytes=bytes,chunks=chunks,blocks=blocks,
        next_block=1,parts={},received_bytes=0}
end
local function block(run,reply)
    local index=reply.next_block
    local path=DIRECTORY.."b_"..run.nonce.."_"..run.epoch.."_"..reply.serial.."_"..index..".txt"
    local value=readkv(run,path,"block")
    local expected=math.min(config.inbound_block_chunks,reply.chunks-(index-1)*config.inbound_block_chunks)
    if not value or value.nonce~=run.nonce or value.epoch~=run.epoch
        or integer(value.serial,1,999999999)~=reply.serial or integer(value.block,1,reply.blocks)~=index
        or integer(value.chunks,0,config.inbound_block_chunks)~=expected then return end
    local staged,total={},0
    for offset=1,expected do
        local encoded=type(value.parts)=="table" and value.parts["p"..offset] or nil
        if type(encoded)~="string" or encoded:sub(1,1)~="b" then return end
        local raw=decode64(encoded:sub(2))
        local chunk=(index-1)*config.inbound_block_chunks+offset
        local bytes=chunk==reply.chunks and reply.bytes-(chunk-1)*config.inbound_chunk_bytes or config.inbound_chunk_bytes
        if not raw or #raw~=bytes then return end
        staged[offset]=raw;total=total+#raw
    end
    for offset=1,expected do reply.parts[#reply.parts+1]=staged[offset] end
    reply.received_bytes=reply.received_bytes+total;reply.next_block=index+1
    if index==reply.blocks and #reply.parts==reply.chunks and reply.received_bytes==reply.bytes then
        local job=run.pending[reply.id]
        if job then
            local body=table.concat(reply.parts)
            emit(run,{event="ack",serial=reply.serial,id=reply.id})
            finish(run,job,reply.status,body)
        end
    end
end
local function permitted()
    local ok,world=pcall(function()
        if config.enabled~=true or config.protocol~=2 or config.base_url~="https://pay.xiaofengnet.com/ws4-web"
            or type(IsServer)~="function" or IsServer()~=true or type(IsInToolsMode)~="function" or IsInToolsMode()~=false
            or type(IsDedicatedServer)~="function" or IsDedicatedServer()~=false
            or type(GetMapName)~="function" or GetMapName()~="template_map"
            or type(LoadKeyValues)~="function" or type(DoUniqueString)~="function" or not clock() then return nil end
        if require("config/release_profile").channel~="production" or require("config/player_web_auth").enabled~=true then return nil end
        local access=require("core/test_access_policy")
        local gate=require("config/test_access")
        if gate.enabled~=true or type(gate.allowed_steamids)~="table" or #gate.allowed_steamids~=5
            or access.enabled()~=true or access.init()~=true then return nil end
        return GameRules:GetGameModeEntity()
    end)
    return ok and world or nil
end
local function tick(run)
    if not current(run) or run.count==0 then run.polling=false;return nil end
    run.tick_count=run.tick_count+1
    local now=clock()
    if not now then run.polling=false;return nil end
    local first=run.deadlines:peek()
    while first and first.task.run_at<=now do
        local job=run.pending[first.id]
        run.deadlines:pop()
        if job then finish(run,job,0,"") end
        first=run.deadlines:peek()
    end
    if run.count==0 then run.polling=false;return nil end
    if not run.nonce then
        if now>=run.next_bootstrap then
            run.next_bootstrap=now+2
            bootstrap(run)
        end
        return 0.2
    end
    -- Only the FIFO head is inspected. A request remains one queue entry while
    -- its bytes are streamed, never a per-tick full pending-table traversal.
    local budget=2
    while budget>0 and run.first<=run.last do
        local job=run.outgoing[run.first]
        if not job or run.pending[job.id]~=job then
            run.outgoing[run.first]=nil;run.first=run.first+1
        elseif not job.announced then
            emit(run,{event="request",id=job.id,method=job.method,path=job.path,headers=job.headers,
                bytes=#job.body,chunks=math.ceil(#job.body/config.outbound_chunk_bytes),timeout_ms=job.timeout_ms})
            job.announced=true;budget=budget-1
            if #job.body==0 then run.outgoing[run.first]=nil;run.first=run.first+1 end
        else
            local chunk=job.body:sub(job.offset,job.offset+config.outbound_chunk_bytes-1)
            emit(run,{event="body",id=job.id,index=job.chunk,data=encode64(chunk)})
            job.offset=job.offset+#chunk;job.chunk=job.chunk+1;budget=budget-1
            if job.offset>#job.body then run.outgoing[run.first]=nil;run.first=run.first+1 end
        end
    end
    local reply=run.incoming
    if reply then block(run,reply) else cursor(run) end
    return (run.incoming or run.first<=run.last) and 0.02 or 0.2
end

function M.create(method,url)
    local path=type(url)=="string" and url:sub(1,#config.base_url)==config.base_url and url:sub(#config.base_url+1) or nil
    if not path or not ((method=="GET" and path=="/health") or (method=="POST" and POST[path])) then return nil end
    local world=permitted()
    if not world then return nil end
    if not state or state.world~=world then
        local epoch=DoUniqueString("sfb")
        if type(epoch)~="string" or #epoch>24 or not epoch:match('^[A-Za-z0-9_]+$') then return nil end
        state={world=world,epoch=epoch,pending={},count=0,serial=0,last_reply=0,deadlines=Queue.new(),
            outgoing={},first=1,last=0,next_bootstrap=0,polling=false,tick_count=0,read_count=0}
    end
    local run=state
    local request={headers={},body="",timeout_ms=30000,sent=false}
    function request:SetHTTPRequestHeaderValue(name,value)
        if self.sent or type(value)~="string" or #value>512 or value:find('[\r\n]')
            or (name~="Authorization" and name~="X-Survival-Wire") then self.invalid=true;return false end
        self.headers[name]=value;return true
    end
    function request:SetHTTPRequestRawPostBody(content_type,body)
        if self.sent or content_type~="application/json; charset=utf-8" or type(body)~="string"
            or #body>config.maximum_request_bytes then self.invalid=true;return false end
        self.body=body;return true
    end
    function request:SetHTTPRequestAbsoluteTimeoutMS(value)
        if self.sent or not integer(value,100,30000) then self.invalid=true;return false end
        self.timeout_ms=value;return true
    end
    function request:Send(callback)
        local now=clock()
        if self.sent or self.invalid or not now or type(callback)~="function" or not current(run) or run.count>=config.maximum_pending
            or run.serial>=9999999 then return false end
        self.sent=true
        run.serial=run.serial+1
        local job={id=run.serial,method=method,path=path,headers=self.headers,body=self.body,
            timeout_ms=self.timeout_ms,callback=callback,offset=1,chunk=1,started=now}
        run.pending[job.id]=job;run.count=run.count+1;run.last=run.last+1;run.outgoing[run.last]=job
        run.deadlines:put(job.id,{run_at=now+self.timeout_ms/1000})
        if not run.polling then
            run.polling=true
            if not run.started_diagnostic then
                run.started_diagnostic=true
                print('[SFB_STATUS] started protocol=2')
            end
            -- As with startup_loading_service: perform the first bounded step
            -- synchronously, then schedule a positive delay. Never defer the
            -- initial handshake behind a zero-time think during custom setup.
            local delay=tick(run)
            if delay then
                run.world:SetContextThink("SurvivalFileHttpBridge",function() return tick(run) end,delay)
            end
        end
        return true
    end
    return request
end

return M
