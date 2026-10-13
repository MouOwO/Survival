(function () {
    "use strict";
    var cfg = GameUI.CustomUIConfig(), owner = $.GetContextPanel(), U = cfg.SurvivalUI;
    if (cfg.SurvivalCollectionNav && cfg.SurvivalCollectionNav.Dispose) cfg.SurvivalCollectionNav.Dispose();
    if (!U || !U.Lifecycle) return;
    var life = U.Lifecycle(), disposed = false, host, top, effects, button, icon, halo, captionHost, caption, underline;
    var generation = null, layoutSignature = "", stateSignature = "", retryTicks = 0;
    var marker = $.CreatePanel("Panel", owner, "");
    marker.visible = false; marker.hittest = false; marker.hittestchildren = false;
    function valid(panel) { return panel && (!panel.IsValid || panel.IsValid()); }
    function alive() { return !disposed && valid(owner) && valid(marker); }
    function style(panel, values) { Object.keys(values).forEach(function (key) { panel.style[key] = values[key]; }); }
    function create(type, parent, id, cls) {
        var panel = $.CreatePanel(type, parent, id);
        panel.hittest = false; panel.hittestchildren = false;
        if (cls) panel.AddClass(cls);
        return panel;
    }
    function activate() {
        if (!alive() || !valid(button) || button.enabled === false) return;
        var layers = cfg.SurvivalUILayers, view = cfg.SurvivalCollection;
        if (layers && layers.Top() === "collection") {
            if (view && typeof view.Close === "function") view.Close();
        } else if (cfg.SurvivalPurpleShell && cfg.SurvivalPurpleShell.Navigate) {
            // Navigate closes known menus and refuses purchase confirmations or
            // other modal layers. Never bypass that guard with a direct Open.
            cfg.SurvivalPurpleShell.Navigate("collection");
        }
        refresh();
    }
    function build() {
        if (valid(button)) button.DeleteAsync(0);
        button = create("Button", host, "HandoffNav_collection", "HandoffNav");
        button.AddClass("HandoffNavUnified"); button.AddClass("HandoffCanvas");
        button.hittest = true; button.hittestchildren = false;
        style(button, {flowChildren:"none", margin:"0px", padding:"0px", borderRadius:"0px", horizontalAlign:"left", verticalAlign:"top"});
        halo = create("Panel", button, "HandoffCollectionGlow", "HandoffNavGlow");
        icon = create("Image", button, "HandoffCollectionIcon");
        icon.SetImage("file://{images}/custom_game/collection_gw2_v1/collection_icon.png");
        captionHost = create("Panel", button, "HandoffCollectionCaptionHost");
        caption = create("Label", captionHost, "HandoffCollectionCaption", "HandoffNavCaption");
        caption.text = "收藏";
        style(caption, {position:"0px 0px 0px", width:"fit-children", maxWidth:"100%", height:"fit-children", minHeight:"0px", horizontalAlign:"center", verticalAlign:"center", margin:"0px", padding:"0px", fontFamily:'"Source Han Sans SC", "Noto Sans SC", "Microsoft YaHei", sans-serif', fontWeight:"bold", textAlign:"center", whiteSpace:"nowrap", textOverflow:"shrink"});
        underline = create("Panel", button, "HandoffCollectionUnderline", "HandoffNavUnderline");
        button.SetPanelEvent("onactivate", activate);
        layoutSignature = ""; stateSignature = "";
    }
    function acquire() {
        var nextGeneration = cfg.HandoffGeneration || 0;
        if (generation === nextGeneration && valid(host) && valid(top) && valid(effects)) return true;
        if (generation === nextGeneration && retryTicks > 0) { retryTicks--; return false; }
        generation = nextGeneration;
        // These local lookups happen only at boot or after HUD replacement.
        host = owner.FindChildTraverse("HandoffHUD");
        top = valid(host) && host.FindChildTraverse("HandoffTop");
        effects = valid(top) && top.FindChildTraverse("HandoffCombatEffects");
        if (!valid(host) || !valid(top) || !valid(effects)) {
            retryTicks = 3;
            if (valid(button)) button.visible = false;
            return false;
        }
        retryTicks = 0;
        if (!valid(button) || button.GetParent() !== host) build();
        layoutSignature = ""; stateSignature = "";
        return true;
    }
    function refresh() {
        if (!alive()) { api.Dispose(); return; }
        if (!acquire()) return;
        if (!valid(button)) build();
        var screenScale = Number(top.actualuiscale_x) || Number(owner.actualuiscale_x) || 1;
        var width = parseFloat(top.style.width) || (Number(top.actuallayoutwidth) || 630) / screenScale;
        var scale = width / 630, position = String(top.style.position || "8px 6px 0px").split(/\s+/);
        var x = parseFloat(position[0]), y = parseFloat(position[1]);
        if (!isFinite(x)) x = 8;
        if (!isFinite(y)) y = 6;
        function px(value) { return Math.round(value * screenScale) / screenScale; }
        function box(panel, left, up, w, h) { style(panel, {position:px(left)+"px "+px(up)+"px 0px", width:px(w)+"px", height:px(h)+"px"}); }
        var signature = [x,y,width,screenScale].join("|");
        if (signature !== layoutSignature) {
            layoutSignature = signature;
            box(button, x+626*scale, y+6*scale, 96*scale, 86*scale);
            box(halo, 17*scale, 0, 62*scale, 62*scale);
            box(icon, 26*scale, 4*scale, 44*scale, 44*scale);
            box(captionHost, 0, 52*scale, 96*scale, 32*scale);
            caption.style.fontSize = px(22*scale)+"px";
            box(underline, 31*scale, 84*scale, 34*scale, 2*scale);
        }
        var view = cfg.SurvivalCollection, nav = cfg.SurvivalPurpleShell, layers = cfg.SurvivalUILayers;
        var enabled = !!(view && typeof view.Open === "function" && nav && typeof nav.Navigate === "function");
        var selected = !!(layers && layers.Top() === "collection"), shown = top.visible !== false && effects.visible !== false;
        var state = [enabled,selected,shown].join("|");
        if (state !== stateSignature) {
            stateSignature = state; button.enabled = enabled; button.visible = shown;
            button.SetHasClass("HandoffNavActive", selected);
        }
    }
    function tick() { refresh(); if (alive()) life.Later(.25, tick); }
    var api = {
        IsAlive:alive, Refresh:refresh,
        Dispose:function () {
            if (disposed) return;
            disposed = true; life.Dispose();
            if (valid(button)) { button.visible = false; button.hittest = false; button.DeleteAsync(0); }
            if (valid(marker)) marker.DeleteAsync(0);
            if (cfg.SurvivalCollectionNav === api) cfg.SurvivalCollectionNav = null;
        }
    };
    cfg.SurvivalCollectionNav = api;
    tick();
})();
