param([string]$DatabaseRoot='D:\survival_database')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$destination=[IO.Path]::GetFullPath($DatabaseRoot)
if(-not (Test-Path -LiteralPath (Join-Path $destination 'backend/fishing_api/server.py'))){throw 'Existing HTTP server not found'}
$source=Join-Path $repo 'server'
$staged=Join-Path $source 'staged/fishing_api/server.py'
if(-not (Test-Path -LiteralPath $staged)){throw 'Run stage_archive_http_server.py first'}
$extension=Join-Path $destination 'backend/archive_backend'
New-Item -ItemType Directory -Path $extension -Force|Out-Null
Get-ChildItem (Join-Path $source 'archive_backend') -Filter '*.py' | ForEach-Object {
 Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $extension $_.Name) -Force
}
$server=Join-Path $destination 'backend/fishing_api/server.py'
$backup=$server+'.before_archive'
if(-not (Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $server -Destination $backup}
Copy-Item -LiteralPath $staged -Destination $server -Force
foreach($relative in @('fishing_api/gameplay_stats.py','tests/test_fishing_api.py')){
 $from=Join-Path $source ('staged/'+$relative)
 $to=Join-Path $destination ('backend/'+$relative)
 if(-not (Test-Path -LiteralPath ($to+'.before_archive'))){Copy-Item -LiteralPath $to -Destination ($to+'.before_archive')}
 Copy-Item -LiteralPath $from -Destination $to -Force
}
Get-ChildItem (Join-Path $source 'migrations') -Filter '*.sql' | ForEach-Object {
 Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination ('supabase/migrations/'+$_.Name)) -Force
}
Write-Output 'ARCHIVE_HTTP_DEPLOYED: restart with SURVIVAL_ARCHIVE_HTTP=1 only after database migrations'
