const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),out=path.join(root,'output/basin_review');
const bake=JSON.parse(fs.readFileSync(path.join(out,'snow_material/bake_report.json'),'utf8'));
if(bake.status!=='complete')throw Error('Slate bake incomplete');
const set=(s,k,v)=>{const re=new RegExp('"'+k+'"\\s*"[^"\\n]*"');return re.test(s)?s.replace(re,'"'+k+'" "'+v+'"'):s.replace(/\n\{/,'\n{\n "'+k+'" "'+v+'"');};
let s=fs.readFileSync(path.join(out,'materials/snow.vmat'),'utf8');
s=set(s,'F_WORLDSPACE_UVS','0');s=set(s,'F_SPECULAR','1');s=set(s,'g_flBumpStrength','.65');s=set(s,'g_flSpecularIntensity','.18');s=set(s,'g_flSpecularBloom','0');
for(let i=0;i<4;i++){
 if(i!==1){s=set(s,'TextureColor'+i,'materials/basin_review/snow_slate_color.png');s=set(s,'TextureNormal'+i,'materials/basin_review/snow_slate_normal.png');s=set(s,'g_vColorTint'+i,'[1 1 1 0]');s=set(s,'TextureRevealMask'+i,'[0.5 0.5 0.5 0]');}
 s=set(s,'g_flTexCoordScale'+i,i===1?'8':'1');s=set(s,'TextureReflectance'+i,i===1?'[0.015 0.015 0.015 1]':'materials/basin_review/snow_slate_reflectance.png');
}
s=set(s,'g_vColorTint1','[.78 .85 .95 0]');
fs.writeFileSync(path.join(out,'materials/snow_authored.vmat'),s);
console.log('Authored slate + controlled snow material prepared');
