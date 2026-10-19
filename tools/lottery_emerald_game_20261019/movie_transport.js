// Offline-only Movie API transport. Production script bodies stay unchanged.
window.LOTTERY_PREVIEW_MOVIES=__LOTTERY_MOVIE_PATHS__;
Panel.prototype.SetControls=function(){};
Panel.prototype.SetRepeat=function(value){this.__previewRepeat=!!value;};
Panel.prototype.SetPlaybackVolume=function(value){this.__previewVolume=Number(value);};
Panel.prototype.SetMovie=function(uri){
 this.__previewMovieSource=String(uri);
 const id=String(uri).split('/').at(-1).replace(/\.webm$/,'');
 if(!LOTTERY_PREVIEW_MOVIES[id])throw Error('Unregistered local movie '+uri);
 const video=document.createElement('video');video.src=LOTTERY_PREVIEW_MOVIES[id];
 video.muted=true;video.loop=this.__previewRepeat;video.preload='auto';
 Object.assign(video.style,{position:'absolute',left:'0px',top:'0px',width:'100%',height:'100%',objectFit:'contain',pointerEvents:'none'});
 this.el.append(video);this.__previewMovie=video;
};
Panel.prototype.Play=function(){if(this.__previewMovie)this.__previewMovie.play().catch(error=>previewMessages.push('Browser-only muted film playback: '+String(error)));};
Panel.prototype.Stop=function(){if(this.__previewMovie){this.__previewMovie.pause();this.__previewMovie.removeAttribute('src');this.__previewMovie.load();}};
// Panorama boosts the shadow alpha by its intensity. Repeated CSS shadows are
// a browser-only approximation; do not use these captures as native pixel proof.
function lotteryBrowserShadow(value){return String(value).split(',').flatMap(part=>{const strength=part.match(/(-?[\d.]+px\s+-?[\d.]+px\s+[\d.]+px)\s+([\d.]+)(?=\s|$)/);const converted=part.trim().replace(/(-?[\d.]+px\s+-?[\d.]+px\s+[\d.]+px)\s+[\d.]+(?=\s|$)/,'$1');return Array.from({length:strength?Math.max(1,Math.ceil(Number(strength[2]))):1},()=>converted);}).join(',');}
const lotteryCreatePanel=$.CreatePanel;
$.CreatePanel=function(type,parent,id){
 const panel=lotteryCreatePanel(type,parent,id),original=panel.style;
 panel.style=new Proxy(original,{set(target,key,value){
  target[key]=value;
  if(key==='textShadow')panel.el.style.textShadow=lotteryBrowserShadow(value);
  return true;
 }});return panel;
};
// XML-created labels bypass $.CreatePanel, so repair their authored shadow at
// the regular layout synchronization point as well.
const lotteryShadowSync=window.syncLayout;
window.syncLayout=()=>{function visit(panel){if(panel._style&&panel._style.textShadow)panel.el.style.textShadow=lotteryBrowserShadow(panel._style.textShadow);panel.Children().forEach(visit);}visit(root);lotteryShadowSync();};
previewGeometryModels.push('Movie panels use the identical repository webm through a muted HTML video. The native decoder, audio and compositing remain unverified.');
previewGeometryModels.push('Native text-shadow intensity is approximated with repeated identical CSS shadows. Native rasterization and exact alpha strength need a game capture.');
