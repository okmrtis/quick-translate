param([string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\QuickTranslate'))
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$root = (Resolve-Path -LiteralPath $InstallRoot).Path.TrimEnd('\')
$runtime = Join-Path $root 'AutoHotkey64.exe'
$script = Join-Path $root 'QuickTranslate.ahk'
$checks = [System.Collections.Generic.List[string]]::new()
function Assert-Check([bool]$condition, [string]$name) {
    if (-not $condition) { throw "Failed: $name" }
    $checks.Add($name)
}
function Resolve-UserSid([string]$userId) {
    if ($userId -match '^S-1-') { return $userId }
    return ([System.Security.Principal.NTAccount]::new($userId)).Translate(
        [System.Security.Principal.SecurityIdentifier]).Value
}
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$task = $service.GetFolder('\').GetTask('QuickTranslate')
$definition = $task.Definition
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert-Check ($task.State -eq 4 -and $task.Enabled) 'task-running-enabled'
Assert-Check ((Resolve-UserSid $definition.Principal.UserId) -eq $sid -and $definition.Principal.LogonType -eq 3) 'interactive-current-user'
$trigger = $definition.Triggers.Item(1)
Assert-Check ($definition.Triggers.Count -eq 1 -and $trigger.Type -eq 9 -and
    (Resolve-UserSid $trigger.UserId) -eq $sid -and $trigger.Delay -eq 'PT30S') 'single-delayed-logon-trigger'
$action = $definition.Actions.Item(1)
Assert-Check ($definition.Actions.Count -eq 1 -and $action.Type -eq 0 -and
    $action.Path -ieq $runtime -and $action.Arguments -ceq ('/ErrorStdOut=UTF-8 "' + $script + '"') -and
    $action.WorkingDirectory -ieq $root) 'direct-gui-listener-action'
Assert-Check ($definition.Settings.ExecutionTimeLimit -eq 'PT0S' -and
    -not $definition.Settings.DisallowStartIfOnBatteries -and
    -not $definition.Settings.StopIfGoingOnBatteries) 'resident-unlimited-and-battery-safe'
Assert-Check ($definition.Settings.MultipleInstances -eq 2 -and $definition.Settings.Hidden -and
    $definition.Settings.RestartCount -eq 3 -and $definition.Settings.RestartInterval -eq 'PT1M') 'single-instance-bounded-failure-recovery'
$listeners = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.ExecutablePath -ieq $runtime -and $_.CommandLine -and $_.CommandLine.Contains($script) })
$listenerCheck = 'exactly-one-installed-listener'
if (-not $listeners.Count -and $definition.Principal.RunLevel -eq 1) {
    # A normal-level reader cannot see an elevated listener's path or command line.
    # The listener records its own PID at start; accept that process while it still runs.
    $events = Join-Path $root 'events.log'
    $ready = if (Test-Path -LiteralPath $events) {
        Select-String -LiteralPath $events -Pattern 'pid=(\d+) listener-ready' | Select-Object -Last 1 }
    if ($ready) {
        $readyPid = [int]$ready.Matches[0].Groups[1].Value
        $listeners = @(Get-CimInstance Win32_Process -Filter "ProcessId=$readyPid" |
            Where-Object { $_.Name -eq 'AutoHotkey64.exe' })
        $listenerCheck = 'recorded-elevated-listener-running'
    }
}
Assert-Check ($listeners.Count -eq 1) $listenerCheck
$runValue = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).QuickTranslate
Assert-Check ($null -eq $runValue) 'legacy-duplicate-startup-absent'
$manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
foreach ($pair in @(@('AutoHotkey64.exe','runtime_sha256'), @('QuickTranslate.ahk','script_sha256'),
                   @('Install-QuickTranslateStartup.ps1','startup_script_sha256'),
                   @('QuickTranslatePanel.html','panel_sha256'), @('WebView2Loader.dll','webview2_loader_sha256'))) {
    $actual = (Get-FileHash -LiteralPath (Join-Path $root $pair[0]) -Algorithm SHA256).Hash
    Assert-Check ($actual -ieq $manifest.($pair[1])) ('verified-hash-' + $pair[0])
}
$loaderSignature = Get-AuthenticodeSignature -LiteralPath (Join-Path $root 'WebView2Loader.dll')
Assert-Check ($loaderSignature.Status -eq 'Valid' -and
    $loaderSignature.SignerCertificate.Subject -like 'CN=Microsoft Corporation,*') 'webview2-loader-signed-by-microsoft'
foreach ($name in @('AutoHotkey64.exe')) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root $name))
    $offset = [BitConverter]::ToInt32($bytes, 0x3c)
    Assert-Check ([BitConverter]::ToUInt16($bytes, $offset + 24 + 68) -eq 2) ('gui-subsystem-' + $name)
}
# Load-time check of the installed script: no errors and no #Warn output, such as a
# global assigned inside a function without being declared there. A copy in a temp
# folder is validated, so the running listener is never replaced.
$validateDir = Join-Path ([IO.Path]::GetTempPath()) ('qt-validate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $validateDir | Out-Null
try {
    Copy-Item -LiteralPath $script -Destination $validateDir
    $psi = [System.Diagnostics.ProcessStartInfo]::new($runtime,
        '/ErrorStdOut=UTF-8 /validate "' + (Join-Path $validateDir 'QuickTranslate.ahk') + '"')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $validator = [System.Diagnostics.Process]::Start($psi)
    $validateOut = $validator.StandardOutput.ReadToEnd() + $validator.StandardError.ReadToEnd()
    $validator.WaitForExit()
    Assert-Check ($validator.ExitCode -eq 0 -and -not $validateOut.Trim()) 'script-loads-without-warnings'
} finally {
    Remove-Item -LiteralPath $validateDir -Recurse -Force -ErrorAction SilentlyContinue
}
$installer = Join-Path $root 'Install-QuickTranslateStartup.ps1'
$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
Assert-Check ($parseErrors.Count -eq 0) 'installer-parses'
$guarded = $false
try { & $installer -InstallRoot $root } catch {
    # The second message is the guard a normal-level setup reaches for an elevated listener.
    $guarded = $_.Exception.Message -in @(
        'An installed QuickTranslate listener is active; preserve it before changing startup.',
        'QuickTranslate is already running; preserve the active listener.')
}
Assert-Check $guarded 'running-listener-preserved-on-reinstall'
$after = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.ProcessId -eq $listeners[0].ProcessId })
Assert-Check ($after.Count -eq 1 -and $service.GetFolder('\').GetTask('QuickTranslate').State -eq 4) 'same-listener-survives-setup-owner'
@{passed=$checks.ToArray(); count=$checks.Count; pid=$listeners[0].ProcessId; parentPid=$listeners[0].ParentProcessId;
  runLevel=$definition.Principal.RunLevel; lastTaskResult=$task.LastTaskResult;
  actualTranslationResponseVerified=$false} | ConvertTo-Json -Depth 4 -Compress
