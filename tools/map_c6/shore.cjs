// Clip boundary terrain against one shared circular shore. Avoid dropping an
// entire grid cell merely because its center lies outside the island.
const radius=3072,segments=176;
const boundary=Array.from({length:segments},(_,i)=>[radius*Math.cos(i*2*Math.PI/segments),radius*Math.sin(i*2*Math.PI/segments)]);
function clip(points){
 if(points.every(p=>Math.hypot(...p)<=radius*Math.cos(Math.PI/segments)))return points;
 let out=points;
 for(let i=0;i<segments&&out.length;i++){
  const a=boundary[i],b=boundary[(i+1)%segments],side=p=>(b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0]);
  const input=out;out=[];
  for(let j=0;j<input.length;j++){
   const p=input[j],q=input[(j+1)%input.length],dp=side(p),dq=side(q),ip=dp>=-1e-7,iq=dq>=-1e-7;
   if(ip)out.push(p);
   if(ip!==iq){const t=dp/(dp-dq);out.push([p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t]);}
  }
 }
 return out.filter((p,i)=>Math.hypot(p[0]-out[(i+1)%out.length][0],p[1]-out[(i+1)%out.length][1])>1e-5);
}
function quads(p){
 if(p.length<3)return [];
 if(p.length===4)return [p];
 const out=[],mid=(a,b)=>[(a[0]+b[0])/2,(a[1]+b[1])/2];
 for(let i=1;i<p.length-1;i++){
  const [a,b,c]=[p[0],p[i],p[i+1]];
  if(Math.abs((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]))<1e-5)continue;
  const center=[(a[0]+b[0]+c[0])/3,(a[1]+b[1]+c[1])/3],ab=mid(a,b),bc=mid(b,c),ca=mid(c,a);
  out.push([a,ab,center,ca],[ab,b,bc,center],[center,bc,c,ca]);
 }
 return out;
}
module.exports={radius,segments,boundary,clip,quads};
