const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),kit=path.join(root,'output/xianxia_kit'),dir=path.join(kit,'cloud_revision_v2/variants');
const source=fs.readFileSync(path.join(__dirname,'xianxia_kit_gallery.cjs'),'utf8');
const {pngRead,pngWrite}=new Function('require','__dirname',source.slice(0,source.indexOf('const a=JSON.parse'))+'return {pngRead,pngWrite};')(require,__dirname);
fs.mkdirSync(path.join(dir,'source_materials'),{recursive:true});const report=[];
for(const [name,base]of [['c01_cloud_sea_b','c01_cloud_sea'],['c02_cliff_cloud_b','c02_cliff_cloud']]){
 const p=pngRead(path.join(dir,name+'.png'));let edge=0,visible=0;
 for(let y=0;y<p.h;y++)for(let x=0;x<p.w;x++){const a=p.data[(y*p.w+x)*4+3];if(x<4||y<4||x>=p.w-4||y>=p.h-4)edge=Math.max(edge,a);if(a>2)visible++;}
 if(edge||visible<100)throw Error('Invalid transparent cloud '+name);
 const padded=Buffer.alloc(2048*2048*4),top=(2048-p.h)>>1;for(let y=0;y<p.h;y++)p.data.copy(padded,((y+top)*2048)*4,y*p.w*4,(y+1)*p.w*4);
 pngWrite(path.join(dir,'source_materials',name+'_v2.png'),2048,2048,padded);
 const tex=fs.readFileSync(path.join(kit,'cloud_revision_v2/source_materials',base+'_v2.vtex'),'utf8').replaceAll(base+'_v2',name+'_v2');
 fs.writeFileSync(path.join(dir,'source_materials',name+'_v2.vtex'),tex);
 for(const bg of ['dark','light']){const rgb=Buffer.from(p.data),back=bg==='dark'?[40,60,75]:[225,227,221];for(let i=0;i<rgb.length;i+=4){const a=rgb[i+3]/255;for(let k=0;k<3;k++)rgb[i+k]=Math.round(rgb[i+k]*a+back[k]*(1-a));rgb[i+3]=255;}pngWrite(path.join(dir,name+'_'+bg+'.png'),p.w,p.h,rgb);}
 report.push({name,borderAlphaMax:edge,visibleFraction:visible/(p.w*p.h),dimensions:[p.w,p.h],pass:true});
}
fs.writeFileSync(path.join(dir,'validation.json'),JSON.stringify(report,null,2));console.log(report);
