@echo off
setlocal EnableExtensions
title TG Mass Sender - Update to latest
cd /d "%~dp0"

echo.
echo TG Mass Sender updater
echo Folder: %CD%
echo.
echo Close TG Mass Sender before update.
echo Press any key to start.
pause >nul

if not exist "data" mkdir "data"
if not exist "data\manual_update" mkdir "data\manual_update"

set "PS1=data\manual_update\update_to_latest.ps1"
set "LOG=data\manual_update\update.log"

> "%PS1%" (
  echo $ErrorActionPreference = 'Stop'
  echo $ProgressPreference = 'SilentlyContinue'
  echo [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  echo $root = ^(Resolve-Path '.'^).Path
  echo $log = Join-Path $root 'data\manual_update\update.log'
  echo function Say^($text^) { $line = '[' + ^(Get-Date -Format 'HH:mm:ss'^) + '] ' + $text; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
  echo try {
  echo   Set-Content -LiteralPath $log -Value ^('Update started: ' + ^(Get-Date^)^) -Encoding UTF8
  echo   $manifestUrls = @^('https://raw.githubusercontent.com/saintwork134/tg-updates/main/remote_manifest.signed','https://github.com/saintwork134/tg-updates/raw/refs/heads/main/remote_manifest.signed'^)
  echo   $manifest = $null
  echo   foreach ^($manifestUrl in $manifestUrls^) {
  echo     try {
  echo       Say ^('Downloading manifest: ' + $manifestUrl^)
  echo       $candidate = ^(Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 60^).Content.Trim^(^)
  echo       if ^($candidate.StartsWith^('TGMSR-'^)^) { $manifest = $candidate; break }
  echo       Say 'Manifest response has wrong format.'
  echo     } catch { Say ^('Manifest URL failed: ' + $_.Exception.Message^) }
  echo   }
  echo   if ^(-not $manifest^) { throw 'Could not download valid manifest.' }
  echo   if ^(-not $manifest.StartsWith^('TGMSR-'^)^) { throw 'Bad manifest format.' }
  echo   $encoded = $manifest.Substring^(6^)
  echo   $encoded = $encoded.Replace^('-','+'^).Replace^('_','/'^)
  echo   while ^(($encoded.Length %% 4^) -ne 0^) { $encoded += '=' }
  echo   $outerJson = [Text.Encoding]::UTF8.GetString^([Convert]::FromBase64String^($encoded^)^)
  echo   $outer = $outerJson ^| ConvertFrom-Json
  echo   $p = $outer.payload
  echo   $url = [string]$p.download_url
  echo   $sha = [string]$p.download_sha256
  echo   $ver = [string]$p.latest_version
  echo   if ^(-not $url^) { throw 'Manifest has no download_url.' }
  echo   if ^(-not $sha^) { throw 'Manifest has no download_sha256.' }
  echo   Say ^('Latest version: ' + $ver^)
  echo   $work = Join-Path $root 'data\manual_update'
  echo   $zip = Join-Path $work ^('update_' + ^($ver -replace '[^^0-9A-Za-z._-]','_'^) + '.zip'^)
  echo   $extract = Join-Path $work 'extracted'
  echo   if ^(Test-Path -LiteralPath $extract^) { Remove-Item -LiteralPath $extract -Recurse -Force }
  echo   Say 'Downloading update ZIP. This can take a few minutes...'
  echo   Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 900
  echo   Say 'Checking SHA256...'
  echo   $actual = ^(Get-FileHash -Algorithm SHA256 -LiteralPath $zip^).Hash.ToLowerInvariant^(^)
  echo   if ^($actual -ne $sha.ToLowerInvariant^(^)^) { throw ^('SHA256 mismatch. Expected ' + $sha + ', got ' + $actual^) }
  echo   Say 'Extracting ZIP...'
  echo   Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
  echo   $payload = $extract
  echo   $items = Get-ChildItem -LiteralPath $extract
  echo   if ^($items.Count -eq 1 -and $items[0].PSIsContainer^) { $payload = $items[0].FullName }
  echo   Say 'Stopping old app processes...'
  echo   Get-Process ^| Where-Object { $_.ProcessName -eq 'TG Mass Sender' -or $_.ProcessName -eq 'Start' } ^| Stop-Process -Force -ErrorAction SilentlyContinue
  echo   Say 'Installing files...'
  echo   robocopy $payload $root /E /XD data sessions logs licenses license_portal tools release build dist_nuitka dist_nuitka_standalone github_upload __pycache__ /XF license_private_key.json sender.db *.log /NFL /NDL /NJH /NJS /NP ^| Out-Null
  echo   $sig = Join-Path $payload 'data\app_integrity.sig'
  echo   if ^(Test-Path -LiteralPath $sig^) { New-Item -ItemType Directory -Force -Path ^(Join-Path $root 'data'^) ^| Out-Null; Copy-Item -LiteralPath $sig -Destination ^(Join-Path $root 'data\app_integrity.sig'^) -Force }
  echo   Say ^('Updated to v' + $ver^)
  echo   $exe = Join-Path $root 'dist\TG Mass Sender.exe'
  echo   if ^(Test-Path -LiteralPath $exe^) { Say 'Starting TG Mass Sender...'; Start-Process -FilePath $exe -WorkingDirectory $root } else { Say 'EXE not found after update.' }
  echo   Say 'Done.'
  echo   exit 0
  echo } catch {
  echo   Say ^('ERROR: ' + $_.Exception.Message^)
  echo   Say ^('Log file: ' + $log^)
  echo   exit 1
  echo }
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" (
  echo Update failed. Log:
  echo %CD%\%LOG%
  echo.
  type "%LOG%"
) else (
  echo Update finished successfully.
)
echo.
pause
exit /b %CODE%
