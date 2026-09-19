// Native rock clusters for the folded entrance. All bounds are from the
// installed Valve model MDAT, not guessed from their editor origin.
const bounds={
 '002a':[[-144.88121,-88.318565,0],[90.34546,183.8272,115.4847]],
 '005a':[[-75.97473,-177.24365,-.038101],[52.018997,179.62158,160.34778]],
 '006a':[[-115.03384,-108.19397,-.070902],[118.086136,91.76007,170.85938]],
 '007a':[[-87.703575,-121.46022,-.011348],[110.615814,147.45201,161.54669]],
 '008a':[[-81.48604,-113.78705,-.032495],[87.044334,105.6503,175.95302]],
 '009a':[[-141.20677,-236.25854,-.37366864],[151.20743,221.26001,288.58884]],
 '010a':[[-123.331245,-203.63135,0],[128.69618,137.60437,288.01114]]
};
function rotatedBounds(name,yaw){
 const [lo,hi]=bounds[name],a=yaw*Math.PI/180,c=Math.cos(a),s=Math.sin(a);
 const p=[lo[0],hi[0]].flatMap(x=>[lo[1],hi[1]].map(y=>[x*c-y*s,x*s+y*c]));
 return {lo:[Math.min(...p.map(p=>p[0])),Math.min(...p.map(p=>p[1])),lo[2]],hi:[Math.max(...p.map(p=>p[0])),Math.max(...p.map(p=>p[1])),hi[2]]};
}
function build(S,at){
 const rocks=[];
 function rock(name,x,y,base,scale,yaw,zone){
  const b=rotatedBounds(name,yaw),cx=(b.lo[0]+b.hi[0])/2,cy=(b.lo[1]+b.hi[1])/2;
  const p=[x-cx*scale,y-cy*scale,base-b.lo[2]*scale];
  at('models/props_rock/riveredge_rock'+name+'.vmdl',...p,scale,yaw);
  rocks.push({zone,model:name,position:p,scale,yaw,bounds:{x0:x-(b.hi[0]-b.lo[0])*scale/2,x1:x+(b.hi[0]-b.lo[0])*scale/2,y0:y-(b.hi[1]-b.lo[1])*scale/2,y1:y+(b.hi[1]-b.lo[1])*scale/2,z0:base,z1:base+(b.hi[2]-b.lo[2])*scale}});
 }
 // The entire column grows from the local low ground, with overlapping
 // courses and a buried crown. No isolated high rock floats halfway up a wall.
 function column({x,y,base,crest,width,axis,yaw,seed,zone}){
  const names=zone==='inner-stairs'?['008a','006a','007a']:['009a','010a','007a','006a'];
  let z=base-18,layer=0;
  while(z<crest){
   const name=names[(seed+layer)%names.length],angle=yaw+((seed*13+layer*11)%23-11);
   const b=rotatedBounds(name,angle),scale=Math.min(zone==='inner-stairs'?.7:.94,width/(b.hi[axis]-b.lo[axis]));
   const h=(b.hi[2]-b.lo[2])*scale;
   // Only lower the final course into place. Lifting a near-final course to
   // the crown would open a gap when the next model is shorter than the last.
   const placeZ=z+h>=crest?crest-h:z;
   rock(name,x,y,placeZ,scale,angle,zone);
   if(placeZ+h>=crest-.1)break;
   z+=h*.68;layer++;
  }
 }
 // The narrow strip between the lawn and stair treads remains 120 wide.
 // Bounding-box fitting keeps every rock outside both playable surfaces.
 for(let j=0;j<7;j++){
  const y=142+j*78,base=S.stairElevation(y-42);
  column({x:2180,y,base,crest:420+[8,27,2,18,35,5,22][j],width:108,axis:0,yaw:(j%2?9:-8),seed:j,zone:'inner-stairs'});
 }
 // Join the long lane bank to the narrow stair-side bank. Their separate
 // model envelopes otherwise leave a small exposed triangular terrain seam.
 column({x:2144,y:320,base:24,crest:432,width:152,axis:0,yaw:-90,seed:3,zone:'bank-junction'});
 // The outside bank continues all the way around the low bend, not just the
 // three staircase sample points. Wider natural boulders cover the outer face.
 for(let j=0;j<8;j++){
  const y=-180+j*132,x=2728+(j%3-1)*5,base=S.stairElevation(y-64);
  column({x,y,base,crest:424+[18,2,35,11,28,0,23,8][j],width:184,axis:0,yaw:j%2?6:-7,seed:j+1,zone:'outer-stairs'});
 }
 for(let j=0;j<5;j++){
  const x=2116+j*129,y=-322+(j%2)*4;
  column({x,y,base:24,crest:426+[12,31,2,22,8][j],width:172,axis:1,yaw:-90,seed:j+2,zone:'bend-foot'});
 }
 // Small partly buried cap stones soften remaining grass/rock knife edges.
 // They are on the blocked strip, never scattered across the building lawn.
 for(let side of [-1,1])for(let j=0;j<11;j++){
  const x=770+j*121,y=side*(396+j%3),name=['002a','007a','008a'][j%3],yaw=(j*37)%360;
  const b=rotatedBounds(name,yaw),scale=Math.min(.23,32/(b.hi[1]-b.lo[1]));
  rock(name,x,y,S.height(x,y)-6,scale,yaw,'lane-crest');
 }
 return rocks;
}
module.exports={build,bounds,rotatedBounds};
