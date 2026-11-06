-- Rare grid bitmap (0x21) or typed lottery receipt (0x22), not a string tunnel.
-- Header: tag, schema/session/epoch/view/base_revision/scope/index/count.
local M={EVENT='gb',KEY='d',VERSION=1,VALUE_BUDGET=896,MAX_RAW=16384,MAX_FRAGMENTS=32}
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
local reverse={};for n=1,#alphabet do reverse[alphabet:sub(n,n)]=n-1 end
local function need(v,e)if not v then error(e,0)end end
local function integer(v,lo,hi)return type(v)=='number'and v==math.floor(v)and v>=lo and v<=hi end
local function guard(fn,...)local ok,a,b=pcall(fn,...);if ok then return a,b end return nil,tostring(a)end
local function uint(v)
 need(integer(v,0,4294967295),'bulk_uint32_required');local out={}
 repeat local p=v%128;v=math.floor(v/128);out[#out+1]=string.char(p+(v>0 and 128 or 0))until v==0
 return table.concat(out)
end
local function read_uint(raw,at)
 local value,multiplier=0,1
 for n=0,4 do local byte=raw:byte(at+n);need(byte,'bulk_truncated_varint');value=value+(byte%128)*multiplier;need(value<=4294967295,'bulk_varint_overflow')
  if byte<128 then need(n==0 or byte~=0,'bulk_noncanonical_varint');return value,at+n+1 end;multiplier=multiplier*128
 end;error('bulk_varint_overflow',0)
end
local function b64(raw)
 local out={};for n=1,#raw,3 do local a,b,c=raw:byte(n,n+2);b,c=b or 0,c or 0
  out[#out+1]=alphabet:sub(math.floor(a/4)+1,math.floor(a/4)+1);local v=(a%4)*16+math.floor(b/16);out[#out+1]=alphabet:sub(v+1,v+1)
  if n+1<=#raw then v=(b%16)*4+math.floor(c/64);out[#out+1]=alphabet:sub(v+1,v+1)end
  if n+2<=#raw then v=c%64;out[#out+1]=alphabet:sub(v+1,v+1)end
 end;return table.concat(out)
end
local function unb64(value)
 need(type(value)=='string'and #value>0 and #value%4~=1 and not value:find('[^A-Za-z0-9_-]'),'bulk_invalid_base64url')
 local out={};for n=1,#value,4 do local a,b,c,d=reverse[value:sub(n,n)],reverse[value:sub(n+1,n+1)],reverse[value:sub(n+2,n+2)],reverse[value:sub(n+3,n+3)]
  need(a and b,'bulk_invalid_base64url');out[#out+1]=string.char(a*4+math.floor(b/16))
  if c then out[#out+1]=string.char((b%16)*16+math.floor(c/4));if d then out[#out+1]=string.char((c%4)*64+d)else need(c%4==0,'bulk_noncanonical_base64url')end
  else need(b%16==0,'bulk_noncanonical_base64url')end
 end;return table.concat(out)
end
local function budget(o)local v=o and o.value_budget or M.VALUE_BUDGET;need(integer(v,64,M.VALUE_BUDGET),'bulk_value_budget_invalid');return v end
local function binding(b)
 need(type(b)=='table'and type(b.schema_sha256)=='string'and #b.schema_sha256==64 and not b.schema_sha256:find('[^a-f0-9]'),'bulk_schema_binding_required')
 need(integer(b.schema,1,16383)and integer(b.session,1,16383)and integer(b.epoch,1,16383)and(b.view==6 or integer(b.view,201,204))and integer(b.base_revision or b.revision,1,2097151),'bulk_binding_invalid')
 return{schema=b.schema,session=b.session,epoch=b.epoch,view=b.view,base_revision=b.base_revision or b.revision}
end
local function header(b,scope,index,count)return string.char(b.view==6 and 33 or 34)..uint(b.schema)..uint(b.session)..uint(b.epoch)..uint(b.view)..uint(b.base_revision)..uint(scope)..uint(index)..uint(count)end
local function encode(b,scope,raw,o)
 b=binding(b);need(integer(scope,1,4294967295),'bulk_scope_invalid');need(type(raw)=='string'and #raw>=1 and #raw<=M.MAX_RAW,'bulk_raw_limit')
 local limit=budget(o);local raw_limit=math.floor(limit*3/4);local count,capacity=1
 while true do capacity=raw_limit-#header(b,scope,count,count);need(capacity>0,'bulk_context_too_large');local next_count=math.ceil(#raw/capacity);need(next_count<=M.MAX_FRAGMENTS,'bulk_fragment_limit');if next_count==count then break end;count=next_count end
 local packets,total,max={},0,0
 for index=1,count do local value=b64(header(b,scope,index,count)..raw:sub((index-1)*capacity+1,index*capacity));need(#value<=limit,'bulk_encoded_budget_exceeded');packets[index]={d=value};total=total+#value;max=math.max(max,#value)end
 return packets,{fragments=count,raw_bytes=#raw,ascii_bytes=total,max_value_bytes=max,value_budget=limit,native_bytes=nil}
end
local function decode(packet,o)
 need(type(packet)=='table'and type(packet.d)=='string','bulk_packet_required');for key in pairs(packet)do need(key=='d','bulk_packet_key_unknown')end
 need(#packet.d<=budget(o),'bulk_encoded_budget_exceeded');local raw=unb64(packet.d);local tag=raw:byte(1);need(tag==33 or tag==34,'bulk_tag_invalid')
 local values,at={},2;for n=1,8 do values[n],at=read_uint(raw,at)end
 local h={schema=values[1],session=values[2],epoch=values[3],view=values[4],base_revision=values[5],revision=values[5],scope=values[6],index=values[7],count=values[8]}
 need(integer(h.schema,1,16383)and integer(h.session,1,16383)and integer(h.epoch,1,16383)and(tag==33 and h.view==6 or tag==34 and integer(h.view,201,204))and integer(h.base_revision,1,2097151)and integer(h.scope,1,4294967295),'bulk_header_invalid')
 need(integer(h.count,1,M.MAX_FRAGMENTS)and integer(h.index,1,h.count),'bulk_fragment_header_invalid')
 local body=raw:sub(at);need(#body>=1 and #body<=M.MAX_RAW,'bulk_fragment_body_invalid');return h,body
end
function M.Encode(...)return guard(encode,...)end
function M.Decode(...)return guard(decode,...)end
M.encode,M.decode=M.Encode,M.Decode
return M
