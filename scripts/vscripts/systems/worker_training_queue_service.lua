local M = {}

-- A city owns one serial production queue. Waiting jobs reserve training
-- quotas, while their currency and population are charged only at the head.
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
    local function refund(job, reason)
        if not job.paid or job.refunded then return end
        job.refunded = true
        deps.refund(job, reason)
    end
    local function schedule(queue, delay, callback)
        queue.timer_sequence = (queue.timer_sequence or 0) + 1
        local timer_sequence = queue.timer_sequence
        deps.schedule(delay, function()
            if queues[queue.source_entindex] ~= queue
                or queue.timer_sequence ~= timer_sequence then return end
            -- Consuming a timer also invalidates a duplicate callback before it
            -- can spend again or replace the next job's timer.
            queue.timer_sequence = timer_sequence + 1
            callback()
        end, queue.task_id)
    end
    function service:reset()
        for _, queue in pairs(queues) do
            queue.cancel_reason = "queue_reset"
            deps.cancel(queue.task_id)
        end
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
        local snapshot = {active_job = {}, blocked_head = {}, blocked_reason = "",
            queued = {}, queue_count = 0, queue_capacity = deps.capacity or 7,
            cost_timing_text = "开始训练时扣费，排队未扣费"}
        if not queue or queue.player_id ~= player_id then return snapshot end
        snapshot.queue_count = #queue.jobs
        snapshot.blocked_reason = queue.blocked_reason or ""
        for index, job in ipairs(queue.jobs) do
            if index == 1 then
                if job.paid then snapshot.active_job = public_job(job)
                else snapshot.blocked_head = public_job(job) end
            else snapshot.queued[#snapshot.queued + 1] = public_job(job) end
        end
        return snapshot
    end
    function service:cancel_city(source_entindex, reason)
        local queue = queues[tonumber(source_entindex)]
        if not queue then return false end
        queue.cancel_reason = reason or "training_cancelled"
        queues[queue.source_entindex] = nil
        deps.cancel(queue.task_id)
        for _, job in ipairs(queue.jobs) do refund(job, queue.cancel_reason) end
        queue.jobs, queue.blocked_reason = {}, ""
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
    local start_next
    start_next = function(queue)
        if queues[queue.source_entindex] ~= queue then return end
        local job = queue.jobs[1]
        if not job then
            queues[queue.source_entindex] = nil
            queue.blocked_reason = ""
            publish(queue)
            return
        end
        if job.paid then return end
        local valid, error_code = deps.validate(job)
        if not valid then
            service:cancel_city(queue.source_entindex, error_code)
            return
        end
        local spent = deps.reserve(job)
        local attached = queues[queue.source_entindex] == queue and queue.jobs[1] == job
        if not spent or not spent.ok then
            if not attached then return end
            local blocked_reason = spent and (spent.error or spent.error_code) or "resource_error"
            if not blocked_reason or blocked_reason == "" then blocked_reason = "resource_error" end
            local changed = queue.blocked_reason ~= blocked_reason
            queue.blocked_reason = blocked_reason
            schedule(queue, math.max(1, tonumber(deps.retry_interval) or 1), function()
                if queue.jobs[1] == job then start_next(queue) end
            end)
            if changed then publish(queue) end
            return
        end
        job.paid = true
        -- Resource publication can synchronously remove the city or cancel its
        -- queue. Roll back this accepted spend before scheduling anything.
        if not attached then
            refund(job, queue.cancel_reason or "training_cancelled")
            return
        end
        queue.blocked_reason = ""
        job.started_at = deps.now()
        job.finish_at = job.started_at + job.duration
        schedule(queue, job.duration, function()
            if queue.jobs[1] ~= job then return end
            local still_valid, reason = deps.validate(job)
            if not still_valid then
                service:cancel_city(queue.source_entindex, reason)
                return
            end
            local ok, result = pcall(deps.finish, job)
            if not ok or not result or not result.ok then
                refund(job, ok and result and result.error or "training_completion_failed")
            end
            if queues[queue.source_entindex] ~= queue or queue.jobs[1] ~= job then return end
            table.remove(queue.jobs, 1)
            start_next(queue)
        end)
        publish(queue)
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
        local allowed = deps.can_reserve(job)
        if not allowed or not allowed.ok then
            return allowed or {ok = false, error = "resource_error"}
        end
        sequence = sequence + 1
        job.job_id = sequence
        job.paid, job.refunded, job.started_at, job.finish_at = nil, nil, nil, nil
        if not queue then
            queue = {source_entindex = key, player_id = job.player_id,
                team = job.team, jobs = {}, blocked_reason = "",
                task_id = "worker_training:" .. tostring(key)}
            queues[key] = queue
        end
        queue.jobs[#queue.jobs + 1] = job
        if #queue.jobs == 1 then start_next(queue) else publish(queue) end
        return {ok = true, queued = true, job_id = job.job_id, queue_count = #queue.jobs}
    end
    return service
end

return M
