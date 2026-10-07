$ErrorActionPreference='Stop'
# Inventory now shares Dota-native assets with skill and shop UI.
& (Join-Path $PSScriptRoot 'compile_native_ui_icons.ps1')
