# Local completion cue for the primary assistant. No network or background process.
$ErrorActionPreference = 'Stop'
# User prefers a louder completion cue. This stock WAV is about 10 dB louder
# than Windows Notify.wav on this machine; system/master volume is unchanged.
$taskSoundPath = Join-Path $env:WINDIR 'Media\Windows Notify System Generic.wav'
if (-not (Test-Path -LiteralPath $taskSoundPath -PathType Leaf)) {
    $taskSoundPath = Join-Path $env:WINDIR 'Media\Windows Notify.wav'
}
if (-not (Test-Path -LiteralPath $taskSoundPath -PathType Leaf)) {
    $taskSoundPath = Join-Path $env:WINDIR 'Media\ding.wav'
}
$taskSoundPlayer = $null
try {
    if (-not (Test-Path -LiteralPath $taskSoundPath -PathType Leaf)) {
        throw 'No Windows notification WAV found.'
    }
    $taskSoundPlayer = New-Object System.Media.SoundPlayer $taskSoundPath
    $taskSoundPlayer.Load()
    $taskSoundPlayer.PlaySync()
    Write-Output 'TASK_COMPLETION_SOUND_PLAYED'
}
catch {
    Write-Warning ('Completion sound unavailable: ' + $_.Exception.Message)
}
finally {
    if ($null -ne $taskSoundPlayer) { $taskSoundPlayer.Dispose() }
}
