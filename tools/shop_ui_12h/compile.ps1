$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/Survival/panorama'
$backup=Join-Path $repo ('output/commerce_ui_12h/before_compile_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$sources=@('scripts/custom_game/common/commerce_art_manifest.js','scripts/custom_game/common/commerce_components.js','scripts/custom_game/commerce_remaining_5d5c1152eb.js','styles/custom_game/common/commerce_jade.css','layout/custom_game/commerce_resources.xml','layout/custom_game/survival_hud.xml')
foreach($rel in $sources){
    $dest=Join-Path $content $rel
    if(Test-Path -LiteralPath $dest){
        $saved=Join-Path $backup $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
        Copy-Item -LiteralPath $dest -Destination $saved -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo ('panorama/src/'+$rel)) -Destination $dest -Force
}
$imageSource=Join-Path $repo 'art/ui/sources/custom_game/commerce_jade_v1'
$imageDest=Join-Path $content 'images/custom_game/commerce_jade_v1'
# Only the new material family is synchronized, no broad image cleanup or source replacement.
foreach($file in Get-ChildItem -LiteralPath $imageSource -Recurse -File){
    $relative=$file.FullName.Substring($imageSource.Length).TrimStart('\')
    $dest=Join-Path $imageDest $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
}
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$log=Join-Path $backup 'compile.log'
foreach($layout in @('commerce_resources.xml','survival_hud.xml')){
    $oneLog=Join-Path $backup ('compile_'+$layout+'.log')
    & $compiler -i (Join-Path $content ('layout/custom_game/'+$layout)) -game (Join-Path $engine 'game/dota') -fshallow -nop4 *> $oneLog
    if($LASTEXITCODE -ne 0){throw "Compilation failed; inspect $oneLog"}
    $text=Get-Content -LiteralPath $oneLog -Raw
    if($text -notmatch '0 failed'){throw "Compilation did not report zero failed; inspect $oneLog"}
    Add-Content -LiteralPath $log -Value $text
}
$results=@()
foreach($rel in $sources){
    $source=Join-Path $repo ('panorama/src/'+$rel)
    $dest=Join-Path $content $rel
    $runtime=$rel.Replace('.js','.vjs_c').Replace('.css','.vcss_c').Replace('.xml','.vxml_c')
    $compiled=Join-Path $repo ('panorama/'+$runtime)
    if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw "Source copy mismatch: $rel"}
    if(-not (Test-Path -LiteralPath $compiled)){throw "Compiled output missing: $rel"}
    $results+=@{source=$rel;sha256=(Get-FileHash -LiteralPath $source).Hash;compiled_sha256=(Get-FileHash -LiteralPath $compiled).Hash}
}
@{time=(Get-Date -Format o);backup=$backup;log=$log;files=$results;scope='native compiler, not visual acceptance'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $repo 'design_refs/shop_ui_12h/work/compile_report.json') -Encoding UTF8
Get-Content -LiteralPath $log -Tail 12
