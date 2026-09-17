$vmap='D:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\Survival\maps\portraits\juggernaut_arcana_origins_v5.vmap'
Write-Host 'Survival Portrait Camera Editor' -ForegroundColor Cyan
Write-Host "VMAP: $vmap"
Write-Host 'Edit the camera in Hammer, then press Enter to open the VMAP in Notepad.'
Read-Host 'Press Enter to continue'
Start-Process notepad.exe -ArgumentList $vmap
Read-Host 'Press Enter to close this editor'
