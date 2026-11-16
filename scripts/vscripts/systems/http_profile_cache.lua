-- Optional same-profile transport. State is held by the authenticated
-- provider, never shared with UI consumers. O(1) header lookup; one O(B)
-- bounded detached clone per full/hit reply. No native/DB/network calls here.
local null=require('core/json_decoder').null
local M={}
local MAX_NODES,MAX_DEPTH,MAX_CACHE_BYTES=100000,64,1024*1024
local function object(v)return type(v)=='table'and v~=null end
local function hash(v)return type(v)=='string'and #v==64 and v:match('^[0-9a-f]+$')~=nil end
local function clone(value)
 local nodes,bytes=0,0
 local function copy(v,depth)
  nodes=nodes+1
  if nodes>MAX_NODES or depth>MAX_DEPTH then error('cache_budget',0)end
  if v==null then bytes=bytes+4
  elseif type(v)=='string'then bytes=bytes+6*#v+2
  elseif type(v)=='number'then bytes=bytes+64
  elseif type(v)=='boolean'then bytes=bytes+5
  elseif type(v)~='table'then error('cache_value',0)end
  if bytes>MAX_CACHE_BYTES then error('cache_budget',0)end
  if not object(v)then return v end
  local out={};bytes=bytes+2
  for k,x in pairs(v)do
   if type(k)=='string'then bytes=bytes+6*#k+4
   elseif type(k)=='number'and k==math.floor(k)and k>=1 then bytes=bytes+4
   else error('cache_key',0)end
   if bytes>MAX_CACHE_BYTES then error('cache_budget',0)end
   out[k]=copy(x,depth+1)
  end
  return out
 end
 return copy(value,0)
end
function M.header(state)
 if object(state)and hash(state.hash)and object(state.snapshot)then return 'v1:'..state.hash end
 return 'v1'
end
function M.decode(value,baseline)
 if not object(value)then return nil,nil,'http_profile_cache_invalid'end
 local marker=value._hp
 if marker==nil then return value,nil end -- Server without this transport.
 if not object(marker)or marker[1]~=1 or not hash(marker[2])or(marker[3]~=0 and marker[3]~=1)then
  return nil,nil,'http_profile_cache_invalid'
 end
 local count=0
 for k in pairs(marker)do if k~=1 and k~=2 and k~=3 then return nil,nil,'http_profile_cache_invalid'end;count=count+1 end
 if count~=3 then return nil,nil,'http_profile_cache_invalid'end
 if marker[3]==1 then
  for k in pairs(value)do if k~='_hp'then return nil,nil,'http_profile_cache_invalid'end end
  if not object(baseline)or baseline.hash~=marker[2]or not object(baseline.snapshot)then
   return nil,nil,'http_profile_cache_miss'
  end
  local ok,result=pcall(clone,baseline.snapshot)
  if not ok then return nil,nil,'http_profile_cache_miss'end
  return result,baseline
 end
 local result={}
 for k,v in pairs(value)do if k~='_hp'then result[k]=v end end
 -- A cache allocation/budget failure leaves this valid full reply usable.
 local ok,cached=pcall(clone,result)
 return result,ok and{hash=marker[2],snapshot=cached}or nil
end
-- Optional metadata on an already complete committed write may seed reads.
-- Failure to cache this hint must never fail or replay that write.
function M.seed(value)
 if not object(value)then return value,nil end
 local marker=value._hp
 if marker==nil then return value,nil end
 local result={};for k,v in pairs(value)do if k~='_hp'then result[k]=v end end
 if not object(marker)or marker[1]~=1 or not hash(marker[2])or marker[3]~=2
    or value.ok~=true or not object(value.profile)then return result,nil end
 local count=0;for k in pairs(marker)do if k~=1 and k~=2 and k~=3 then return result,nil end;count=count+1 end
 if count~=3 then return result,nil end
 local ok,cached=pcall(clone,value.profile)
 return result,ok and{hash=marker[2],snapshot=cached}or nil
end
return M
