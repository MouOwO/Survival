'use strict';
const fs=require('fs'),crypto=require('crypto');const base='design_refs/ui_20h/work/checkpoints';
const files=JSON.parse(fs.readFileSync(base+'/best/manifest.json','utf8')).files;
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');let restored=0;
for(const f of files.filter(x=>x.path.startsWith('panorama/src/')&&/\.(js|css|xml)$/.test(x.path))){
 const current=fs.readFileSync(f.path),saved=fs.readFileSync(base+'/'+f.object);if(hash(current)===f.sha256)continue;
 if(current.toString('utf8').replaceAll('\r\n','\n')!==saved.toString('utf8').replaceAll('\r\n','\n'))throw Error('Substantive change detected, refusing overwrite: '+f.path);
 fs.writeFileSync(f.path,saved);restored++;
}
console.log('UI20H_EXACT_SOURCE_BYTES_PRESERVED',restored,'newline-only differences');
