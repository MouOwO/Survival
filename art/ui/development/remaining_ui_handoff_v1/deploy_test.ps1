param([switch]$ReuseVerifiedTextures)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$engine=[IO.Path]::GetFullPath((Join-Path $repo '../../..'))
$content=Join-Path $engine 'content/dota_addons/survival_ui_handoff_v1/panorama'
$game=Join-Path $engine 'game/dota_addons/survival_ui_handoff_v1/panorama'
if(-not(Test-Path -LiteralPath $content) -or -not(Test-Path -LiteralPath $game)){throw 'Missing isolated test addon'}
$build=Get-Content (Join-Path $PSScriptRoot 'build.json') -Raw | ConvertFrom-Json
$source=Join-Path $PSScriptRoot 'candidate/panorama'
$previousTextures=$null
if($ReuseVerifiedTextures){
 $previousTextures=Get-Content (Join-Path $PSScriptRoot 'texture_audit.json') -Raw | ConvertFrom-Json
 $previousMasters=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 # Reuse verified old textures while compiling newly added art recipes.
 foreach($entry in $previousTextures.textures){
  # Retired versioned art remains on disk for rollback, but is not reused.
  if($build.textureInputs -notcontains $entry.source){continue}
  if((Get-FileHash -LiteralPath (Join-Path $game ($entry.source+'_c'))).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'Deployed texture changed; full compile required'}
  $recipe=[IO.File]::ReadAllText((Join-Path $content $entry.source))
  $master=[regex]::Match($recipe,'"m_fileName"\s+"string"\s+"panorama/([^"]+)"')
  if($master.Success){[void]$previousMasters.Add($master.Groups[1].Value)}
 }
 foreach($asset in (Get-Content (Join-Path $PSScriptRoot 'asset_audit.json') -Raw | ConvertFrom-Json | Where-Object {$_.kind -in @('compiled_icon_recipe','generated_archive_icon','generated_rogue_art')})){
  $oldSource=Join-Path $content $asset.runtime
  $wasCompiled=$previousTextures.textures.source -contains $asset.runtime
  $masterWasCompiled=$previousMasters.Contains($asset.runtime)
  if(($wasCompiled -or $masterWasCompiled) -and ((-not(Test-Path -LiteralPath $oldSource)) -or (Get-FileHash -LiteralPath $oldSource).Hash.ToLowerInvariant() -ne $asset.sha256)){throw 'Previously verified icon source changed; full compile required'}
 }
}
$hudPath=Join-Path $content 'layout/custom_game/survival_hud.xml'
$hudBytes=[Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($hudPath).Replace("`r`n","`n"))
$hashAlgorithm=[Security.Cryptography.SHA256]::Create()
try{$currentHudHash=[Convert]::ToHexString($hashAlgorithm.ComputeHash($hudBytes)).ToLowerInvariant()}finally{$hashAlgorithm.Dispose()}
if($currentHudHash -ne $build.hudSourceHash){throw 'Test HUD changed after prepare; rebuild before deploying'}
$protected=@(Get-ChildItem (Join-Path $repo 'panorama') -File -Recurse)
$protected+=@(Get-ChildItem $game -File -Recurse | Where-Object {$_.Name -match 'archive|handoff_hud|handoff_geometry' -and $_.Name -ne 'archive.vxml_c'})
$baseline=@($protected | ForEach-Object {@{path=$_.FullName;hash=(Get-FileHash -LiteralPath $_.FullName).Hash}})
$backup=Join-Path $PSScriptRoot ('backups/'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $content 'layout/custom_game/survival_hud.xml') -Destination (Join-Path $backup 'survival_hud.xml')
Copy-Item -LiteralPath (Join-Path $content 'layout/custom_game/archive.xml') -Destination (Join-Path $backup 'archive.xml')
Copy-Item -LiteralPath (Join-Path $content 'layout/custom_game/rogue_reward_ui.xml') -Destination (Join-Path $backup 'rogue_reward_ui.xml')
foreach($rel in $build.inputs){
 $destination=Join-Path $content $rel
 New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $source $rel) -Destination $destination -Force
}
foreach($asset in (Get-Content (Join-Path $PSScriptRoot 'asset_audit.json') -Raw | ConvertFrom-Json)){
 $destination=Join-Path $content $asset.runtime
 New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
 Copy-Item -LiteralPath (Join-Path $source $asset.runtime) -Destination $destination -Force
 if((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -ne $asset.sha256){throw 'Asset mismatch'}
}
$compiler=Join-Path $engine 'game/bin/win64/resourcecompiler.exe'
$textureAudit=@();$textureDone=0
$compileInputs=@($build.textureInputs)+@($build.inputs)
if($ReuseVerifiedTextures){$textureAudit=@($previousTextures.textures | Where-Object {$build.textureInputs -contains $_.source});$compileInputs=@($build.textureInputs | Where-Object {$previousTextures.textures.source -notcontains $_})+@($build.inputs)}
foreach($rel in $compileInputs){
 $output=& $compiler -i (Join-Path $content $rel) -game (Join-Path $engine 'game/dota') -f -nop4 2>&1
 $code=$LASTEXITCODE
 $logLeaf=[IO.Path]::GetFileName($rel)
 if($rel.EndsWith('.vtex')){$logLeaf=(Split-Path -Leaf (Split-Path -Parent $rel))+'_'+$logLeaf}
 $output | Out-File (Join-Path $PSScriptRoot ('compile_'+$logLeaf+'.log')) -Encoding utf8
 if($rel.EndsWith('.vtex')){
  $textureDone++
  if($textureDone%32 -eq 0 -or $textureDone -eq $build.textureInputs.Count){"Icon textures: $textureDone/$($build.textureInputs.Count)"}
  $compiledFile=Join-Path $game ($rel+'_c')
  if(-not(Test-Path -LiteralPath $compiledFile)){throw "Compiled texture missing: $rel"}
  $details=[regex]::Match(($output -join "`n"),'Encoding (\d+)x(\d+)x\d+ texture to (\w+)')
  if(-not $details.Success -or $details.Groups[3].Value -ne 'BGRA8888'){throw "Texture format/size not verified: $rel"}
  $textureAudit+=@{source=$rel;width=[int]$details.Groups[1].Value;height=[int]$details.Groups[2].Value;format=$details.Groups[3].Value;bytes=(Get-Item -LiteralPath $compiledFile).Length;sha256=(Get-FileHash -LiteralPath $compiledFile).Hash.ToLowerInvariant()}
 }else{$output | Select-String 'OK:|ERROR|failed' | ForEach-Object {$_.Line}}
 if($code -ne 0){throw "Compile failed: $rel"}
}
@{version=$build.version;textures=$textureAudit} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'texture_audit.json') -Encoding utf8
foreach($entry in $baseline){if((Get-FileHash -LiteralPath $entry.path).Hash -ne $entry.hash){throw "Protected file changed: $($entry.path)"}}
@{version=$build.version;protectedFiles=$baseline.Count;formalUiUnchanged=$true;acceptedTestModulesUnchanged=$true;backup=$backup;time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'deployment_verification.json') -Encoding utf8
'LOTTERY_TEST_DEPLOY_PASS: formal UI and accepted test archive/HUD modules unchanged'
