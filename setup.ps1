<#
One-line setup for QuickTranslate. Run in PowerShell:

  irm https://raw.githubusercontent.com/okmrtis/quick-translate/main/setup.ps1 | iex

It downloads the latest QuickTranslate from GitHub to a temporary folder, runs its
install.ps1 for the current user, and removes the temporary folder.
#>
& {
    # Runs in its own scope so the settings below do not stay in the caller's session.
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $work = Join-Path ([IO.Path]::GetTempPath()) ('quicktranslate-setup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work 'quick-translate.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/okmrtis/quick-translate/archive/refs/heads/main.zip' -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'src')
        $source = Get-ChildItem -LiteralPath (Join-Path $work 'src') -Directory | Select-Object -First 1
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source.FullName 'install.ps1')
        if ($LASTEXITCODE) { throw "Setup did not finish (exit code $LASTEXITCODE)." }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
