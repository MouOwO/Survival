// Four natural round island platforms around a small circular shallow pool.
const center=[-1152,2688],radius=1536,islandOffset=3456,lakeRadius=1024;
const clamp=t=>Math.max(0,Math.min(1,t)),smooth=t=>{t=clamp(t);return t*t*(3-2*t);};
function local(x,y){x-=center[0];y-=center[1];const q=Math.abs(x)>=Math.abs(y)?x>=0?0:2:y>=0?1:3;return {q,r:[x,y,-x,-y][q],v:[y,-x,-y,x][q]};}
function world(r,v,q){return [center[0]+[r,-v,-r,v][q],center[1]+[v,r,-v,-r][q]];}
function channelHalfWidth(r){return 576-256*clamp((r-1152)/896);}
function lakeDistance(x,y){const {r,v}=local(x,y);return Math.min(Math.hypot(x-center[0],y-center[1])-lakeRadius,Math.max(r-2304,Math.abs(v)-channelHalfWidth(r)));}
function islandDistance(x,y){const {r,v}=local(x,y);return Math.hypot(r-islandOffset,v)-radius;}
function shallow(x,y){return lakeDistance(x,y)<=0;}
function stairHole(x,y){const {r,v}=local(x,y),a=Math.abs(v);return (r>=2304&&r<3072&&a<288)||(r>=2432&&r<3072&&a>=512&&a<896);}
function height(x,y){
 const {r,v}=local(x,y),a=Math.abs(v),d=islandDistance(x,y);
 if(shallow(x,y))return 396;
 if(d>0)return 254;
 let h=640;
 // Side tower lawns rise behind the gate, with broad soil/grass slopes elsewhere.
 const sideRise=smooth((a-880)/160),frontRise=1-smooth((r-2784)/96);
 h+=128*Math.max(sideRise,frontRise*smooth((a-300)/80));
 if(r>=2304&&r<=2816&&a<=288)h=396+244*(r-2304)/512;
 if(r>=2432&&r<=2816&&a>=512&&a<=896)h=r<2560?768:768-128*(r-2560)/256;
 // Natural shore slope instead of a vertical masonry extrusion.
 const rimWidth=r<2560&&a>=500&&a<=960?64:160;
 const rim=smooth((-d)/rimWidth);h=400+(h-400)*rim;
 if(r<2304)h=396+(h-396)*smooth((a-channelHalfWidth(r))/150);
 return h;
}
function outline(q){return Array.from({length:96},(_,i)=>world(islandOffset+radius*Math.cos(i*Math.PI/48),radius*Math.sin(i*Math.PI/48),q));}
function lakeOutline(){
 let p=Array.from({length:256},(_,i)=>{const a=i*Math.PI/128;let lo=0,hi=3400;for(let j=0;j<28;j++){const m=(lo+hi)/2;shallow(center[0]+m*Math.cos(a),center[1]+m*Math.sin(a))?lo=m:hi=m;}return [center[0]+lo*Math.cos(a),center[1]+lo*Math.sin(a)];});
 // Remove collinear points; the VMAP polygon normal needs a non-collinear start.
 p=p.filter((v,i)=>{const a=p[(i+p.length-1)%p.length],b=p[(i+1)%p.length];return Math.abs((v[0]-a[0])*(b[1]-v[1])-(v[1]-a[1])*(b[0]-v[0]))>.05;});return p;
}
function noise(x,y){return .5+.20*Math.sin(x/283+y/421)+.14*Math.sin(x/101-y/173)+.08*Math.cos(x/53+y/79);}
function paint(v,m=0){
 if(m!==0)return [0,0,0,0];const [x,y]=v,{r,v:side}=local(x,y),a=Math.abs(side),n=noise(x,y),shore=islandDistance(x,y);
 const slope=Math.hypot(height(x+24,y)-height(x-24,y),height(x,y+24)-height(x,y-24))/48;
 const path=(1-smooth((a-150-(n-.5)*170)/290))*smooth((r-2784)/256)*(1-smooth((r-4096)/384));
 const lawn=.76+.16*n,earth=(.15+.35*path)*smooth((n-.23)/.55),gravel=.12*path+.09*(1-n);
 const grass=lawn*(1-.7*path)*(1-.90*smooth((slope-.4)/1.7))*smooth((-shore-20)/160);
 return [grass,earth,gravel,0];
}
module.exports={center,radius,islandOffset,lakeRadius,local,world,channelHalfWidth,lakeDistance,islandDistance,shallow,height,stairHole,outline,lakeOutline,paint,noise};
