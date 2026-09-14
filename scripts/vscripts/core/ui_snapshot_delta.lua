local M = {}
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function M.diff(previous,current)
    local changes={}
    local function visit(a,b,path)
        if equal(a,b) then return end
        if type(a)=="table" and type(b)=="table" then
            for k,v in pairs(b) do
                local next_path={unpack(path)};next_path[#next_path+1]=tostring(k)
                visit(a[k],v,next_path)
            end
            for k in pairs(a) do if b[k]==nil then
                local next_path={unpack(path)};next_path[#next_path+1]=tostring(k)
                changes[#changes+1]={path=next_path,remove=1}
            end end
        else changes[#changes+1]={path=path,value=b} end
    end
    visit(previous,current,{})
    return changes
end
return M
