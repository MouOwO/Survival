local M = {
    GAME_STARTED = "game.started",
    HERO_READY = "player.hero_ready",
    HERO_SUMMONED = "hero.summoned",
    ENGINE_ENTITY_KILLED = "engine.entity_killed",

    GRID_CAN_PLACE_REQUEST = "grid.can_place.request",
    GRID_OCCUPY_REQUEST = "grid.occupy.request",
    GRID_RELEASE_REQUEST = "grid.release.request",

    RESOURCE_GET_REQUEST = "resource.get.request",
    RESOURCE_TRY_SPEND_REQUEST = "resource.try_spend.request",
    RESOURCE_ADD_REQUEST = "resource.add.request",
    RESOURCE_RELEASE_POP_REQUEST = "resource.release_pop.request",
    RESOURCE_CHANGED = "resource.changed",

    BUILD_CAN_PLACE_REQUEST = "building.can_place.request",
    BUILD_REQUEST = "building.build.request",
    BUILDING_UPGRADE_REQUEST = "building.upgrade.request",
    TOWER_CLASS_REQUEST = "tower.class.request",
    BUILDING_QUERY_REQUEST = "building.query.request",
    BUILDING_CREATED = "building.created",
    BUILDING_CHANGED = "building.changed",
    BUILDING_DESTROYED = "building.destroyed",

    WORKER_TRAIN_REQUEST = "worker.train.request",
    WORKER_CHANGED = "worker.changed",

    BUILDER_UNLOCK_CHANGED = "builder.unlock.changed",
    BUILDER_STAGE_CHANGED = "builder.stage.changed",

    GOLD_MINE_UPGRADE_REQUEST = "gold_mine.upgrade.request",
    GOLD_MINE_CRIT_UPGRADE_REQUEST = "gold_mine.crit_upgrade.request",
    GOLD_MINE_CHANGED = "gold_mine.changed",

    TREE_SPAWNED = "tree.spawned",
    TREE_HIT = "tree.hit",
    TREE_DESTROYED = "tree.destroyed",
    TREE_CHANGED = "tree.changed",

    WAVE_CHANGED = "wave.changed",
    WAVE_START_NEXT = "wave.internal.start_next",
    WAVE_DIFFICULTY_SET_REQUEST = "wave.difficulty.set.request",

    UI_NOTIFICATION = "ui.notification",
    UI_DIRTY = "ui.dirty",
    UI_SNAPSHOT_REQUESTED = "ui.snapshot.requested",

    SHOP_OPEN_REQUEST = "shop.open.request",
    SHOP_CLOSE_REQUEST = "shop.close.request",
    SHOP_PURCHASE_REQUEST = "shop.purchase.request",
    SHOP_STATE_CHANGED = "shop.state.changed",
    SHOP_UNLOCK_CHANGED = "shop.unlock.changed",

    HERO_ALTAR_OPEN_REQUEST = "hero.altar.open.request",
    HERO_SUMMON_SNAPSHOT_REQUEST = "hero.summon.snapshot.request",
    HERO_SUMMON_REQUEST = "hero.summon.request",
    HERO_SUMMON_GET_REQUEST = "hero.summon.get.request",
    HERO_SUMMON_STATE_CHANGED = "hero.summon.state.changed",

    PLAYER_ENTITLEMENT_GET_REQUEST = "player.entitlement.get.request",
    PLAYER_ENTITLEMENT_SET_REQUEST = "player.entitlement.set.request",
    PLAYER_ENTITLEMENT_CHANGED = "player.entitlement.changed",

    HERO_PROGRESSION_GET_REQUEST = "hero.progression.get.request",
    HERO_PROGRESSION_APPLY_REQUEST = "hero.progression.apply.request",
    HERO_PROGRESSION_CHANGED = "hero.progression.changed",
    HERO_SKILL_REWARD_REQUEST = "hero.skill_reward.request",

    HERO_SKILL_STATE_GET_REQUEST = "hero.skill.state.get.request",
    HERO_SKILL_GRANT_REQUEST = "hero.skill.grant.request",
    HERO_SKILL_CHANGED = "hero.skill.changed",
    HERO_SKILL_POOL_DRAW_REQUEST = "hero.skill.pool.draw.request",
    HERO_SKILL_CHOICE_CREATE_REQUEST = "hero.skill.choice.create.request",
    HERO_SKILL_CHOICE_GET_REQUEST = "hero.skill.choice.get.request",
    HERO_SKILL_CHOICE_SELECT_REQUEST = "hero.skill.choice.select.request",
    HERO_SKILL_CHOICE_CHANGED = "hero.skill.choice.changed",

    CONTENT_INVENTORY_GRANT_REQUEST = "content.inventory.grant.request",
    CONTENT_INVENTORY_TRANSACTION_REQUEST = "content.inventory.transaction.request",
    CONTENT_INVENTORY_GET_REQUEST = "content.inventory.get.request",
    CONTENT_INVENTORY_CHANGED = "content.inventory.changed",

    WEAPON_EQUIPMENT_GET_REQUEST = "weapon.equipment.get.request",
    WEAPON_EQUIPPED_CHANGED = "weapon.equipped.changed",
    WEAPON_ATTACK_LANDED = "weapon.attack.landed",
    WEAPON_GROWTH_GET_REQUEST = "weapon.growth.get.request",
    WEAPON_GROWTH_DEBUG_REQUEST = "weapon.growth.debug.request",
    WEAPON_GROWTH_CHANGED = "weapon.growth.changed",
    WEAPON_SYNTHESIZED = "weapon.synthesized",

    HERO_COMBAT_STATS_GET_REQUEST = "hero.combat_stats.get.request",
    HERO_COMBAT_STATS_CHANGED = "hero.combat_stats.changed",
    COMBAT_DAMAGE_RESOLVED = "combat.damage.resolved",

    MONSTER_ENCOUNTER_START_REQUEST = "monster.encounter.start.request",
    MONSTER_ENCOUNTER_QUERY_REQUEST = "monster.encounter.query.request",
    MONSTER_ENCOUNTER_CHANGED = "monster.encounter.changed",
    MONSTER_SPAWNED = "monster.spawned",
    MONSTER_KILLED = "monster.killed",
    MONSTER_REWARD_GRANTED = "monster.reward.granted",
}

return M
