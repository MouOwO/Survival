// Same bounded fix for the formal controller and the handoff candidate.
module.exports=function patch(source){
 if(source.includes('HANDOFF_REFRESH_COALESCED'))return source;
 const replace=(from,to)=>{if(source.split(from).length!==2)throw Error('HUD refresh anchor changed: '+from.slice(0,80));source=source.replace(from,to);};
 replace('if(p.__handoffOverflow){style(p,{visibility:"visible"});p.__handoffOverflow=false;}\n            if(p.visible!==false&&String(p.style.visibility)!=="collapse")candidates.push(p);',
  '// Include our collapsed overflow slots without showing and hiding them every tick.\n            if(p.__handoffOverflow||(p.visible!==false&&String(p.style.visibility)!=="collapse"))candidates.push(p);');
 replace('}else{square(p);style(p,{marginRight:"4px"});}});',
  '}else{if(p.__handoffOverflow){style(p,{visibility:"visible"});p.__handoffOverflow=false;}square(p);style(p,{marginRight:"4px"});}});');
 const start=source.indexOf('    ["dota_player_update_selected_unit","dota_player_update_query_unit","dota_ability_changed"].forEach(');
 const end=source.indexOf('    GameEvents.Subscribe("survival_ui_private_snapshot",data);',start);
 if(start<0||end<0)throw Error('HUD event block missing');
 source=source.slice(0,start)+`    // HANDOFF_REFRESH_COALESCED: notifications are not geometry invalidations.
    // Native panel validity + unit/ability handles in layout() own invalidation.
    var refreshQueued=false, eventUnit=selectedUnit();
    function refreshFromEvent(){
        if(cfg.HandoffGeneration!==generation||!valid(ctx))return;
        var unit=selectedUnit();
        if(unit!==eventUnit){eventUnit=unit;if(cfg.HandoffCombat)cfg.HandoffCombat.RefreshSelection();}
        refreshNow();
    }
    ["dota_player_update_selected_unit","dota_player_update_query_unit","dota_ability_changed"].forEach(function(event){GameEvents.Subscribe(event,function(payload){
        if(cfg.HandoffGeneration!==generation)return;
        var pid=payload&&(payload.PlayerID!==undefined?payload.PlayerID:payload.player_id!==undefined?payload.player_id:payload.playerid);
        if(pid!==undefined&&Number(pid)!==Number(Game.GetLocalPlayerID()))return;
        // Update real selection immediately; native children may arrive next frame.
        if(selectedUnit()!==eventUnit)refreshFromEvent();
        if(refreshQueued)return;refreshQueued=true;
        $.Schedule(0,function(){refreshQueued=false;refreshFromEvent();});
    });});
`+source.slice(end);
 return source;
};
