// Font files are raw addon assets, not Panorama CSS resources. Never install OS fonts.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'..'),kit=path.join(root,'art/ui/development/font_import/source_han_game_fonts');
const original=JSON.parse(fs.readFileSync(path.join(kit,'font_manifest.json'),'utf8'));
const names=['SourceHanSansSC-Regular.otf','SourceHanSansSC-Medium.otf','SourceHanSerifSC-Bold.otf'];
const manifest={version:1,modified_fonts:false,registration:'Dota client custom font directory: panorama/fonts/',
 filename_compatibility:'Radiance-Survival- prefix is accepted by the installed fonts.conf <fontpattern>Radiance</fontpattern>. Font bytes, internal Source Han families, PostScript names and OTF format stay unchanged. No stock font is replaced.',
 native_addon_verification:'pending_in_game',files:[]};
for(const item of original.files.filter(f=>names.includes(path.basename(f.file))||f.file.startsWith('licenses/'))){
 const bytes=fs.readFileSync(path.join(kit,item.file));
 if(crypto.createHash('sha256').update(bytes).digest('hex')!==item.sha256)throw Error('Font/license hash mismatch: '+item.file);
 const relative=item.file.startsWith('fonts/')?'Radiance-Survival-'+path.basename(item.file):item.file;
 for(const base of ['panorama/src/fonts','panorama/fonts']){const dest=path.join(root,base,relative);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,bytes);
  // Remove only a byte-identical file created by the first import, never a user font.
  const old=path.join(root,base,path.basename(item.file));
  if(item.file.startsWith('fonts/')&&fs.existsSync(old)&&crypto.createHash('sha256').update(fs.readFileSync(old)).digest('hex')===item.sha256)fs.unlinkSync(old);
 }
 manifest.files.push({...item,runtime:'panorama/fonts/'+relative});
}
fs.writeFileSync(path.join(root,'panorama/src/ui/font_manifest.json'),JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(root,'panorama/fonts/font_manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('FONT_IMPORT_PASS: 3 unmodified OTFs and both original OFL licenses; no system installation.');
