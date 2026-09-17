(function(){
    'use strict';
    // One original texture, nine clipped UV regions. Corners have fixed design
    // dimensions; edge lengths and center alone fill the available layout.
    // No layout polling, image regeneration, or separately scaled X/Y corners.
    function make(parent,uri,w,h,b,cls){
        if(!(w>b[0]+b[2]&&h>b[1]+b[3]))throw Error('Invalid nine-slice margins');
        var root=$.CreatePanel('Panel',parent,'');root.AddClass('UINineSlice');
        if(cls)cls.split(/\s+/).forEach(function(c){root.AddClass(c);});
        root.hittest=false;root.hittestchildren=false;
        var widths=[b[0],w-b[0]-b[2],b[2]],heights=[b[1],h-b[1]-b[3],b[3]];
        for(var y=0;y<3;y++){
            var row=$.CreatePanel('Panel',root,'');row.AddClass('UINineRow');
            row.hittest=false;row.hittestchildren=false;
            row.style.height=y===1?'fill-parent-flow(1)':heights[y]+'px';
            for(var x=0;x<3;x++){
                var tile=$.CreatePanel('Panel',row,'');tile.AddClass('UINineTile');
                tile.hittest=false;tile.hittestchildren=false;
                tile.style.width=x===1?'fill-parent-flow(1)':widths[x]+'px';
                tile.style.backgroundImage='url("'+uri+'")';
                tile.style.backgroundSize=(w/widths[x]*100)+'% '+(h/heights[y]*100)+'%';
                // The center UV is not 50% when opposite corner margins differ.
                tile.style.backgroundPosition=['left',(b[0]/(b[0]+b[2])*100)+'%','right'][x]+' '+['top',(b[1]/(b[1]+b[3])*100)+'%','bottom'][y];
            }
        }
        return root;
    }
    // PNG dimensions and cut margins are source pixels. Scale every fixed
    // region by the same height ratio; the host width stretches only the middle.
    function atHeight(parent,uri,sourceWidth,sourceHeight,b,height,cls){
        var scale=height/sourceHeight;
        return make(parent,uri,sourceWidth*scale,height,b.map(function(v){return v*scale;}),cls);
    }
    GameUI.CustomUIConfig().SurvivalNineSlice={Create:make,AtHeight:atHeight,version:'1.1.0'};
})();
