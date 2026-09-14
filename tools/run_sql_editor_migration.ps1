param([Parameter(Mandatory=$true)][string]$SqlPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms
Add-Type 'using System; using System.Runtime.InteropServices; public class MigrationWindow { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd); }'
$root=[System.Windows.Automation.AutomationElement]::RootElement
$win=$root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object {$_.Current.Name -match 'SQL Editor.*Supabase' -and $_.Current.ClassName -eq 'Chrome_WidgetWin_1'} | Select-Object -First 1
if(-not $win){throw 'SQL Editor window unavailable'}
function Find-Control([string]$Name){$win.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$Name))}
[MigrationWindow]::SetForegroundWindow([IntPtr]$win.Current.NativeWindowHandle)|Out-Null
(Find-Control 'Create a new query').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
Start-Sleep -Milliseconds 150
(Find-Control 'Create a new snippet').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 250
(Find-Control 'Editor content').SetFocus()
$sql=Get-Content -LiteralPath $SqlPath -Raw
$prior=[System.Windows.Forms.Clipboard]::GetDataObject()
try {
 [System.Windows.Forms.Clipboard]::SetText($sql)
 [System.Windows.Forms.SendKeys]::SendWait('^a');[System.Windows.Forms.SendKeys]::SendWait('^v')
 Start-Sleep -Milliseconds 300
 [System.Windows.Forms.SendKeys]::SendWait('^a');[System.Windows.Forms.SendKeys]::SendWait('^c')
 Start-Sleep -Milliseconds 150
 $actual=[System.Windows.Forms.Clipboard]::GetText()
 if($actual.Trim().Replace("`r`n","`n") -ne $sql.Trim().Replace("`r`n","`n")){throw 'SQL text mismatch; not executed'}
} finally {if($prior){[System.Windows.Forms.Clipboard]::SetDataObject($prior,$true)}}
(Find-Control 'Run selected').GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
Write-Output 'SQL_SUBMITTED_VERIFIED_CONTENT'
