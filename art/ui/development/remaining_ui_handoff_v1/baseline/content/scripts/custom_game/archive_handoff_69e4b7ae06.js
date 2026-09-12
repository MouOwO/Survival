(function () {
    'use strict';
    var cfg=GameUI.CustomUIConfig(),assets=cfg.ArchiveHandoffAssets,root=$.GetContextPanel(),generation=0,anchor=null;
    function p(id){return root.FindChildTraverse(id);}
    function style(el,s){Object.keys(s).forEach(function(k){el.style[k]=s[k];});}
    function img(parent,name,cls){var el=$.CreatePanel('Image',parent,'');el.AddClass(cls);el.SetImage(assets[name]);el.hittest=false;return el;}
    function label(parent,text,cls){var el=$.CreatePanel('Label',parent,'');el.AddClass(cls);el.text=String(text);el.hittest=false;return el;}
    function unlocked(item,category){
        if(item.unlocked!==undefined)return Number(item.unlocked)===1;
        if(item.completed!==undefined && ['clear','endless','pet','boss','map_level','work','building'].indexOf(category)>=0)return Number(item.completed)===1;
        if(category==='fishing'&&Number(item.count_known)!==1)return null;
        return item.count!==undefined?Number(item.count)>0:null;
    }
    function progress(item){
        var count=item.count, target=item.target;
        if(item.count_known!==undefined&&Number(item.count_known)!==1)count=undefined;
        return (count!==undefined&&isFinite(Number(count))?String(count):'—')+' / '+(target!==undefined&&Number(target)>0?String(target):'—');
    }
    function condition(item,category){
        if(item.unlock_condition||item.condition_text)return item.unlock_condition||item.condition_text;
        if(category==='clear'&&Number(item.target)>0)return '累计通关 '+(item.rune||'对应难度')+' '+item.target+' 次';
        if(category==='endless'&&Number(item.target)>0)return '无尽累计积分达到 '+item.target+' 分';
        return '以当前存档配置为准（服务端未提供独立条件说明）';
    }
    // Pixel-space positioning, converted to root UI units only at the final assignment.
    function place(rect,tip,w,h,gap,pad){
        var x=rect.x+rect.w+gap,side='right';
        if(x+tip.w>w-pad){x=rect.x-gap-tip.w;side='left';}
        return {x:Math.max(pad,Math.min(x,w-tip.w-pad)),y:Math.max(pad,Math.min(rect.y+16,h-tip.h-pad)),side:side};
    }
    function hide(){generation++;if(anchor&&anchor.IsValid())anchor.RemoveClass('ArchiveHovered');anchor=null;p('ArchiveTooltip').AddClass('ArchiveHidden');}
    function position(g){
        if(g!==generation||!anchor||!anchor.IsValid())return;
        var tip=p('ArchiveTooltip'),sx=root.actualuiscale_x||1,sy=root.actualuiscale_y||1;
        var w=root.actuallayoutwidth||1920,h=root.actuallayoutheight||1080;
        // The modal uses U.Fit. Apply its SAME scale to the detached tooltip.
        var fit=Math.min(w/sx/1672,h/sy/941);
        tip.style.transform='scale3d('+fit+','+fit+',1)';
        tip.style.maxHeight=Math.floor((h/sy-24)/fit)+'px';
        p('ArchiveTooltipBody').style.maxHeight=tip.style.maxHeight;
        var pos=anchor.GetPositionWithinWindow(),r={x:pos.x,y:pos.y,w:anchor.actuallayoutwidth,h:anchor.actuallayoutheight};
        // actual layout dimensions exclude CSS transforms; the archive's own UI scale includes its ancestor transform.
        r.w=143*sx*fit;r.h=138*sy*fit;
        var t={w:300*sx*fit,h:(tip.actuallayoutheight||274*sy)*fit};
        var windowPos=p('ArchiveWindow').GetPositionWithinWindow();
        // Prefer staying inside the modal, as in the approved rightmost-card example.
        var at=place(r,t,Math.min(w,windowPos.x+869*sx*fit),h,12*sx*fit,12*sx);
        nine(p('ArchiveTooltipFrame'),300,(tip.actuallayoutheight||274*sy)/sy);
        tip.style.position=Math.round(at.x/sx)+'px '+Math.round(at.y/sy)+'px 0px';
        tip.SetAttributeString('expand_side',at.side);
        tip.style.zIndex=String((Number(p('ArchiveWindow').style.zIndex)||100000)+2);
        $.Schedule(.05,function(){position(g);});
    }
    function show(item,category,card){
        hide();anchor=card;
        // Auxiliary promotion help uses its actual button when no card argument is provided.
        if(!anchor)return;
        anchor.AddClass('ArchiveHovered');
        var state=unlocked(item,category);
        p('ArchiveTooltipName').text=item.name||'';
        p('ArchiveTooltipStateText').text=state===null?'状态待同步':state?'已解锁':'未解锁';
        p('ArchiveTooltipStateIcon').SetImage(assets[state?'icon_check_light.png':'icon_lock_light.png']);
        p('ArchiveTooltipEffect').text=item.description||'服务端未提供效果说明';
        p('ArchiveTooltipCondition').text=condition(item,category);
        p('ArchiveTooltipProgress').text=progress(item);
        p('ArchiveTooltip').RemoveClass('ArchiveHidden');position(generation);
    }
    function icon(parent,item,category,buildings){
        var art=$.CreatePanel('Panel',parent,'');art.AddClass('ArchiveArt');art.hittest=false;
        if(category==='building'&&buildings[item.id])cfg.SurvivalRewardPresentation.CreateIcon(art,{icon_type:'item',icon:buildings[item.id]},'ArchiveRewardIcon');
        else if(item.icon&&['image','item','ability'].indexOf(item.icon_type)>=0)cfg.SurvivalRewardPresentation.CreateIcon(art,item,'ArchiveRewardIcon');
        else {
            // Preserve the pre-existing semantic icon_style mapping, using this handoff's mapped originals.
            var artId={scroll:'02',seal:'01',crystal:'04',sword:'05',flower:'06',hourglass:'10',shard:'03'}[item.icon_style];
            if(artId)img(art,'art_'+artId+'.png','ArchiveRewardIcon');
            else {art.AddClass('ArchiveMissingArt');label(art,'未配置图标','ArchiveMissingArtText');}
        }
        label(parent,progress(item),'ArchiveCount');
    }
    function nine(parent,w,h){
        // Unmodified shared texture, nine clipped images; fixed 12px source corners.
        var size=assets.tooltipSize,e=12;
        if(!parent.parts){parent.parts=[];for(var i=0;i<9;i++){
            var cell=$.CreatePanel('Panel',parent,'');cell.AddClass('ArchiveTipSlice');cell.hittest=false;
            var image=img(cell,'tooltip_panel.png','ArchiveTipImage');parent.parts.push({cell:cell,image:image});
        }}
        var sw=[e,size[0]-2*e,e],sh=[e,size[1]-2*e,e],dw=[e,w-2*e,e],dh=[e,h-2*e,e];
        var ox=[0,e,size[0]-e],oy=[0,e,size[1]-e],dx=[0,e,w-e],dy=[0,e,h-e];
        parent.parts.forEach(function(part,i){var x=i%3,y=Math.floor(i/3),sx=dw[x]/sw[x],sy=dh[y]/sh[y];
            style(part.cell,{position:dx[x]+'px '+dy[y]+'px 0px',width:dw[x]+'px',height:dh[y]+'px'});
            style(part.image,{position:(-ox[x]*sx)+'px '+(-oy[y]*sy)+'px 0px',width:(size[0]*sx)+'px',height:(size[1]*sy)+'px'});
        });
    }
    cfg.ArchiveHandoff={
        Observe:function(data){this.snapshot=data;},
        Unlocked:unlocked,Progress:progress,Condition:condition,Place:place,Hide:hide,Show:show,Icon:icon,
        NavIcon:function(toggle,id,key){var name='archive_ui_kit_v1_'+(id==='clear'?'clear_selected':(key||'clear')+'_normal')+'.png';if(!assets[name])name='archive_ui_kit_v1_clear_selected.png';img(toggle,name,'ArchiveNavIcon');},
        Card:function(card){card.AddClass('ArchiveHandoffCard');
            card.Children().forEach(function(c){if(!c.BHasClass('ArchiveItemName'))return;
                var host=$.CreatePanel('Panel',card,'');host.AddClass('ArchiveNameHost');host.hittest=false;c.SetParent(host);
            });
        },
        Init:function(){
            p('ArchiveWindow').RemoveClass('UIModal');
            style(p('ArchiveWindow'),{backgroundImage:'none',backgroundColor:'transparent',border:'0px',boxShadow:'none'});
            style(p('ArchiveHeader'),{backgroundImage:'url("'+assets['header_background.png']+'")',backgroundColor:'transparent'});
            p('ArchiveSidebarBacking').SetImage(assets['sidebar_background.png']);p('ArchiveContentBacking').SetImage(assets['content_background.png']);
            p('ArchiveTooltipDivider').SetImage(assets['tooltip_divider.png']);
            p('ArchiveClose').RemoveAndDeleteChildren();img(p('ArchiveClose'),'window_foundation_v1_close_normal.png','ArchiveCloseImage');
            // Keep the shared modal lifecycle/escape/scrim policy; change only its artwork.
            p('ArchiveTooltip').RemoveClass('UITooltip');
            $.Msg('ARCHIVE_HANDOFF_READY v1');
        }
    };
    // Read-only diagnostics available solely in this isolated candidate, not a release script.
    var diagnosticGeneration=(cfg.ArchiveHandoffDiagnosticGeneration||0)+1;cfg.ArchiveHandoffDiagnosticGeneration=diagnosticGeneration;
    Game.AddCommand('archive_view_action_'+diagnosticGeneration,function(){var args=Array.prototype.slice.call(arguments);$.Msg('ARCHIVE_ACTION_ARGS '+JSON.stringify(args));if(String(args[0]).indexOf('archive_view_action_')===0)args.shift();
        if(args[0]==='open')cfg.SurvivalArchive.Toggle();
        if(args[0]==='filter')cfg.SurvivalArchive.Filter(args[1]);
        if(args[0]==='hover'){
            var cards=p('ArchiveGrid').Children().filter(function(c){return c.BHasClass('ArchiveCard');});
            var d=cfg.ArchiveHandoff.snapshot,i=Number(args[1]);if(d&&cards[i]&&d.rows[i])show(d.rows[i],d.category_id,cards[i]);
        }
        if(args[0]==='category'){var tab=p('ArchiveTab_'+args[1]);if(tab)$.DispatchEvent('Activated',tab,'mouse');}
        if(args[0]==='hide')hide();
    },'',0);
    Game.AddCommand('archive_view_open_'+diagnosticGeneration,function(){cfg.SurvivalArchive.Toggle();$.Msg('ARCHIVE_OPENED');},'',0);
    Game.AddCommand('archive_view_dump_'+diagnosticGeneration,function(){
        var d=cfg.ArchiveHandoff.snapshot||{},t=p('ArchiveTooltip');
        $.Msg('ARCHIVE_VIEW '+JSON.stringify({category:d.category_id,rows:d.rows,root:[root.actuallayoutwidth,root.actuallayoutheight,root.actualuiscale_x,root.actualuiscale_y],window:[p('ArchiveWindow').GetPositionWithinWindow(),p('ArchiveWindow').actuallayoutwidth,p('ArchiveWindow').actuallayoutheight],tip:[t.GetPositionWithinWindow(),t.actuallayoutwidth,t.actuallayoutheight,t.actualuiscale_x,t.actualuiscale_y,t.GetAttributeString('expand_side','')],grid:p('ArchiveGrid').Children().filter(function(c){return c.BHasClass('ArchiveCard');}).map(function(c){return {xy:c.GetPositionWithinWindow(),w:c.actuallayoutwidth,h:c.actuallayoutheight};})}));
    },'',0);
    $.Msg('ARCHIVE_DIAGNOSTIC archive_view_dump_'+diagnosticGeneration);
})();
