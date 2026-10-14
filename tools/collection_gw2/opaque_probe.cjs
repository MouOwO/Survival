'use strict';
// Browser-only pixel proof. Never changes production panel styles or game state.
const fs=require('fs'),zlib=require('zlib'),assert=require('node:assert/strict');
function decodePng(bytes){
 assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20),channels={2:3,6:4}[bytes[25]];assert.equal(bytes[24],8);assert(channels);assert.equal(bytes[28],0);const chunks=[];
 for(let offset=8;offset<bytes.length;){const size=bytes.readUInt32BE(offset);if(bytes.toString('ascii',offset+4,offset+8)==='IDAT')chunks.push(bytes.subarray(offset+8,offset+8+size));offset+=size+12;}
 const raw=zlib.inflateSync(Buffer.concat(chunks)),stride=width*channels,pixels=Buffer.alloc(height*stride);let offset=0;
 for(let y=0;y<height;y++){const filter=raw[offset++];for(let x=0;x<stride;x++){const at=y*stride+x,a=x>=channels?pixels[at-channels]:0,b=y?pixels[at-stride]:0,c=y&&x>=channels?pixels[at-stride-channels]:0;let value=0;if(filter===1)value=a;else if(filter===2)value=b;else if(filter===3)value=Math.floor((a+b)/2);else if(filter===4){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);value=pa<=pb&&pa<=pc?a:pb<=pc?b:c;}else assert.equal(filter,0);pixels[at]=(raw[offset++]+value)&255;}}
 return {width,height,channels,pixels};
}
function diff(first,second,rect){
 assert.equal(first.width,second.width);assert.equal(first.height,second.height);let changed=0,pixels=0,maxDelta=0;
 for(let y=rect.y;y<rect.y+rect.height;y++)for(let x=rect.x;x<rect.x+rect.width;x++){let delta=0;for(let channel=0;channel<3;channel++)delta=Math.max(delta,Math.abs(first.pixels[(y*first.width+x)*first.channels+channel]-second.pixels[(y*second.width+x)*second.channels+channel]));pixels++;if(delta)changed++;maxDelta=Math.max(maxDelta,delta);}
 return {rect,pixels,changed,maxDelta};
}
async function probeOpaque(b,output,width,height){
 const geometry=await b.run(`(()=>{const windowPanel=nodes.CollectionWindow.el,canvas=nodes.CollectionGW2Canvas.el,rect=canvas.getBoundingClientRect();const probe=document.createElement('div');probe.id='PreviewOpacityBackdrop';probe.style.cssText='position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;';probe.style.zIndex=String((parseInt(getComputedStyle(windowPanel).zIndex)||1)-1);windowPanel.parentElement.insertBefore(probe,windowPanel);window.entryOpacityProbe=probe;return {canvas:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},probeZ:getComputedStyle(probe).zIndex,windowZ:getComputedStyle(windowPanel).zIndex};})()`);
 try{
  const captures=[];for(const color of ['#ff00ff','#00ff00']){await b.run('entryOpacityProbe.style.background='+JSON.stringify(color)+';new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');const file=output+'_'+(color==='#ff00ff'?'magenta':'green')+'.png';await b.shot(file,{x:0,y:0,width,height});captures.push(decodePng(fs.readFileSync(file)));}
  const bounds=geometry.canvas,left=Math.ceil(bounds.x),top=Math.ceil(bounds.y),right=Math.floor(bounds.x+bounds.width),bottom=Math.floor(bounds.y+bounds.height),full={x:left,y:top,width:right-left,height:bottom-top};
  const region={fullCanvas:full,topEdge:{x:left,y:top,width:full.width,height:2},bottomEdge:{x:left,y:bottom-2,width:full.width,height:2},leftEdge:{x:left,y:top,width:2,height:full.height},rightEdge:{x:right-2,y:top,width:2,height:full.height},center:{x:Math.floor((left+right)/2)-4,y:Math.floor((top+bottom)/2)-4,width:8,height:8}};
  const regions=Object.fromEntries(Object.entries(region).map(([name,rect])=>[name,diff(...captures,rect)]));for(const [name,value]of Object.entries(regions))assert.equal(value.changed,0,'Opaque '+name+' pixels cannot depend on backdrop color');
  let control=null;if(left>=6)control={x:1,y:Math.floor(height/2),width:Math.min(8,left-2),height:8};else if(top>=6)control={x:Math.floor(width/2),y:1,width:8,height:Math.min(8,top-2)};else if(height-bottom>=6)control={x:Math.floor(width/2),y:bottom+1,width:8,height:Math.min(8,height-bottom-2)};
  const outsideControl=control?diff(...captures,control):null;if(outsideControl){assert(outsideControl.changed>0&&outsideControl.maxDelta>=200,'Outside control proves the extreme backdrop actually changed');}
  return {width,height,...geometry,regions,outsideControl,edgePolicy:'Every fully covered pixel from ceil(left/top) to floor(right/bottom) is compared exactly; fractional raster boundary pixels are excluded.',controlNote:control?'Outside-window pixels visibly change between extreme backdrops.':'Window fills this viewport; external control is verified at the larger resolutions.'};
 }finally{await b.run('entryOpacityProbe.remove();delete window.entryOpacityProbe;true');}
}
module.exports={decodePng,diff,probeOpaque};
