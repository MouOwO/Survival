package.path='scripts/vscripts/?.lua;'..package.path
local delta=require('core/ui_snapshot_delta')
local previous={rows={{id='a',count=0},{id='b',count=5}},revision=1}
local current={rows={{id='a',count=0},{id='b',count=6}},revision=2}
local changes=delta.diff(previous,current)
assert(#changes==2)
for _,op in ipairs(changes) do assert(type(op.value)~='table','unchanged rows must not be resent') end
assert(#delta.diff(current,current)==0)
print('UI_SNAPSHOT_DELTA_PASS: only changed leaf fields transmitted')
