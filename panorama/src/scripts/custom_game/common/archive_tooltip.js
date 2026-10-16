(function () {
    "use strict";
    var cfg = GameUI.CustomUIConfig();
    // Each caller owns its panel, hover state and timers. The renderer never
    // calls ArchiveHandoff.Show or assumes that the archive window is open.
    function create(options) {
        options = options || {};
        var U = cfg.SurvivalUI, D = cfg.ArchiveV10Data, P = cfg.ArchiveParchmentData || {};
        var S = cfg.ArchiveV10Semantics, A = cfg.ArchiveHandoff;
        if (!U || !U.Lifecycle || !D || !S || !A) throw new Error("Archive tooltip dependencies must load before Create");
        var parent = options.parent, root = options.root || parent, prefix = options.idPrefix || "ArchiveSharedTooltip";
        var life = U.Lifecycle(), disposed = false, showEpoch = 0, hideEpoch = 0, anchor = null;
        var currentItem = null, currentCategory = "", elements = {}, pieces = {}, panel, dismiss;
        var surfaceWidth = 320, bodyWidth = 276, padding = 24, measuredHeight = 198, fitScale = 1;
        function valid(node) { return node && (!node.IsValid || node.IsValid()); }
        function alive() { return !disposed && valid(parent) && valid(root) && valid(panel) && (!options.isAlive || options.isAlive()); }
        function active() { return alive() && (!options.isActive || options.isActive()); }
        function style(node, values) {
            var cache = node.__archiveTooltipStyle || (node.__archiveTooltipStyle = {});
            Object.keys(values).forEach(function (key) { if (cache[key] !== values[key]) { node.style[key] = values[key]; cache[key] = values[key]; } });
        }
        function rect(node, x, y, width, height) {
            style(node, {position:Math.round(x)+"px "+Math.round(y)+"px 0px", width:width+"px", height:height+"px", margin:"0px", padding:"0px", horizontalAlign:"left", verticalAlign:"top"});
        }
        function make(type, owner, role, classes) {
            var node = $.CreatePanel(type, owner, role ? prefix+role : "");
            if (classes) node.AddClass(classes);
            node.hittest = false; node.hittestchildren = false;
            if (role) elements[role] = node;
            return node;
        }
        function text(owner, role) {
            var node = make("Label", owner, role, "ArchiveSharedTooltipText");
            style(node, {fontFamily:'"Source Han Sans SC"', fontWeight:"normal", textShadow:"none", letterSpacing:"0px"});
            return node;
        }
        function nineFrame(role, key, assetOverride) {
            var asset = assetOverride || P.assets && P.assets[key] || D.assets[key];
            var spec = D.tooltip.assets[key.replace(/^tooltip_/, "")] || {};
            var insets = asset.nine_slice_ltrb || spec.nine_slice_ltrb || [10,10,10,10];
            var host = make("Panel", panel, role, "ArchiveSharedTooltipNineFrame"), cells = [];
            host.__v10Slice = {asset:key, insets:insets.slice()};
            for (var r=0; r<3; r++) for (var c=0; c<3; c++) {
                var clip = make("Panel", host, "", "ArchiveSharedTooltipCrop");
                var art = make("Panel", clip, "", "ArchiveSharedTooltipArt");
                style(clip, {flowChildren:"none", overflow:"clip"});
                style(art, {backgroundImage:'url("'+asset.file+'")', backgroundSize:"100% 100%", backgroundPosition:"0px 0px", backgroundRepeat:"no-repeat", flowChildren:"none"});
                cells.push({clip:clip, art:art, col:c, row:r});
            }
            pieces[role] = cells;
            host.Resize = function (x, y, width, height) {
                var left=insets[0], top=insets[1], right=insets[2], bottom=insets[3];
                width=Math.max(width,left+right); height=Math.max(height,top+bottom); rect(host,x,y,width,height);
                var xs=[0,left,asset.size[0]-right,asset.size[0]], ys=[0,top,asset.size[1]-bottom,asset.size[1]];
                var dx=[0,left,width-right,width], dy=[0,top,height-bottom,height];
                cells.forEach(function (cell) {
                    var c=cell.col, r=cell.row, sw=xs[c+1]-xs[c], sh=ys[r+1]-ys[r], dw=dx[c+1]-dx[c], dh=dy[r+1]-dy[r], sx=dw/sw, sy=dh/sh;
                    rect(cell.clip,dx[c],dy[r],dw,dh); rect(cell.art,-xs[c]*sx,-ys[r]*sy,asset.size[0]*sx,asset.size[1]*sy);
                });
            };
            return host;
        }
        panel = $.CreatePanel("Panel", parent, prefix);
        panel.AddClass("ArchiveSharedTooltipHost"); panel.hittest=false; panel.hittestchildren=true; panel.visible=false;
        rect(panel,0,0,368,246);
        var shadow=make("Panel",panel,"Shadow","ArchiveSharedTooltipShadow"); rect(shadow,24,24,320,198);
        var backing=nineFrame("Backing","tooltip_reference_clean",{file:"file://{images}/custom_game/gw2_tooltip_v1/background.png",size:[354,103],nine_slice_ltrb:[3,3,3,3]}); backing.AddClass("ArchiveSharedTooltipBacking"); backing.Resize(24,24,320,198);
        var frame=nineFrame("Frame","tooltip_frame"); frame.AddClass("ArchiveSharedTooltipFrame"); frame.Resize(24,24,320,198);
        var surface=make("Panel",panel,"Surface","ArchiveSharedTooltipSurface"); rect(surface,24,24,320,198);
        surface.hittest=true; surface.hittestchildren=true; style(surface,{flowChildren:"none",overflow:"clip"});
        var viewport=make("Panel",surface,"Viewport","ArchiveSharedTooltipViewport"); rect(viewport,22,19,bodyWidth+16,157);
        viewport.hittest=true; viewport.hittestchildren=true; style(viewport,{flowChildren:"none",overflow:"squish scroll"});
        var body=make("Panel",viewport,"Body","ArchiveSharedTooltipBody"); rect(body,0,0,276,160);
        body.hittestchildren=true; style(body,{height:"fit-children",flowChildren:"down",overflow:"noclip"});
        ["Title","State","EffectCaption","Effect","Condition"].forEach(function (role) { text(body,role); });
        var metric=make("Panel",body,"Metric","ArchiveSharedTooltipMetric"); rect(metric,0,0,276,27); style(metric,{flowChildren:"none",marginBottom:"4px"});
        var caption=text(metric,"MetricCaption"), quantity=text(metric,"Quantity"), colors=D.tooltip.text_colors;
        rect(caption,0,0,162,27); style(caption,{fontSize:"17px",color:colors.caption,textAlign:"left"});
        rect(quantity,162,0,114,27); style(quantity,{position:"0px 0px 0px",width:"fit-children",maxWidth:"114px",horizontalAlign:"right",fontSize:"17px",color:colors.quantity,textAlign:"right"});
        var separator=make("Image",body,"Separator","ArchiveSharedTooltipSeparator");
        separator.SetImage(D.assets.tooltip_separator.file); separator.SetScaling("stretch-to-fit"); rect(separator,0,0,276,4); style(separator,{marginBottom:"8px"});
        body.MoveChildBefore(separator,elements.EffectCaption);

        function hide() {
            showEpoch++; hideEpoch++; life.Cancel();
            if (valid(anchor)) anchor.RemoveClass("ArchiveHovered");
            anchor=null;
            if (valid(panel)) panel.visible=false;
            if (dismiss) dismiss.Hidden();
            if (options.onHide) options.onHide();
        }
        function queueHide() {
            if (!active() || !panel.visible) return;
            var epoch=++hideEpoch;
            life.Later(.15,function () { if (active() && epoch===hideEpoch) hide(); });
        }
        function tooltipRect(node) { var at=node.GetPositionWithinWindow(); return {x:at.x,y:at.y,width:node.actuallayoutwidth*fitScale,height:node.actuallayoutheight*fitScale}; }
        dismiss=cfg.SurvivalTooltipDismiss.Create({panel:panel,surface:surface,getRect:tooltipRect,hide:hide,isAlive:alive,isVisible:function () { return active() && panel.visible; }});
        surface.SetPanelEvent("onmouseout",queueHide);
        function getBounds() {
            var value=options.getBounds ? options.getBounds() : {width:1200,height:900};
            return Array.isArray(value) ? {width:Number(value[0]),height:Number(value[1])} : {width:Number(value.width),height:Number(value.height)};
        }
        function position(epoch) {
            if (epoch!==showEpoch || !active() || !valid(anchor) || !panel.visible) return;
            var scale=Number(options.getScale ? options.getScale() : 1) || 1; fitScale=scale;
            var cp=parent.GetPositionWithinWindow(), at=anchor.GetPositionWithinWindow();
            var sx=(parent.actualuiscale_x||1)*scale, sy=(parent.actualuiscale_y||1)*scale, bounds=getBounds();
            var contentHeight=0;
            body.Children().forEach(function (child) {
                if (child.visible===false) return;
                var margin=String(child.style.margin||"").split(/\s+/), bottom=child.style.marginBottom||margin[2]||margin[0];
                contentHeight+=(child.actuallayoutheight||0)/(root.actualuiscale_y||1)+(parseFloat(bottom)||0)+(parseFloat(child.style.marginTop)||0);
            });
            var maximum=Number(typeof options.maxHeight==="function" ? options.maxHeight(bounds) : options.maxHeight) || 778;
            var maximumSurface=Math.max(1,maximum-padding*2);
            measuredHeight=Math.max(Math.min(198,maximumSurface),Math.min(maximumSurface,Math.ceil(contentHeight)+41));
            var info={anchor:{x:(at.x-cp.x)/sx,y:(at.y-cp.y)/sy,width:(anchor.actuallayoutwidth||0)/sx,height:(anchor.actuallayoutheight||0)/sy,panel:anchor},bounds:bounds,width:368,height:measuredHeight+48,surfaceWidth:surfaceWidth,surfaceHeight:measuredHeight,padding:padding};
            var origin;
            if (options.position) origin=options.position(info);
            else {
                // Preserve the archive's existing row-relative placement.
                var tx=info.anchor.x+Math.min(anchor.actuallayoutwidth||745,745)-340;
                tx=Math.max(40,Math.min(bounds.width-360,tx));
                var ty=Math.max(80,Math.min(bounds.height-35-measuredHeight,info.anchor.y+72));
                origin={x:tx-24,y:ty-24};
            }
            rect(panel,origin.x,origin.y,368,measuredHeight+48);
            backing.Resize(24,24,320,measuredHeight); frame.Resize(24,24,320,measuredHeight);
            rect(surface,24,24,320,measuredHeight); rect(shadow,24,24,320,measuredHeight);
            style(viewport,{height:Math.max(1,measuredHeight-41)+"px"});
        }
        function trackAnchor(epoch, origin) {
            if (!options.watchAnchor) return;
            life.Later(.08,function () {
                if (epoch!==showEpoch || !active() || !valid(anchor) || !panel.visible) return;
                var at=anchor.GetPositionWithinWindow();
                if (Math.abs(at.x-origin.x)>.5 || Math.abs(at.y-origin.y)>.5) { hide(); return; }
                trackAnchor(epoch,origin);
            });
        }
        function show(item, category, card, onlyEffect) {
            if (!active() || !valid(card) || !dismiss.CanShow(card)) return false;
            hide(); anchor=card; currentItem=item; currentCategory=category; card.AddClass("ArchiveHovered");
            var state=S.State(item,category), name=options.categoryName ? options.categoryName(category) : category;
            elements.Title.text=String(item.name||"");
            elements.State.text=onlyEffect ? "" : name+" · "+(state===null ? "状态待同步" : state ? (["shadow","pet","fishing","friend","ex","beast","points","shop"].indexOf(category)>=0 ? "已拥有" : "已解锁") : "未解锁");
            elements.EffectCaption.text="道具效果";
            var description=String(item.description||"服务端未提供效果说明"), effect=elements.Effect;
            effect.html=!!A.FormatEffects;
            effect.text=A.FormatEffects ? A.FormatEffects(description,category==="fragment" ? (item.level===undefined ? 0 : item.level) : undefined,item.id ? state : undefined) : description;
            var details=item.unlock_condition||item.condition_text||"";
            if (category==="work" || category==="building") details+=(details?"\n":"")+(Number(item.completed)===1 ? "已达到最高等级" : "点击"+(category==="building"?"升级":"激活")+" · 消耗 "+item.cost+(category==="building"?" 信仰值":" 软妹币"));
            if (category==="titles") details+=(details?"\n":"")+(Number(item.equipped)===1 ? "当前已穿戴 · 点击恢复最高档自动选择" : state ? "点击穿戴称号" : "达成条件后解锁称号");
            if (category==="fragment" && item.level!==undefined) details+=(details?"\n":"")+"神兵等级 LV"+item.level;
            var source=options.currencySourceText && options.currencySourceText(category,item);
            if (["building","work","starjoy_points"].indexOf(category)>=0 && source) details+=(details?"\n":"")+source;
            if (category==="map_level" && item.count!==undefined) details+=(details?"\n":"")+"累计有效在线 "+item.count+" 分钟";
            elements.Condition.text=details; elements.Condition.visible=!!details;
            metric.visible=!onlyEffect; caption.text=S.Metric(item,category); quantity.text=S.Quantity(item,category);
            ["Title","State","EffectCaption","Effect","Condition"].forEach(function (role) {
                style(elements[role],{width:bodyWidth+"px",height:"fit-children",ignoreParentFlow:"false",fontSize:(role==="Title"?22:role==="State"||role==="EffectCaption"?15:17)+"px",color:role==="Title"?colors.title:role==="Effect"?colors.body:role==="State"?colors.state:colors.caption,margin:"0px 0px "+(role==="Title"?6:role==="State"?8:role==="Effect"?8:4)+"px",whiteSpace:"normal",textOverflow:"clip"});
            });
            body.style.height="fit-children"; panel.visible=true;
            var epoch=showEpoch; position(epoch); dismiss.Shown(card);
            [0,.05,.1,.2,.4,.8].forEach(function (delay) { life.Later(delay,function () { position(epoch); }); });
            if (options.watchAnchor) trackAnchor(epoch,card.GetPositionWithinWindow());
            return true;
        }
        return {
            Show:show, Hide:hide, QueueHide:queueHide, IsVisible:function () { return alive() && panel.visible; }, panel:panel, elements:elements,
            Inspect:function () { return {visible:alive()&&panel.visible,category:currentCategory,itemId:currentItem&&currentItem.id,anchorId:anchor&&anchor.id,prefix:prefix,surfaceHeight:measuredHeight,nineSlices:{Backing:{count:pieces.Backing.length,asset:backing.__v10Slice.asset,insets:backing.__v10Slice.insets.slice()},Frame:{count:pieces.Frame.length,asset:frame.__v10Slice.asset,insets:frame.__v10Slice.insets.slice()}}}; },
            Dispose:function () { if (disposed) return; hide(); dismiss.Dispose(); disposed=true; life.Dispose(); if (valid(panel)) panel.DeleteAsync(0); }
        };
    }
    cfg.SurvivalArchiveTooltip = {Create:create};
})();
