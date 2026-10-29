package.path="scripts/vscripts/?.lua;"..package.path
local presentation=require("systems/archive_reward_presentation")
local qualities={N="#8fc47b",R="#74c8f2",SR="#b680ee",SSR="#f5c65e",UR="#ef5350",
    white="#d7dee4",blue="#74c8f2",purple="#b680ee",gold="#f5c65e"}
local checks=0
for quality,color in pairs(qualities) do
    local message=presentation.message({awarded=2,rewards={{name="测试碎片",quality=quality,count=2}}})
    assert(message=='获得 <font color="'..color..'">测试碎片</font> ×2')
    checks=checks+1
end
local escaped=presentation.message({awarded=1,rewards={{name='<img src="x">&碎片',quality="gold",count=1}}})
assert(not escaped:find("<img",1,true) and escaped:find("&lt;img",1,true) and escaped:find("&amp;",1,true));checks=checks+1
for _,response in ipairs({
    {},{awarded=1},{awarded=0,rewards={}},{awarded=1,rewards={}},
    {awarded=2,rewards={{name="碎片",count=1}}},
    {awarded=1,rewards={{name="碎片",count=2}}},
    {awarded=1,rewards={{name="碎片",count=-1}}},
    {awarded=1,rewards={{name="碎片",count=1.5}}},
    {awarded=1,rewards={{name="",count=1}}},
    {awarded=1,skipped_reason="未达条件",rewards={{name="碎片",count=1}}},
}) do assert(presentation.message(response)==nil);checks=checks+1 end
local multiple=presentation.message({awarded=3,rewards={
    {name="白色材料",quality="white",count=1},{name="紫色材料",quality="purple",count=2}}})
assert(multiple:find('color="#d7dee4"',1,true) and multiple:find('color="#b680ee"',1,true));checks=checks+1
print("ARCHIVE_REWARD_PRESENTATION_PASS: "..checks.." quality colors, escaped names, exact accepted quantities and no invented legacy rewards")
