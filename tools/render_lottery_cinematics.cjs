const fs=require('fs'),path=require('path'),{spawn}=require('child_process');
const {createCanvas,loadImage}=require('../output/lottery_cinematic_20260929/render/node_modules/@napi-rs/canvas');
const {LotteryFilm:film}=require('./lottery_cinematic_compositor.cjs');
const ff=fs.readFileSync('output/lottery_cinematic_20260929/ffmpeg.txt','utf8').trim();
const out='panorama/videos/custom_game/lottery_cinematic_v1',preview='output/lottery_cinematic_20260929/previews';
fs.mkdirSync(out,{recursive:true});fs.mkdirSync(preview,{recursive:true});
async function main(){
 const images={};for(const id of ['gate','dragon',...Object.keys(film.THEMES)])images[id]=await loadImage('panorama/src/images/custom_game/lottery_cinematic_v1/'+id+'.png');
 for(const pool of process.argv.slice(2).length?process.argv.slice(2):Object.keys(film.THEMES)){
  const c=createCanvas(film.W,film.H),ctx=c.getContext('2d'),file=path.join(out,pool+'.webm');
  const args=['-y','-hide_banner','-loglevel','error','-f','rawvideo','-pix_fmt','rgba','-s',film.W+'x'+film.H,'-r','30','-i','pipe:0','-i','output/lottery_cinematic_20260929/audio/'+pool+'.wav','-c:v','libvpx-vp9','-crf','30','-b:v','0','-deadline','good','-cpu-used','5','-row-mt','1','-threads','4','-pix_fmt','yuv420p','-c:a','libvorbis','-q:a','5','-t','7',file];
  const proc=spawn(ff,args,{stdio:['pipe','ignore','pipe'],windowsHide:true});let errors='';proc.stderr.on('data',x=>errors+=x);const done=new Promise((resolve,reject)=>proc.on('exit',code=>code===0?resolve():reject(Error(errors))));
  for(let f=0;f<210;f++){film.draw(ctx,images,pool,f/30);if([15,60,110,160,182].includes(f))fs.writeFileSync(path.join(preview,pool+'_'+f+'.png'),c.toBuffer('image/png'));
   const b=Buffer.from(ctx.getImageData(0,0,film.W,film.H).data.buffer);if(!proc.stdin.write(b))await new Promise(r=>proc.stdin.once('drain',r));}
  proc.stdin.end();await done;console.log(pool+' rendered '+fs.statSync(file).size+' bytes');
  await new Promise((resolve,reject)=>{let p=spawn(ff,['-y','-hide_banner','-loglevel','error','-i',file,'-c:v','libx264','-preset','fast','-crf','22','-c:a','aac','-b:a','160k','-movflags','+faststart',path.join(preview,pool+'.mp4')],{stdio:'ignore',windowsHide:true});p.on('exit',n=>n===0?resolve():reject(Error('Preview encoding failed')));});
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
