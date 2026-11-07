package.path='scripts/vscripts/?.lua;'..package.path
local dir=arg[1]
if dir then package.preload['ui/compact_selected_projection']=function()return dofile(dir..'/compact_selected_projection.lua')end end
local L=require('config/generated/ui_static_catalog_lookup')
local W=require('ui/compact_wire')
local S=assert(W.compile_lookup(L,1))
local factory=assert(require('ui/compact_selected_projection').new(L,{derive_aliases=true}))
local legacy=assert(require('ui/compact_selected_projection').new(L))
local projection=require('ui/combat_stat_projection')
local cases={-1/math.huge,0,1.25,-999.5,9007199254740991,1e100}
local result={}
for index,value in ipairs(cases)do
 local raw={success=1,entindex=100,attack_min=value,attack_max=value,
  strength=value,agility=value,intellect=value}
 local source=projection.for_ui(raw)
 local state,ops=assert(factory.initialize(source,100,1))
 local packets=assert(W.encode(S,{schema=1,schema_sha256=L.sha256,session=900,epoch=1,view=5},1,ops,{full=true}))
 local _,old_ops=assert(legacy.initialize(source,100,1))
 local old_packets=assert(W.encode(S,{schema=1,schema_sha256=L.sha256,session=900,epoch=1,view=5},1,old_ops,{full=true}))
 local expected={}
 for _,entry in ipairs({{'minimum',source.stat_tooltips.attack.minimum},{'maximum',source.stat_tooltips.attack.maximum},
  {'strength',source.stat_tooltips.attributes.strength},{'agility',source.stat_tooltips.attributes.agility},
  {'intellect',source.stat_tooltips.attributes.intellect}})do expected[entry[1]]=assert(W.float64_words(entry[2]))end
 result[#result+1]={packets=packets,legacy=old_packets,expected=expected,negative_zero=index==1}
end
print(require('core/json_encoder').encode(result))
