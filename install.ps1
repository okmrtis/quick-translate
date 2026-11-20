<#
QuickTranslate installer (current Windows user, no administrator rights needed).

  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

What it does:
  1. Checks 64-bit Windows, the Microsoft Edge WebView2 Runtime and Claude Code (claude.exe).
  2. Stops a running QuickTranslate (when updating).
  3. Copies the app files to %LOCALAPPDATA%\Programs\QuickTranslate.
  4. Downloads AutoHotkey v2.0.28 from its official GitHub release and checks the
     SHA-256 of the archive and of AutoHotkey64.exe against manifest.json.
  5. Registers the "QuickTranslate" task that starts at sign-in, and starts it now.
#>
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\QuickTranslate')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell started from PowerShell 7 inherits its module path and then cannot
# load its own modules (Expand-Archive, Get-AuthenticodeSignature, ...). Use its own.
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') + ';' +
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules')
}
function Get-Sha256([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($stream)) -replace '-', '') }
    finally { $stream.Dispose() }
}
$here = $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $here 'manifest.json') -Raw | ConvertFrom-Json
function Step([string]$text) { Write-Host "  - $text" }

Write-Host ""
Write-Host "QuickTranslate $($manifest.version) setup"

# 1. Requirements -------------------------------------------------------------
if (-not [Environment]::Is64BitOperatingSystem) { throw 'QuickTranslate needs 64-bit Windows 10 or 11.' }
$webView = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
             'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') |
    ForEach-Object { (Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue).pv } |
    Where-Object { $_ -and $_ -ne '0.0.0.0' } | Select-Object -First 1
if ($webView) { Step "Microsoft Edge WebView2 Runtime $webView" }
else { Write-Warning 'Microsoft Edge WebView2 Runtime was not found. Translations will open in a simpler window. Get it from https://developer.microsoft.com/microsoft-edge/webview2/' }

$defaultClaude = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
$claude = $null
if (Test-Path -LiteralPath $defaultClaude) { $claude = $defaultClaude }
else {
    $found = Get-Command claude.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $claude = $found.Source }
}
if (-not $claude) {
    throw ('Claude Code (claude.exe) was not found. Install it with "irm https://claude.ai/install.ps1 | iex", ' +
           'run "claude" once to sign in, then run this setup again.')
}
Step "Claude Code: $claude"

# 2. Stop a running copy --------------------------------------------------------
$runtime = Join-Path $InstallRoot 'AutoHotkey64.exe'
$task = Get-ScheduledTask -TaskName 'QuickTranslate' -ErrorAction SilentlyContinue
if ($task -and $task.State -eq 'Running') {
    Step 'Stopping the running QuickTranslate'
    Stop-ScheduledTask -TaskName 'QuickTranslate'
}
$deadline = (Get-Date).AddSeconds(10)
do {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $runtime })
    if ($running.Count -and (Get-Date) -gt $deadline.AddSeconds(-7)) {
        $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    if ($running.Count) { Start-Sleep -Milliseconds 300 }
} while ($running.Count -and (Get-Date) -lt $deadline)

# 3. App files ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$files = 'QuickTranslate.ahk', 'QuickTranslatePanel.html', 'QuickTranslate.ico', 'WebView2Loader.dll',
         'WebView2Loader-LICENSE.txt', 'manifest.json', 'Install-QuickTranslateStartup.ps1',
         'Test-QuickTranslateStartup.ps1', 'uninstall.ps1', 'README.md', 'LICENSE'
foreach ($name in $files) {
    $source = Join-Path $here $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $InstallRoot -Force }
}
foreach ($check in @(@('QuickTranslate.ahk', $manifest.script_sha256), @('QuickTranslatePanel.html', $manifest.panel_sha256),
                     @('WebView2Loader.dll', $manifest.webview2_loader_sha256))) {
    $hash = Get-Sha256 (Join-Path $InstallRoot $check[0])
    if ($hash -ine $check[1]) { throw "$($check[0]) does not match manifest.json. Download QuickTranslate again." }
}
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $InstallRoot 'WebView2Loader.dll')
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
    throw 'WebView2Loader.dll is not signed by Microsoft.'
}
Step "Files: $InstallRoot"

# 4. AutoHotkey runtime -----------------------------------------------------------
$haveRuntime = (Test-Path -LiteralPath $runtime) -and
    ((Get-Sha256 $runtime) -ieq $manifest.runtime_sha256)
if (-not $haveRuntime) {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('quicktranslate-ahk-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work 'AutoHotkey_2.0.28.zip'
        Step 'Downloading AutoHotkey v2.0.28 (official GitHub release)'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.28/AutoHotkey_2.0.28.zip' -OutFile $zip
        if ((Get-Sha256 $zip) -ine $manifest.archive_sha256) {
            throw 'The downloaded AutoHotkey archive does not match its expected SHA-256.'
        }
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'x')
        $exe = Get-ChildItem -LiteralPath (Join-Path $work 'x') -Recurse -Filter 'AutoHotkey64.exe' | Select-Object -First 1
        if (-not $exe -or (Get-Sha256 $exe.FullName) -ine $manifest.runtime_sha256) {
            throw 'AutoHotkey64.exe in the archive does not match its expected SHA-256.'
        }
        Copy-Item -LiteralPath $exe.FullName -Destination $runtime -Force
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Step 'AutoHotkey v2.0.28 checked'

# 5. Claude Code outside its default place ----------------------------------------
$settings = Join-Path $InstallRoot 'settings.ini'
if ($claude -ine $defaultClaude -and -not (Test-Path -LiteralPath $settings)) {
    [IO.File]::WriteAllText($settings, "[Cli]`r`nExecutable=$claude`r`n", [Text.Encoding]::Unicode)
    Step 'settings.ini: Claude Code path saved'
}

# 6. Start at sign-in, and now ----------------------------------------------------
$events = Join-Path $InstallRoot 'events.log'
$startedAt = Get-Date
& (Join-Path $InstallRoot 'Install-QuickTranslateStartup.ps1') -InstallRoot $InstallRoot | Out-Null
Step 'Task "QuickTranslate" registered (starts when you sign in)'
$deadline = (Get-Date).AddSeconds(25)
$ready = $false
do {
    Start-Sleep -Milliseconds 500
    if (Test-Path -LiteralPath $events) {
        $tail = Get-Content -LiteralPath $events -Tail 8 -ErrorAction SilentlyContinue
        $line = $tail | Where-Object { $_ -match 'listener-ready' } | Select-Object -Last 1
        if ($line -and [datetime]::ParseExact($line.Substring(0, 14), 'yyyyMMddHHmmss', $null) -ge $startedAt.AddSeconds(-2)) {
            $listenerPid = ($line -split ' ')[1]
            $ready = [bool]($tail | Where-Object { $_ -match "$listenerPid (panel-ready|panel-failed)" })
        }
    }
} while (-not $ready -and (Get-Date) -lt $deadline)
if ($ready) { Step 'QuickTranslate is running' }
else { Write-Warning "QuickTranslate started, but the panel did not report ready yet. See $events" }

Write-Host ""
Write-Host "Done. Select text in any app and press Ctrl+C+C."
Write-Host "To remove: powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallRoot 'uninstall.ps1')`""
