-- Indexed minimum heap: cancellation/replacement removes its node immediately,
-- so repeatedly replacing an ID cannot leave unbounded cancelled entries.
local M = {}
M.__index = M

function M.new()
    return setmetatable({heap={}, positions={}, sequence=0}, M)
end

local function earlier(a, b)
    return a.task.run_at < b.task.run_at
        or (a.task.run_at == b.task.run_at and a.sequence < b.sequence)
end

local function swap(queue, a, b)
    local heap=queue.heap
    heap[a],heap[b]=heap[b],heap[a]
    queue.positions[heap[a].id]=a
    queue.positions[heap[b].id]=b
end

local function up(queue, index)
    while index>1 do
        local parent=math.floor(index/2)
        if not earlier(queue.heap[index],queue.heap[parent]) then break end
        swap(queue,index,parent);index=parent
    end
end

local function down(queue, index)
    local heap=queue.heap
    while index*2<=#heap do
        local child=index*2
        if child<#heap and earlier(heap[child+1],heap[child]) then child=child+1 end
        if not earlier(heap[child],heap[index]) then break end
        swap(queue,index,child);index=child
    end
end

function M:remove(id)
    local index=self.positions[id]
    if not index then return nil end
    local heap=self.heap
    local removed=heap[index]
    self.positions[id]=nil
    local last=table.remove(heap)
    if index<=#heap then
        heap[index]=last;self.positions[last.id]=index
        local parent=math.floor(index/2)
        if index>1 and earlier(last,heap[parent]) then up(self,index)
        else down(self,index) end
    end
    return removed
end

function M:put(id, task)
    self:remove(id)
    self.sequence=self.sequence+1
    local node={id=id,task=task,sequence=self.sequence}
    local index=#self.heap+1
    self.heap[index]=node;self.positions[id]=index
    up(self,index)
end

function M:peek() return self.heap[1] end

function M:pop()
    local first=self.heap[1]
    if first then return self:remove(first.id) end
end

function M:clear()
    self.heap={};self.positions={};self.sequence=0
end

function M:count() return #self.heap end

return M
