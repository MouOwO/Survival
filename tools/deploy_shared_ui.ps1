param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$gameRoot=Split-Path -Parent (Split-Path -Parent $repo)
$engineRoot=Split-Path -Parent $gameRoot
$content=Join-Path $engineRoot 'content/dota_addons/Survival/panorama'
$source=Join-Path $repo 'panorama/src'
$registry=Get-Content -LiteralPath (Join-Path $repo 'art/ui/development/ui_reuse_import/runtime_registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$files=Get-Content -LiteralPath (Join-Path $repo 'art/ui/development/ui_reuse_import/page_files.json') -Raw | ConvertFrom-Json
$files+=@('scripts/custom_game/common/ui_registry.js','scripts/custom_game/common/ui_components.js','styles/custom_game/common/ui_assets.css','styles/custom_game/common/ui_components.css')
$files+=@('scripts/custom_game/common/ui_typography.js','styles/custom_game/common/ui_typography.css','styles/custom_game/common/font_test.css','layout/custom_game/font_test.xml')
$fontManifest=Get-Content -LiteralPath (Join-Path $source 'ui/font_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fontFiles=@($fontManifest.files | ForEach-Object {$_.runtime.Substring('panorama/'.Length)})
foreach($font in $fontManifest.files){
 $relative=$font.runtime.Substring('panorama/'.Length)
 $raw=Join-Path $source $relative
 if((Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash.ToLowerInvariant() -ne $font.sha256){throw "Font/license hash mismatch: $relative"}
}
$assets=@($registry.assets.psobject.Properties | Where-Object {$_.Value.runtime.StartsWith('ui/')})
$images=@($assets | ForEach-Object {'images/'+$_.Value.runtime})
$prepared=@{}
foreach($f in $files){
 $p=Join-Path $source $f
 if(-not(Test-Path -LiteralPath $p)){throw "Missing source $f"}
 $text=Get-Content -LiteralPath $p -Raw -Encoding UTF8
 $text=[regex]::Replace($text,'ui-resource://([a-zA-Z0-9_.-]+)',{param($m)
   $entry=$registry.assets.psobject.Properties[$m.Groups[1].Value]
   if(-not $entry){throw "Unknown resource ID $($m.Value)"}
   return 'file://{images}/'+$entry.Value.runtime
 })
 if($f.EndsWith('.xml')){
   [xml]$xml=$text
   $old=Join-Path $content $f
   if(Test-Path -LiteralPath $old){[xml]$live=Get-Content -LiteralPath $old -Raw -Encoding UTF8
    foreach($node in $live.SelectNodes('//*[@id]')){
     $next=$xml.SelectSingleNode('//*[@id="'+$node.id+'"]')
     if(-not $next){throw "Lost live panel ID $f : $($node.id)"}
     foreach($attr in @('onactivate','onmouseover','onmouseout')){if($node.HasAttribute($attr) -and $node.GetAttribute($attr) -ne $next.GetAttribute($attr)){throw "Changed live handler $f : $($node.id) $attr"}}
    }
   }
 }
 $prepared[$f]=$text
}
foreach($a in $registry.assets.psobject.Properties){
 $r=$a.Value.runtime
 $candidate=Join-Path $source ('images/'+$r)
 if(-not(Test-Path -LiteralPath $candidate)){$candidate=Join-Path $content ('images/'+$r)}
 if(-not(Test-Path -LiteralPath $candidate)){throw "Missing registered asset $($a.Name): $r"}
 if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $a.Value.source_sha256){throw "Resource changed without registry rebuild: $($a.Name)"}
}
if($CheckOnly){Write-Output "SHARED_UI_CHECK_PASS: $($files.Count) sources; $($assets.Count) canonical assets; live IDs/handlers preserved";exit 0}
$backup=Join-Path $repo ('art/ui/development/ui_reuse_import/backups/'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force $backup | Out-Null
$all=@($files)+$images+$fontFiles
foreach($f in $all){$dest=Join-Path $content $f;if(Test-Path -LiteralPath $dest){$old=Join-Path $backup $f;New-Item -ItemType Directory -Force (Split-Path -Parent $old)|Out-Null;Copy-Item -LiteralPath $dest -Destination $old};New-Item -ItemType Directory -Force (Split-Path -Parent $dest)|Out-Null
 if($prepared.ContainsKey($f)){[IO.File]::WriteAllText($dest,$prepared[$f],[Text.UTF8Encoding]::new($false))}else{Copy-Item -LiteralPath (Join-Path $source $f) -Destination $dest -Force}
}
# OTF and OFL files are raw addon assets; resourcecompiler does not register fonts.
foreach($relative in $fontFiles){
 $runtime=Join-Path $repo ('panorama/'+$relative)
 New-Item -ItemType Directory -Force (Split-Path -Parent $runtime)|Out-Null
 Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $runtime -Force
}
# Retire only byte-identical, unprefixed files from the initial import. The native
# filename filter ignores them, and shipping both would double the font payload.
foreach($font in $fontManifest.files){
 if(-not $font.file.StartsWith('fonts/')){continue}
 $old=Join-Path $content $font.file
 if(Test-Path -LiteralPath $old){
  if((Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash.ToLowerInvariant() -eq $font.sha256){
   $oldBackup=Join-Path $backup $font.file
   New-Item -ItemType Directory -Force (Split-Path -Parent $oldBackup)|Out-Null
   Copy-Item -LiteralPath $old -Destination $oldBackup
   Remove-Item -LiteralPath $old
  }
 }
}
$backup | Set-Content -LiteralPath (Join-Path $repo 'art/ui/development/ui_reuse_import/last_backup.txt') -Encoding UTF8
$log=Join-Path $repo 'art/ui/development/ui_reuse_import/compile.log'
'' | Set-Content -LiteralPath $log
# lottery_window.xml is the authoring fragment embedded in survival_hud.xml, not a standalone <root> layout.
$compile=@($files | Where-Object {$_ -like 'scripts/*'})+@($files | Where-Object {$_ -like 'styles/*'})+@($files | Where-Object {$_ -like 'layout/*' -and $_ -ne 'layout/custom_game/lottery_window.xml'})
foreach($f in $compile){
 $result=& (Join-Path $gameRoot 'bin/win64/resourcecompiler.exe') -i (Join-Path $content $f) -game (Join-Path $gameRoot 'dota') -f 2>&1
 $exitCode=$LASTEXITCODE
 $result | Add-Content -LiteralPath $log
 if($exitCode -ne 0){throw "Compile failed: $f. Log: $log. Source backup: $backup"}
}
foreach($a in $assets){$runtime=$a.Value.runtime;$artifact=Join-Path $repo ('panorama/images/'+$runtime.Substring(0,$runtime.Length-4)+'_png.vtex_c');if(-not(Test-Path -LiteralPath $artifact)){throw "Missing canonical runtime image $artifact"}}
Write-Output "SHARED_UI_DEPLOY_PASS: $($files.Count) sources compiled, $($assets.Count) canonical textures verified. Backup: $backup"
