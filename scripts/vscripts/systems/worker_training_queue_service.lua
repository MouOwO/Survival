local M = {}

-- A city owns one serial production queue. Reservations belong to the player,
-- so multiple cities cannot bypass a training tier's lifetime limit.
function M.create(deps)
    local queues, sequence = {}, 0
    local service = {}
    local function publish(queue)
        deps.changed(queue.player_id, queue.team, queue.source_entindex)
    end
    local function public_job(job)
        return {
            job_id = job.job_id, training_id = job.training_id,
            level = job.level, name = job.name, duration = job.duration,
            started_at = job.started_at or 0, finish_at = job.finish_at or 0,
        }
    end
    local start_next
    local function refund(job, reason)
        if job.refunded then return end
        job.refunded = true
        deps.refund(job, reason)
    end
    function service:reset()
        for _, queue in pairs(queues) do deps.cancel(queue.task_id) end
        queues, sequence = {}, 0
    end
    function service:reserved(player_id, training_id)
        local count = 0
        for _, queue in pairs(queues) do
            if queue.player_id == player_id then
                for _, job in ipairs(queue.jobs) do
                    if job.training_id == training_id then count = count + 1 end
                end
            end
        end
        return count
    end
    function service:snapshot(source_entindex, player_id)
        local queue = queues[tonumber(source_entindex)]
        local snapshot = {active_job = {}, queued = {}, queue_count = 0,
            queue_capacity = deps.capacity or 7}
        if not queue or queue.player_id ~= player_id then return snapshot end
        snapshot.queue_count = #queue.jobs
        for index, job in ipairs(queue.jobs) do
            if index == 1 then snapshot.active_job = public_job(job)
            else snapshot.queued[#snapshot.queued + 1] = public_job(job) end
        end
        return snapshot
    end
    function service:cancel_city(source_entindex, reason)
        local queue = queues[tonumber(source_entindex)]
        if not queue then return false end
        queues[queue.source_entindex] = nil
        deps.cancel(queue.task_id)
        for _, job in ipairs(queue.jobs) do refund(job, reason) end
        queue.jobs = {}
        publish(queue)
        return true
    end
    function service:cancel_player(player_id, reason)
        local cities = {}
        for entindex, queue in pairs(queues) do
            if queue.player_id == player_id then cities[#cities + 1] = entindex end
        end
        for _, entindex in ipairs(cities) do self:cancel_city(entindex, reason) end
    end
    start_next = function(queue)
        local job = queue.jobs[1]
        if not job then queues[queue.source_entindex] = nil; return end
        local valid, error_code = deps.validate(job)
        if not valid then
            service:cancel_city(queue.source_entindex, error_code)
            return
        end
        job.started_at = deps.now()
        job.finish_at = job.started_at + job.duration
        deps.schedule(job.duration, function()
            -- Removed cities, old sessions and duplicate callbacks are harmless.
            if queues[queue.source_entindex] ~= queue or queue.jobs[1] ~= job then return end
            local still_valid, reason = deps.validate(job)
            if not still_valid then
                service:cancel_city(queue.source_entindex, reason)
                return
            end
            local ok, result = pcall(deps.finish, job)
            if not ok or not result or not result.ok then
                refund(job, ok and result and result.error or "training_completion_failed")
            end
            table.remove(queue.jobs, 1)
            start_next(queue)
            publish(queue)
        end, queue.task_id)
    end
    function service:enqueue(job)
        local key = tonumber(job.source_entindex)
        local queue = queues[key]
        if queue and queue.player_id ~= job.player_id then
            return {ok = false, error = "training_owner_mismatch"}
        end
        if queue and #queue.jobs >= (deps.capacity or 7) then
            return {ok = false, error = "training_queue_full"}
        end
        local valid, error_code = deps.validate(job)
        if not valid then return {ok = false, error = error_code} end
        local spent = deps.reserve(job)
        if not spent or not spent.ok then return spent or {ok = false, error = "resource_error"} end
        sequence = sequence + 1
        job.job_id = sequence
        if not queue then
            queue = {source_entindex = key, player_id = job.player_id,
                team = job.team, jobs = {}, task_id = "worker_training:" .. tostring(key)}
            queues[key] = queue
        end
        queue.jobs[#queue.jobs + 1] = job
        if #queue.jobs == 1 then start_next(queue) end
        publish(queue)
        return {ok = true, queued = true, job_id = job.job_id, queue_count = #queue.jobs}
    end
    return service
end

return M