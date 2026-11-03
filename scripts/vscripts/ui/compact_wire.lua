-- Presentation codec only. This module grants no player, reward or SDK authority.
-- cw/{d=<base64url>} is the entire native event. Native byte limits require a
-- fresh net_showmsg measurement; a business/base64 byte count is not that proof.
-- A trusted bootstrap must bind the full static-schema SHA before using the
-- short schema/session/epoch/view tokens. Tokens must not silently wrap/reuse.
local M={EVENT="cw",KEY="d",VERSION=1,DEFAULT_VALUE_BUDGET=24}
M.ROLLOVER_REVISION=1048575
local MAX_UINT,MAX_SINT,MAX_TOKEN,MAX_REVISION=4294967295,2147483647,16383,2097151
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local reverse={};for index=1,#alphabet do reverse[alphabet:sub(index,index)]=index-1 end
local compiled=setmetatable({},{__mode="k"})
local calibrated=setmetatable({},{__mode="k"})
local function need(ok,message) if not ok then error(message,0) end end
local function integer(value,minimum,maximum)
    return type(value)=="number" and value==value and value==math.floor(value)
        and value>=minimum and value<=maximum
end
local function guarded(fn,...)
    local ok,value,detail=pcall(fn,...)
    if ok then return value,detail end
    return nil,tostring(value)
end
local function dense(value,maximum)
    need(type(value)=="table","array_required")
    local length=#value;need(length<=maximum,"array_limit")
    local count=0
    for key in pairs(value) do need(integer(key,1,length),"sparse_or_named_array");count=count+1 end
    need(count==length,"sparse_or_named_array");return length
