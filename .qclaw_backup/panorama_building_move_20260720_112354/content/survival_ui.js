(function () {
    "use strict";

    var playerId = Game.GetLocalPlayerID();
    var tableName = "survival_ui_state";
    var tableKey = "player_" + playerId;
    var lastSequence = -1;
    var lastSnapshotAt = 0;

    var waveStatusText = {
        waiting: "等待",
        countdown: "倒计时",
        spawning: "出怪中",
        active: "战斗中",
        all_waves_spawned: "全部波次已生成"
    };

    function panel(id) {
        return $("#" + id);
    }

    function setText(id, value) {
        var target = panel(id);
        if (target) target.text = String(value);
    }

    function numberValue(value) {
        var number = Number(value || 0);
        if (Math.abs(number - Math.round(number)) < 0.001) {
            return String(Math.round(number));
        }
        return number.toFixed(1).replace(/\.0$/, "");
    }

    function sequenceOf(snapshot) {
        var sequence = Number(snapshot && snapshot.sequence);
        return isNaN(sequence) ? -1 : sequence;
    }

    function update(snapshot) {
        if (!snapshot) return;
        var sequence = sequenceOf(snapshot);
        if (sequence >= 0 && sequence < lastSequence) return;
        if (sequence >= 0) lastSequence = sequence;
        lastSnapshotAt = Game.GetGameTime();

        var resources = snapshot.resources || {};
        var wave = snapshot.wave || {};
        setText("WoodValue", "木材 " + numberValue(resources.wood));
        setText("GoldValue", "金币 " + numberValue(resources.gold));
        setText(
            "PopulationValue",
            "人口 " + numberValue(resources.population)
                + "/" + numberValue(resources.max_population)
        );
        setText("CityLevelValue", "主城 Lv." + numberValue(snapshot.city_level));
        setText(
            "WaveNumber",
            "波次 " + numberValue(wave.current_wave)
                + "/" + numberValue(wave.total_waves || 30)
        );
        setText("WaveState", waveStatusText[wave.status] || wave.status || "等待");
        setText("WaveTimer", Math.max(0, Math.ceil(Number(wave.timer || 0))));
        setText("AliveValue", "存活 " + numberValue(wave.alive));
        setText("PendingValue", "待生成 " + numberValue(wave.pending));
    }

    function readSnapshot() {
        update(CustomNetTables.GetTableValue(tableName, tableKey));
    }

    function requestSnapshot() {
        GameEvents.SendCustomGameEventToServer("ui_request_full_snapshot", {
            request_id: "hud_" + String(Date.now())
        });
    }

    function pollSnapshot() {
        readSnapshot();
        if (Game.GetGameTime() - lastSnapshotAt > 2.0) requestSnapshot();
        $.Schedule(0.25, pollSnapshot);
    }

    function showNotification(payload) {
        var container = panel("NotificationContainer");
        if (!container) return;
        var item = $.CreatePanel("Panel", container, "");
        item.AddClass("Notification");
        if (payload.level === "error") item.AddClass("error");
        var label = $.CreatePanel("Label", item, "");
        label.text = payload.message || "";
        $.Schedule(3.0, function () {
            if (item && item.IsValid()) item.DeleteAsync(0);
        });
    }

    CustomNetTables.SubscribeNetTableListener(tableName, function (name, key, value) {
        if (key === tableKey) update(value);
    });
    GameEvents.Subscribe("ui_state_snapshot", update);
    GameEvents.Subscribe("ui_notification", showNotification);

    $.Msg("[SurvivalUI] realtime HUD listener ready.");
    $.Schedule(0.10, function () {
        readSnapshot();
        requestSnapshot();
        pollSnapshot();
    });
})();
