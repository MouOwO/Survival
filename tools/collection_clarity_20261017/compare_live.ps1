$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$clarityRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$clarityFrames=@(
 @{label='Original 512 single mip';file='live/wife_before.png'},
 @{label='128 Box mips';file='live/wife_single_candidate.png'},
 @{label='128 prefiltered single mip';file='live/wife_single_mip_candidate.png'}
)
$clarityDir=Join-Path $clarityRepo 'design_refs/collection_clarity_20261017'
$clarityComposite=[Drawing.Bitmap]::new(918,370)
$clarityGraphics=[Drawing.Graphics]::FromImage($clarityComposite)
$clarityFont=[Drawing.Font]::new('Arial',13)
try{
 $clarityGraphics.Clear([Drawing.Color]::FromArgb(30,33,40))
 $clarityGraphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
 $clarityGraphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
 for($clarityIndex=0;$clarityIndex -lt $clarityFrames.Count;$clarityIndex++){
  $clarityFrame=$clarityFrames[$clarityIndex]
  $clarityImage=[Drawing.Bitmap]::new((Join-Path $clarityDir $clarityFrame.file))
  $clarityTile=$clarityImage.Clone([Drawing.Rectangle]::new(344,581,86,86),[Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try{
   $clarityGraphics.DrawString($clarityFrame.label,$clarityFont,[Drawing.Brushes]::White,($clarityIndex*306+8),8)
   $clarityGraphics.DrawImage($clarityTile,[Drawing.Rectangle]::new(($clarityIndex*306+24),50,258,258))
   $clarityTile.Save((Join-Path $clarityDir ('live/sample_'+$clarityIndex+'_native86.png')),[Drawing.Imaging.ImageFormat]::Png)
  }finally{$clarityTile.Dispose();$clarityImage.Dispose()}
 }
 $clarityComposite.Save((Join-Path $clarityDir 'live/single_picture_comparison.png'),[Drawing.Imaging.ImageFormat]::Png)
}finally{$clarityFont.Dispose();$clarityGraphics.Dispose();$clarityComposite.Dispose()}
Write-Output 'Native 86px screenshots cropped; 3x nearest-neighbor diagnostic only; game artwork unchanged.'
