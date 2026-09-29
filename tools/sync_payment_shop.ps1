[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string]$SshKey=(Join-Path $env:USERPROFILE '.ssh/goufayu_ecs_ed25519_v2')
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $repo
try {
$pythonCandidates=@((Join-Path $repo 'output/payment_venv/Scripts/python.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe'))
$python=$pythonCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(-not $python){$python=(Get-Command python -ErrorAction Stop).Source}
$catalogFile=Join-Path $repo 'output/payment_catalog.json'
& $python (Join-Path $repo 'tools/build_payment_catalog.py') --output $catalogFile
if($LASTEXITCODE -ne 0){throw 'Shop CSV validation failed. Nothing published.'}
$catalog=Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json
if($CheckOnly){Write-Output 'SHOP_LOCAL_CHECK_PASS: CSV is valid; no client/server changes.';exit 0}
if(-not (Test-Path -LiteralPath $SshKey -PathType Leaf)){throw 'SSH key missing. Use -SshKey with the existing authorized deployment key path.'}
$knownHosts='tools/deploy/goufayu_test_known_hosts'
$sshOptions=@('-F','none','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
    '-o',('UserKnownHostsFile='+$knownHosts),'-o','IdentitiesOnly=yes','-o','ConnectTimeout=10','-i',$SshKey)
$digest=(Get-FileHash -LiteralPath $catalogFile -Algorithm SHA256).Hash.ToLower()
$remote='/tmp/goufayu-shop-'+$digest+'.json'
& scp.exe @sshOptions $catalogFile ('root@47.110.238.248:'+$remote)
if($LASTEXITCODE -ne 0){throw 'Catalog upload failed. Nothing published.'}
$cli='/opt/goufayu/payments/current/.venv/bin/python /opt/goufayu/payments/current/payment_backend/sync_catalog.py'
& ssh.exe @sshOptions 'root@47.110.238.248' ($cli+' check '+$remote+' '+$digest)
if($LASTEXITCODE -ne 0){throw 'Server validation failed. Nothing published.'}
# Build the actual game UI before publishing; prices and reward lists are fetched
# from the server, so there is no separate client-side price copy to go stale.
& (Join-Path $repo 'tools/build_payment_ui.ps1')
if($LASTEXITCODE -ne 0){throw 'Client build failed. Nothing published.'}
$result=@(& ssh.exe @sshOptions 'root@47.110.238.248' ($cli+' apply '+$remote+' '+$digest))
if($LASTEXITCODE -ne 0){throw 'Server publication failed or response was lost. Run again to verify/reapply the same catalog.'}
$confirmation=($result | Select-Object -Last 1) | ConvertFrom-Json
if(-not $confirmation.applied -or $confirmation.catalog_hash -ne $catalog.catalog_hash){throw 'Server catalog hash was not confirmed. Run again to verify.'}
Write-Output ('SHOP_SYNC_PASS: '+$confirmation.enabled_products+' products; catalog '+$confirmation.catalog_hash)
Write-Output 'Reopen the shop in game. Existing orders and player rewards were preserved.'
} finally { Pop-Location }