end
local function uint(value)
    need(integer(value,0,MAX_UINT),"uint32_required")
    local bytes={}
    repeat
        local part=value%128;value=math.floor(value/128)
        bytes[#bytes+1]=string.char(part+(value>0 and 128 or 0))
    until value==0
    return table.concat(bytes)
end
local function read_uint(raw,offset)
    local value,multiplier=0,1
    for index=0,4 do
        local byte=raw:byte(offset+index);need(byte~=nil,"truncated_varint")
        value=value+(byte%128)*multiplier;need(value<=MAX_UINT,"varint_overflow")
        if byte<128 then
            need(index==0 or byte~=0,"noncanonical_varint")
            return value,offset+index+1
        end
        multiplier=multiplier*128
    end
    error("varint_overflow",0)
end
local function b64encode(raw)
    local out={}
    for index=1,#raw,3 do
        local a,b,c=raw:byte(index,index+2)
        b,c=b or 0,c or 0
        out[#out+1]=alphabet:sub(math.floor(a/4)+1,math.floor(a/4)+1)
        local second=(a%4)*16+math.floor(b/16)
        out[#out+1]=alphabet:sub(second+1,second+1)
        if index+1<=#raw then
            local third=(b%16)*4+math.floor(c/64)
            out[#out+1]=alphabet:sub(third+1,third+1)
        end
        if index+2<=#raw then out[#out+1]=alphabet:sub(c%64+1,c%64+1) end
    end
    return table.concat(out)
end
local function b64decode(value)
    need(type(value)=="string" and not value:find("[^A-Za-z0-9_-]") and #value%4~=1,"invalid_base64url")
    local out={}
    for index=1,#value,4 do
        local a,b,c,d=reverse[value:sub(index,index)],reverse[value:sub(index+1,index+1)],
            reverse[value:sub(index+2,index+2)],reverse[value:sub(index+3,index+3)]
        need(a~=nil and b~=nil,"invalid_base64url")
        out[#out+1]=string.char(a*4+math.floor(b/16))
        if c~=nil then
            out[#out+1]=string.char((b%16)*16+math.floor(c/4))
            if d~=nil then out[#out+1]=string.char((c%4)*64+d)
            else need(c%4==0,"noncanonical_base64url") end
        else need(b%16==0,"noncanonical_base64url") end
    end
    return table.concat(out)
end
local function sha(value) return type(value)=="string" and #value==64 and not value:find("[^a-f0-9]") end
local function schema_data(schema) local data=compiled[schema];need(data~=nil,"uncompiled_schema");return data end
local function compile_schema(spec)
    need(type(spec)=="table" and integer(spec.id,1,MAX_TOKEN) and sha(spec.sha256),"schema_identity_invalid")
    local data={id=spec.id,sha256=spec.sha256,records={},fields={}}
    dense(spec.records,65535)
    for _,id in ipairs(spec.records) do
        need(integer(id,1,65535) and not data.records[id],"record_registry_invalid")
        data.records[id]=true
    end
    need(type(spec.fields)=="table","field_registry_required")
    local field_count=0
    for id,field in pairs(spec.fields) do
        need(integer(id,1,127) and type(field)=="table","field_registry_invalid")
        local kind=field.kind
        need(kind=="uint" or kind=="sint" or kind=="bool","field_type_unknown")
        local lower=kind=="sint" and -MAX_SINT or 0
        local upper=kind=="bool" and 1 or kind=="sint" and MAX_SINT or MAX_UINT
        local minimum,maximum=field.min==nil and lower or field.min,field.max==nil and upper or field.max
        need(integer(minimum,lower,upper) and integer(maximum,minimum,upper),"field_range_invalid")
        -- nil means unknown/not provided. Never manufacture a zero value for
        -- an unsynchronized field; only explicit numeric defaults are retained.
        need(field.default==nil or integer(field.default,minimum,maximum),"field_default_invalid")
        local definition={kind=kind,min=minimum,max=maximum,default=field.default}
        if field.enum then
            dense(field.enum,256)
            definition.enum={}
            for _,number in ipairs(field.enum) do
                need(integer(number,minimum,maximum) and not definition.enum[number],"field_enum_invalid")
                definition.enum[number]=true
            end
            need(next(definition.enum)~=nil and (field.default==nil or definition.enum[field.default]),"field_enum_default_invalid")
        end
        data.fields[id]=definition;field_count=field_count+1
    end
    need(field_count>0,"field_registry_empty")
    local schema={id=data.id,sha256=data.sha256,record_count=#spec.records,field_count=field_count}
    compiled[schema]=data;return schema
end
function M.compile_schema(spec) return guarded(compile_schema,spec) end
function M.compile_lookup(lookup,schema_token)
    return guarded(function()
        need(type(lookup)=="table" and sha(lookup.sha256) and type(lookup.records)=="table","lookup_identity_invalid")
        local ids={}
        for id,record in pairs(lookup.records) do
            need(integer(id,1,65535) and type(record)=="table" and record.id==id
                and (record.tombstone==nil or type(record.tombstone)=="boolean"),"record_registry_invalid")
            if record.tombstone~=true then ids[#ids+1]=id end
        end
        return compile_schema({id=schema_token,sha256=lookup.sha256,records=ids,fields=lookup.fields})
    end)
end
local function binding_data(schema,binding)
    local data=schema_data(schema)
    need(type(binding)=="table" and binding.schema_sha256==data.sha256 and binding.schema==data.id,"schema_binding_mismatch")
    need(integer(binding.session,1,MAX_TOKEN) and integer(binding.epoch,1,MAX_TOKEN)
        and integer(binding.view,1,MAX_TOKEN),"binding_token_invalid")
    return {schema=data.id,schema_sha256=data.sha256,session=binding.session,epoch=binding.epoch,view=binding.view}
end
function M.next_revision(schema,binding,last_revision)
    return guarded(function()
        binding=binding_data(schema,binding)
        need(integer(last_revision,0,MAX_REVISION),"revision_requires_new_epoch")
        if last_revision<M.ROLLOVER_REVISION then
            return {binding=binding,revision=last_revision+1,full=last_revision==0,requires_rebind=false}
        end
        need(binding.epoch<MAX_TOKEN,"new_session_alias_required")
        binding.epoch=binding.epoch+1
        -- The controller must cancel prior callbacks and establish this binding
        -- through its trusted lifecycle/bootstrap before delivering the full.
        return {binding=binding,revision=1,full=true,requires_rebind=true}
    end)
end
function M.float64_words(value)
    return guarded(function()
        need(type(value)=="number" and value==value and value~=math.huge and value~=-math.huge,"finite_float64_required")
        need(type(math.frexp)=="function" and type(math.ldexp)=="function","float64_platform_unsupported")
        local negative=value<0 or value==0 and 1/value==-math.huge
        local absolute=math.abs(value)
        if absolute==0 then return {hi=negative and 2147483648 or 0,lo=0} end
        local fraction,exponent
        if absolute<math.ldexp(1,-1022) then fraction=math.ldexp(absolute,1074);exponent=0
        else
            local mantissa,power=math.frexp(absolute)
            fraction=(mantissa*2-1)*4503599627370496;exponent=power+1022
        end
        local hi=(negative and 2147483648 or 0)+exponent*1048576+math.floor(fraction/4294967296)
        return {hi=hi,lo=fraction%4294967296}
    end)
end
function M.float64_from_words(hi,lo)
    return guarded(function()
        need(integer(hi,0,MAX_UINT) and integer(lo,0,MAX_UINT),"float64_words_invalid")
        local negative=hi>=2147483648
        local exponent=math.floor(hi%2147483648/1048576)
        need(exponent<2047,"finite_float64_required")
        local fraction=(hi%1048576)*4294967296+lo
        local value=exponent==0 and math.ldexp(fraction,-1074)
            or math.ldexp(1+fraction/4503599627370496,exponent-1023)
        return negative and -value or value
    end)
end
local function field_value(field,value)
    if field.kind=="bool" and type(value)=="boolean" then value=value and 1 or 0 end
    need(integer(value,field.min,field.max),"field_value_range")
    need(not field.enum or field.enum[value],"field_enum_unknown")
    return value
end
local function encode_changes(data,changes)
    local size=dense(changes,65535)
    local out,seen={},{}
    for index=1,size do
        local change=changes[index]
        need(type(change)=="table","change_required")
        for key in pairs(change) do
            need(key=="record" or key=="field" or key=="value" or key=="remove","change_key_unknown")
        end
        local record,field_id=change.record,change.field
        need(data.records[record],"record_unknown")
        local field=data.fields[field_id];need(field~=nil,"field_unknown")
        local key=record*128+field_id;need(not seen[key],"duplicate_changed_index");seen[key]=true
        need(change.remove==nil or change.remove==true,"remove_flag_invalid")
        out[#out+1]=uint(record);out[#out+1]=uint(field_id*2+(change.remove and 1 or 0))
        if change.remove then need(change.value==nil,"removed_value_present")
        else
            local value=field_value(field,change.value)
            if field.kind=="sint" then value=value<0 and -value*2-1 or value*2 end
            out[#out+1]=uint(value)
        end
    end
    return table.concat(out)
end
local function decode_changes(data,raw)
    local changes,seen,offset={},{},1
    while offset<=#raw do
        local record,tag,value
        record,offset=read_uint(raw,offset);tag,offset=read_uint(raw,offset)
        need(data.records[record],"record_unknown")
        local field_id,removed=math.floor(tag/2),tag%2==1
        local field=data.fields[field_id];need(field~=nil,"field_unknown")
        local key=record*128+field_id;need(not seen[key],"duplicate_changed_index");seen[key]=true
        local change={record=record,field=field_id}
        if removed then change.remove=true
        else
            value,offset=read_uint(raw,offset)
            if field.kind=="sint" then value=value%2==1 and -(value+1)/2 or value/2 end
            change.value=field_value(field,value)
        end
        changes[#changes+1]=change;need(#changes<=65535,"change_count_limit")
    end
    return changes
end
local function header(binding,revision,full,index,count)
    return string.char(full and 17 or 16)..uint(binding.schema)..uint(binding.session)..uint(binding.epoch)
        ..uint(binding.view)..uint(revision)..uint(index)..uint(count)
end
local function encode(schema,binding,revision,changes,options)
    options=options or {};binding=binding_data(schema,binding)
    need(integer(revision,1,MAX_REVISION),"revision_requires_new_epoch")
    local budget=options.value_budget or M.DEFAULT_VALUE_BUDGET
    need(integer(budget,16,50),"value_budget_invalid")
    local raw=encode_changes(schema_data(schema),changes)
    if #raw==0 and options.full~=true then return {},{changes=0,business_bytes=0,protocol_bytes=0,ascii_bytes=0,native_bytes=nil} end
    local raw_limit=math.floor(budget*3/4)
    local count,capacity=1,nil
    -- Header length changes only when fragment IDs cross a varint boundary.
    -- Starting at one gives a monotone fixed point, at most two uint14 widths;
    -- it avoids reserving large-fragment overhead for a small urgent delta.
    while true do
        capacity=raw_limit-#header(binding,revision,options.full==true,count,count)
        need(capacity>0 or #raw==0 and capacity==0,"context_exceeds_value_budget")
        local next_count=#raw==0 and 1 or math.ceil(#raw/capacity)
        need(next_count<=MAX_TOKEN,"transaction_fragment_limit")
        if next_count==count then break end
        count=next_count
    end
    local packets,total_raw,total_ascii,max_ascii={},0,0,0
    for index=1,count do
        local frame=header(binding,revision,options.full==true,index,count)..raw:sub((index-1)*capacity+1,index*capacity)
        local value=b64encode(frame);need(#value<=budget,"encoded_value_budget_exceeded")
        packets[index]={d=value};total_raw=total_raw+#frame;total_ascii=total_ascii+#value;max_ascii=math.max(max_ascii,#value)
    end
    return packets,{changes=#changes,business_bytes=#raw,protocol_bytes=total_raw,ascii_bytes=total_ascii,
        max_value_bytes=max_ascii,fragments=count,value_budget=budget,native_bytes=nil}
end
function M.encode(schema,binding,revision,changes,options) return guarded(encode,schema,binding,revision,changes,options) end
local function parse_frame(packet,budget)
    need(type(packet)=="table","packet_required")
    for key in pairs(packet) do need(key=="d","packet_key_unknown") end
    need(type(packet.d)=="string" and #packet.d<=budget,"encoded_value_budget_exceeded")
    local raw=b64decode(packet.d);local tag=raw:byte(1)
    need(tag==16 or tag==17 or tag==18,"wire_version_unknown")
    local offset,values=2,{}
    for index=1,7 do values[index],offset=read_uint(raw,offset) end
    for index=1,4 do need(integer(values[index],1,MAX_TOKEN),"binding_token_invalid") end
    need(integer(values[5],tag==18 and 0 or 1,MAX_REVISION),"revision_requires_new_epoch")
    need(integer(values[7],1,MAX_TOKEN) and integer(values[6],1,values[7]),"fragment_index_invalid")
    return {kind=tag==18 and "resync" or tag==17 and "full" or "delta",full=tag==17,
        schema=values[1],session=values[2],epoch=values[3],view=values[4],
        revision=values[5],index=values[6],count=values[7],body=raw:sub(offset)}
end
local function decode_frame(schema,binding,packet,budget)
    binding=binding_data(schema,binding)
    local frame=parse_frame(packet,budget)
    need(frame.schema==binding.schema,"schema_unknown")
    need(frame.session==binding.session and frame.epoch==binding.epoch and frame.view==binding.view,"stale_binding")
    return frame
end
function M.peek_header(packet)
    return guarded(function()
        local frame=parse_frame(packet,24)
        frame.body=nil -- Routing metadata only; not a decoded/authorized update.
        return frame
    end)
end
function M.decode_packet(schema,binding,packet,options)
    return guarded(decode_frame,schema,binding,packet,(options and options.value_budget) or M.DEFAULT_VALUE_BUDGET)
end
-- Failure-only request. No routine ACK, polling or mandatory delay is encoded.
-- Reason IDs: 1 missing base, 2 assembly deadline, 3 schema mismatch,
-- 4 conflicting/corrupt fragment, 5 bounded-buffer refusal.
function M.encode_resync(schema,binding,last_revision,reason,options)
    return guarded(function()
        binding=binding_data(schema,binding)
        need(integer(last_revision,0,MAX_REVISION) and integer(reason,1,5),"resync_fields_invalid")
        local budget=(options and options.value_budget) or M.DEFAULT_VALUE_BUDGET
        need(integer(budget,16,50),"value_budget_invalid")
        local raw=string.char(18)..uint(binding.schema)..uint(binding.session)..uint(binding.epoch)..uint(binding.view)
            ..uint(last_revision)..uint(1)..uint(1)..uint(reason)
        local value=b64encode(raw);need(#value<=budget,"encoded_value_budget_exceeded")
        return {d=value}
    end)
end
function M.decode_resync(schema,binding,packet,options)
    return guarded(function()
        local frame=decode_frame(schema,binding,packet,(options and options.value_budget) or M.DEFAULT_VALUE_BUDGET)
        need(frame.kind=="resync" and frame.index==1 and frame.count==1,"resync_frame_required")
        local reason,offset=read_uint(frame.body,1)
        need(integer(reason,1,5) and offset==#frame.body+1,"resync_fields_invalid")
        return {revision=frame.revision,reason=reason}
    end)
end
local function new_receiver(schema,binding,options)
    local data=schema_data(schema);binding=binding_data(schema,binding);options=options or {}
    local budget=options.value_budget or M.DEFAULT_VALUE_BUDGET
    local byte_limit=options.assembly_bytes or 262144
    need(integer(budget,16,50) and integer(byte_limit,1,1048576),"receiver_budget_invalid")
    local revision,initialized,assembly,pending=0,false,nil,nil
    local api={}
    function api.accept(packet)
        return guarded(function()
            need(not pending,"commit_required")
            local frame=decode_frame(schema,binding,packet,budget)
            need(frame.kind~="resync","unexpected_control")
            need(frame.revision>revision,"stale_revision")
            if assembly and frame.revision<assembly.revision then error("stale_fragment",0) end
            if not frame.full and (not initialized or frame.revision~=revision+1) then assembly=nil;error("missing_base",0) end
            if not assembly or frame.revision>assembly.revision then
                assembly={revision=frame.revision,full=frame.full,count=frame.count,parts={},received=0,bytes=0}
            end
            if assembly.full~=frame.full or assembly.count~=frame.count then assembly=nil;error("fragment_identity_conflict",0) end
            local old=assembly.parts[frame.index]
            if old then
                if old~=frame.body then assembly=nil;error("duplicate_fragment_conflict",0) end
                return {pending=true,duplicate=true}
            end
            if assembly.bytes+#frame.body>byte_limit then assembly=nil;error("assembly_byte_limit",0) end
            assembly.parts[frame.index]=frame.body;assembly.bytes=assembly.bytes+#frame.body;assembly.received=assembly.received+1
            if assembly.received<assembly.count then return {pending=true,received=assembly.received,count=assembly.count} end
            local raw=table.concat(assembly.parts,"",1,assembly.count)
            local changes,error_message=guarded(decode_changes,data,raw)
            if not changes then assembly=nil;error(error_message,0) end
            local transaction={full=assembly.full,revision=assembly.revision,changes=changes}
            pending={transaction=transaction,revision=assembly.revision};assembly=nil
            return transaction
        end)
    end
    function api.commit(transaction)
        if not pending or pending.transaction~=transaction then return nil,"transaction_not_pending" end
        revision,initialized=pending.revision,true;pending=nil;return true
    end
    function api.abort() assembly,pending=nil,nil end -- Only a real gap/failure/deadline should trigger caller resync.
    function api.inspect()
        return {revision=revision,initialized=initialized,assembling=assembly~=nil,commit_pending=pending~=nil,
            received=assembly and assembly.received or 0,buffered_bytes=assembly and assembly.bytes or 0}
    end
    return api
end
function M.new_receiver(schema,binding,options) return guarded(new_receiver,schema,binding,options) end
-- Fixed-channel native probe specification. The caller supplies the authenticated
-- recipient and net_showmsg capture; this function sends/records nothing itself.
function M.probe_cases()
    local out={}
    for _,length in ipairs({0,1,8,16,24,28,32}) do
        out[#out+1]={event=M.EVENT,value_bytes=length,packet={d=string.rep("A",length)}}
    end
    return out
end
local function measure_budget(evidence,native_limit)
    need(type(evidence)=="table" and evidence.method=="net_showmsg" and evidence.layer=="CUserMsg_CustomGameEvent",
        "native_measurement_required")
    need(evidence.event==M.EVENT and evidence.key==M.KEY and type(evidence.engine_build)=="string"
        and #evidence.engine_build>0 and sha(evidence.source_log_sha256),"native_measurement_identity_invalid")
    native_limit=native_limit or 50;need(native_limit==50,"native_limit_must_be_50")
    local required={[0]=true,[1]=true,[8]=true,[16]=true,[24]=true,[28]=true,[32]=true}
    local optional={[40]=true}
    local overhead,bits_overhead,count,bit_samples=nil,nil,0,0
    dense(evidence.samples,8)
    for _,sample in ipairs(evidence.samples) do
        need(type(sample)=="table" and (required[sample.value_bytes] or optional[sample.value_bytes])
            and integer(sample.native_bytes,sample.value_bytes,4096),
            "native_sample_invalid")
        required[sample.value_bytes]=nil;optional[sample.value_bytes]=nil;count=count+1
        local difference=sample.native_bytes-sample.value_bytes
        need(overhead==nil or overhead==difference,"native_overhead_not_constant")
        overhead=difference
        if sample.native_bits~=nil then
            bit_samples=bit_samples+1
            need(integer(sample.native_bits,1,32768) and math.ceil(sample.native_bits/8)==sample.native_bytes,"native_bits_invalid")
            local bit_difference=sample.native_bits-sample.value_bytes*8
            need(bits_overhead==nil or bits_overhead==bit_difference,"native_bits_not_constant")
            bits_overhead=bit_difference
        else need(bits_overhead==nil,"native_bit_samples_incomplete") end
    end
    need(count>=7 and next(required)==nil and overhead>0,"native_samples_incomplete")
    need(bit_samples==0 or bit_samples==count,"native_bit_samples_incomplete")
    -- Current verified base64 boundary is 24 (49 native bytes). A 25-character
    -- unpadded base64 value is not canonical; do not round into the next 26-byte
    -- representation or infer a larger boundary from a permissive limit.
    local value_budget=math.min(24,native_limit-overhead)
    need(value_budget>=16,"native_50_budget_insufficient")
    local proof={engine_build=evidence.engine_build,event=M.EVENT,key=M.KEY,layer=evidence.layer,
        networksystem_sha256=evidence.networksystem_sha256,source_log_sha256=evidence.source_log_sha256,
        native_limit=native_limit,overhead_bytes=overhead,overhead_bits=bits_overhead,value_budget=value_budget}
    need(evidence.networksystem_sha256==nil or sha(evidence.networksystem_sha256),"networksystem_identity_invalid")
    calibrated[proof]={engine_build=proof.engine_build,networksystem_sha256=proof.networksystem_sha256,
        native_limit=native_limit,overhead=overhead,bits_overhead=bits_overhead,budget=value_budget}
    return proof
end
function M.measure_budget(evidence,native_limit) return guarded(measure_budget,evidence,native_limit) end
function M.production_send(packet,proof,engine_build,emit,networksystem_sha256)
    return guarded(function()
        local measured=calibrated[proof]
        need(measured~=nil and measured.engine_build==engine_build,"current_native_measurement_required")
        need(not measured.networksystem_sha256 or measured.networksystem_sha256==networksystem_sha256,"current_networksystem_measurement_required")
        need(type(packet)=="table" and type(packet.d)=="string" and not packet.d:find("[^A-Za-z0-9_-]"),"packet_required")
        for key in pairs(packet) do need(key==M.KEY,"packet_key_unknown") end
        need(#packet.d<=measured.budget and measured.overhead+#packet.d<=measured.native_limit,"native_50_budget_exceeded")
        local raw=b64decode(packet.d)
        need(raw:byte(1)==16 or raw:byte(1)==17 or raw:byte(1)==18,"wire_version_unknown")
        need(type(emit)=="function","private_authenticated_emitter_required")
        local accepted=emit(M.EVENT,packet)
        need(accepted~=false,"native_send_failed")
        return {sent=true,value_bytes=#packet.d,native_message_bytes=measured.overhead+#packet.d,
            native_message_bits=measured.bits_overhead and measured.bits_overhead+#packet.d*8 or nil,
            layer="CUserMsg_CustomGameEvent",outer_transport_framing_included=false}
    end)
end
M.limits={record_id=65535,field_id=127,token=MAX_TOKEN,revision=MAX_REVISION,uint=MAX_UINT,sint=MAX_SINT}
return M
