param([string[]]$ModelNames)
$ErrorActionPreference='Stop'
$wallGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$wallContent=[IO.Path]::GetFullPath((Join-Path $wallGame '../../../content/dota_addons/survival'))
$wallStage=Join-Path $wallGame 'output/reference_walls'
$wallCompiler=[IO.Path]::GetFullPath((Join-Path $wallGame '../../bin/win64/resourcecompiler.exe'))
if (-not $ModelNames) { $ModelNames=@((Get-Content -LiteralPath (Join-Path $wallStage 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).name) }
$wallCompile=@()
foreach ($wallKind in @('materials','models')) {
    $wallRelative=$wallKind+'/survival_buildings'
    $wallTarget=Join-Path $wallContent $wallRelative
    New-Item -ItemType Directory -Force -Path $wallTarget | Out-Null
    foreach ($wallName in $ModelNames) {
        foreach ($wallFile in Get-ChildItem -LiteralPath (Join-Path $wallStage ('source/'+$wallRelative)) -Filter ($wallName+'*') -File) {
            Copy-Item -LiteralPath $wallFile.FullName -Destination (Join-Path $wallTarget $wallFile.Name) -Force
            if ($wallFile.Extension -in @('.vmat','.vmdl')) { $wallCompile+=Join-Path $wallTarget $wallFile.Name }
        }
    }
}
foreach ($wallFile in $wallCompile) {
    $wallLog=Join-Path $wallStage ([IO.Path]::GetFileName($wallFile)+'.compile.log')
    # Reuse shared flow material dependencies across all wall models.
    & $wallCompiler -i $wallFile -game (Join-Path $wallGame '../../dota') *> $wallLog
    if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $wallLog -Pattern '0 failed')) { throw "Wall compilation failed: $wallLog" }
    Write-Output ('Compiled '+[IO.Path]::GetFileName($wallFile))
}
