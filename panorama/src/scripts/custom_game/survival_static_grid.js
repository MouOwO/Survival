(function () {
    "use strict";

    // Pure plane geometry. The white grid has no dependency on validation,
    // units, terrain scans or server preview packets. Range clipping and edge
    // feathering happen in world space; camera zoom cannot fade the center.
    function geometry(layout, size) {
        var b=layout && layout.bounds;
        if (!b || !(size>0)) return null;
        var values=[b.min_x,b.min_y,b.max_x,b.max_y,layout.height].map(Number);
        if (!values.every(isFinite) || values[2]<=values[0] || values[3]<=values[1]) return null;
        var xs=[],ys=[],segments=[];
        var x0=Math.ceil(values[0]/size),x1=Math.floor(values[2]/size);
        var y0=Math.ceil(values[1]/size),y1=Math.floor(values[3]/size);
        if (x1-x0>512 || y1-y0>512) return null;
        for (var x=x0;x<=x1;x++) xs.push(x*size);
        for (var y=y0;y<=y1;y++) ys.push(y*size);
        if (xs.length<2 || ys.length<2) return null;
        for (var i=0;i<xs.length;i++) segments.push([xs[i],ys[0],xs[i],ys[ys.length-1]]);
        for (var j=0;j<ys.length;j++) segments.push([xs[0],ys[j],xs[xs.length-1],ys[j]]);
        var cx=(values[0]+values[2])/2,cy=(values[1]+values[3])/2;
        return {xs:xs,ys:ys,segments:segments,height:values[4],size:size,
            reference:[cx-512,cy-512,1024,1024]};
    }

    function invert(m) {
        var a=m[0],b=m[1],c=m[2],d=m[3],e=m[4],f=m[5],g=m[6],h=m[7],i=m[8];
        var det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g);
        if (Math.abs(det)<1e-12) return null;
        return [e*i-f*h,c*h-b*i,b*f-c*e,f*g-d*i,a*i-c*g,c*d-a*f,d*h-e*g,b*g-a*h,a*e-b*d]
            .map(function(v){return v/det;});
    }

    // Recover a plane homography from four engine projections. This retains
    // perspective, unlike an affine approximation that creates half-cell gaps.
    function projection(reference, points) {
        if (points.length!==4 || points.some(function(p){return !p || !p.every(isFinite);})) return null;
        var p=points,dx1=p[1][0]-p[2][0],dx2=p[3][0]-p[2][0];
        var dy1=p[1][1]-p[2][1],dy2=p[3][1]-p[2][1];
        var sx=p[0][0]-p[1][0]+p[2][0]-p[3][0],sy=p[0][1]-p[1][1]+p[2][1]-p[3][1];
        var det=dx1*dy2-dx2*dy1;
        if (Math.abs(det)<1e-9) return null;
        var g=(sx*dy2-dx2*sy)/det,h=(dx1*sy-sx*dy1)/det;
        var a=p[1][0]-p[0][0]+g*p[1][0],b=p[3][0]-p[0][0]+h*p[3][0];
        var d=p[1][1]-p[0][1]+g*p[1][1],e=p[3][1]-p[0][1]+h*p[3][1];
        var x=reference[0],y=reference[1],w=reference[2],v=reference[3];
        var m=[a/w,b/v,p[0][0]-a*x/w-b*y/v,d/w,e/v,p[0][1]-d*x/w-e*y/v,
            g/w,h/v,1-g*x/w-h*y/v];
        var inverse=invert(m);
        return inverse ? {matrix:m,inverse:inverse} : null;
    }

    function homogeneous(view,x,y) {
        var m=view.matrix;
        return [m[0]*x+m[1]*y+m[2],m[3]*x+m[4]*y+m[5],m[6]*x+m[7]*y+m[8]];
    }

    function point(view,x,y) {
        var p=homogeneous(view,x,y);
        return p[2]>1e-6 ? [p[0]/p[2],p[1]/p[2]] : null;
    }

    function unproject(view,x,y) {
        if(!view || !isFinite(x) || !isFinite(y)) return null;
        var n=view.inverse,w=n[6]*x+n[7]*y+n[8];
        if(Math.abs(w)<1e-9) return null;
        var world=[(n[0]*x+n[1]*y+n[2])/w,(n[3]*x+n[4]*y+n[5])/w];
        return world.every(isFinite) && point(view,world[0],world[1]) ? world : null;
    }

    // Clip BEFORE dividing by depth. A corner behind the camera must not hide
    // an otherwise visible terrain polygon or create a huge offscreen panel.
    function polygon(view,world,width,height) {
        var vertices=world.map(function(p){return homogeneous(view,p[0],p[1]);});
        var planes=[function(p){return p[2]-1e-6;},function(p){return p[0];},
            function(p){return width*p[2]-p[0];},function(p){return p[1];},
            function(p){return height*p[2]-p[1];}];
        for(var i=0;i<planes.length && vertices.length;i++) {
            var result=[],a=vertices[vertices.length-1],da=planes[i](a);
            for(var j=0;j<vertices.length;j++) {
                var b=vertices[j],db=planes[i](b);
                if((da>=0)!==(db>=0)) {
                    var t=da/(da-db);
                    result.push([a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t]);
                }
                if(db>=0) result.push(b);
                a=b;da=db;
            }
            vertices=result;
        }
        return vertices.map(function(p){return [Math.max(0,Math.min(width,p[0]/p[2])),
            Math.max(0,Math.min(height,p[1]/p[2]))];});
    }

    function circleSegment(line,range) {
        var ax=line[0]-range.x,ay=line[1]-range.y,dx=line[2]-line[0],dy=line[3]-line[1];
        var a=dx*dx+dy*dy,b=ax*dx+ay*dy,c=ax*ax+ay*ay-range.radius*range.radius;
        var discriminant=b*b-a*c;
        if(a<=0 || discriminant<=0) return null;
        var root=Math.sqrt(discriminant),lo=Math.max(0,(-b-root)/a),hi=Math.min(1,(-b+root)/a);
        return lo<hi ? [line[0]+dx*lo,line[1]+dy*lo,line[0]+dx*hi,line[1]+dy*hi] : null;
    }

    function rangeAlpha(range,x,y) {
        var distance=Math.sqrt((x-range.x)*(x-range.x)+(y-range.y)*(y-range.y))/range.radius;
        var t=Math.max(0,Math.min(1,(1-distance)/0.25));
        return t*t*(3-2*t);
    }

    function segment(view,line,width,height) {
        var a=homogeneous(view,line[0],line[1]),b=homogeneous(view,line[2],line[3]);
        if (a[2]<=1e-6 && b[2]<=1e-6) return null;
        if (a[2]<=1e-6 || b[2]<=1e-6) {
            var t=(1e-6-a[2])/(b[2]-a[2]);
            var cut=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,1e-6];
            if (a[2]<=1e-6) a=cut; else b=cut;
        }
        var ax=a[0]/a[2],ay=a[1]/a[2],dx=b[0]/b[2]-ax,dy=b[1]/b[2]-ay;
        var ps=[-dx,dx,-dy,dy],qs=[ax,width-ax,ay,height-ay],lo=0,hi=1;
        for (var i=0;i<4;i++) {
            if (Math.abs(ps[i])<1e-9) { if (qs[i]<0) return null; }
            else if (ps[i]<0) lo=Math.max(lo,qs[i]/ps[i]);
            else hi=Math.min(hi,qs[i]/ps[i]);
        }
        return lo<=hi ? [[ax+lo*dx,ay+lo*dy],[ax+hi*dx,ay+hi*dy]] : null;
    }

    // Transform the actual world circle conic, including off-center perspective
    // and camera rotation. A screen-space bounding-box ellipse is not sufficient.
    function ellipse(view,x,y,radius) {
        var n=view.inverse,q=[1,0,-x,0,1,-y,-x,-y,x*x+y*y-radius*radius],out=[];
        for (var i=0;i<3;i++) for (var j=0;j<3;j++) {
            var sum=0;
            for (var k=0;k<3;k++) for (var l=0;l<3;l++) sum+=n[k*3+i]*q[k*3+l]*n[l*3+j];
            out[i*3+j]=sum;
        }
        var a=out[0],b=out[1],c=out[4],d=out[2],e=out[5],f=out[8];
        if (a<0) {a=-a;b=-b;c=-c;d=-d;e=-e;f=-f;}
        var det=a*c-b*b;
        if (det<=1e-12) return null;
        var cx=(b*e-c*d)/det,cy=(b*d-a*e)/det;
        var scale=-(f+d*cx+e*cy),delta=Math.sqrt((a-c)*(a-c)+4*b*b);
        var small=(a+c-delta)/2,large=(a+c+delta)/2;
        if (scale<=0 || small<=0) return null;
        var angle=(Math.atan2(2*b,a-c)/2+Math.PI/2)*180/Math.PI;
        while (angle>90) angle-=180;
        return {x:cx,y:cy,rx:Math.sqrt(scale/small),ry:Math.sqrt(scale/large),angle:angle};
    }

    function create(options) {
        var mesh=null,view=null,viewKey="",width=0,height=0,revision=0;
        var visual={},configured=false,range=null,rangeKey="",geometryKey="";
        var lines=[],marks=[],ring=[],lineByKey={},markByKey={},freeLines=[],freeMarks=[];
        var coverage=null,coverageKey="",markStride=1,lodKey="";
        var mask=options.mask,host=options.host,outline=options.outline,planeRange=false;
        var stats={geometry_builds:0,view_builds:0,layout_writes:0,mask_updates:0,line_panels:0,
            mark_panels:0,reference_rebases:0,corner_candidates:0,coverage_builds:0,
            visible_lines:0,visible_marks:0,mark_stride:1,mask_pixels:0};
        var reportedState="";
        function report(state) {
            stats.state=state;
            if(reportedState===state) return;
            reportedState=state;
            if($.Msg) $.Msg("[SurvivalStaticGrid] "+state);
        }
        function set(panel,key,value) {
            var cache=panel.__gridStyles || (panel.__gridStyles={});
            if(cache[key]===value) return false;
            options.setStyle(panel,key,value);cache[key]=value;return true;
        }
        function show(panel,visible) {if(panel.visible!==visible) panel.visible=visible;}
        function allocate(lineTarget,markTarget,budget) {
            while(lines.length<lineTarget && budget-->0) {
                var line=$.CreatePanel("Panel",host,"StaticGridLine"+lines.length);
                line.AddClass("StaticGridLine");line.hittest=false;line.visible=false;
                lines.push(line);freeLines.push(line);
            }
            while(marks.length<markTarget && budget-->0) {
                var mark=$.CreatePanel("Panel",host,"StaticGridMark"+marks.length);
                mark.AddClass("StaticGridMark");mark.hittest=false;mark.visible=false;
                marks.push(mark);freeMarks.push(mark);
            }
            stats.line_panels=lines.length;stats.mark_panels=marks.length;
        }
        function visibleBounds() {
            if(!view) return null;
            var corners=[[-8,-8],[width+8,-8],[width+8,height+8],[-8,height+8]].map(function(p){
                return unproject(view,p[0],p[1]);
            });
            if(corners.some(function(p){return !p;})) return null;
            return [Math.min.apply(Math,corners.map(function(p){return p[0];})),
                Math.min.apply(Math,corners.map(function(p){return p[1];})),
                Math.max.apply(Math,corners.map(function(p){return p[0];})),
                Math.max.apply(Math,corners.map(function(p){return p[1];}))];
        }
        function selectCoverage(world) {
            var radius=Number(visual.radius)||1280,block=mesh.size*8;
            range={x:world[0],y:world[1],radius:radius};
            rangeKey=range.x+":"+range.y+":"+radius;
            if(coverage && coverage.radius===radius && Math.abs(world[0]-coverage.x)<=block/2
                && Math.abs(world[1]-coverage.y)<=block/2) return;
            var x=Math.round(world[0]/block)*block,y=Math.round(world[1]/block)*block;
            coverage={x:x,y:y,radius:radius};coverageKey=x+":"+y+":"+radius;stats.coverage_builds++;
        }
        function drawBounds() {
            var visible=visibleBounds();
            if(!range) return visible;
            var patch=[range.x-range.radius,range.y-range.radius,range.x+range.radius,range.y+range.radius];
            if(!visible) return patch;
            return [Math.max(visible[0],patch[0]),Math.max(visible[1],patch[1]),
                Math.min(visible[2],patch[2]),Math.min(visible[3],patch[3])];
        }
        function refreshView() {
            if(!mesh || !configured) return;
            var viewport=options.viewport();
            if(!viewport || !viewport.every(isFinite) || viewport[0]<=0 || viewport[1]<=0) return;
            var center=options.referenceWorld && options.referenceWorld(),r=mesh.reference,z=mesh.height;
            if(center && isFinite(center[0]) && isFinite(center[1])
                && (Math.abs(center[0]-r[0]-r[2]/2)>1024 || Math.abs(center[1]-r[1]-r[3]/2)>1024)) {
                mesh.reference=r=[Math.round(center[0]/512)*512-512,Math.round(center[1]/512)*512-512,1024,1024];
                stats.reference_rebases++;
            }
            var points,key,next;
            for(var attempt=0;attempt<5;attempt++) {
                points=[[r[0],r[1],z],[r[0]+r[2],r[1],z],
                    [r[0]+r[2],r[1]+r[3],z],[r[0],r[1]+r[3],z]].map(options.project);
                key=r.join(",")+":"+points.map(function(p){return p?p[0].toFixed(3)+","+p[1].toFixed(3):"off";}).join(";")
                    +":"+viewport.join(",");
                if(view && viewKey===key) return;
                next=projection(r,points);
                if(next) break;
                if(!center || !isFinite(center[0]) || !isFinite(center[1])) break;
                // In very close/rotated views the old 1024-unit probe can cross
                // the horizon. Retry a smaller camera-centered probe, not a
                // mouse-centered projection that jitters when placing units.
                var size=r[2]/2;r=[center[0]-size/2,center[1]-size/2,size,size];
                stats.reference_rebases++;
            }
            if(!next) {view=null;show(mask,false);if(outline)show(outline,false);report("projection_unavailable");return;}
            mesh.reference=r;view=next;viewKey=key;width=viewport[0];height=viewport[1];revision++;
            stats.view_builds++;stats.mask_pixels=0;
            // No opacity-mask or inverse transforms: compositing bounds are
            // always the viewport, independent of camera distance and horizon.
            [mask,host,outline].forEach(function(p){if(!p)return;
                set(p,"position","0px 0px 0px");set(p,"width",width.toFixed(2)+"px");
                set(p,"height",height.toFixed(2)+"px");set(p,"transform","none");
            });
        }
        function gradient(points) {
            var a=points[0],b=points[1],fractions=[0,0.125,0.25,0.375,0.5,0.625,0.75,0.875,1];
            // Include the nearest world point and both opaque-core boundaries.
            // They need not lie at the midpoint of a perspective screen line.
            var wa=unproject(view,a[0],a[1]),wb=unproject(view,b[0],b[1]);
            if(wa && wb) {
                var dx=wb[0]-wa[0],dy=wb[1]-wa[1],length2=dx*dx+dy*dy;
                var t=((range.x-wa[0])*dx+(range.y-wa[1])*dy)/length2;
                var near=[wa[0]+t*dx,wa[1]+t*dy];
                var distance2=(near[0]-range.x)*(near[0]-range.x)+(near[1]-range.y)*(near[1]-range.y);
                var inner=range.radius*0.75,delta=Math.sqrt(Math.max(0,inner*inner-distance2)/length2);
                [t-delta,t,t+delta].forEach(function(u){
                    if(u<=0 || u>=1) return;
                    var p=point(view,wa[0]+u*dx,wa[1]+u*dy);
                    var f=Math.abs(b[0]-a[0])>Math.abs(b[1]-a[1])?(p[0]-a[0])/(b[0]-a[0]):(p[1]-a[1])/(b[1]-a[1]);
                    if(f>0 && f<1) fractions.push(f);
                });
            }
            fractions.sort(function(a,b){return a-b;});
            var stops=[],last=-1;
            for(var i=0;i<fractions.length;i++) {
                var f=Number(fractions[i].toFixed(5));if(f===last)continue;last=f;
                var world=unproject(view,a[0]+(b[0]-a[0])*f,a[1]+(b[1]-a[1])*f);
                var alpha=world?rangeAlpha(range,world[0],world[1]):0;
                stops.push("color-stop("+f.toFixed(5)+",rgba(213,230,211,"+alpha.toFixed(4)+"))");
            }
            return "gradient(linear,0% 0%,100% 0%,"+stops.join(",")+")";
        }
        function layoutSet(items,byKey,free,isLine) {
            var wanted={};
            for(var i=0;i<items.length;i++) wanted[items[i].key]=true;
            Object.keys(byKey).forEach(function(key){
                if(wanted[key]) return;
                var p=byKey[key];show(p,false);free.push(p);delete byKey[key];
            });
            for(var j=0;j<items.length;j++) {
                var item=items[j],panel=byKey[item.key];
                if(!panel) {panel=free.pop();if(!panel)continue;byKey[item.key]=panel;panel.__gridKey=item.key;}
                var changed=false;
                if(isLine) {
                    var shape=item.points.map(function(p){return p[0].toFixed(3)+","+p[1].toFixed(3);}).join(":");
                    if(panel.__shapeKey!==shape) {
                        options.positionSegment(panel,item.points[0],item.points[1],2);panel.__shapeKey=shape;changed=true;
                    }
                    changed=set(panel,"backgroundColor",gradient(item.points)) || changed;
                } else {
                    changed=set(panel,"position",(item.x-4).toFixed(2)+"px "+(item.y-4).toFixed(2)+"px 0px");
                    changed=set(panel,"opacity",(0.75*item.alpha).toFixed(4)) || changed;
                }
                if(changed)stats.layout_writes++;
                show(panel,true);
            }
        }
        function layoutRing() {
            if(!outline) return;
            if(!planeRange) {show(outline,false);return;}
            while(ring.length<64) {
                var p=$.CreatePanel("Panel",outline,"");p.AddClass("StaticGridRangeLine");p.hittest=false;p.visible=false;ring.push(p);
            }
            for(var i=0;i<64;i++) {
                var a=i*Math.PI/32,b=(i+1)*Math.PI/32;
                var clipped=segment(view,[range.x+range.radius*Math.cos(a),range.y+range.radius*Math.sin(a),
                    range.x+range.radius*Math.cos(b),range.y+range.radius*Math.sin(b)],width,height);
                if(clipped) options.positionSegment(ring[i],clipped[0],clipped[1],1);
                show(ring[i],!!clipped);
            }
            show(outline,true);
        }
        function layout() {
            if(!view || !range) return;
            var next=revision+":"+rangeKey+":"+planeRange;
            if(geometryKey===next && lines.length>=128 && marks.length>=160) return;
            geometryKey=next;
            var screenLines=[],screenMarks=[];
            for(var i=0;i<mesh.segments.length;i++) {
                var worldLine=circleSegment(mesh.segments[i],range);
                if(!worldLine)continue;
                var clipped=segment(view,worldLine,width,height);
                if(clipped && Math.abs(clipped[0][0]-clipped[1][0])+Math.abs(clipped[0][1]-clipped[1][1])>=0.5)
                    screenLines.push({key:"l"+i,points:clipped});
            }
            var bounds=drawBounds(),x0=Math.max(0,Math.floor((bounds[0]-mesh.xs[0])/mesh.size)),
                y0=Math.max(0,Math.floor((bounds[1]-mesh.ys[0])/mesh.size)),
                x1=Math.min(mesh.xs.length-1,Math.ceil((bounds[2]-mesh.xs[0])/mesh.size)),
                y1=Math.min(mesh.ys.length-1,Math.ceil((bounds[3]-mesh.ys[0])/mesh.size));
            // Decoration is sparse and bounded; every actual grid boundary and
            // all footprint cells remain full resolution at every zoom level.
            var nextLod=revision+":"+range.radius;
            if(lodKey!==nextLod) {
                // Density depends on camera coverage, never cursor position.
                var cameraBounds=visibleBounds(),diameter=Math.ceil(2*range.radius/mesh.size)+3;
                var spanX=Math.min(mesh.xs.length,diameter,cameraBounds?Math.ceil((cameraBounds[2]-cameraBounds[0])/mesh.size)+3:diameter);
                var spanY=Math.min(mesh.ys.length,diameter,cameraBounds?Math.ceil((cameraBounds[3]-cameraBounds[1])/mesh.size)+3:diameter);
                markStride=Math.max(1,Math.ceil(Math.sqrt(spanX*spanY/144)));
                while(Math.ceil(spanX/markStride)*Math.ceil(spanY/markStride)>160) markStride++;
                lodKey=nextLod;
            }
            stats.corner_candidates=0;
            for(var x=Math.ceil(x0/markStride)*markStride;x<=x1;x+=markStride)
                for(var y=Math.ceil(y0/markStride)*markStride;y<=y1;y+=markStride) {
                    stats.corner_candidates++;
                    var alpha=rangeAlpha(range,mesh.xs[x],mesh.ys[y]);if(alpha<0.01)continue;
                    var p=point(view,mesh.xs[x],mesh.ys[y]);
                    if(p && p[0]>=0 && p[0]<=width && p[1]>=0 && p[1]<=height)
                        screenMarks.push({key:"m"+x+":"+y,x:p[0],y:p[1],alpha:alpha});
                }
            allocate(Math.max(128,screenLines.length),160,32);
            layoutSet(screenLines,lineByKey,freeLines,true);layoutSet(screenMarks,markByKey,freeMarks,false);layoutRing();
            stats.visible_lines=screenLines.length;stats.visible_marks=screenMarks.length;stats.mark_stride=markStride;
        }
        function configure(data,size,settings) {
            var next=geometry(data,size);mask.RemoveClass("StaticGridActive");
            if(!next) {
                configured=false;view=null;range=null;geometryKey="";show(mask,false);if(outline)show(outline,false);
                lines.concat(marks).forEach(function(p){show(p,false);});return false;
            }
            var key=JSON.stringify([data,size,settings.grid_z_offset]);
            if(mesh && mesh.key===key && configured) {visual=settings;return true;}
            mesh=next;mesh.key=key;mesh.height+=Number(settings.grid_z_offset)||0;
            visual=settings;view=null;viewKey="";geometryKey="";range=null;rangeKey="";coverage=null;coverageKey="";
            configured=true;stats.geometry_builds++;show(mask,false);return true;
        }
        function prewarm() {if(configured)allocate(128,160,32);}
        function warm() {prewarm();}
        function update(world,viewIsCurrent) {
            if(!world) {show(mask,false);if(outline)show(outline,false);return;}
            if(!configured) {show(mask,true);return;}
            if(!viewIsCurrent)refreshView();
            if(!view)return;
            selectCoverage(world);layout();
            show(mask,lines.length>=stats.visible_lines);
            if(outline)show(outline,planeRange && mask.visible);
            report(mask.visible?"visible":"warming");
        }
        return {configure:configure,warm:warm,prewarm:prewarm,update:update,
            hide:function(){show(mask,false);if(outline)show(outline,false);},
            setPlaneRange:function(enabled){planeRange=enabled;return !!outline;},
            refreshView:refreshView,visibleBounds:visibleBounds,drawBounds:drawBounds,
            coverageKey:function(){return coverageKey;},range:function(){return range;},
            projectPolygon:function(points){return configured && view?polygon(view,points,width,height):[];},
            worldAtScreen:function(screen){
                var world=configured && screen?unproject(view,screen[0],screen[1]):null;
                return world?[world[0],world[1],mesh.height-(Number(visual.grid_z_offset)||0)]:null;
            },
            project:function(world){return configured && view && Math.abs(world[2]-mesh.height)<0.001?
                point(view,world[0],world[1]):null;},cameraKey:function(){return viewKey;},
            enabled:function(){return configured;},stats:stats};
    }

    GameUI.CustomUIConfig().SurvivalStaticGrid={geometry:geometry,projection:projection,
        point:point,unproject:unproject,segment:segment,ellipse:ellipse,create:create};
})();
