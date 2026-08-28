(function () {
    "use strict";

    var customUIConfig = GameUI.CustomUIConfig();
    var stages = customUIConfig.Phase2APortraitData;
    var metricValues = {
        rendered: ["unknown", "yes", "no"],
        defaultWearable: ["unknown", "replaced", "overlap"],
        style0: ["unknown", "correct", "wrong"],
        animation: ["unknown", "running", "frozen"],
        consoleErrors: ["unknown", "none", "present"]
    };
    var metricPrefixes = {
        rendered: "MetricRendered_",
        defaultWearable: "MetricDefaultWearable_",
        style0: "MetricStyle0_",
        animation: "MetricAnimation_",
        consoleErrors: "MetricConsoleErrors_"
    };
    var currentIndex = 0;
    var stopped = false;
    var metrics = {};

    function byId(id) {
        return $("#" + id);
    }

    function currentStage() {
        return stages[currentIndex] || null;
    }

    function hasString(value, property) {
        return value && typeof value[property] === "string" && value[property].length > 0;
    }

    function hasSceneBinding(value) {
        return value
            && hasString(value, "map")
            && hasString(value, "camera")
            && hasString(value, "light")
            && hasString(value, "particleOnly");
    }

    function hasStageSchema(stage) {
        return stage
            && typeof stage === "object"
            && hasString(stage, "id")
            && hasString(stage, "label")
            && hasString(stage, "sceneMap")
            && hasString(stage, "snippet")
            && typeof stage.expectedItems === "string"
            && hasString(stage, "directUnit")
            && hasSceneBinding(stage.backgroundScene)
            && hasSceneBinding(stage.backgroundProp);
    }

    function hasValidStageData() {
        return Array.isArray(stages)
            && stages.length === 1
            && hasStageSchema(stages[0]);
    }

    function setStatus(text, className) {
        var status = byId("Phase2AStatus");
        if (!status) return;
        status.text = text;
        status.SetHasClass("StatusSuccess", className === "success");
        status.SetHasClass("StatusFailure", className === "failure");
    }

    function setButtonEnabled(id, enabled) {
        var button = byId(id);
        if (!button) return;
        button.enabled = enabled;
        button.SetHasClass("Disabled", !enabled);
    }

    function resetMetrics() {
        metrics = {
            rendered: "unknown",
            defaultWearable: "unknown",
            style0: "unknown",
            animation: "unknown",
            consoleErrors: "unknown"
        };
        Object.keys(metricValues).forEach(function (metric) {
            updateMetricClasses(metric);
        });
    }

    function updateMetricClasses(metric) {
        var values = metricValues[metric] || [];
        var prefix = metricPrefixes[metric] || "";
        values.forEach(function (value) {
            var choice = byId(prefix + value);
            if (choice) choice.SetHasClass("Selected", metrics[metric] === value);
        });
    }

    function resultPayload(result) {
        var stage = currentStage();
        return {
            result: result,
            stageIndex: currentIndex + 1,
            stageCount: stages.length,
            stageId: stage ? stage.id : "missing",
            stageLabel: stage ? stage.label : "missing",
            sceneMap: stage ? stage.sceneMap : "missing",
            expectedItems: stage ? stage.expectedItems : "missing",
            rendered: metrics.rendered,
            defaultWearable: metrics.defaultWearable,
            style0: metrics.style0,
            animation: metrics.animation,
            consoleErrors: metrics.consoleErrors
        };
    }

    function emitResult(result) {
        $.Msg("[PHASE2A_RESULT] ", JSON.stringify(resultPayload(result)));
    }

    function metricsComplete() {
        return Object.keys(metricValues).every(function (metric) {
            return metrics[metric] !== "unknown";
        });
    }

    function passCriteria() {
        return metricsComplete()
            && metrics.rendered === "yes"
            && metrics.style0 === "correct"
            && metrics.animation === "running"
            && metrics.consoleErrors === "none";
    }

    function loadCurrentStage() {
        var stage = currentStage();
        var host = byId("Phase2ASceneHost");
        if (!stage || !host) {
            stopped = true;
            setStatus("阶段数据或场景容器缺失；停止。", "failure");
            $.Msg("[PHASE2A_RESULT] LOAD_FAILED missing_stage_or_host index=", String(currentIndex));
            return;
        }

        host.RemoveAndDeleteChildren();
        if (typeof host.BLoadLayoutSnippet !== "function") {
            stopped = true;
            setStatus("Panorama snippet 加载失败；停止。", "failure");
            $.Msg("[PHASE2A_RESULT] LOAD_FAILED missing_BLoadLayoutSnippet snippet=", stage.snippet);
            return;
        }
        var loaded = host.BLoadLayoutSnippet(stage.snippet);
        if (loaded === false) {
            stopped = true;
            setStatus("Panorama snippet 加载失败；停止。", "failure");
            $.Msg("[PHASE2A_RESULT] LOAD_FAILED snippet=", stage.snippet);
            return;
        }

        resetMetrics();
        byId("Phase2AStageLabel").text = "Stage " + String(currentIndex + 1)
            + "/" + String(stages.length) + " · " + stage.label;
        byId("Phase2AStageItems").text = "Expected: " + stage.expectedItems;
        setButtonEnabled("Phase2APass", true);
        setButtonEnabled("Phase2AFail", true);
        setButtonEnabled("Phase2AReload", true);
        setStatus("A/B/C 已同屏加载：A 已知可见，B 已知纯黑；只判定 C，禁止进入 ItemDef 22217。", "");
        $.Msg("[PHASE2A] LOAD stage=", stage.id,
            " map=", stage.sceneMap, " expected=", stage.expectedItems);
    }

    function setMetric(metric, value) {
        if (stopped || !metricValues[metric]
            || metricValues[metric].indexOf(value) < 0) return;
        metrics[metric] = value;
        updateMetricClasses(metric);
    }

    function pass() {
        if (stopped || !currentStage()) return;
        if (!metricsComplete()) {
            setStatus("通过前必须填写全部五项观察记录。", "failure");
            return;
        }
        if (!passCriteria()) {
            setStatus("关键通过条件未满足；请点击“失败并停止”，不要继续后续阶段。", "failure");
            return;
        }
        emitResult("PASS");
        if (currentIndex >= stages.length - 1) {
            stopped = true;
            setButtonEnabled("Phase2APass", false);
            setButtonEnabled("Phase2AFail", false);
            setButtonEnabled("Phase2AReload", false);
            setStatus("Renderer Sanity Base 已判定结束；已停止，不加载 ItemDef 22217。", "success");
            $.Msg("[PHASE2A_RESULT] COMPLETE phase=2A next_phase_started=false");
            return;
        }
        currentIndex += 1;
        loadCurrentStage();
    }

    function fail() {
        if (stopped || !currentStage()) return;
        emitResult("FAIL");
        stopped = true;
        setButtonEnabled("Phase2APass", false);
        setButtonEnabled("Phase2AFail", false);
        setButtonEnabled("Phase2AReload", false);
        setStatus("本阶段失败；按 Phase 2A 规则已停止，后续阶段不会加载。", "failure");
    }

    function reload() {
        if (stopped && currentIndex < stages.length) {
            stopped = false;
        }
        loadCurrentStage();
    }

    GameUI.CustomUIConfig().Phase2APortraitSpike = {
        SetMetric: setMetric,
        Pass: pass,
        Fail: fail,
        Reload: reload
    };

    if (!hasValidStageData()) {
        stopped = true;
        setStatus("Renderer Sanity 运行数据必须只包含 Base；停止。", "failure");
        $.Msg("[PHASE2A_RESULT] DATA_INVALID schema=array_single_base_with_ABC_bindings");
        return;
    }
    loadCurrentStage();
})();