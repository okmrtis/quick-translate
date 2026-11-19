<#
Removes QuickTranslate for the current Windows user: stops it, removes the
"QuickTranslate" sign-in task and deletes the install folder.

  powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
#>
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\QuickTranslate')
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell started from PowerShell 7 inherits its module path and then cannot
# load its own modules (Get-ScheduledTask, ...). Use its own.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') + ';' +
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')
}
$runtime = Join-Path $InstallRoot 'AutoHotkey64.exe'

$task = Get-ScheduledTask -TaskName 'QuickTranslate' -ErrorAction SilentlyContinue
if ($task) {
    $action = @($task.Actions)[0]
    if ($action -and $action.Execute -ieq $runtime) {
        if ($task.State -eq 'Running') { Stop-ScheduledTask -TaskName 'QuickTranslate' }
        Unregister-ScheduledTask -TaskName 'QuickTranslate' -Confirm:$false
        Write-Host '  - Task "QuickTranslate" removed'
    } else {
        Write-Warning 'A "QuickTranslate" task that runs from another folder was left as it is.'
    }
}
$deadline = (Get-Date).AddSeconds(10)
do {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $runtime })
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($running.Count) { Start-Sleep -Milliseconds 300 }
} while ($running.Count -and (Get-Date) -lt $deadline)

if ((Test-Path -LiteralPath (Join-Path $InstallRoot 'QuickTranslate.ahk')) -and -not $running.Count) {
    Start-Sleep -Milliseconds 500 # WebView2 helper processes end with QuickTranslate
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    Write-Host "  - Removed $InstallRoot"
}
Write-Host 'QuickTranslate is removed.'
