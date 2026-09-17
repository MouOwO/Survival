(function(){
    'use strict';
    var cfg=GameUI.CustomUIConfig(),entries=/*ROGUE_ART_ENTRIES*/,base=/*ROGUE_CARD_BASE*/,cleanBase=/*ROGUE_CLEAN_BASE*/;
    function make(type,parent,cls){var p=$.CreatePanel(type,parent,'');p.AddClass(cls);p.hittest=false;p.hittestchildren=false;return p;}
    function rect(p,x,y,w,h){p.style.position=x+'px '+y+'px 0px';p.style.width=w+'px';p.style.height=h+'px';p.style.minWidth=w+'px';p.style.minHeight=h+'px';p.style.maxWidth='10000px';p.style.maxHeight='10000px';}
    // Display crops of the unchanged approved 352 x 816 card. Its outer frame,
    // header jewel and entire text footer retain their original proportions.
    function framePart(parent,x,y,w,h){
        var clip=make('Panel',parent,'RogueFrameCrop');rect(clip,x,y,w,h);clip.style.overflow='clip';
        var source=make('Panel',clip,'RogueFrameSource');rect(source,-x,-y,290,672);source.style.backgroundImage='url("'+base+'")';source.style.backgroundSize='100% 100%';source.style.backgroundPosition='0px 0px';source.style.backgroundRepeat='no-repeat';
    }
    cfg.SurvivalRogueArt={Apply:function(front,data){
        var entry=entries[String(data.card_id)];if(!entry)return false;
        front.style.backgroundImage='none';front.style.backgroundColor='transparent';
        var skin=make('Panel',front,'RogueArtSkin');rect(skin,0,0,290,672);
        // The clean upper compartment is sampled at the card's own scale.
        // Clip inside the original frame: generated outer pixels are never shown.
        var paper=make('Panel',skin,'RogueArtPaper');rect(paper,14,38,262,376);
        paper.style.overflow='clip';
        paper.style.backgroundColor='#eee6d3';
        // Use a real image at card scale instead of CSS background offsets.
        // The opaque interior remains behind the transparent character artwork.
        var paperImage=make('Image',paper,'RogueArtPaperImage');
        rect(paperImage,-14,-38,290,672);
        paperImage.SetImage(cleanBase);paperImage.SetScaling('stretch-to-fit');
        framePart(skin,0,0,290,38);framePart(skin,0,38,14,376);framePart(skin,276,38,14,376);framePart(skin,0,414,290,258);
        var art=make('Image',front,'RogueOptionIllustration');rect(art,29,56,232,348);
        art.SetImage(entry.uri);art.SetScaling('stretch-to-fit-preserve-aspect');
        return true;
    }};
})();
