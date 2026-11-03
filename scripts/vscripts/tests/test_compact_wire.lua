-- Real shared codec, deterministic synthetic values. No Dota, HTTP or SDK.
package.path="scripts/vscripts/?.lua;"..package.path
local wire=require("ui/compact_wire")
local json=require("core/json_encoder")
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,child in pairs(value) do out[key]=copy(child) end;return out
end
local checks=0
local function rejected(fn,reason)
    local value,error_message=fn();assert(value==nil and error_message==reason,
        "expected "..reason..", received "..tostring(error_message));checks=checks+1
end
local definition={id=1,sha256=string.rep("a",64),records={1,2,128,65535},fields={
    [1]={kind="uint",min=0,max=4294967295,default=0},
    [2]={kind="sint",default=0},[3]={kind="bool",default=0},
    [4]={kind="uint",default=0,enum={0,2,5}}}}
local schema=assert(wire.compile_schema(definition))
local binding={schema=1,schema_sha256=definition.sha256,session=1,epoch=1,view=1}
local golden_full,full_report=assert(wire.encode(schema,binding,1,{{record=1,field=1,value=7}},{full=true}))
assert(#golden_full==1 and golden_full[1].d=="EQEBAQEBAQEBAgc","v1 cross-language golden vector changed")
assert(full_report.business_bytes==3 and full_report.protocol_bytes==11 and full_report.ascii_bytes==15)
local frame=assert(wire.decode_packet(schema,binding,golden_full[1]));assert(frame.kind=="full" and frame.count==1)
local peek=assert(wire.peek_header(golden_full[1]))
assert(peek.schema==1 and peek.session==1 and peek.view==1 and peek.revision==1 and peek.body==nil)
rejected(function() return wire.peek_header({d=string.rep("A",25)}) end,"encoded_value_budget_exceeded")
rejected(function() return wire.peek_header({d="!"}) end,"invalid_base64url")
rejected(function() return wire.peek_header({d=golden_full[1].d,PlayerID=0}) end,"packet_key_unknown")
local receiver=assert(wire.new_receiver(schema,binding))
local first=assert(receiver.accept(golden_full[1]));assert(first.revision==1 and first.changes[1].value==7)
assert(receiver.inspect().revision==0 and receiver.inspect().commit_pending,"accept must not commit before application")
rejected(function() return receiver.accept(golden_full[1]) end,"commit_required")
assert(receiver.commit(first));assert(receiver.inspect().revision==1)
rejected(function() return receiver.accept(golden_full[1]) end,"stale_revision")
local empty,empty_report=assert(wire.encode(schema,binding,2,{}))
assert(#empty==0 and empty_report.ascii_bytes==0 and empty_report.protocol_bytes==0,"unchanged delta must emit nothing")

local delta_changes={{record=2,field=2,value=-2147483647},{record=128,field=1,value=4294967295},
    {record=65535,field=3,value=true},{record=1,field=4,value=5},{record=1,field=1,remove=true}}
local golden_delta,delta_report=assert(wire.encode(schema,binding,2,delta_changes))
local transaction
for index=#golden_delta,1,-1 do
    local result=assert(receiver.accept(golden_delta[index]));if not result.pending then transaction=result end
end
assert(transaction and not transaction.full and #transaction.changes==#delta_changes)
assert(transaction.changes[1].value==-2147483647 and transaction.changes[2].value==4294967295)
assert(transaction.changes[3].value==1 and transaction.changes[5].remove)
assert(receiver.commit(transaction))
local skipped=assert(wire.encode(schema,binding,4,{{record=1,field=1,value=9}}))
rejected(function() return receiver.accept(skipped[1]) end,"missing_base")
assert(receiver.inspect().revision==2 and not receiver.inspect().assembling)
local recovered=assert(wire.encode(schema,binding,5,{}, {full=true}))
assert(receiver.commit(assert(receiver.accept(recovered[1]))));assert(receiver.inspect().revision==5)

-- Compile once into direct indexes. Holes, unknown enums and untyped fields
-- cannot be turned into a guessed record or reward state by the wire decoder.
local bad=copy(definition);bad.records={1,1}
rejected(function() return wire.compile_schema(bad) end,"record_registry_invalid")
bad=copy(definition);bad.fields[1].default=nil
assert(wire.compile_schema(bad),"unknown default must stay unknown rather than being filled with zero")
bad.fields[1].default="0"
rejected(function() return wire.compile_schema(bad) end,"field_default_invalid")
bad=copy(definition);bad.fields[1].kind="string"
rejected(function() return wire.compile_schema(bad) end,"field_type_unknown")
bad=copy(definition);bad.fields[4].enum={[1]=0,[3]=5}
rejected(function() return wire.compile_schema(bad) end,"sparse_or_named_array")
rejected(function() return wire.encode(schema,binding,1,{{record=3,field=1,value=0}}) end,"record_unknown")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=5,value=0}}) end,"field_unknown")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=4,value=1}}) end,"field_enum_unknown")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=1,value=0.5}}) end,"field_value_range")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=1,value=4294967296}}) end,"field_value_range")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=3,value=2}}) end,"field_value_range")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=1,value=0,remove=true}}) end,"removed_value_present")
rejected(function() return wire.encode(schema,binding,1,{{record=1,field=1,value=0},{record=1,field=1,value=1}}) end,"duplicate_changed_index")
rejected(function() return wire.encode(schema,binding,2097152,{}) end,"revision_requires_new_epoch")
bad=copy(binding);bad.schema_sha256=string.rep("b",64)
rejected(function() return wire.encode(schema,bad,1,{}) end,"schema_binding_mismatch")
bad=copy(binding);bad.session=16384
rejected(function() return wire.encode(schema,bad,1,{}) end,"binding_token_invalid")
bad=copy(binding);bad.epoch=2
rejected(function() return wire.decode_packet(schema,bad,golden_full[1]) end,"stale_binding")
rejected(function() return wire.decode_packet(schema,binding,{d="!"}) end,"invalid_base64url")
rejected(function() return wire.decode_packet(schema,binding,{d="AB"}) end,"noncanonical_base64url")
rejected(function() return wire.decode_packet(schema,binding,{d=golden_full[1].d,extra=1}) end,"packet_key_unknown")

