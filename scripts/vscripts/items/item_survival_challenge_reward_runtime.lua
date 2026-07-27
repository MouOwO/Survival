local event_bus = require("core/event_bus")
local events = require("core/events")
local catalog = require("config/generated/content_catalog")
local content_id_aliases = require("config/content_id_aliases")

item_survival_challenge_reward = class({})

function item_survival_challenge_reward:GetBehavior()
    return DOTA_ABILITY_BEHAVIOR_PASSIVE
end

function item_survival_challenge_reward:Claim(caster)
    if not IsServer() then return false end
    local player_id = caster and caster:GetPlayerOwnerID() or -1
    local owner_id = tonumber(self.survival_owner_player_id)
    local original_content_id = tostring(self.survival_content_id or "")
    local content_id = content_id_aliases.canonical(original_content_id)
    local reward_key = tostring(self.survival_reward_key or "unknown")
    print(string.format(
        "[CHALLENGE_REWARD_CLAIM] implementation=runtime player=%s owner=%s key=%s content=%s entindex=%s claimed=%s action=start",
        tostring(player_id), tostring(owner_id), reward_key,
        tostring(content_id), tostring(self:entindex()),
        tostring(self.survival_claimed == true)))
    if self.survival_claimed then return false end
    if player_id < 0 or owner_id ~= player_id or content_id == "" then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "该挑战材料不属于你",
            level = "error",
        })
        return false
    end

    if content_id ~= original_content_id then
        print("[CHALLENGE_REWARD_ID_NORMALIZED] from="
            .. original_content_id .. " to=" .. content_id)
        self.survival_content_id = content_id
    end

    -- The engine has already placed this entity in a visible equipment slot.
    -- Adopt it as the persistent material shell. The authoritative inventory
    -- transaction removes it only after synthesis succeeds.
    local adoption = event_bus.request(events.INVENTORY_ITEM_SHELL_ADOPT_REQUEST, {
        player_id = player_id,
        content_id = content_id,
        hero = caster,
        item = self,
    })
    print(string.format(
        "[CHALLENGE_REWARD_ADOPT] player=%s key=%s content=%s entindex=%s ok=%s adopted=%s error=%s",
        tostring(player_id), reward_key, tostring(content_id),
        tostring(self:entindex()), tostring(adoption and adoption.ok == true),
        tostring(adoption and adoption.adopted == true),
        tostring(adoption and adoption.error or "none")))
    if not adoption or not adoption.ok then
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "挑战材料无法放入装备栏："
                .. tostring(adoption and adoption.error or "handler_missing"),
            level = "error",
        })
        return false
    end

    local result = event_bus.request(events.CONTENT_INVENTORY_GRANT_REQUEST, {
        player_id = player_id,
        content_id = content_id,
        count = 1,
        reason = "challenge_ground_reward_pickup",
    })
    local granted_count = result and result.snapshot and result.snapshot.counts
        and result.snapshot.counts[content_id] or 0
    print(string.format(
        "[CHALLENGE_REWARD_GRANT] player=%s key=%s content=%s entindex=%s ok=%s inventory_count=%s error=%s",
        tostring(player_id), reward_key, tostring(content_id),
        tostring(self:entindex()), tostring(result and result.ok == true),
        tostring(granted_count), tostring(result and result.error or "none")))
    if not result or not result.ok then
        if adoption.adopted then
            event_bus.request(events.INVENTORY_ITEM_SHELL_RELEASE_REQUEST, {
                player_id = player_id,
                content_id = content_id,
                item = self,
            })
            -- Returning false lets addon_game_mode.lua move this same entity
            -- back to the hero's feet; no duplicate container is created here.
        end
        event_bus.emit(events.UI_NOTIFICATION, {
            player_id = player_id,
            message = "挑战材料登记失败："
                .. tostring(result and result.error or "handler_missing"),
            level = "error",
        })
        return false
    end

    self.survival_claimed = true
    -- Further copies merge into the existing visible shell. Remove only this
    -- duplicate entity; the represented material and its count remain visible.
    if not adoption.adopted then
        CustomNetTables:SetTableValue(
            "survival_inventory_item_identity",
            tostring(self:entindex()),
            { content_id = content_id, removed = 1 }
        )
        if caster.RemoveItem then caster:RemoveItem(self) end
        UTIL_Remove(self)
    end

    -- Pickup owns only shell adoption and authoritative inventory registration.
    -- Recipe matching, material consumption and result granting belong entirely
    -- to weapon_synthesis_service and are triggered through this event.
    event_bus.emit(events.WEAPON_SYNTHESIS_CHECK_REQUESTED, {
        player_id = player_id,
        content_id = content_id,
        reason = "challenge_ground_reward_pickup",
    })

    local definition = catalog.by_id[content_id] or {}
    event_bus.emit(events.UI_NOTIFICATION, {
        player_id = player_id,
        message = "已拾取：" .. tostring(definition.name or content_id)
            .. "（保存在装备栏，满足配方时自动合成）",
    })
    return true
end

return item_survival_challenge_reward