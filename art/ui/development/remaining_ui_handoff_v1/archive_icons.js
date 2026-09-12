(function () {
    'use strict';
    var cfg=GameUI.CustomUIConfig(),view=cfg.ArchiveHandoff,entries=/*ICON_ENTRIES*/;
    var originalIcon=view.Icon,originalInit=view.Init,originalObserve=view.Observe,index={},trial,caption,trialCategory;
    var names={shadow:'虚空之影',points:'积分道具',fragment:'神兵碎片',pet:'秘法牢笼',friend:'我的好基友',ex:'我的前女友',beast:'瑞兽赐福',fishing:'钓鱼存档',building:'存档建筑',shop:'商店道具'};
    var categories=[],category='shadow',page=0,grid,heading,pageText,previousPage,nextPage;
    entries.forEach(function(row){index[row.category_id+':'+row.item_id]=row;});
    entries.forEach(function(row){if(categories.indexOf(row.category_id)<0)categories.push(row.category_id);});
    function label(parent,text,cls){var p=$.CreatePanel('Label',parent,'');p.AddClass(cls);p.text=text;p.hittest=false;return p;}
    function image(parent,row){
        var p=$.CreatePanel('Image',parent,'');p.AddClass('ArchiveRewardIcon');
        // 64px full-body textures lose the face at the native card size.
        p.SetImage(row.runtime_uri||'file://{images}/'+row.icon_path);p.SetScaling('stretch-to-fit-preserve-aspect');p.hittest=false;p.hittestchildren=false;
        if(row.portrait){var v=row.portrait,s=row.display_width/v[2];parent.AddClass('ArchivePortraitViewport');p.style.width=s+'px';p.style.height=s+'px';p.style.position=(-v[0]*s)+'px '+(-v[1]*s)+'px 0px';}
        if(row.tone_color){
            parent.AddClass('ArchiveToneArt');parent.style.backgroundColor=row.tone_color+'22';parent.style.border='1px solid '+row.tone_color;
            if(row.tint_icon)p.style.washColor=row.tone_color;
        }
        return p;
    }
    function action(parent,id,text,callback){var b=$.CreatePanel('Button',parent,id);b.AddClass('ArchiveArtTrialAction');label(b,text,'ArchiveArtTrialActionText');b.SetPanelEvent('onactivate',callback);return b;}
    function selectedRows(){return entries.filter(function(row){return row.category_id===category;});}
    function renderTrial(){
        var rows=selectedRows(),pages=Math.max(1,Math.ceil(rows.length/8));page=Math.max(0,Math.min(page,pages-1));
        heading.text='图标试览 · '+(names[category]||category)+' · '+rows.length+' 项';
        pageText.text=(page+1)+' / '+pages;grid.RemoveAndDeleteChildren();
        previousPage.enabled=page>0;nextPage.enabled=page<pages-1;
        previousPage.SetHasClass('Disabled',!previousPage.enabled);nextPage.SetHasClass('Disabled',!nextPage.enabled);
        rows.slice(page*8,page*8+8).forEach(function(row){
            var unit=$.CreatePanel('Panel',grid,'');unit.AddClass('ArchiveArtTrialUnit');
            var card=$.CreatePanel('Panel',unit,'');card.AddClass('ArchiveArtTrialCard');
            var art=$.CreatePanel('Panel',card,'');art.AddClass('ArchiveArt');
            art.style.width=row.display_width+'px';art.style.height=row.display_height+'px';image(art,row);
            label(card,row.display_name,'ArchiveArtTrialName');
            if(cfg.SurvivalUI&&cfg.SurvivalUI.Tooltip)cfg.SurvivalUI.Tooltip.Bind(card,{title:row.display_name,body:row.description||'属性以当前游戏配置为准'});
        });
    }
    function changeCategory(step){var i=categories.indexOf(category);category=categories[(i+step+categories.length)%categories.length];page=0;renderTrial();}
    function foregroundCorner(card){
        // Use the exact same UV grid as the card frame. A separately clipped
        // background duplicates the star at a different native sampling boundary.
        var corner=cfg.SurvivalNineSlice.Create(card,
            'file://{images}/custom_game/archive_handoff_v1/interaction_components_v2_card_selected.png',
            143,138,[29,33,12,12],'ArchiveHoverCorner');
        corner.Children().forEach(function(row,y){row.Children().forEach(function(tile,x){
            // Keep layout space: collapsing unused tiles would move the UV grid.
            if(x!==0||y!==0)tile.style.opacity='0';
        });});
    }
    view.Icon=function(parent,item,category,buildings){
        var row=index[category+':'+item.id];
        if(!row){var result=originalIcon.call(view,parent,item,category,buildings);foregroundCorner(parent);return result;}
        var art=$.CreatePanel('Panel',parent,'');art.AddClass('ArchiveArt');art.hittest=false;
        art.style.width=row.display_width+'px';art.style.height=row.display_height+'px';
        image(art,row);
        // Retain the real server count / target and the existing badge formatter.
        label(parent,view.Progress(item),'ArchiveCount');
        foregroundCorner(parent);
    };
    view.Observe=function(data){
        originalObserve.call(view,data);
        if(trial&&trial.visible&&data.category_id!==trialCategory){trial.visible=false;caption.text='图标试览';}
    };
    view.Init=function(){
        originalInit.call(view);
        var content=$.GetContextPanel().FindChildTraverse('ArchiveContent');
        var toggle=$.CreatePanel('Button',content,'ArchiveArtTrialToggle');
        caption=label(toggle,'图标试览','ArchiveArtTrialToggleText');
        trial=$.CreatePanel('Panel',content,'ArchiveArtTrial');trial.visible=false;
        heading=label(trial,'','ArchiveArtTrialHeading');
        label(trial,'美术试览不表示持有。悬停查看配置说明；每页 8 项。','ArchiveArtTrialHint');
        var nav=$.CreatePanel('Panel',trial,'ArchiveArtTrialNav');
        action(nav,'ArchiveArtPreviousCategory','上一分类',function(){changeCategory(-1);});
        action(nav,'ArchiveArtNextCategory','下一分类',function(){changeCategory(1);});
        grid=$.CreatePanel('Panel',trial,'ArchiveArtTrialGrid');
        var footer=$.CreatePanel('Panel',trial,'ArchiveArtTrialFooter');
        previousPage=action(footer,'ArchiveArtPreviousPage','上一页',function(){page--;renderTrial();});
        pageText=label(footer,'','ArchiveArtTrialPageText');
        nextPage=action(footer,'ArchiveArtNextPage','下一页',function(){page++;renderTrial();});
        toggle.SetPanelEvent('onactivate',function(){view.Hide();trialCategory=view.snapshot&&view.snapshot.category_id;trial.visible=!trial.visible;caption.text=trial.visible?'返回存档':'图标试览';if(trial.visible){category=categories.indexOf(trialCategory)>=0?trialCategory:categories[0];page=0;renderTrial();}else grid.RemoveAndDeleteChildren();});
    };
})();
