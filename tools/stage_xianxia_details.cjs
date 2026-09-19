const fs=require('fs'),path=require('path');
const out=path.resolve(__dirname,'../output/xianxia_kit/detail_pass');
const assets=JSON.parse(fs.readFileSync(path.join(out,'asset_manifest.json')));
const dest=path.join(out,'source_models');fs.mkdirSync(dest,{recursive:true});
const header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->';
for(const a of assets){
 const n=a.name;fs.copyFileSync(path.join(out,'models',n+'.fbx'),path.join(dest,n+'.fbx'));
 if(a.materials.some(m=>!/^materials\/xianxia_kit\/xx_\w+\.vmat$/.test(m)))throw Error('Invalid material slot');
 fs.writeFileSync(path.join(dest,n+'.vmdl'),`${header}\n{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" name="${n}" filename="models/xianxia_kit/${n}.fbx" import_scale=0.01}]},{_class="MaterialGroupList" children=[{_class="DefaultMaterialGroup" remaps=[${a.materials.map(m=>`{from="${m}" to="${m}"}`).join(',')}] use_global_default=false}]}]}}`);
}
let render=fs.readFileSync(path.join(__dirname,'xianxia_kit_render.py'),'utf8').split('# Small playable-looking assembly')[0];
render=render.replace("OUT=os.path.join(ROOT,'output','xianxia_kit')","OUT=os.path.join(ROOT,'output','xianxia_kit','detail_pass')\nos.makedirs(os.path.join(OUT,'previews'),exist_ok=True)").replace('xianxia_library.blend','xianxia_detail_modules.blend').replace("s.name.startswith('Xianxia modular asset library')and len(s.objects)>=26","s.name.startswith('Xianxia detail and junction modules')");
fs.writeFileSync(path.join(out,'render_details.py'),render);
console.log({staged:assets.length});
