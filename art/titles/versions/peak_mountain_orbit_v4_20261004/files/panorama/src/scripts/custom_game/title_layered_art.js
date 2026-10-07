(function () {
    "use strict";
    var PATH="file://{images}/custom_game/titles/peak_clean_",SEGMENTS=32;
    function panel(parent,cls) {
        var p=$.CreatePanel("Panel",parent,"");p.AddClass(cls);p.hittest=false;p.hittestchildren=false;return p;
    }
    function image(parent,cls,file) {
        var p=$.CreatePanel("Image",parent,"");p.AddClass(cls);p.hittest=false;p.hittestchildren=false;
        if(p.SetScaling)p.SetScaling("stretch-to-fit-preserve-aspect");p.SetImage(PATH+file+".png");return p;
    }
    function create(parent,animated) {
        parent.hittest=false;parent.hittestchildren=false;
        var back=image(parent,"SurvivalTitleDragon","dragon");back.AddClass("SurvivalTitleDragonBack");
        var far=animated?panel(parent,"SurvivalTitleOrbitLayer"):null;
        var mountain=image(parent,"SurvivalTitleMountains","mountains");
        var front=image(parent,"SurvivalTitleDragon","dragon");front.AddClass("SurvivalTitleDragonFront");
        var art=image(parent,"SurvivalTitleBase","letters");
        var over=image(parent,"SurvivalTitleDragon","dragon");over.AddClass("SurvivalTitleDragonOver");
        var near=animated?panel(parent,"SurvivalTitleOrbitLayer"):null;
        var pieces=[],heads=[];
        if(animated){
            for(var i=0;i<SEGMENTS;i++)pieces.push([panel(far,"SurvivalTitleOrbitBody"),panel(near,"SurvivalTitleOrbitBody")]);
            heads=[image(far,"SurvivalTitleOrbitHead","head"),image(near,"SurvivalTitleOrbitHead","head")];
        }
        var mask=panel(parent,"SurvivalTitleShineMask"),sweep=panel(mask,"SurvivalTitleSweep");
        return {back:back,mountain:mountain,front:front,over:over,art:art,mask:mask,sweep:sweep,pieces:pieces,heads:heads};
    }
    function smooth(x){x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);}
    function timing(now){
        var cycle=((now%5)+5)%5;
        var q=smooth(Math.min(1,cycle/2.45)),settle=smooth((cycle-2.45)/.55);
        var staticWeight=smooth((settle-.35)/.65);
        return {cycle:cycle,q:q,settle:settle,staticWeight:staticWeight,procedural:1-staticWeight,
            alpha:cycle<.32?smooth(cycle/.32):cycle>4.55?1-smooth((cycle-4.55)/.45):1,
            phase:cycle<3?"ascending":"resting",duration:3,period:5};
    }
    // Head-to-tail curve at the final artwork position; the live body settles
    // into this silhouette before handing over to the unchanged resting art.
    var rest=[[192,24],[172,16],[149,17],[147,30],[168,43],[197,54],[201,69],[181,80],[160,80]];
    function restPoint(v){
        var s=Math.min(.999999,Math.max(0,v))*(rest.length-1),i=Math.floor(s),t=s-i;
        var a=rest[Math.max(0,i-1)],b=rest[i],c=rest[Math.min(rest.length-1,i+1)],d=rest[Math.min(rest.length-1,i+2)];
        function at(k){return .5*((2*b[k])+(-a[k]+c[k])*t+(2*a[k]-5*b[k]+4*c[k]-d[k])*t*t+(-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t);}
        return {x:at(0),y:at(1)};
    }
    function point(state,v){
        // Project a helix around the mountain's vertical axis. Every body
        // section has its OWN depth, so front and rear arcs coexist on screen.
        var theta=Math.PI/2+3.5*Math.PI*state.q-1.6*Math.PI*v;
        var radius=62-20*state.q+9*v,z=Math.sin(theta);
        var x=108+radius*Math.cos(theta),y=54-35*state.q+24*v+(9+3*v)*z;
        var target=restPoint(v),s=state.settle;
        return {x:x+(target.x-x)*s,y:y+(target.y-y)*s,depth:z*(1-s)+s,
            thickness:(7-5.6*v)*(1+.10*z)};
    }
    function pose(now){var p=timing(now);p.head=point(p,0);return p;}
    function drawLine(pair,a,b,opacity){
        var dx=b.x-a.x,dy=b.y-a.y,length=Math.sqrt(dx*dx+dy*dy)+2;
        var height=(a.thickness+b.thickness)/2,angle=Math.atan2(dy,dx)*180/Math.PI;
        var front=smooth(((a.depth+b.depth)/2+.10)/.20);
        for(var i=0;i<2;i++){
            var p=pair[i],weight=i?front:1-front;p.visible=opacity*weight>.002;
            if(!p.visible)continue;
            p.style.width=length.toFixed(2)+"px";p.style.height=height.toFixed(2)+"px";
            p.style.position=((a.x+b.x-length)/2).toFixed(2)+"px "+((a.y+b.y-height)/2).toFixed(2)+"px 0px";
            p.style.transform="rotateZ("+angle.toFixed(2)+"deg)";p.style.opacity=(opacity*weight).toFixed(4);
            p.style.brightness=i?"1":"0.76";
        }
    }
    function animate(fx,now){
        var state=pose(now);fx.pose=state;
        fx.back.style.opacity="0";fx.over.style.opacity="0";
        fx.front.style.opacity=(state.alpha*state.staticWeight).toFixed(4);
        var alpha=state.alpha*state.procedural;
        if(!fx.pieces.length)return;
        if(alpha<.002){
            fx.pieces.forEach(function(pair){pair[0].visible=false;pair[1].visible=false;});
            fx.heads[0].visible=false;fx.heads[1].visible=false;return;
        }
        var points=[];for(var j=0;j<=SEGMENTS;j++)points.push(point(state,j/SEGMENTS));
        for(var k=0;k<SEGMENTS;k++)drawLine(fx.pieces[k],points[k],points[k+1],alpha);
        var h=points[0],neck=points[1],dx=h.x-neck.x,dy=h.y-neck.y,len=Math.max(.001,Math.sqrt(dx*dx+dy*dy));
        var facing=dx/len,tilt=Math.atan2(dy,Math.abs(dx))*180/Math.PI;
        tilt=Math.max(-48,Math.min(48,tilt));
        var front=smooth((h.depth+.10)/.20);
        for(var n=0;n<2;n++){
            var head=fx.heads[n],weight=n?front:1-front;head.visible=alpha*weight>.002;
            if(!head.visible)continue;
            head.style.position=(h.x+dx/len*9-18).toFixed(2)+"px "+(h.y+dy/len*6-15).toFixed(2)+"px 0px";
            head.style.transform="rotateZ("+tilt.toFixed(2)+"deg) scale3d("+facing.toFixed(4)+", 1, 1)";
            head.style.opacity=(alpha*weight).toFixed(4);head.style.brightness=n?"1":"0.8";
        }
    }
    GameUI.CustomUIConfig().SurvivalTitleLayeredArt={Create:create,Animate:animate,Pose:pose,Point:function(now,v){return point(timing(now),v);},Segments:SEGMENTS};
})();
