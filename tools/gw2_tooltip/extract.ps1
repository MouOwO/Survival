param(
    [string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ReferencePath = ""
)
$ErrorActionPreference = 'Stop'
# The repository's image tools use Windows PowerShell's GDI+ implementation.
# Delegate from PowerShell 7 so that both entry points produce identical bytes.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $legacyArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-ProjectRoot',$ProjectRoot)
    if ($ReferencePath) { $legacyArguments += @('-ReferencePath',$ReferencePath) }
    & (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') @legacyArguments
    if ($LASTEXITCODE -ne 0) { throw "Tooltip extraction failed in Windows PowerShell: $LASTEXITCODE" }
    return
}
Add-Type -AssemblyName System.Drawing
if (-not ('Gw2TooltipTextureExtraction' -as [type])) {
    $drawingAssemblies = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Color].Assembly.Location) | Select-Object -Unique
    Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

public static class Gw2TooltipTextureExtraction {
    public static int[] Extract(string input, string output, string maskOutput) {
        const int w=354,h=103,radius=2;
        var source=new int[w*h];
        using(var raw=new Bitmap(input)) {
            if(raw.Width!=426 || raw.Height!=177) throw new InvalidOperationException("Reference must be the original 426x177 image.");
            for(int y=0;y<h;y++) for(int x=0;x<w;x++) source[y*w+x]=raw.GetPixel(x+46,y+17).ToArgb();
        }
        var seed=new bool[w*h]; var mask=new bool[w*h]; var depth=new int[w*h];
        int[,] boxes={{4,8,49,27},{4,31,331,49},{4,47,351,65},{4,63,247,81},{4,79,98,96}};
        int seeds=0;
        for(int k=0;k<boxes.GetLength(0);k++)
            for(int y=boxes[k,1];y<boxes[k,3];y++) for(int x=boxes[k,0];x<boxes[k,2];x++) {
                int c=source[y*w+x]; int high=Math.Max((c>>16)&255,Math.Max((c>>8)&255,c&255));
                if(high>90 && !seed[y*w+x]) { seed[y*w+x]=true; seeds++; }
            }
        for(int i=0;i<depth.Length;i++) depth[i]=99;
        for(int y=3;y<h-3;y++) for(int x=3;x<w-3;x++) if(seed[y*w+x]) {
            for(int dy=-2;dy<=2;dy++) for(int dx=-2;dx<=2;dx++) {
                int xx=x+dx,yy=y+dy;
                if(xx<3||yy<3||xx>=w-3||yy>=h-3) continue;
                int d=Math.Max(Math.Abs(dx),Math.Abs(dy)); int id=yy*w+xx;
                mask[id]=true; depth[id]=Math.Min(depth[id],d);
            }
        }
        var donors=new List<int>();
        for(int y=3+radius;y<h-3-radius;y++) for(int x=3+radius;x<w-3-radius;x++) {
            bool clean=true;
            for(int dy=-radius;dy<=radius&&clean;dy++) for(int dx=-radius;dx<=radius;dx++) if(mask[(y+dy)*w+x+dx]) { clean=false; break; }
            if(clean) donors.Add(y*w+x);
        }
        var result=(int[])source.Clone(); var remaining=(bool[])mask.Clone();
        int holes=0; foreach(bool item in mask) if(item) holes++;
        int initialHoles=holes, patches=0;
        while(holes>0) {
            int target=-1,bestKnown=-1;
            for(int y=3;y<h-3;y++) for(int x=3;x<w-3;x++) if(remaining[y*w+x]) {
                int known=0;
                for(int dy=-radius;dy<=radius;dy++) for(int dx=-radius;dx<=radius;dx++) if(!remaining[(y+dy)*w+x+dx]) known++;
                if(known>bestKnown) { target=y*w+x; bestKnown=known; }
            }
            if(target<0 || bestKnown<=0) throw new InvalidOperationException("No original-texture boundary available for clone repair.");
            int tx=target%w,ty=target/w,best=-1; double bestScore=double.MaxValue;
            foreach(int donor in donors) {
                int sx=donor%w,sy=donor/w; double sum=0; int count=0;
                for(int dy=-radius;dy<=radius;dy++) for(int dx=-radius;dx<=radius;dx++) {
                    int targetId=(ty+dy)*w+tx+dx;
                    if(remaining[targetId]) continue;
                    int a=result[targetId],b=source[(sy+dy)*w+sx+dx];
                    int dr=((a>>16)&255)-((b>>16)&255),dg=((a>>8)&255)-((b>>8)&255),db=(a&255)-(b&255);
                    sum+=dr*dr+dg*dg+db*db; count++;
                }
                double distance=(sx-tx)*(sx-tx)+(sy-ty)*(sy-ty);
                double score=sum/Math.Max(1,count)+distance*.004;
                if(score<bestScore) { bestScore=score; best=donor; }
            }
            int bx=best%w,by=best/w;
            for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++) {
                int xx=tx+dx,yy=ty+dy,id=yy*w+xx;
                if(xx<3||yy<3||xx>=w-3||yy>=h-3||!remaining[id]) continue;
                result[id]=source[(by+dy)*w+bx+dx]; remaining[id]=false; holes--;
            }
            patches++;
        }
        using(var clean=new Bitmap(w,h,PixelFormat.Format32bppArgb))
        using(var debug=new Bitmap(w,h,PixelFormat.Format32bppArgb)) {
            for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
                int id=y*w+x; Color a=Color.FromArgb(source[id]),b=Color.FromArgb(result[id]);
                double alpha=depth[id]==2?.65:depth[id]==1?.95:1;
                Color chosen=mask[id]?Color.FromArgb(255,(int)Math.Round(a.R*(1-alpha)+b.R*alpha),(int)Math.Round(a.G*(1-alpha)+b.G*alpha),(int)Math.Round(a.B*(1-alpha)+b.B*alpha)):a;
                clean.SetPixel(x,y,chosen);
                debug.SetPixel(x,y,mask[id]?Color.FromArgb(255,200,40,100):a);
            }
            clean.Save(output,ImageFormat.Png);
            if(!String.IsNullOrEmpty(maskOutput)) debug.Save(maskOutput,ImageFormat.Png);
        }
        return new int[]{seeds,initialHoles,donors.Count,patches};
    }
}
'@
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$referenceOutput=Join-Path $ProjectRoot 'design_refs/gw2_tooltip_v1/reference.png'
if (-not $ReferencePath) { $ReferencePath=$referenceOutput }
$ReferencePath=[IO.Path]::GetFullPath($ReferencePath)
$expectedReferenceHash='291bf9020c15bf2f8265c997248e3d1ad659a1a7f0cebccf2d195d2ea08d43ae'
$referenceHash=(Get-FileHash -LiteralPath $ReferencePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($referenceHash -ne $expectedReferenceHash) { throw 'Input is not the approved original tooltip reference; no assets were changed.' }
$assetOutput=Join-Path $ProjectRoot 'art/ui/sources/custom_game/gw2_tooltip_v1/background.png'
$runtimeOutput=Join-Path $ProjectRoot 'panorama/src/images/custom_game/gw2_tooltip_v1/background.png'
$recipeOutput=Join-Path $ProjectRoot 'art/ui/sources/custom_game/gw2_tooltip_v1/recipe.json'
foreach($target in @($referenceOutput,$assetOutput,$runtimeOutput,$recipeOutput)) { [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null }
if($ReferencePath -ne $referenceOutput) { Copy-Item -LiteralPath $ReferencePath -Destination $referenceOutput }
$stats=[Gw2TooltipTextureExtraction]::Extract($referenceOutput,$assetOutput,'')
Copy-Item -LiteralPath $assetOutput -Destination $runtimeOutput
$recipe=[ordered]@{
    schema='survival.original_tooltip_extract.v1'
    reference=[ordered]@{ file='design_refs/gw2_tooltip_v1/reference.png'; size=@(426,177); sha256=(Get-FileHash -LiteralPath $referenceOutput -Algorithm SHA256).Hash.ToLowerInvariant() }
    output=[ordered]@{ file='art/ui/sources/custom_game/gw2_tooltip_v1/background.png'; panorama_source='panorama/src/images/custom_game/gw2_tooltip_v1/background.png'; size=@(354,103); nine_slice_ltrb=@(3,3,3,3); sha256=(Get-FileHash -LiteralPath $assetOutput -Algorithm SHA256).Hash.ToLowerInvariant() }
    crop_xywh=@(46,17,354,103)
    method='Original-pixel crop, text luminance mask with two-pixel dilation, deterministic clean-original-patch clone repair, one-pixel feather. No generated imagery or solid-color replacement.'
    text_seed_rectangles_xyxy=@(@(4,8,49,27),@(4,31,331,49),@(4,47,351,65),@(4,63,247,81),@(4,79,98,96))
    repair=[ordered]@{ seed_max_channel_threshold=90; dilation_chebyshev_radius=2; preserved_border_pixels=3; unchanged_outside_mask_pixels=(354*103-$stats[1]); donor_patch_size=@(5,5); donor_policy='Only 5x5 patches containing no text-mask pixels; squared RGB context error plus spatial distance penalty 0.004'; copy_patch_size=@(3,3); feather_alpha_by_dilation=@(1,.95,.65); text_seed_pixels=$stats[0]; repair_pixels=$stats[1]; donor_patches=$stats[2]; clone_steps=$stats[3] }
    regenerate='powershell -NoProfile -ExecutionPolicy Bypass -File tools/gw2_tooltip/extract.ps1'
}
[IO.File]::WriteAllText($recipeOutput,($recipe|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ($recipe|ConvertTo-Json -Depth 10)
