-- Tools-only native attack-record accounting. Never required by gameplay.
-- Lua observes native lifetime notifications; it does not free C++ records.
local M = { modifier_name = 'modifier_wall_native_attack_record_audit' }
local Ledger = {};Ledger.__index=Ledger
local KEY='survival_native_attack_record_lifecycle'
local function valid(unit) return unit and (not unit.IsNull or not unit:IsNull()) end
local function native(object,name,...)
    if not object or type(object[name])~='function' then return false,'missing '..name end
    return pcall(object[name],object,...)
end
function M.new(options)
    options=options or {}
    return setmetatable({units={},pending=0,created=0,destroyed=0,drain_created=0,unknown_destroy=0,
        errors={},error_count=0,now=options.now or function() return GameRules:GetGameTime() end,
        timeout=math.max(.15,math.min(10,tonumber(options.timeout) or 5)),
        quiet_seconds=math.max(0,tonumber(options.quiet_seconds) or .1),
        min_drain_seconds=math.max(0,tonumber(options.min_drain_seconds) or .15)},Ledger)
end
function Ledger:error(message)
    self.error_count=self.error_count+1
    if #self.errors<32 then self.errors[#self.errors+1]=message end
end
function Ledger:check_deadline(stamp)
    -- A delayed final destroy must not erase that the bounded drain expired.
    if self.draining and not self.timed_out and self.pending>0
        and stamp-self.drain_started>=self.timeout then
        self.timed_out=true;self:error('native attack record drain timeout')
    end
end
function Ledger:attach(unit)
    if self.draining then return false,'drain already started' end
    if not valid(unit) then return false,'invalid audit unit' end
    if self.units[unit] then return true end
    if unit[KEY] then return false,'unit already owned by another record audit' end
    local row={owner=self,unit=unit,pending={},pending_count=0,created=0,destroyed=0,draining=false}
    self.units[unit]=row;unit[KEY]=row
    local ok,modifier=native(unit,'AddNewModifier',unit,nil,M.modifier_name,{})
    if not ok or not modifier then
        self.units[unit]=nil;unit[KEY]=nil
        self:error('native attack-record audit modifier unavailable')
        return false,'native attack-record audit modifier unavailable'
    end
    row.modifier=modifier
    return true
end
function Ledger:on_record(unit,event)
    local row=self.units[unit]
    if not row or not event or event.attacker~=unit then return end
    local record=tonumber(event.record)
    if not record or record<0 or record%1~=0 then self:error('attack record event missing native id');return end
    if row.pending[record] then self:error('duplicate native attack record '..record);return end
    local stamp=self.now()
    self:check_deadline(stamp)
    row.pending[record]=stamp;row.pending_count=row.pending_count+1;row.created=row.created+1
    self.pending=self.pending+1;self.created=self.created+1;self.last_record_at=stamp;self.last_event_at=stamp
    if self.draining then self.drain_created=self.drain_created+1 end
end
function Ledger:on_record_destroy(unit,event)
    local row=self.units[unit]
    if not row or not event or event.attacker~=unit then return end
    local record=tonumber(event.record)
    if record==nil or row.pending[record]==nil then
        self.unknown_destroy=self.unknown_destroy+1
        self:error('unknown native attack record destroy '..tostring(record));return
    end
    local stamp=self.now();self:check_deadline(stamp);self.last_event_at=stamp
    row.pending[record]=nil;row.pending_count=row.pending_count-1;row.destroyed=row.destroyed+1
    self.pending=self.pending-1;self.destroyed=self.destroyed+1
end
function Ledger:on_modifier_destroyed(unit)
    local row=self.units[unit]
    if row and not row.detaching and row.pending_count>0 then
        self:error('audit modifier removed with pending native attack records')
    end
end
function Ledger:begin_drain()
    if self.draining then return true end
    self.draining=true;self.drain_started=self.now();self.ready=false
    self.pending_at_drain_start=self.pending
    for unit,row in pairs(self.units) do
        row.draining=true
        if valid(unit) then
            for _,operation in ipairs({'SetForceAttackTarget','Stop','Interrupt','SetAcquisitionRange'}) do
                local ok,reason
                if operation=='SetForceAttackTarget' then ok,reason=native(unit,operation,nil)
                elseif operation=='SetAcquisitionRange' then ok,reason=native(unit,operation,0)
                else ok,reason=native(unit,operation) end
                if not ok then self:error('drain '..operation..' failed: '..tostring(reason)) end
            end
            local ok,reason=native(row.modifier,'SetStackCount',1)
            if not ok then self:error('drain disarm state failed: '..tostring(reason)) end
            ok,reason=native(row.modifier,'ForceRefresh')
            if not ok then self:error('drain disarm refresh failed: '..tostring(reason)) end
        elseif row.pending_count>0 then self:error('native unit lost before attack records drained') end
    end
    return true
end
function Ledger:poll()
    if not self.draining then return 'pending' end
    for unit,row in pairs(self.units) do
        if row.pending_count>0 and not valid(unit) and not row.reported_lost then
            row.reported_lost=true;self:error('native unit lost with pending attack records')
        end
    end
    local stamp=self.now()
    self:check_deadline(stamp)
    if self.timed_out then return 'timeout' end
    if self.error_count>0 then return 'failed' end
    if self.pending==0 and stamp-self.drain_started>=self.min_drain_seconds
        and stamp-math.max(self.last_event_at or self.drain_started,self.drain_started)>=self.quiet_seconds then
        self.ready=true;return 'ready'
    end
    return 'pending'
end
function Ledger:summary()
    local rows={}
    for unit,row in pairs(self.units) do
        local records={};for record,created_at in pairs(row.pending) do
            if #records<32 then records[#records+1]={record=record,age=math.max(0,self.now()-created_at)} end
        end
        table.sort(records,function(a,b) return a.record<b.record end)
        local ok,id=native(unit,'entindex')
        local capability_ok,capability=native(unit,'GetAttackCapability')
        rows[#rows+1]={id=ok and id or nil,valid=valid(unit),created=row.created,destroyed=row.destroyed,
            pending=row.pending_count,records=records,draining=row.draining,
            attack_capability=capability_ok and capability or nil}
    end
    return {pending=self.pending,created=self.created,destroyed=self.destroyed,drain_created=self.drain_created,
        unknown_destroy=self.unknown_destroy,errors=self.errors,error_count=self.error_count,
        pending_at_drain_start=self.pending_at_drain_start,
        draining=self.draining==true,ready=self.ready==true,timed_out=self.timed_out==true,
        elapsed=self.draining and self.now()-self.drain_started or 0,timeout=self.timeout,
        passed=self.ready==true and not self.timed_out and self.error_count==0 and self.pending==0,units=rows}
end
function Ledger:detach(unit)
    local row=self.units[unit]
    if not row then return true end
    if row.pending_count>0 then return false,'native attack records still pending' end
    row.detaching=true
    if row.modifier then native(row.modifier,'Destroy') end
    if unit[KEY]==row then unit[KEY]=nil end
    self.units[unit]=nil
    return true
end
return M
