exports.archive=function(s){
 if(s.includes('ShowEffectOnly:'))return s;
 s=s.replace('generation=0,anchor=null;','generation=0,anchor=null,effectOnly=false;');
 s=s.replace('function show(item,category,card){','function show(item,category,card,onlyEffect){');
 s=s.replace('hide();anchor=card;','hide();anchor=card;effectOnly=!!onlyEffect;');
 s=s.replace("p('ArchiveTooltipName').text=item.name||'';", "p('ArchiveTooltipState').visible=!effectOnly;\n        p('ArchiveTooltipProgressRow').visible=!effectOnly;\n        p('ArchiveTooltipName').text=item.name||'';");
 s=s.replace('r.w=143*sx*fit;r.h=138*sy*fit;', 'if(!effectOnly){r.w=143*sx*fit;r.h=138*sy*fit;}');
 s=s.replace('Math.min(w,windowPos.x+869*sx*fit)','effectOnly?w:Math.min(w,windowPos.x+869*sx*fit)');
 s=s.replace("String((Number(p('ArchiveWindow').style.zIndex)||100000)+2)","effectOnly?'100012':String((Number(p('ArchiveWindow').style.zIndex)||100000)+2)");
 s=s.replace('Show:show,Icon:icon,',"Show:show,ShowEffectOnly:function(item,card){show(item,'',card,true);},Icon:icon,");
 if(!s.includes('ShowEffectOnly:'))throw Error('Archive tooltip export missing');return s;
};
exports.lottery=function(s){
 if(s.includes('archiveEffectTooltipActive'))return s;
 s=s.replace('var activeTooltipItem = null;','var activeTooltipItem = null, archiveEffectTooltipActive = false;');
 s=s.replace('    function hideTooltip() {','    function hideTooltip() {\n        if(archiveEffectTooltipActive){var archiveTip=GameUI.CustomUIConfig().ArchiveHandoff;if(archiveTip)archiveTip.Hide();archiveEffectTooltipActive=false;}');
 s=s.replace('    function showTooltip(item, sourcePanel, simple) {',`    function showTooltip(item, sourcePanel, simple) {
        hideTooltip();
        if(simple){
            var archiveTip=GameUI.CustomUIConfig().ArchiveHandoff;
            if(archiveTip&&archiveTip.ShowEffectOnly&&item&&sourcePanel){
                archiveEffectTooltipActive=true;
                archiveTip.ShowEffectOnly({name:item.name||item.id||'未命名道具',description:item.description||'暂无效果说明'},sourcePanel);
            }
            return;
        }`);return s;
};
const patchArchiveBase=exports.archive;
exports.archive=function(s){
 s=patchArchiveBase(s);if(s.includes('raisedTooltipParents'))return s;
 s=s.replace('effectOnly=false;','effectOnly=false,raisedTooltipParents=[];');
 s=s.replace('function hide(){generation++;',`function hide(){generation++;
        raisedTooltipParents.forEach(function(e){if(e.panel.IsValid()&&String(e.panel.style.zIndex)==='100012')e.panel.style.zIndex=e.z;});raisedTooltipParents=[];`);
 s=s.replace("p('ArchiveTooltip').RemoveClass('ArchiveHidden');position(generation);",`if(effectOnly){
            var ancestors=[],source=card;
            while(source){ancestors.push(source);source=source.GetParent();}
            var parent=root;
            while(parent&&ancestors.indexOf(parent)<0){
                raisedTooltipParents.push({panel:parent,z:String(Number(parent.style.zIndex)||0)});
                parent.style.zIndex='100012';parent=parent.GetParent();
            }
        }
        p('ArchiveTooltip').RemoveClass('ArchiveHidden');position(generation);`);
 return s;
};

const patchArchiveWithLayers=exports.archive;exports.archive=function(s){return patchArchiveWithLayers(s).replace("p('ArchiveTooltipCondition').text=condition(item,category);","p('ArchiveTooltipCondition').text='';p('ArchiveTooltipCondition').visible=false;p('ArchiveTooltipCondition').style.visibility='collapse';");};
const patchArchiveWithoutLineBreaks=exports.archive;
exports.archive=function(s){
 s=patchArchiveWithoutLineBreaks(s);
 if(s.includes('function formatArchiveEffects('))return s;
 const formatter=require('fs').readFileSync(require('path').join(__dirname,'../art/ui/development/remaining_ui_handoff_v1/effect_lines.js'),'utf8').replace(/^\uFEFF/,'').split("if(typeof module")[0];
 s=s.replace('    function show(item,category,card,onlyEffect){',formatter+'\n    function show(item,category,card,onlyEffect){');
 s=s.replace("p('ArchiveTooltipEffect').text=item.description||'服务端未提供效果说明';","p('ArchiveTooltipEffect').text=formatArchiveEffects(item.description||'服务端未提供效果说明');");
 if(!s.includes('text=formatArchiveEffects('))throw Error('Effect formatter binding missing');return s;
};
