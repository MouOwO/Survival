param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
try {
    $games=@(Get-Process -Name dota2 -ErrorAction SilentlyContinue)
    if($games.Count -gt 0){
        Write-Output 'Dota is already running. Use the current game or exit it normally before launching.'
        exit 1
    }
    $steamProcesses=@(Get-Process -Name steam -ErrorAction SilentlyContinue)
    if($steamProcesses.Count -eq 0){
        Write-Output 'Please start Steam and sign in, then run this launcher again.'
        exit 1
    }
    $steamExe=[string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamExe).SteamExe
    if(-not $steamExe -or -not (Test-Path -LiteralPath $steamExe -PathType Leaf)){
        Write-Output 'The signed-in Steam executable could not be located.'
        exit 1
    }
    $launchArguments=@('-applaunch','570','-novid','+sv_cheats','0',
        '+dota_launch_custom_game','3824360109','ws4_entry')
    if($CheckOnly){
        [ordered]@{ok=$true;mode='published_workshop';workshop_id='3824360109';
            steam_running=$true;game_started=$false;installation_changed=$false;
            local_candidate_staged=$false;publication_performed=$false}|ConvertTo-Json -Compress
        exit 0
    }
    Write-Output 'Starting the Steam-installed published Workshop game. Steam handles the subscription and updates.'
    Start-Process -FilePath $steamExe -ArgumentList $launchArguments -WindowStyle Hidden
    [ordered]@{ok=$true;mode='published_workshop';workshop_id='3824360109';
        launch_requested=$true;installation_changed=$false;local_candidate_staged=$false;
        publication_performed=$false}|ConvertTo-Json -Compress
    exit 0
} catch {
    Write-Output 'published_workshop_launch_failed'
    exit 1
}
