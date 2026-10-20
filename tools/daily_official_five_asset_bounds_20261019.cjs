'use strict';
const fs=require('node:fs');
const {browser}=require('./shop_ui_12h/cdp.cjs');
async function main(){
 const b=await browser();
 try{
  await b.go('design_refs/daily_official_five_20261019/native_asset_sheet.html');
  const manifest=JSON.parse(fs.readFileSync('design_refs/daily_official_five_20261019/native_assets.json','utf8'));
  const images=manifest.records.map(r=>({key:r.key,src:'data:image/png;base64,'+fs.readFileSync('design_refs/daily_official_five_20261019/'+r.local).toString('base64')}));
  await b.run(`Promise.all(${JSON.stringify(images)}.map(async row=>{const i=[...document.images].find(i=>i.src.endsWith('/'+row.key+'.png'));i.dataset.key=row.key;i.src=row.src;await i.decode()})).then(()=>true)`);
  const rows=await b.run(`(()=>[...document.images].filter(i=>/button|slot|_frame|header/.test(i.dataset.key)).map(i=>{const c=document.createElement('canvas');c.width=i.naturalWidth;c.height=i.naturalHeight;const ctx=c.getContext('2d');ctx.drawImage(i,0,0);const a=ctx.getImageData(0,0,c.width,c.height).data;let l=c.width,t=c.height,r=-1,bt=-1;for(let y=0;y<c.height;y++)for(let x=0;x<c.width;x++)if(a[(y*c.width+x)*4+3]>32){l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);bt=Math.max(bt,y);}return{key:i.dataset.key,image:{width:c.width,height:c.height},alpha32:{x:l,y:t,width:r-l+1,height:bt-t+1}}}))()`);
  fs.writeFileSync('design_refs/daily_official_five_20261019/native_alpha_bounds.json',JSON.stringify(rows,null,2));console.log(JSON.stringify(rows));
 }finally{b.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1});
