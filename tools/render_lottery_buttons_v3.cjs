// Rasterize authored vector plaques to preserve all strokes in Panorama's SVG renderer.
const fs=require('fs');const {createCanvas,loadImage}=require('../output/lottery_cinematic_20260929/render/node_modules/@napi-rs/canvas');
const out='panorama/src/images/custom_game/lottery_actions_v3';fs.mkdirSync(out,{recursive:true});
function svg(gold){const c=gold?['#fff6cd','#efcf7f','#d6a447','#987022','#fff3be']:['#fffef1','#faf1cd','#e6d4a0','#a58c50','#ffffff'];
return `<svg xmlns="http://www.w3.org/2000/svg" width="936" height="216" viewBox="0 0 312 72">
<defs><linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop stop-color="${c[4]}"/><stop offset=".45" stop-color="${c[2]}"/><stop offset=".65" stop-color="${c[3]}"/><stop offset="1" stop-color="${c[4]}"/></linearGradient>
<linearGradient id="face" x1="0" y1="0" x2=".15" y2="1"><stop stop-color="${c[0]}"/><stop offset=".28" stop-color="${c[1]}"/><stop offset=".7" stop-color="${c[1]}"/><stop offset="1" stop-color="${c[2]}"/></linearGradient>
<radialGradient id="light"><stop stop-color="#fffde6" stop-opacity=".8"/><stop offset="1" stop-color="#fffde6" stop-opacity="0"/></radialGradient></defs>
<path d="M16 8L295 8L309 37L295 65L16 65L3 37Z" fill="#100c05" opacity=".42"/>
<path d="M16 5L295 5L309 34L295 62L16 62L3 34Z" fill="url(#edge)" stroke="${c[3]}" stroke-width="1"/>
<path d="M19 9L292 9L304 34L292 58L19 58L8 34Z" fill="url(#face)" stroke="${c[4]}" stroke-width="1.3"/>
<path d="M22 12H289L299 34L289 54H22L13 34Z" fill="none" stroke="${c[3]}" stroke-opacity=".48" stroke-width=".6"/>
<path d="M24 14H287L294 30H17Z" fill="#fffef0" opacity=".12"/>
<path d="M25 10H288M21 57H290" fill="none" stroke="${c[4]}" stroke-width="1.2"/>
<!-- faint carved clouds; each path declares fill for deterministic rasterization -->
<path d="M15 32C23 34 32 28 35 20C39 10 53 14 51 21C49 28 39 25 43 20 M21 39C33 39 36 30 42 29C49 27 51 32 49 35" fill="none" stroke="${c[3]}" stroke-opacity=".25" stroke-width="1.1"/>
<path d="M267 56C259 53 260 46 266 44C271 42 277 46 274 49C272 52 268 48 271 47 M252 55C245 51 246 44 252 43 M278 55C295 57 302 45 294 38C287 31 277 39 281 45C285 51 292 47 290 43" fill="none" stroke="${c[3]}" stroke-width="2.7" stroke-linecap="round"/>
<path d="M267 54C261 51 263 46 267 45 M279 53C291 55 299 46 293 40C287 35 280 40 283 44C286 47 290 45 289 42" fill="none" stroke="${c[4]}" stroke-width="1.35" stroke-linecap="round"/>
<path d="M17 13L11 29M294 15L302 31" fill="none" stroke="#fffef0" stroke-width="1.3" opacity=".85"/>
</svg>`;}
(async()=>{for(const [id,gold] of [['ivory',false],['gold',true]]){const source=svg(gold);fs.writeFileSync(`${out}/${id}.svg`,source);const img=await loadImage(Buffer.from(source));const canvas=createCanvas(936,216);canvas.getContext('2d').drawImage(img,0,0);fs.writeFileSync(`${out}/${id}.png`,canvas.toBuffer('image/png'));console.log(id,'936x216 transparent PNG');}
const c=createCanvas(1200,280),x=c.getContext('2d');x.fillStyle='#28323a';x.fillRect(0,0,1200,280);for(const [i,id] of ['ivory','gold'].entries()){const im=await loadImage(`${out}/${id}.png`);x.drawImage(im,20+i*590,64,560,129);x.fillStyle='#35230d';x.font='bold 32px Microsoft YaHei';x.textAlign='center';x.fillText(i?'十连  10':'单抽  1',295+i*590,140);}fs.writeFileSync('output/lottery_polish_20260929/button_preview.png',c.toBuffer('image/png'));})();