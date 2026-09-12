(function(){
    'use strict';
    var cfg=GameUI.CustomUIConfig(),entries=/*ICON_ENTRIES*/,index={};
    entries.forEach(function(row){
        index[row.item_id]=row;
        if(row.content_id)index[row.content_id]=row;
    });
    function lookup(item){
        if(!item)return null;
        var keys=[item.id,item.item_id,item.content_id,item.entry_id,item.shop_entry_id];
        for(var i=0;i<keys.length;i++)if(keys[i]&&index[keys[i]])return index[keys[i]];
        return null;
    }
    function create(parent,item,className){
        var row=lookup(item);if(!row)return null;
        var icon=$.CreatePanel('Image',parent,'');
        icon.SetImage(row.runtime_uri||'file://{images}/'+row.icon_path);
        icon.SetScaling('stretch-to-fit-preserve-aspect');
        if(className)icon.AddClass(className);
        icon.hittest=false;icon.hittestchildren=false;
        return icon;
    }
    cfg.SurvivalItemArt={Lookup:lookup,Create:create};
    var presentation=cfg.SurvivalRewardPresentation;
    if(presentation){
        var colors={n:'#398754',r:'#3283c5',sr:'#a052c8',ssr:'#bd8b25',ur:'#66338f'};
        var originalColor=presentation.OriginalNameColor||presentation.NameColor;
        presentation.OriginalNameColor=originalColor;
        presentation.NameColor=function(q){return colors[String(q||'n').toLowerCase()]||originalColor(q);};
        // Reinstall safely after reload without accumulating nested wrappers.
        var original=presentation.OriginalCreateIcon||presentation.CreateIcon;
        presentation.OriginalCreateIcon=original;
        presentation.CreateIcon=function(parent,item,className){return create(parent,item,className)||original.call(presentation,parent,item,className);};
    }
})();
