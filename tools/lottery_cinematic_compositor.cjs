/* Original cinematic compositor. Source illustrations are generated assets; no reference video pixels are used. */
(function(exports){
const W=1280,H=720,TAU=Math.PI*2;
const THEMES={map:{color:'#9dcaff',gold:'#f5d49a',title:'星门寻宝'},cultivation:{color:'#e1baff',gold:'#fff0b1',title:'云海龙吟'},dragon_knight:{color:'#ff7236',gold:'#ffc06a',title:'龙脊觉醒'},summer:{color:'#61e7ef',gold:'#dcffe9',title:'潮汐秘藏'}};
const clamp=x=>Math.max(0,Math.min(1,x)),smooth=x=>{x=clamp(x);return x*x*(3-2*x);};
function rand(i){let x=Math.sin(i*127.1+311.7)*43758.5453;return x-Math.floor(x);}
function glow(c,x,y,r,color,a){if(a<=0||r<=0)return;c.save();c.globalAlpha=clamp(a);let g=c.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,'#fff9eb');g.addColorStop(.08,color);g.addColorStop(.4,color+'66');g.addColorStop(1,color+'00');c.fillStyle=g;c.fillRect(x-r,y-r,r*2,r*2);c.restore();}
function cover(c,img,zoom=1,x=W/2,y=H/2){let k=Math.max(W/img.width,H/img.height)*zoom;c.drawImage(img,x-img.width*k/2,y-img.height*k/2,img.width*k,img.height*k);}
function ring(c,x,y,r,t,col,a){c.save();c.translate(x,y);c.rotate(t);c.globalAlpha=clamp(a);c.strokeStyle=col;c.lineWidth=1.2;c.beginPath();c.arc(0,0,r,0,TAU);c.stroke();c.beginPath();c.arc(0,0,r*.93,0,TAU);c.stroke();for(let i=0;i<48;i++){let q=i*TAU/48,l=i%4?7:18;c.beginPath();c.moveTo(Math.cos(q)*(r-l),Math.sin(q)*(r-l));c.lineTo(Math.cos(q)*r,Math.sin(q)*r);c.stroke();}c.restore();}
function draw(c,images,pool,t){
 const th=THEMES[pool]||THEMES.map,opening=smooth((t-1.05)/1.75),entered=smooth((t-2.45)/.7),summon=smooth((t-3.05)/1.5),converge=smooth((t-4.8)/1.2);
 c.clearRect(0,0,W,H);c.fillStyle='#030613';c.fillRect(0,0,W,H);
 c.save();c.globalAlpha=.38+.62*entered;cover(c,images[pool],1.02+.045*t,W/2+Math.sin(t*.35)*13,H/2+Math.sin(t*.22)*5);c.restore();
 // Slow atmospheric drift and concentric mechanism, with distinct per-pool colour.
 c.save();c.globalCompositeOperation='screen';
 let focalY=pool==='cultivation'?270:340;
 glow(c,640,focalY,220+50*Math.sin(t*.8),th.color,.15+.13*entered);
 if(pool==='map'){ring(c,640,340,196+summon*58,t*.16,th.gold,.36*entered);ring(c,640,340,235+summon*62,-t*.09,th.color,.24*entered);}
 if(pool==='dragon_knight'){ring(c,640,328,177+summon*28,-t*.12,th.gold,.2*entered);}
 c.restore();
 // Foreground golden dragon approaches through the open doorway in the immortal pool.
 if(pool==='cultivation' && t>2.5 && t<6.25){
  let u=smooth((t-2.5)/1.5),away=smooth((t-4.65)/1.3),size=(.15+.76*u)*(1+.4*away),dw=1060*size,dh=dw*images.dragon.height/images.dragon.width;
  let x=660-130*u+400*away,y=300+45*u-270*away;
  c.save();c.globalAlpha=clamp(u*1.5)*(1-away*.9);c.translate(x,y);c.rotate(-.13+.15*u-.3*away);
  // Narrow textured strips gently undulate the long body; avoid rigid postcard movement.
  let img=images.dragon,n=90;for(let i=0;i<n;i++){let sx=i*img.width/n,sw=img.width/n+.6,dx=-dw/2+i*dw/n;
   let wave=Math.sin(i/n*7-t*3.2)*7*(1-i/n)*u;c.drawImage(img,sx,0,sw,img.height,dx,-dh/2+wave,dw/n+1,dh);}
  c.restore();
 }
 // Gold leaves physically separate. The composition uses the same source for a seamless closed door.
 if(opening<1){let img=images.gate,shift=opening*690,z=1+.025*t;
  c.save();c.translate(640,360);c.scale(z,z);c.translate(-640,-360);
  c.drawImage(img,0,0,img.width/2,img.height,-shift,0,640,720);
  c.drawImage(img,img.width/2,0,img.width/2,img.height,640+shift,0,640,720);
  c.globalCompositeOperation='screen';glow(c,640,350,75+opening*420,th.gold,.18+.7*smooth(t/1.3));
  let beam=2+smooth(t/1.2)*6+opening*30;let g=c.createLinearGradient(640-beam,0,640+beam,0);g.addColorStop(0,th.gold+'00');g.addColorStop(.5,'#fff2c8');g.addColorStop(1,th.gold+'00');c.fillStyle=g;c.globalAlpha=(1-opening)*.8;c.fillRect(640-beam,20,beam*2,680);c.restore();
 }
 // Depth particles: orbit -> travel -> converge. Summer bubbles and dragon embers have their own trajectories.
 c.save();c.globalCompositeOperation='screen';
 for(let i=0;i<185;i++){
  let seed=rand(i+1),angle=rand(i+700)*TAU+t*(.06+seed*.1),depth=rand(i+1100),radius=80+depth*650;
  let x=640+Math.cos(angle)*radius,y=350+Math.sin(angle)*radius*.6;
  if(pool==='summer')y=((y-t*(25+seed*60))%800+800)%800-40;
  if(pool==='dragon_knight')y=((y-t*(50+seed*80))%800+800)%800-40;
  let a=(.15+.5*seed)*(.25+.75*entered)*(1-smooth((t-6.5)/.5));
  x=x*(1-converge*.91)+640*converge*.91;y=y*(1-converge*.91)+345*converge*.91;
  c.globalAlpha=a;c.strokeStyle=th.color;c.fillStyle=i%5?th.gold:'#ffffff';let r=.6+seed*2.1;
  if(pool==='summer'&&i%4===0){c.lineWidth=.6;c.beginPath();c.arc(x,y,r*2.3,0,TAU);c.stroke();}else{c.beginPath();c.arc(x,y,r,0,TAU);c.fill();}
 }
 // Streaks accelerate into a readable single burst, never a repeated flash.
 if(t>4.7){let k=smooth((t-4.7)/1.2)*(1-smooth((t-6.25)/.6));for(let i=0;i<34;i++){let a=i*TAU/34+t*.08,r=150+rand(i+80)*520;c.globalAlpha=k*(.1+rand(i)*.4);c.strokeStyle=th.color;c.lineWidth=.8+rand(i+60)*1.8;c.beginPath();c.moveTo(640+Math.cos(a)*r,345+Math.sin(a)*r*.6);c.lineTo(640+Math.cos(a)*r*(1-k*.6),345+Math.sin(a)*r*.6*(1-k*.6));c.stroke();}}
 c.restore();
 if(t>5.35){let a=smooth((t-5.35)/.65)*(1-smooth((t-6.15)/.5));glow(c,640,345,120+smooth((t-5.7)/.4)*950,th.gold,a*.85);}
 if(t>6.18){c.fillStyle='rgba(4,8,18,'+smooth((t-6.18)/.82)+')';c.fillRect(0,0,W,H);}
 // Edge vignette remains part of the scene; no baked-in letterbox on adaptive full-screen playback.
 let vig=c.createRadialGradient(640,340,180,640,360,740);vig.addColorStop(0,'#00000000');vig.addColorStop(1,'#02040bb0');c.fillStyle=vig;c.fillRect(0,0,W,H);

}
exports.LotteryFilm={draw,THEMES,W,H,duration:7};
})(typeof module==='object'?module.exports:window);
