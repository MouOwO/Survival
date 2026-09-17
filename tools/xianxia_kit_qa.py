"""Validate exported data, including periodic boundary gradients and alpha edges."""
import bpy,os,json,numpy as np,zlib,struct
OUT=os.path.abspath('output/xianxia_kit');reports={'materials':[],'clouds':[]}
def read(p):
 im=bpy.data.images.load(p,check_existing=False);im.colorspace_settings.name='Non-Color'
 a=np.array(im.pixels[:],dtype=np.float32).reshape(im.size[1],im.size[0],4)[::-1].copy();bpy.data.images.remove(im);return a
def png(path,a):
 a=np.asarray(np.clip(a,0,1)*255+.5,dtype=np.uint8);h,w,c=a.shape
 def ch(t,d):return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
 open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('!2I5B',w,h,8,6 if c==4 else 2,0,0,0))+ch(b'IDAT',zlib.compress(b''.join(b'\0'+r.tobytes()for r in a)))+ch(b'IEND',b''))
for m in json.load(open(os.path.join(OUT,'material_manifest.json'))):
 a=read(os.path.join(OUT,'materials',m['name']+'_color.png'))[:,:,:3];n=read(os.path.join(OUT,'materials',m['name']+'_normal.png'))[:,:,:3]*2-1
 ratios=[]
 for axis in [0,1]:
  seam=np.abs(np.take(a,0,axis)-np.take(a,-1,axis)).mean();inside=np.abs(np.diff(a,axis=axis)).mean();ratios.append(float(seam/max(inside,1e-7)))
 error=float(np.max(np.abs(np.linalg.norm(n,axis=2)-1)))
 reports['materials'].append({'name':m['name'],'seamToSameAxisInterior':ratios,'normalUnitMaxError':error,'finite':bool(np.isfinite(n).all()),'pass':max(ratios)<3 and error<.012})
if os.path.isfile(os.path.join(OUT,'clouds/cloud_manifest.json')):
 status=json.load(open(os.path.join(OUT,'clouds/cloud_manifest.json')))
 if status['complete']:
  for m in status['items']:
   a=read(os.path.join(OUT,'clouds',m['name']+'.png'));alpha=a[:,:,3];h,w=alpha.shape
   edge=float(max(alpha[:4].max(),alpha[-4:].max(),alpha[:,:4].max(),alpha[:,-4:].max()));nz=np.argwhere(alpha>.01)
   rec={'name':m['name'],'borderAlphaMax':edge,'visibleFraction':float((alpha>.01).mean()),'softEdgePixels':int(((alpha>.01)&(alpha<.95)).sum()),'pass':edge==0 and len(nz)>100}
   reports['clouds'].append(rec)
   yy,xx=np.indices((h,w));checker=np.where(((xx//48+yy//48)%2)[:,:,None],.30,.48)*np.ones((h,w,3))
   for suffix,bg in [('checker',checker),('dark',np.full((h,w,3),.075)),('light',np.full((h,w,3),.86))]:
    # Blender pixels are premultiplied for alpha images; unpremultiply safely.
    rgb=np.divide(a[:,:,:3],alpha[:,:,None],out=np.zeros_like(a[:,:,:3]),where=alpha[:,:,None]>.0001)
    png(os.path.join(OUT,'previews',m['name']+'_'+suffix+'.png'),np.clip(rgb,0,1)*alpha[:,:,None]+bg*(1-alpha[:,:,None]))
json.dump(reports,open(os.path.join(OUT,'validation.json'),'w'),indent=2)
print(json.dumps(reports))
