$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'panorama/src/images/custom_game/shop_v2/inventory_manifest.json') | ConvertFrom-Json
$dest=Join-Path $repo 'panorama/src/images/items/survival_shop_v2'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Add-Type -AssemblyName System.Drawing
# Deterministic sprite packaging from the approved atlas, no artwork changes.
foreach($group in ($manifest.images | Group-Object atlas)){
 $atlas=[Drawing.Bitmap]::FromFile((Join-Path $repo ('panorama/src/images/custom_game/shop_v2/'+$group.Name+'.png')))
 try {foreach($cell in $group.Group){
  $col=$cell.index % $cell.grid; $row=[Math]::Floor($cell.index/$cell.grid)
  $x=[int][Math]::Round($col*$atlas.Width/$cell.grid);$y=[int][Math]::Round($row*$atlas.Height/$cell.grid)
  $right=[int][Math]::Round(($col+1)*$atlas.Width/$cell.grid);$bottom=[int][Math]::Round(($row+1)*$atlas.Height/$cell.grid)
  $rect=[Drawing.Rectangle]::new($x,$y,$right-$x,$bottom-$y)
  $tile=$atlas.Clone($rect,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try{$tile.Save((Join-Path $dest $cell.file),[Drawing.Imaging.ImageFormat]::Png)}finally{$tile.Dispose()}
 }}finally{$atlas.Dispose()}
}
Write-Output ('Packaged '+$manifest.images.Count+' inventory textures')
