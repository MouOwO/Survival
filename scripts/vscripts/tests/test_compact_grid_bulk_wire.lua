package.path='scripts/vscripts/?.lua;'..package.path
local W=require('ui/compact_grid_bulk_wire')
if arg and arg[1]=='decode'then local h,why=W.Decode({d=arg[2]});print(h and 'ok'or why);return end
local sha=string.rep('a',64)
local binding={schema=1,schema_sha256=sha,session=7,epoch=2,view=6,revision=1}
local bytes={};for n=0,2303 do bytes[n+1]=string.char(n*37%256)end;local raw=table.concat(bytes)
local packets,report=assert(W.Encode(binding,3,raw));assert(#packets==4 and report.max_value_bytes==896)
local rebuilt={};for n,p in ipairs(packets)do local h,body=assert(W.Decode(p));assert(h.session==7 and h.epoch==2 and h.base_revision==1 and h.scope==3 and h.index==n and h.count==4);rebuilt[n]=body end
assert(table.concat(rebuilt)==raw)
assert(not W.Encode(binding,3,string.rep('x',16385)))
assert(not W.Encode(binding,0,raw));assert(not W.Encode(binding,3,raw,{value_budget=64}))
assert(not W.Decode({d=packets[1].d,extra=1}));assert(not W.Decode({d=packets[1].d..'='}))
local largest={schema=16383,schema_sha256=sha,session=16383,epoch=16383,view=6,revision=2097151}
local large=assert(W.Encode(largest,4294967295,string.rep(string.char(170),16384)));assert(#large<=32)
for _,packet in ipairs(large)do assert(#packet.d<=896)end
if arg and arg[1]=='emit'then print(require('core/json_encoder').encode({binding=binding,scope=3,packets=packets,report=report,largest=largest,large=large}))else print('PASS grid bulk Lua codec canonical/private bounds 2304bytes4frames/max16384')end
