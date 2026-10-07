// Native Dota textures are shared by skills, shops, tooltips and inventory.
// Keep the legacy build entry point, but use the single maintained CSV mapping.
const {spawnSync}=require('child_process');
const path=require('path');
const result=spawnSync(process.env.PYTHON||'python',[
    '-X','utf8',path.join(__dirname,'restore_native_ui_icons.py')
],{cwd:path.resolve(__dirname,'..'),stdio:'inherit',env:{...process.env,PYTHONIOENCODING:'utf-8'}});
if(result.error)throw result.error;
process.exit(result.status===null?1:result.status);
