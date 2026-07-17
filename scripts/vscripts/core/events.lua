local M = {
    GAME_STARTED = "game.started",
    HERO_READY = "player.hero_ready",
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

    GOLD_MINE_UPGRADE_REQUEST = "gold_mine.upgrade.request",
    GOLD_MINE_CRIT_UPGRADE_REQUEST = "gold_mine.crit_upgrade.request",
    GOLD_MINE_CHANGED = "gold_mine.changed",

    TREE_SPAWNED = "tree.spawned",
    TREE_HIT = "tree.hit",
    TREE_DESTROYED = "tree.destroyed",

    WAVE_CHANGED = "wave.changed",
    WAVE_START_NEXT = "wave.internal.start_next",

    UI_NOTIFICATION = "ui.notification",
    UI_DIRTY = "ui.dirty",
    UI_SNAPSHOT_REQUESTED = "ui.snapshot.requested",

    SHOP_OPEN_REQUEST = "shop.open.request",
    SHOP_CLOSE_REQUEST = "shop.close.request",
    SHOP_PURCHASE_REQUEST = "shop.purchase.request",
    SHOP_STATE_CHANGED = "shop.state.changed",
}

return M
