param(
    [string]$SourceTga = 'art/maps/minimap/template_map_native.tga',
    [string]$WaterArt = 'art/maps/minimap/ocean_style_reference.png',
    [string]$OutputTga = 'art/maps/minimap/template_map_ocean.tga',
    [string]$Preview = 'output/minimap_ocean_preview.png'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class MinimapOceanBuilder {
 public static void Build(string input,string art,string output,string preview) {
  byte[] source=File.ReadAllBytes(input), result=(byte[])source.Clone();
  int width=BitConverter.ToUInt16(source,12),height=BitConverter.ToUInt16(source,14),channels=source[16]/8,offset=18+source[0];
  if(source[1]!=0 || source[2]!=2 || width!=height || (channels!=3 && channels!=4)) throw new Exception("Expected square uncompressed TGA");
  bool top=(source[17]&32)!=0;
  int count=width*height; bool[] candidate=new bool[count], ocean=new bool[count];
  for(int y=0;y<height;y++) for(int x=0;x<width;x++) {
   int i=y*width+x,p=offset+((top?y:height-1-y)*width+x)*channels;
   int b=source[p],g=source[p+1],r=source[p+2];
   // Only saturated blue-green water connected to the outside ocean.
   // Isolated cyan room art and inland pools cannot enter this mask.
   candidate[i]=g>=25 && b>=25 && g<=180 && b<=200 && r<Math.Min(g,b)*0.48 && g>b*0.70 && g<b*1.35;
  }
  int[] queue=new int[count];int head=0,tail=0;
  for(int y=0;y<height;y++)for(int x=0;x<width;x++)if(x==0||y==0||x==width-1||y==height-1) {
   int i=y*width+x;if(candidate[i]&&!ocean[i]){ocean[i]=true;queue[tail++]=i;}
  }
  while(head<tail){int i=queue[head++],x=i%width,y=i/width;
   if(x>0) Visit(i-1,candidate,ocean,queue,ref tail);
   if(x+1<width) Visit(i+1,candidate,ocean,queue,ref tail);
   if(y>0) Visit(i-width,candidate,ocean,queue,ref tail);
   if(y+1<height) Visit(i+width,candidate,ocean,queue,ref tail);
  }
  if(tail<count*0.35 || tail>count*0.80)throw new Exception("Unexpected ocean mask coverage: "+tail);
  using(Bitmap texture=new Bitmap(art)) {
   // Sample only a clean ocean strip from the generated reference, never its land.
   int sx=(int)(texture.Width*.33),sy=(int)(texture.Height*.52),sw=(int)(texture.Width*.40),sh=(int)(texture.Height*.08);
   Color[] patch=new Color[sw*sh];for(int y=0;y<sh;y++)for(int x=0;x<sw;x++){ Color sample=texture.GetPixel(sx+x,sy+y); if(sample.R>75 || sample.G>120 || sample.B>155 || sample.B<sample.R*1.3) throw new Exception("Water patch contains non-water detail"); patch[y*sw+x]=sample; }
   for(int y=0;y<height;y++)for(int x=0;x<width;x++) {
    int i=y*width+x;if(!ocean[i])continue;
    int p=offset+((top?y:height-1-y)*width+x)*channels;
    Color c=patch[Mirror(y,sh)*sw+Mirror(x,sw)];
    double depth=.83+.32*Math.Min(1.0,source[p+1]/145.0);
    result[p]=Channel(c.B*depth);result[p+1]=Channel(c.G*depth);result[p+2]=Channel(c.R*depth);
   }
  }
  int changed=0;
  for(int y=0;y<height;y++)for(int x=0;x<width;x++){
   int i=y*width+x,p=offset+((top?y:height-1-y)*width+x)*channels;
   bool difference=false;for(int k=0;k<channels;k++)if(source[p+k]!=result[p+k])difference=true;
   if(difference&&!ocean[i])throw new Exception("Protected terrain changed");if(difference)changed++;
  }
  File.WriteAllBytes(output,result);
  using(Bitmap image=new Bitmap(width,height,PixelFormat.Format24bppRgb)){
   BitmapData data=image.LockBits(new Rectangle(0,0,width,height),ImageLockMode.WriteOnly,PixelFormat.Format24bppRgb);
   byte[] rgb=new byte[data.Stride*height];
   for(int y=0;y<height;y++)for(int x=0;x<width;x++){
    int p=offset+((top?y:height-1-y)*width+x)*channels,q=y*data.Stride+x*3;
    rgb[q]=result[p];rgb[q+1]=result[p+1];rgb[q+2]=result[p+2];
   }
   Marshal.Copy(rgb,0,data.Scan0,rgb.Length);image.UnlockBits(data);
   using(Bitmap small=new Bitmap(512,512))using(Graphics graphics=Graphics.FromImage(small)){
    graphics.DrawImage(image,0,0,512,512);small.Save(preview,ImageFormat.Png);
   }
  }
  Console.WriteLine("OCEAN_BUILD_PASS size="+width+"x"+height+" water_pixels="+tail+" changed="+changed+" protected_terrain_pixels="+(count-tail)+" protected_changes=0");
 }
 static void Visit(int i,bool[] candidate,bool[] ocean,int[] queue,ref int tail){if(candidate[i]&&!ocean[i]){ocean[i]=true;queue[tail++]=i;}}
 static int Mirror(int p,int size){p%=size*2;return p<size?p:size*2-1-p;}
 static byte Channel(double value){return (byte)Math.Max(0,Math.Min(255,Math.Round(value)));}
}
"@
[MinimapOceanBuilder]::Build([IO.Path]::GetFullPath($SourceTga), (Join-Path (Get-Location) $WaterArt), (Join-Path (Get-Location) $OutputTga), (Join-Path (Get-Location) $Preview))
