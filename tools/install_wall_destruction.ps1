$ErrorActionPreference='Stop'
$deathGame=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$deathContent=[IO.Path]::GetFullPath((Join-Path $deathGame '../../../content/dota_addons/survival'))
$deathStage=Join-Path $deathGame 'output/wall_destruction'
$deathSource=Join-Path $deathStage 'source'
$deathCompiler=[IO.Path]::GetFullPath((Join-Path $deathGame '../../bin/win64/resourcecompiler.exe'))
$deathInputs=@(Get-ChildItem -LiteralPath $deathSource -Recurse -File)
foreach($deathFile in $deathInputs) {
    $deathRelative=$deathFile.FullName.Substring($deathSource.Length+1)
    $deathTarget=Join-Path $deathContent $deathRelative
    New-Item -ItemType Directory -Force -Path (Split-Path $deathTarget) | Out-Null
    Copy-Item -LiteralPath $deathFile.FullName -Destination $deathTarget -Force
}
foreach($deathExtension in @('.vmat','.vmdl','.vpcf')) {
    foreach($deathFile in $deathInputs | Where-Object Extension -eq $deathExtension) {
        $deathTarget=Join-Path $deathContent $deathFile.FullName.Substring($deathSource.Length+1)
        $deathLog=Join-Path $deathStage ($deathFile.Name+'.compile.log')
        & $deathCompiler -i $deathTarget -game (Join-Path $deathGame '../../dota') *> $deathLog
        if($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $deathLog -Pattern '0 failed')) {throw "Wall death compile failed: $deathLog"}
        Write-Output ('Compiled '+$deathFile.Name)
    }
}
