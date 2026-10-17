[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$Ids, [ValidateSet('v3','v4','v5')][string]$TextureVersion='v5', [switch]$CheckOnly)
$ErrorActionPreference='Stop'
$portraitRepo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portraitEngine=[IO.Path]::GetFullPath((Join-Path $portraitRepo '../../..'))
$portraitContent=Join-Path $portraitEngine 'content/dota_addons/survival/panorama/images/custom_game'
$portraitCompiler=Join-Path $portraitEngine 'game/bin/win64/resourcecompiler.exe'
$portraitManifest=Get-Content -LiteralPath (Join-Path $portraitRepo 'data/ui/archive_portraits_v3.json') -Raw -Encoding UTF8|ConvertFrom-Json
$portraitCatalogText=Get-Content -LiteralPath (Join-Path $portraitRepo 'panorama/src/scripts/custom_game/icons_remaining_5d5c1152eb.js') -Raw -Encoding UTF8
$portraitCatalogMatch=[regex]::Match($portraitCatalogText,'entries=(\[[^\r\n]+\]);')
if(-not $portraitCatalogMatch.Success){throw 'Formal portrait runtime catalog is missing.'}
$portraitCatalog=@($portraitCatalogMatch.Groups[1].Value|ConvertFrom-Json)
$portraitSocial=@(Import-Csv -LiteralPath (Join-Path $portraitRepo 'data/csv/存档系统/archive_social_items.csv') -Encoding UTF8|Where-Object {$_.enabled -eq '1' -and $_.pool_id -in @('friend','ex')})
$portraitIcons=@(Import-Csv -LiteralPath (Join-Path $portraitRepo 'data/csv/存档系统/archive_item_icons.csv') -Encoding UTF8|Where-Object {$_.enabled -eq '1'})
if($portraitSocial.Count -ne 80 -or @($portraitSocial.item_id|Select-Object -Unique).Count -ne 80 -or @($portraitManifest.PSObject.Properties).Count -ne 80){throw 'Expected exactly eighty formal portrait identities.'}
foreach($portraitItem in $portraitSocial){
    $portraitRow=@($portraitCatalog|Where-Object {$_.item_id -eq $portraitItem.item_id -and $_.category_id -eq $portraitItem.pool_id -and $_.enabled -eq '1'})
    $portraitIcon=@($portraitIcons|Where-Object {$_.item_id -eq $portraitItem.item_id -and $_.category_id -eq $portraitItem.pool_id})
    $portraitOriginal=$portraitManifest.PSObject.Properties[$portraitItem.item_id].Value
    if($portraitRow.Count -ne 1 -or $portraitIcon.Count -ne 1 -or -not $portraitOriginal -or $portraitRow[0].icon_path -ne $portraitOriginal.icon_path -or $portraitIcon[0].icon_path -ne $portraitOriginal.icon_path -or $portraitRow[0].runtime_uri -ne $portraitOriginal.runtime_uri -or $portraitRow[0].small_runtime_uri -ne $portraitOriginal.runtime_uri -or $portraitRow[0].sha256 -ne $portraitOriginal.sha256){throw "Formal portrait mapping differs: $($portraitItem.item_id)"}
}
if(-not $Ids.Count -or @($Ids|Select-Object -Unique).Count -ne $Ids.Count){throw 'Choose distinct formal portrait IDs.'}
$portraitRecords=@()
foreach($portraitId in $Ids){
    if($portraitId -notmatch '^(?:friend|ex)_(?:0[1-9]|[1-3][0-9]|40)$'){throw "Unexpected portrait ID: $portraitId"}
    $portraitReceipt=$portraitManifest.PSObject.Properties[$portraitId].Value
    if(-not $portraitReceipt){throw "Missing original portrait receipt: $portraitId"}
    $portraitImage=Join-Path $portraitRepo "panorama/src/images/custom_game/archive_portraits_v3/$portraitId.png"
    $portraitTextureName='head_'+$TextureVersion+'_'+$portraitId
    $portraitRecipe=Join-Path $portraitRepo "panorama/src/images/custom_game/archive_gpu_regular/$portraitTextureName.vtex"
    $portraitRecipeText=Get-Content -LiteralPath $portraitRecipe -Raw -Encoding UTF8
    if((Get-FileHash -LiteralPath $portraitImage -Algorithm SHA256).Hash.ToLowerInvariant() -ne $portraitReceipt.sha256){throw "Original portrait SHA differs: $portraitId"}
    if($portraitRecipeText -notmatch ('"m_fileName"\s+"string"\s+"panorama/images/custom_game/archive_portraits_v3/'+[regex]::Escape($portraitId)+'\.png"')){throw "Recipe image identity differs: $portraitId"}
    if($portraitReceipt.runtime_uri -notin @("s2r://panorama/images/custom_game/archive_gpu_regular/head_v3_$portraitId.vtex","s2r://panorama/images/custom_game/archive_gpu_regular/head_v4_$portraitId.vtex","s2r://panorama/images/custom_game/archive_gpu_regular/head_v5_$portraitId.vtex")){throw "Runtime portrait URI differs: $portraitId"}
    if($TextureVersion -eq 'v5'){
        $portraitPng=[IO.File]::ReadAllBytes($portraitImage)
        if($portraitPng.Length -lt 24 -or [BitConverter]::ToString($portraitPng,0,8) -ne '89-50-4E-47-0D-0A-1A-0A'){throw "Original portrait is not PNG: $portraitId"}
        $portraitSourceWidth=([int]$portraitPng[16]*16777216)+([int]$portraitPng[17]*65536)+([int]$portraitPng[18]*256)+[int]$portraitPng[19]
        $portraitSourceHeight=([int]$portraitPng[20]*16777216)+([int]$portraitPng[21]*65536)+([int]$portraitPng[22]*256)+[int]$portraitPng[23]
        if($portraitSourceWidth -ne 1254 -or $portraitSourceHeight -ne 1254 -or $portraitReceipt.source_width -ne 1254 -or $portraitReceipt.source_height -ne 1254){throw "V5 must use the original 1254px portrait: $portraitId"}
        if($portraitRecipeText -notmatch '"m_outputFormat"\s+"string"\s+"BGRA8888"' -or $portraitRecipeText -notmatch '"m_nOutputMaxDimension"\s+"int"\s+"512"' -or $portraitRecipeText -notmatch '"m_bNoLod"\s+"bool"\s+"1"' -or $portraitRecipeText -notmatch '"m_algorithm"\s+"string"\s+"ScaleToPowerOfTwo"' -or $portraitRecipeText -notmatch '"m_mipAlgorithm"\s+"CDmeImageProcessor"\s*\{\s*"m_algorithm"\s+"string"\s+""'){throw "V5 requires 512px BGRA8888 NO_LOD and no mip filter: $portraitId"}
    }
    $portraitRecords+=[pscustomobject]@{id=$portraitId;image=$portraitImage;recipe=$portraitRecipe;imageContent=(Join-Path $portraitContent "archive_portraits_v3/$portraitId.png");recipeContent=(Join-Path $portraitContent "archive_gpu_regular/$portraitTextureName.vtex");runtime=(Join-Path $portraitRepo "panorama/images/custom_game/archive_gpu_regular/$portraitTextureName.vtex_c");imageHash=$portraitReceipt.sha256;recipeHash=(Get-FileHash -LiteralPath $portraitRecipe -Algorithm SHA256).Hash;runtimeHash=$null}
}
if($CheckOnly){[pscustomobject]@{success=$true;checkOnly=$true;ids=$Ids;textureVersion=$TextureVersion;textureCount=$portraitRecords.Count;formalMappingsChecked=80;otherResourcesToCompile=0}|ConvertTo-Json -Depth 4;return}
if(-not(Test-Path -LiteralPath $portraitCompiler -PathType Leaf)){throw 'Native texture compiler is missing.'}
$portraitBackup=Join-Path $portraitRepo ('output/archive_portrait_compile/'+(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$null=New-Item -ItemType Directory -Path $portraitBackup -Force
$portraitSaved=@()
foreach($portraitRecord in $portraitRecords){
    foreach($portraitKind in @('imageContent','recipeContent','runtime')){
        $portraitTarget=$portraitRecord.$portraitKind
        $portraitSavedFile=Join-Path $portraitBackup ($portraitRecord.id+'_'+$portraitKind+'.bak')
        $portraitExisted=Test-Path -LiteralPath $portraitTarget -PathType Leaf
        if($portraitExisted){Copy-Item -LiteralPath $portraitTarget -Destination $portraitSavedFile}
        $portraitSaved+=[pscustomobject]@{path=$portraitTarget;backup=$portraitSavedFile;existed=$portraitExisted}
    }
}
try {
    foreach($portraitRecord in $portraitRecords){
        $null=New-Item -ItemType Directory -Path (Split-Path -Parent $portraitRecord.imageContent),(Split-Path -Parent $portraitRecord.recipeContent) -Force
        Copy-Item -LiteralPath $portraitRecord.image -Destination $portraitRecord.imageContent -Force
        Copy-Item -LiteralPath $portraitRecord.recipe -Destination $portraitRecord.recipeContent -Force
        if((Get-FileHash -LiteralPath $portraitRecord.imageContent -Algorithm SHA256).Hash.ToLowerInvariant() -ne $portraitRecord.imageHash -or (Get-FileHash -LiteralPath $portraitRecord.recipeContent -Algorithm SHA256).Hash -ne $portraitRecord.recipeHash){throw "Copied input differs: $($portraitRecord.id)"}
        $portraitStarted=(Get-Date).ToUniversalTime()
        $portraitLog=@(& $portraitCompiler -i $portraitRecord.recipeContent -game (Join-Path $portraitEngine 'game/dota') -f -nop4 2>&1)
        $portraitExit=$LASTEXITCODE
        $portraitLog|Set-Content -LiteralPath (Join-Path $portraitBackup ($portraitRecord.id+'.log')) -Encoding UTF8
        if($portraitExit -ne 0 -or -not ($portraitLog -match 'OK: 1 compiled, 0 failed,')){throw "Focused texture compile failed: $($portraitRecord.id)"}
        $portraitFile=Get-Item -LiteralPath $portraitRecord.runtime
        if($portraitFile.Length -le 0 -or $portraitFile.LastWriteTimeUtc -lt $portraitStarted){throw "Texture output is stale or empty: $($portraitRecord.id)"}
        if((Get-FileHash -LiteralPath $portraitRecord.image -Algorithm SHA256).Hash.ToLowerInvariant() -ne $portraitRecord.imageHash -or (Get-FileHash -LiteralPath $portraitRecord.recipe -Algorithm SHA256).Hash -ne $portraitRecord.recipeHash){throw "Input changed during compilation: $($portraitRecord.id)"}
        $portraitRecord.runtimeHash=(Get-FileHash -LiteralPath $portraitRecord.runtime -Algorithm SHA256).Hash
        Write-Output ('PORTRAIT_TEXTURE_COMPILED '+$portraitRecord.id)
    }
    $portraitAudit=@(& node (Join-Path $PSScriptRoot 'audit_archive_portrait_textures.cjs') --version $TextureVersion @Ids 2>&1)
    $portraitAuditExit=$LASTEXITCODE
    $portraitAudit|Set-Content -LiteralPath (Join-Path $portraitBackup 'audit.json') -Encoding UTF8
    if($portraitAuditExit -ne 0){throw 'Compiled portrait byte audit failed; see audit.json.'}
    [pscustomobject]@{success=$true;ids=$Ids;textureCount=$portraitRecords.Count;otherResourcesCompiled=0;backup=$portraitBackup;records=$portraitRecords}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $portraitBackup 'manifest.json') -Encoding UTF8
} catch {
    $portraitFailure=$_
    foreach($portraitSavedRecord in $portraitSaved){
        if($portraitSavedRecord.existed){Copy-Item -LiteralPath $portraitSavedRecord.backup -Destination $portraitSavedRecord.path -Force}
        elseif(Test-Path -LiteralPath $portraitSavedRecord.path -PathType Leaf){Remove-Item -LiteralPath $portraitSavedRecord.path}
    }
    throw $portraitFailure
}
Write-Output ('ARCHIVE_PORTRAITS_COMPILE_PASS: '+$portraitRecords.Count+' formal textures; original PNG bytes; backup='+$portraitBackup)
