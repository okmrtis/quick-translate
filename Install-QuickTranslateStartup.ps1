param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\QuickTranslate'),
    [switch]$RunElevated
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = (Resolve-Path -LiteralPath $InstallRoot).Path.TrimEnd('\')
$runtime = Join-Path $root 'AutoHotkey64.exe'
$script = Join-Path $root 'QuickTranslate.ahk'
foreach ($path in @($runtime, $script)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file missing: $path" }
}
$bytes = [System.IO.File]::ReadAllBytes($runtime)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
if ([BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68) -ne 2) {
    throw 'AutoHotkey must use the Windows GUI subsystem; no console launcher is allowed.'
}
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $identity.User.Value
if ($RunElevated -and -not ([System.Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Elevated startup requires an already elevated setup process.'
}
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$folder = $service.GetFolder('\')
$activeListeners = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.ExecutablePath -ieq $runtime -and $_.CommandLine -and $_.CommandLine.Contains($script) })
if ($activeListeners.Count) { throw 'An installed QuickTranslate listener is active; preserve it before changing startup.' }
$existing = @($folder.GetTasks(1) | Where-Object { $_.Name -eq 'QuickTranslate' })
if ($existing.Count -gt 1) { throw 'Ambiguous QuickTranslate task ownership.' }
if ($existing.Count -eq 1) {
    $actions = @($existing[0].Definition.Actions)
    if ($actions.Count -ne 1 -or $actions[0].Type -ne 0 -or
        $actions[0].Path -ine $runtime -or -not $actions[0].Arguments.Contains($script)) {
        throw 'A different QuickTranslate task already exists; preserve it.'
    }
    if ($existing[0].State -eq 4) { throw 'QuickTranslate is already running; preserve the active listener.' }
}
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$oldValue = (Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue).QuickTranslate
$expectedOld = '"' + $runtime + '" "' + $script + '"'
if ($null -ne $oldValue -and $oldValue -ine $expectedOld) {
    throw 'The old Run entry has a different owner; preserve it.'
}
$backupPath = Join-Path $root 'startup-backup.json'
if (-not (Test-Path -LiteralPath $backupPath)) {
    @{schema='quicktranslate-startup-backup/v1'; capturedAt=[DateTime]::UtcNow.ToString('o');
      oldRunValue=$oldValue; oldTaskXml=$(if ($existing.Count) { $existing[0].Xml } else { $null })} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backupPath -Encoding UTF8
}
$definition = $service.NewTask(0)
$definition.RegistrationInfo.Description = 'User-triggered Ctrl+C+C translation listener. No browser opens at startup.'
$definition.Principal.UserId = $sid
$definition.Principal.LogonType = 3 # TASK_LOGON_INTERACTIVE_TOKEN; hotkeys need the user's desktop.
$definition.Principal.RunLevel = $(if ($RunElevated) { 1 } else { 0 })
$definition.Settings.Enabled = $true
$definition.Settings.Hidden = $true
$definition.Settings.AllowDemandStart = $true
$definition.Settings.StartWhenAvailable = $true
$definition.Settings.DisallowStartIfOnBatteries = $false
$definition.Settings.StopIfGoingOnBatteries = $false
$definition.Settings.ExecutionTimeLimit = 'PT0S' # Resident, not a three-day batch task.
$definition.Settings.MultipleInstances = 2 # TASK_INSTANCES_IGNORE_NEW.
$definition.Settings.RestartCount = 3
$definition.Settings.RestartInterval = 'PT1M'
$trigger = $definition.Triggers.Create(9) # TASK_TRIGGER_LOGON.
$trigger.UserId = $sid
$trigger.Delay = 'PT30S'
$trigger.Enabled = $true
$action = $definition.Actions.Create(0)
$action.Path = $runtime
$action.Arguments = '/ErrorStdOut=UTF-8 "' + $script + '"'
$action.WorkingDirectory = $root
$registered = $folder.RegisterTaskDefinition('QuickTranslate', $definition, 6, $sid, $null, 3, $null)
$instance = $registered.Run($null)
$deadline = [DateTime]::UtcNow.AddSeconds(8)
do {
    Start-Sleep -Milliseconds 100
    $listeners = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
        Where-Object { $_.ExecutablePath -ieq $runtime -and $_.CommandLine -and $_.CommandLine.Contains($script) })
    $registered = $folder.GetTask('QuickTranslate')
} while (($listeners.Count -ne 1 -or $registered.State -ne 4) -and [DateTime]::UtcNow -lt $deadline)
if ($listeners.Count -ne 1 -or $registered.State -ne 4) {
    throw 'The scheduled listener did not start exactly once; old Run entry and backup are preserved.'
}
if ($null -ne $oldValue) {
    $currentValue = (Get-ItemProperty -LiteralPath $runKey).QuickTranslate
    if ($currentValue -cne $oldValue) { throw 'Run entry changed during setup; preserve it.' }
    Remove-ItemProperty -LiteralPath $runKey -Name 'QuickTranslate'
}
$readback = $folder.GetTask('QuickTranslate')
if ($readback.Definition.Principal.LogonType -ne 3 -or
    $readback.Definition.Actions.Item(1).Path -ine $runtime -or
    $readback.Definition.Settings.ExecutionTimeLimit -ne 'PT0S') {
    throw 'Registered startup readback does not match the resident listener contract.'
}
@{taskPath=$readback.Path; state=$readback.State; pid=$listeners[0].ProcessId;
  parentPid=$listeners[0].ParentProcessId; logonType=$readback.Definition.Principal.LogonType;
  runLevel=$readback.Definition.Principal.RunLevel; executionTimeLimit=$readback.Definition.Settings.ExecutionTimeLimit;
  legacyRunRemoved=($null -ne $oldValue); backupPath=$backupPath} | ConvertTo-Json -Compress
