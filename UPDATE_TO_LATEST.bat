@echo off
setlocal
title TG Mass Sender - Update to latest
cd /d "%~dp0"

echo.
echo TG Mass Sender updater
echo Working folder: %CD%
echo.
echo Close TG Mass Sender before continuing.
pause

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"$ErrorActionPreference='Stop';" ^
"$root=(Resolve-Path '.').Path;" ^
"$manifestUrl='https://github.com/saintwork134/tg-updates/raw/refs/heads/main/remote_manifest.signed';" ^
"Write-Host 'Downloading manifest...';" ^
"$manifest=(Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 60).Content.Trim();" ^
"if(-not $manifest.StartsWith('TGMSR-')){ throw 'Bad manifest format.' }" ^
"$encoded=$manifest.Substring(6).Split('.')[0];" ^
"$encoded=$encoded.Replace('-','+').Replace('_','/');" ^
"while(($encoded.Length %% 4) -ne 0){ $encoded += '=' }" ^
"$outerJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded));" ^
"$outer=$outerJson | ConvertFrom-Json;" ^
"$p=$outer.payload;" ^
"$url=[string]$p.download_url;" ^
"$sha=[string]$p.download_sha256;" ^
"$ver=[string]$p.latest_version;" ^
"if(-not $url){ throw 'Manifest has no download_url.' }" ^
"if(-not $sha){ throw 'Manifest has no download_sha256.' }" ^
"$work=Join-Path $root 'data\\manual_update';" ^
"$zip=Join-Path $work ('update_' + ($ver -replace '[^0-9A-Za-z._-]','_') + '.zip');" ^
"$extract=Join-Path $work 'extracted';" ^
"New-Item -ItemType Directory -Force -Path $work | Out-Null;" ^
"if(Test-Path $extract){ Remove-Item -LiteralPath $extract -Recurse -Force }" ^
"Write-Host ('Downloading v' + $ver + '...');" ^
"Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 600;" ^
"$actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant();" ^
"if($actual -ne $sha.ToLowerInvariant()){ throw ('SHA256 mismatch. Expected ' + $sha + ', got ' + $actual) }" ^
"Write-Host 'Extracting...';" ^
"Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force;" ^
"$payload=$extract;" ^
"$items=Get-ChildItem -LiteralPath $extract;" ^
"if($items.Count -eq 1 -and $items[0].PSIsContainer){ $payload=$items[0].FullName }" ^
"Write-Host 'Stopping running app processes...';" ^
"Get-Process | Where-Object { $_.ProcessName -eq 'TG Mass Sender' -or $_.ProcessName -eq 'Start' } | Stop-Process -Force -ErrorAction SilentlyContinue;" ^
"Write-Host 'Installing files...';" ^
"robocopy $payload $root /E /XD data sessions logs licenses license_portal tools release build dist_nuitka dist_nuitka_standalone github_upload __pycache__ /XF license_private_key.json sender.db *.log /NFL /NDL /NJH /NJS /NP | Out-Null;" ^
"$sig=Join-Path $payload 'data\\app_integrity.sig';" ^
"if(Test-Path $sig){ New-Item -ItemType Directory -Force -Path (Join-Path $root 'data') | Out-Null; Copy-Item -LiteralPath $sig -Destination (Join-Path $root 'data\\app_integrity.sig') -Force }" ^
"Write-Host ('Updated to v' + $ver + '.');" ^
"Write-Host 'Starting TG Mass Sender...';" ^
"$exe=Join-Path $root 'dist\\TG Mass Sender.exe';" ^
"if(Test-Path $exe){ Start-Process -FilePath $exe -WorkingDirectory $root }" ^
"Write-Host 'Done.'"

if errorlevel 8 (
  echo.
  echo Update failed.
  pause
  exit /b 1
)

echo.
echo Update finished.
pause
