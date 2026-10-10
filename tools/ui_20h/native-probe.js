// Temporary Tools-only observer. native-probe.ps1 restores both files after capture.
(function () {
    if (!Game.IsInToolsMode || !Game.IsInToolsMode()) return;
    var c = GameUI.CustomUIConfig(), root = $.GetContextPanel();
    function find(id) { for(var p=root;p;p=p.GetParent()){var node=p.FindChildTraverse(id);if(node)return node;}return null; }
    Game.AddCommand("COMMAND", function () {
        var a = Array.prototype.slice.call(arguments);
        if (String(a[0]).indexOf("COMMAND") === 0) a.shift();
        if (a[0] === "select") GameUI.SelectUnit(Number(a[1]), false);
        if (a[0] === "archive") c.SurvivalArchive.Toggle();
        if (a[0] === "archiveopen" && !c.SurvivalArchive.IsOpen()) c.SurvivalArchive.Toggle();
        if (a[0] === "archivehover") {
            var grid=find("ArchiveGrid"), data=c.ArchiveHandoff.snapshot;
            var rows=data&&data.rows, index=Number(a[1])||0;
            if(rows&&!Array.isArray(rows))rows=Object.keys(rows).sort(function(x,y){return Number(x)-Number(y);}).map(function(key){return rows[key];});
            var cards=grid&&grid.Children().filter(function(node){return node.BHasClass("ArchiveCard");});
            if(rows&&cards&&cards[index]&&rows[index])c.ArchiveHandoff.Show(rows[index],data.category_id,cards[index]);
        }
        if (a[0] === "daily") c.SurvivalDaily.Open(false);
        if (a[0] === "lottery") c.SurvivalLottery.Open();
        if (a[0] === "info") c.SurvivalLottery.Feature(a[1] || "details");
        if (a[0] === "close") {
            c.SurvivalLottery.CloseInfo(); c.SurvivalLottery.Close(); c.SurvivalDaily.Close();
        }
        if (a[0] === "train") {
            var slot=Math.max(0,Math.min(3,Number(a[2])||0));
            var button = root.FindChildTraverse("ProductionTrainingSlot"+slot);
            if (button) for (var i = 0; i < Math.min(4, Number(a[1]) || 1); i++) $.DispatchEvent("Activated", button, "mouse");
        }
        if (a[0] === "layout") c.SurvivalQueueLayout = a[1];
        if(a[0]==='geometry'){
            var grid=find('ArchiveGrid'),card=grid&&grid.Children().filter(function(n){return n.BHasClass('ArchiveCard');})[0];
            function describe(n){return {id:n.id,text:typeof n.text==='string'?n.text:undefined,xy:n.GetPositionWithinWindow(),width:n.actuallayoutwidth,height:n.actuallayoutheight,font:n.style.fontSize,fontFamily:n.style.fontFamily,transform:n.style.transform,position:n.style.position,children:n.Children().map(describe)};}
            $.Msg('[UI20_LAYOUT] '+JSON.stringify({header:describe(find('ArchiveTitleBlock')),card:card&&describe(card)}));
        }
        var m = c.SurvivalMainHUD && c.SurvivalMainHUD.Inspect();
        if ((a[0] === "layout" || a[0] === "inspect") && m && c.SurvivalProductionHUD)
            c.SurvivalProductionHUD.Refresh(m.geometry, m.unit, m.nativeReady, []);
        var production = c.SurvivalProductionHUD && c.SurvivalProductionHUD.Inspect();
        var panel = root.FindChildTraverse("SurvivalProductionPanel");
        $.Msg("[UI20_PROBE] " + JSON.stringify({action:a, layout:c.SurvivalQueueLayout,
            selected:m && m.unit, nativeReady:m && m.nativeReady,
            panel:panel && {width:panel.style.width,height:panel.style.height,visible:panel.visible},
            slots:production && production.slots, training:production && production.snapshot.training && {
                queue_count:production.snapshot.training.queue_count,
                active_job:production.snapshot.training.active_job,
                queued:production.snapshot.training.queued
            }}));
    }, "Tools UI observation and original interface actions", 0);
    $.Msg("[UI20_COMMAND] COMMAND");
})();
