(function () {
    "use strict";

    var data = GameUI.CustomUIConfig().TAPortraitProbeData;
    var runtimeReady = false;
    var focusedBody = -1;

    function hasValidData(value) {
        return value
            && value.addonName === "survival_ta_portrait_probe"
            && value.assetId === "tower_death_templar_assassin"
            && value.body
            && typeof value.body.model === "string"
            && Array.isArray(value.wearables)
            && value.wearables.length === 3
            && value.runtimeTable
            && typeof value.runtimeTable.name === "string"
            && typeof value.runtimeTable.key === "string";
    }

    function setStatus(result, stateClass) {
        var status = $("#ProbeStatus");
        if (!status) return;
        status.text = result;
        status.SetHasClass("Ready", stateClass === "ready");
        status.SetHasClass("Passed", stateClass === "passed");
        status.SetHasClass("Failed", stateClass === "failed");
    }

    function focusRuntimeBody(bodyEntindex) {
        var target = Number(bodyEntindex || -1);
        if (target <= 0 || target === focusedBody) return;
        if (typeof GameUI.SetCameraTarget !== "function") {
            $.Msg("[TA_PORTRAIT_PROBE_RUNTIME] CAMERA_TARGET_API_MISSING");
            setStatus("CAMERA_TARGET_API_MISSING", "failed");
            return;
        }
        GameUI.SetCameraTarget(target);
        focusedBody = target;
        $.Msg("[TA_PORTRAIT_PROBE_RUNTIME] CAMERA_TARGET_SET body=", target);
    }

    function applyRuntimeState(_tableName, _key, state) {
        if (!state) return;
        runtimeReady = Number(state.success) === 1
            && state.status === "ready_visual_check_required"
            && Number(state.body_entindex) > 0
            && Number(state.wearable_count) === 3;
        if (!runtimeReady) {
            $.Msg("[TA_PORTRAIT_PROBE_RUNTIME] NOT_READY ", JSON.stringify(state));
            setStatus(String(state.status || "RUNTIME_NOT_READY"), "failed");
            return;
        }
        focusRuntimeBody(state.body_entindex);
        setStatus("RUNTIME READY — INSPECT IDLE FRAMES", "ready");
        $.Msg("[TA_PORTRAIT_PROBE_RUNTIME] READY ", JSON.stringify(state));
    }

    function record(result) {
        if (!hasValidData(data)) {
            $.Msg("[TA_PORTRAIT_PROBE_RESULT] DATA_INVALID");
            setStatus("DATA_INVALID", "failed");
            return;
        }
        if (!runtimeReady) {
            $.Msg("[TA_PORTRAIT_PROBE_RESULT] RUNTIME_NOT_READY result=", result);
            setStatus("RUNTIME_NOT_READY", "failed");
            return;
        }
        setStatus(result, result === "PASS" ? "passed" : "failed");
        GameEvents.SendCustomGameEventToServer("ta_portrait_probe_record_result", {
            result: result
        });
        $.Msg("[TA_PORTRAIT_PROBE_RESULT] ", JSON.stringify({
            result: result,
            evidence: "manual_multi_frame_runtime_observation",
            sceneMap: data.sceneMap,
            bodyModel: data.body.model,
            wearableModels: data.wearables.map(function (wearable) {
                return wearable.model;
            })
        }));
    }

    GameUI.CustomUIConfig().TAPortraitProbe = {
        Record: record
    };

    if (!hasValidData(data)) {
        $.Msg("[TA_PORTRAIT_PROBE] DATA_INVALID");
        setStatus("DATA_INVALID", "failed");
        return;
    }

    CustomNetTables.SubscribeNetTableListener(data.runtimeTable.name, function (
        tableName,
        key,
        state
    ) {
        if (key === data.runtimeTable.key) applyRuntimeState(tableName, key, state);
    });
    applyRuntimeState(
        data.runtimeTable.name,
        data.runtimeTable.key,
        CustomNetTables.GetTableValue(data.runtimeTable.name, data.runtimeTable.key)
    );
    $.Msg("[TA_PORTRAIT_PROBE] LOAD ", JSON.stringify(data));
})();
