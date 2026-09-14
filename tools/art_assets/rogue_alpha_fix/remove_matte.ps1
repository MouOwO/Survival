$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
public class RogueMatte {
 public static int Run(string src,string dst) {
  using(var original=new Bitmap(src)) using(var output=new Bitmap(original.Width,original.Height,PixelFormat.Format32bppArgb)) {
   using(var g=Graphics.FromImage(output)){g.DrawImageUnscaled(original,0,0);}
   int w=output.Width,h=output.Height,count=0;var seen=new bool[w*h];var q=new Queue<int>();
   for(int x=0;x<w;x++){q.Enqueue(x);q.Enqueue((h-1)*w+x);}for(int y=0;y<h;y++){q.Enqueue(y*w);q.Enqueue(y*w+w-1);}
   while(q.Count>0){int i=q.Dequeue();if(seen[i])continue;seen[i]=true;int x=i%w,y=i/w;Color c=original.GetPixel(x,y);
    int hi=Math.Max(c.R,Math.Max(c.G,c.B)),lo=Math.Min(c.R,Math.Min(c.G,c.B));
    // Only neutral checkerboard connected to the canvas exterior; gold/teal are barriers.
    if(hi-lo>25||lo<70)continue;
    output.SetPixel(x,y,Color.FromArgb(0,c.R,c.G,c.B));count++;
    if(x>0)q.Enqueue(i-1);if(x+1<w)q.Enqueue(i+1);if(y>0)q.Enqueue(i-w);if(y+1<h)q.Enqueue(i+w);
   }
   output.Save(dst,ImageFormat.Png);return count;
  }
 }
}
'@
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source=Join-Path $root 'art/ui/sources/custom_game/rogue_clean_base_v1/blank.png'
$temp=Join-Path $PSScriptRoot 'blank.fixed.png'
$count=[RogueMatte]::Run((Join-Path $PSScriptRoot 'blank.before.png'),$temp)
if($count -lt 1000 -or $count -gt 150000){throw "Unexpected matte area: $count"}
Copy-Item -LiteralPath $temp -Destination $source -Force
Write-Output "Removed $count exterior matte pixels; original RGB pixels preserved."
