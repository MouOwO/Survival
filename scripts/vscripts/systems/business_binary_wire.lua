-- BW2 is an explicit opt-in representation, not a save or authorization cache.
-- Per reply O(B+N) time/space, idle O(0); no timers/native/network/DB calls.
-- This module only recovers BW1 nodes; business_wire performs all expansion,
-- template, field collision and completed-reference validation afterwards.
local M = {}
local null = require('core/json_decoder').null
local MAX_BYTES, MAX_NODES, MAX_DEPTH = 8*1024*1024, 100000, 64
local MAX_INT = 9007199254740991
local function need(ok) if not ok then error('business_binary_invalid',0) end end
local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local digits = {}
for i=1,64 do digits[alphabet:byte(i)]=i-1 end
local function unbase64(text)
    need(type(text)=='string' and #text%4==0 and #text<=4*math.ceil(MAX_BYTES/3))
    local result = {}
    for i=1,#text,4 do
        local a,b,c,d=text:byte(i,i+3)
        local av,bv,cv,dv=digits[a],digits[b],digits[c],digits[d]
        need(av~=nil and bv~=nil)
        if c==61 then
            need(d==61 and i+3==#text and bv%16==0)
            result[#result+1]=string.char(av*4+math.floor(bv/16))
        elseif d==61 then
            need(cv~=nil and i+3==#text and cv%4==0)
            result[#result+1]=string.char(av*4+math.floor(bv/16),bv%16*16+math.floor(cv/4))
        else
            need(cv~=nil and dv~=nil)
            result[#result+1]=string.char(av*4+math.floor(bv/16),bv%16*16+math.floor(cv/4),cv%4*64+dv)
        end
    end
    local raw=table.concat(result);need(#raw<=MAX_BYTES);return raw
end
local function utf8(text)
    local i=1
    while i<=#text do
        local a=text:byte(i);local count,code,minimum
        if a<128 then count,code,minimum=1,a,0
        elseif a>=194 and a<=223 then count,code,minimum=2,a-192,128
        elseif a>=224 and a<=239 then count,code,minimum=3,a-224,2048
        elseif a>=240 and a<=244 then count,code,minimum=4,a-240,65536
        else need(false) end
        need(i+count-1<=#text)
        for j=i+1,i+count-1 do local b=text:byte(j);need(b>=128 and b<=191);code=code*64+b-128 end
        need(code>=minimum and code<=1114111 and (code<55296 or code>57343));i=i+count
    end
    return text
end
function M.to_envelope(raw,catalog)
    need(type(raw)=='string' and #raw>35 and #raw<=MAX_BYTES)
    need(type(catalog)=='table' and type(catalog.hash)=='string' and #catalog.hash==64)
    local hash=catalog.hash:gsub('..',function(x)return string.char(tonumber(x,16))end)
    need(raw:sub(1,35)=='BW'..string.char(2)..hash)
    local offset,nodes=36,0
    local strings={}
    local function take(size)
        need(size>=0 and size<=#raw-offset+1)
        local value=raw:sub(offset,offset+size-1);offset=offset+size;return value
    end
    local function uint()
        local value,multiple=0,1
        for shift=0,7 do
            local b=take(1):byte();value=value+(b%128)*multiple
            need(value<=MAX_INT)
            if b<128 then need(shift==0 or b~=0);return value end
            multiple=multiple*128
        end
        need(false)
    end
    local function text(size)size=size or uint();need(size<=MAX_BYTES);return utf8(take(size))end
    local visit
    local function fields(depth)
        local count=uint();need(count<=MAX_NODES-nodes)
        local result={}
        for _=1,count do
            local key=uint();local mode,identity=key%4,math.floor(key/4);local name
            if mode==0 then
                need(identity>=1 and catalog.schema.fields[identity]~=nil);name=tostring(identity)
            elseif mode==1 then
                local symbol=catalog.schema.symbols[identity];name='@'..tostring(identity)
                need(type(symbol)=='string' and #name<#symbol)
            else need(mode==2);name=text(identity) end
            need(result[name]==nil);result[name]=visit(depth+1)
        end
        return result
    end
    visit=function(depth)
        nodes=nodes+1;need(nodes<=MAX_NODES and depth<=MAX_DEPTH)
        local tag=take(1):byte()
        if tag>=32 then return tag-32 end
        if tag==0 then return null end
        if tag==1 then return false end
        if tag==2 then return true end
        if tag==3 or tag==12 then local number=uint();need(tag==3 or number>0);return tag==3 and number or -number end
        if tag==4 then
            local a,b,c,d,e,f,g,h=take(8):byte(1,8)
            local sign=h>=128 and -1 or 1;local exponent=(h%128)*16+math.floor(g/16)
            local fraction=a+b*256+c*65536+d*16777216+e*4294967296+f*1099511627776+(g%16)*281474976710656
            need(exponent<2047)
            if exponent==0 then return sign*(fraction*2^-1074) end
            return sign*((1+fraction/4503599627370496)*2^(exponent-1023))
        end
        if tag==5 then
            local length=uint();local value=text(length)
            if length>=8 and #strings<4096 then strings[#strings+1]=value end
            return value
        end
        if tag==13 then local id=uint();need(id>=1 and id<=#strings);return strings[id] end
        if tag==6 then return fields(depth) end
        if tag==7 then
            local length=uint();need(length<=MAX_NODES-nodes);local value={0}
            for i=1,length do value[i+1]=visit(depth+1) end
            return value
        end
        if tag==8 or tag==10 then return {tag==8 and 1 or 3,uint()} end
        if tag==9 then local id=uint();return {2,id,fields(depth+1)} end
        if tag==11 then local id=uint();return {4,id,visit(depth+1)} end
        need(false)
    end
    local root=visit(0);need(offset==#raw+1)
    return {_bw={1,catalog.hash,root}}
end
function M.unwrap(value,catalog)
    need(type(value)=='table' and type(value._bb)=='string')
    for key in pairs(value)do need(key=='_bb')end
    return M.to_envelope(unbase64(value._bb),catalog)
end
return M
