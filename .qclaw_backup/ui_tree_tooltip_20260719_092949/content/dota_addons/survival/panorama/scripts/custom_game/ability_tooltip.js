(function () {
    "use strict";

    var activeAbilityIndex = -1;
    var activeAbilityName = "";
    var activeSourcePanel = null;

    function byId(id) { return $("#" + id); }

    function asArray(value) {
        if (!value) return [];
        if (Array.isArray(value)) return value;
        return Object.keys(value).sort(function (a, b) {
            return Number(a) - Number(b);
        }).map(function (key) { return value[key]; });
    }

    function setText(id, value) {
        var target = byId(id);
        if (target) target.text = String(value === undefined ? "" : value);
    }

    function hideNativeTooltip() {
        try { $.DispatchEvent("DOTAHideAbilityTooltip"); } catch (error) {}
        try { $.DispatchEvent("DOTAHideTextTooltip"); } catch (error) {}
        try { $.DispatchEvent("DOTAHideTitleTextTooltip"); } catch (error) {}
    }

    function hideCustomTooltip() {
        activeAbilityIndex = -1;
        activeAbilityName = "";
        activeSourcePanel = null;
        var tooltip = byId("CustomAbilityTooltip");
        if (tooltip) tooltip.AddClass("Hidden");
        hideNativeTooltip();
    }

    function addField(container, label, value) {
        if (value === undefined || value === null || value === "") return;
        var row = $.CreatePanel("Panel", container, "");
        row.AddClass("AbilityFieldRow");
        var left = $.CreatePanel("Label", row, "");
        left.AddClass("AbilityFieldLabel");
        left.text = label;
        var right = $.CreatePanel("Label", row, "");
        right.AddClass("AbilityFieldValue");
        right.text = String(value);
    }

    function render(abilityIndex, abilityName, sourcePanel) {
        var definition = CustomNetTables.GetTableValue(
            "survival_ability_data",
            abilityName
        );
        if (!definition) return false;

        var runtime = CustomNetTables.GetTableValue(
            "survival_ability_runtime",
            String(abilityIndex)
        ) || {};
        if (runtime.removed === 1) runtime = {};

        var tooltip = byId("CustomAbilityTooltip");
        var fields = byId("CustomAbilityFields");
        var icon = byId("CustomAbilityIcon");
        if (!tooltip || !fields) return false;

        if (icon) icon.abilityname = definition.abilityicon || abilityName;
        setText("CustomAbilityTitle", definition.abilityname || abilityName);
        setText("CustomAbilityDescription", definition.abilitydesc || "");
        setText("AbilityWoodCost", runtime.cost_wood || 0);
        setText("AbilityGoldCost", runtime.cost_gold || 0);
        setText("CustomAbilityStatus", runtime.status_text || "");

        fields.RemoveAndDeleteChildren();
        asArray(definition.fields).forEach(function (field) {
            if (field) addField(fields, field.label, field.value);
        });
        addField(fields, "当前等级", runtime.current_level);
        addField(fields, "下一等级", runtime.next_level);
        addField(fields, "人口消耗", runtime.population);
        addField(fields, "转职", runtime.tower_class_name);
        addField(fields, "资源条件", runtime.can_afford === 0 ? "不足" : "满足");
        asArray(runtime.fields).forEach(function (field) {
            if (field) addField(fields, field.label, field.value);
        });

        tooltip.SetHasClass(
            "Unavailable",
            runtime.available === 0 || runtime.can_afford === 0
        );
        tooltip.RemoveClass("Hidden");
        hideNativeTooltip();

        $.Schedule(0.0, function () {
            if (activeAbilityIndex !== abilityIndex) return;
            var positioner = GameUI.CustomUIConfig().SurvivalTooltipPosition;
            if (positioner) positioner.PlaceRight(tooltip, sourcePanel, 430, 300);
        });
        return true;
    }

    function selectedUnit() {
        try {
            var unit = Players.GetLocalPlayerPortraitUnit();
            if (unit !== undefined && unit !== -1) return unit;
        } catch (error) {}
        return Players.GetPlayerHeroEntityIndex(Game.GetLocalPlayerID());
    }

    function abilityFromSlot(slot) {
        var unit = selectedUnit();
        if (unit === undefined || unit < 0) return -1;
        try { return Entities.GetAbility(unit, slot); } catch (error) { return -1; }
    }

    function showSlot(slot, sourcePanel) {
        var abilityIndex = abilityFromSlot(slot);
        if (abilityIndex === undefined || abilityIndex < 0) return;
        var abilityName = Abilities.GetAbilityName(abilityIndex);
        if (!abilityName) return;

        activeAbilityIndex = abilityIndex;
        activeAbilityName = abilityName;
        activeSourcePanel = sourcePanel;
        if (!render(abilityIndex, abilityName, sourcePanel)) {
            activeAbilityIndex = -1;
            activeAbilityName = "";
            activeSourcePanel = null;
            try {
                $.DispatchEvent("DOTAShowAbilityTooltip", sourcePanel, abilityName);
            } catch (error) {}
        }
    }

    function slotFromPanel(panel) {
        var id = panel && panel.id ? panel.id : "";
        var match = id.match(/^Ability([0-9]+)$/);
        return match ? Number(match[1]) : -1;
    }

    function inventorySlot(panel) {
        var id = panel && panel.id ? panel.id : "";
        var match = id.match(/(?:inventory_slot_|inventoryslot)([0-9]+)/i);
        return match ? Number(match[1]) : -1;
    }

    function showItemSlot(slot, panel) {
        var unit = selectedUnit();
        var item = unit >= 0 ? Entities.GetItemInSlot(unit, slot) : -1;
        if (item === undefined || item < 0) return;
        var name = Abilities.GetAbilityName(item);
        if (!name) return;
        hideNativeTooltip();
        var tooltip = GameUI.CustomUIConfig().SurvivalShopTooltip;
        if (tooltip) tooltip.Show({
            name: $.Localize("#DOTA_Tooltip_ability_" + name),
            description: $.Localize("#DOTA_Tooltip_ability_" + name + "_Description"),
            icon: name, icon_type: "item", fields: [],
            wood_cost: 0, gold_cost: 0, purchasable: 1,
            purchase_condition_text: "已装备", owned_count: 1, purchase_limit: 1
        }, panel);
    }

    function bindPanel(panel) {
        if (!panel || panel.BHasClass("SurvivalTooltipBound")) return;
        var slot = slotFromPanel(panel);
        var itemSlot = inventorySlot(panel);
        if (slot < 0 && itemSlot < 0) return;
        panel.AddClass("SurvivalTooltipBound");
        panel.SetPanelEvent("onmouseover", function () {
            if (itemSlot >= 0) showItemSlot(itemSlot, panel);
            else showSlot(slot, panel);
        });
        panel.SetPanelEvent("onmouseout", function () {
            hideCustomTooltip();
            var tooltip = GameUI.CustomUIConfig().SurvivalShopTooltip;
            if (tooltip) tooltip.Hide();
        });
    }

    function scan(panel) {
        if (!panel) return;
        bindPanel(panel);
        var count = panel.GetChildCount();
        for (var index = 0; index < count; index++) scan(panel.GetChild(index));
    }

    function hudRoot() {
        var panel = $.GetContextPanel();
        while (panel && panel.GetParent()) panel = panel.GetParent();
        return panel;
    }

    function refreshBindings() {
        var root = hudRoot();
        var abilityContainer = root && root.FindChildTraverse
            ? root.FindChildTraverse("abilities") : null;
        scan(abilityContainer || root);
        $.Schedule(0.75, refreshBindings);
    }

    function refreshVisible() {
        if (activeAbilityIndex >= 0 && activeAbilityName && activeSourcePanel) {
            render(activeAbilityIndex, activeAbilityName, activeSourcePanel);
        }
        $.Schedule(0.15, refreshVisible);
    }

    refreshBindings();
    refreshVisible();
})();
