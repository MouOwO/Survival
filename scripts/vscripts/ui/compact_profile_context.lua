-- UI invalidation metadata across synchronous authoritative profile commits.
-- No profile/reward mutation. O(1) push/read/pop; per-player stacks handle
-- nested commits without copying an account or retaining a completed frame.
local M={}
local current={}
local function pack(...)return {n=select("#",...),...}end
function M.current(player_id)return current[player_id]end
function M.with(player_id,changes,callback)
    assert(type(player_id)=="number" and type(changes)=="table" and type(callback)=="function",
        "compact_profile_context_arguments_invalid")
    local previous=current[player_id];current[player_id]=changes
    local result=pack(pcall(callback))
    current[player_id]=previous
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
end
function M.reset()current={}end
return M