-- Count depends on the K changed fields, never all N registered records.
local records={};for id=1,10000 do records[id]=id end
local large_schema=assert(wire.compile_schema({id=1,sha256=definition.sha256,records=records,fields=definition.fields}))
local sparse=assert(wire.encode(large_schema,binding,2,{{record=1,field=1,value=7}}))
assert(#sparse==#golden_full and #sparse[1].d==#golden_full[1].d)
local function instructions(value)
    local count=0
    debug.sethook(function() count=count+1 end,"",1)
    local packets=assert(wire.encode(value,binding,2,{{record=1,field=1,value=7}}))
    debug.sethook()
    assert(#packets==1)
    return count
end
local small_instructions,large_instructions=instructions(schema),instructions(large_schema)
assert(large_instructions<=small_instructions+5,"stable sparse encode scanned the registered catalogue")
local many={};for id=1,1000 do many[id]={record=id,field=1,value=id*1234567} end
local many_packets,many_report=assert(wire.encode(large_schema,binding,1,many,{full=true}))
local maximum=0;for _,packet in ipairs(many_packets) do maximum=math.max(maximum,#packet.d);assert(#packet.d<=24) end
local large_receiver=assert(wire.new_receiver(large_schema,binding))
assert(large_receiver.accept(many_packets[1]).pending)
assert(large_receiver.accept(many_packets[1]).duplicate)
for index=#many_packets,2,-1 do
    local result=assert(large_receiver.accept(many_packets[index]))
    if index==2 then
        assert(#result.changes==1000 and result.changes[1000].value==1234567000)
        assert(large_receiver.commit(result))
    else assert(result.pending) end
end
assert(large_receiver.inspect().revision==1 and large_receiver.inspect().buffered_bytes==0)
local limited=assert(wire.new_receiver(large_schema,binding,{assembly_bytes=1}))
rejected(function() return limited.accept(many_packets[1]) end,"assembly_byte_limit")
assert(not limited.inspect().assembling and limited.inspect().revision==0)
local conflicting=copy(many);conflicting[1].value=1234568
local conflict_packets=assert(wire.encode(large_schema,binding,1,conflicting,{full=true}))
assert(#conflict_packets==#many_packets)
local conflicted=assert(wire.new_receiver(large_schema,binding))
assert(conflicted.accept(many_packets[1]).pending)
rejected(function() return conflicted.accept(conflict_packets[1]) end,"duplicate_fragment_conflict")
assert(not conflicted.inspect().assembling)
local forged_schema=assert(wire.compile_schema({id=1,sha256=definition.sha256,records={3},fields=definition.fields}))
local unknown_record=assert(wire.encode(forged_schema,binding,1,{{record=3,field=1,value=9}},{full=true}))
local strict_receiver=assert(wire.new_receiver(schema,binding))
rejected(function() return strict_receiver.accept(unknown_record[1]) end,"record_unknown")
assert(strict_receiver.inspect().revision==0 and not strict_receiver.inspect().commit_pending)
local lookup={sha256=definition.sha256,records={[1]={id=1,tombstone=false},[3]={id=3,tombstone=true}},fields=definition.fields}
local lookup_schema=assert(wire.compile_lookup(lookup,1))
assert(lookup_schema.record_count==1)
rejected(function() return wire.encode(lookup_schema,binding,1,{{record=3,field=1,value=0}}) end,"record_unknown")

-- Header maxima still fragment the business stream rather than allowing one
-- long record/value to exceed the selected ASCII budget.
local maximal_binding={schema=16383,schema_sha256=definition.sha256,session=16383,epoch=16383,view=16383}
local maximal_schema=assert(wire.compile_schema({id=16383,sha256=definition.sha256,records=definition.records,fields=definition.fields}))
local worst,worst_report=assert(wire.encode(maximal_schema,maximal_binding,2097151,delta_changes,{full=true}))
local worst_receiver=assert(wire.new_receiver(maximal_schema,maximal_binding))
local worst_transaction
for _,packet in ipairs(worst) do
    assert(#packet.d<=24);local result=assert(worst_receiver.accept(packet));if not result.pending then worst_transaction=result end
end
assert(worst_transaction and #worst_transaction.changes==5 and worst_receiver.commit(worst_transaction))
local narrow_binding=copy(binding);narrow_binding.view=128
local narrow=assert(wire.encode(schema,narrow_binding,10000,delta_changes,{full=true,value_budget=16}))
for _,packet in ipairs(narrow) do assert(#packet.d<=16) end
rejected(function() return wire.encode(maximal_schema,maximal_binding,2097151,delta_changes,{full=true,value_budget=16}) end,
    "context_exceeds_value_budget")
local following=assert(wire.next_revision(schema,binding,wire.ROLLOVER_REVISION))
assert(following.full and following.revision==1 and following.binding.epoch==2 and following.requires_rebind)
assert(binding.epoch==1,"rollover must not mutate a live binding")
local exhausted=copy(binding);exhausted.epoch=16383
rejected(function() return wire.next_revision(schema,exhausted,wire.ROLLOVER_REVISION) end,"new_session_alias_required")
for _,sample in ipairs({{value=0.1,hi=1069128089,lo=2576980378},{value=0.3,hi=1070805811,lo=858993459},
    {value=1,hi=1072693248,lo=0},{value=math.ldexp(1,-1074),hi=0,lo=1},
    {value=math.ldexp(1,-1022),hi=1048576,lo=0}}) do
    local words=assert(wire.float64_words(sample.value))
    assert(words.hi==sample.hi and words.lo==sample.lo,"IEEE754 golden words changed")
    assert(wire.float64_from_words(words.hi,words.lo)==sample.value,"float64 bits were rounded")
end
local minus_zero=assert(wire.float64_words(-1/math.huge))
assert(minus_zero.hi==2147483648 and minus_zero.lo==0 and 1/wire.float64_from_words(minus_zero.hi,0)==-math.huge)
rejected(function() return wire.float64_words(math.huge) end,"finite_float64_required")
local resync=assert(wire.encode_resync(schema,binding,0,1))
local resync_value=assert(wire.decode_resync(schema,binding,resync))
assert(resync_value.revision==0 and resync_value.reason==1)
rejected(function() return receiver.accept(resync) end,"unexpected_control")

-- Synthetic calibration tests the gate only. These numbers are intentionally
-- marked non-native; they must never be used as runtime release evidence.
local calls=0
local function emit(event,packet) assert(event=="cw" and type(packet.d)=="string");calls=calls+1 end
rejected(function() return wire.production_send(golden_full[1],nil,"fixture",emit) end,"current_native_measurement_required")
assert(calls==0)
local cases=wire.probe_cases();assert(#cases==7 and cases[1].value_bytes==0 and cases[7].value_bytes==32)
local evidence={method="net_showmsg",layer="CUserMsg_CustomGameEvent",event="cw",key="d",
    engine_build="SYNTHETIC_NOT_RELEASE_EVIDENCE",source_log_sha256=string.rep("c",64),samples={}}
for index,case in ipairs(cases) do evidence.samples[index]={value_bytes=case.value_bytes,native_bytes=case.value_bytes+20} end
local proof=assert(wire.measure_budget(evidence))
assert(proof.value_budget==24 and proof.overhead_bytes==20)
local sent=assert(wire.production_send(golden_full[1],proof,evidence.engine_build,emit))
assert(calls==1 and sent.native_message_bytes==35 and not sent.outer_transport_framing_included)
rejected(function() return wire.production_send(golden_full[1],proof,"different engine",emit) end,"current_native_measurement_required")
proof.value_budget=50;proof.overhead_bytes=0
rejected(function() return wire.production_send({d=string.rep("A",31)},proof,evidence.engine_build,emit) end,"native_50_budget_exceeded")
bad=copy(evidence);bad.samples[7].native_bytes=bad.samples[7].native_bytes+1
rejected(function() return wire.measure_budget(bad) end,"native_overhead_not_constant")
bad=copy(evidence);bad.samples[1]=nil
rejected(function() return wire.measure_budget(bad) end,"sparse_or_named_array")
bad=copy(evidence);bad.source_log_sha256=""
rejected(function() return wire.measure_budget(bad) end,"native_measurement_identity_invalid")
assert(calls==1,"rejected evidence must never invoke a native emitter")
local result={status="PASS_COMPACT_WIRE_SYNTHETIC_NOT_NATIVE",reject_cases=checks,
    golden_full=golden_full,golden_delta=golden_delta,golden_resync=resync,
    one_change_lua_instructions_small_registry=small_instructions,
    one_change_lua_instructions_10000_registry=large_instructions,
    ten_thousand_records_one_change_packets=#sparse,thousand_changes_packets=#many_packets,
    thousand_changes_business_bytes=many_report.business_bytes,max_ascii_value_bytes=maximum,
    worst_context_packets=#worst,worst_context_max_ascii_bytes=worst_report.max_value_bytes,
    native_calls=0,sdk_calls=0,http_calls=0,actual_native_budget_measured=false,production_default_refuses=true}
if arg and arg[1]=="catalog" then
    local path=arg[2] or "scripts/vscripts/config/generated/ui_static_catalog_lookup.lua"
    local catalogue=assert(loadfile(path))()
    local real_schema=assert(wire.compile_lookup(catalogue,1))
    local real_binding={schema=1,schema_sha256=catalogue.sha256,session=1,epoch=1,view=1}
    local record=assert(catalogue.by_key["daily:state"])
    local known,day=assert(catalogue.field_by_name.known),assert(catalogue.field_by_name.day)
    local real_packets=assert(wire.encode(real_schema,real_binding,1,
        {{record=record,field=known,value=1},{record=record,field=day,value=25001}},{full=true}))
    local real_receiver=assert(wire.new_receiver(real_schema,real_binding))
    for _,packet in ipairs(real_packets) do
        local item=assert(real_receiver.accept(packet))
        if not item.pending then assert(#item.changes==2 and real_receiver.commit(item)) end
    end
    assert(real_receiver.inspect().revision==1)
    result.real_catalogue={sha256=catalogue.sha256,records=real_schema.record_count,fields=real_schema.field_count,
        packets=#real_packets,passed=true}
    local typical_binding={schema=1,schema_sha256=catalogue.sha256,session=4095,epoch=3,view=127}
    local updates={{record=record,field=known,value=1},{record=record,field=day,value=25001}}
    local typical,typical_report=assert(wire.encode(real_schema,typical_binding,18001,updates,{full=true}))
    local max_schema=assert(wire.compile_lookup(catalogue,16383))
    local max_binding={schema=16383,schema_sha256=catalogue.sha256,session=16383,epoch=16383,view=16383}
    local max_packets,max_report=assert(wire.encode(max_schema,max_binding,2097151,updates,{full=true}))
    result.production_header_examples={typical={binding=typical_binding,revision=18001,packets=#typical,max_ascii=typical_report.max_value_bytes},
        maximal={binding=max_binding,revision=2097151,packets=#max_packets,max_ascii=max_report.max_value_bytes},
        maximum_legal_header_raw_bytes=16,binary_frame_budget=18,minimum_remaining_business_bytes=2,
        rollover_revision=wire.ROLLOVER_REVISION,requires_trusted_rebind=true}
    local proof_file=io.open("output/network50_native_probe_20261103/native_budget.json","rb")
    if proof_file then
        local measured=require("core/json_decoder").decode(proof_file:read("*a"));proof_file:close()
        local measured_proof=assert(wire.measure_budget(measured))
        assert(measured_proof.value_budget==24 and measured_proof.overhead_bytes==25 and measured_proof.overhead_bits==194)
        result.native_size_evidence={engine_build=measured_proof.engine_build,source_log_sha256=measured_proof.source_log_sha256,
            measured_max_value_bytes=24,measured_native_bits=386,measured_native_ceil_bytes=49,
            ordinary_production_acceptance=false,production_send_performed=false}
    end
end
if arg and arg[1]=="emit" then result.schema=definition;result.binding=binding;result.delta_changes=delta_changes end
print(json.encode(result))
