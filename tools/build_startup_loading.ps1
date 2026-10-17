param()
$ErrorActionPreference="Stop"
# Keep the established feature-build entry point; compile only its reviewed sources.
& (Join-Path $PSScriptRoot 'dawnward_loading_20261015/compile.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
