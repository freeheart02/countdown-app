@echo off
powershell -NoProfile -Command "$p='%~dp0setup-autostart.ps1'; $b=[IO.File]::ReadAllBytes($p); if($b.Length -lt 3 -or $b[0] -ne 239 -or $b[1] -ne 187 -or $b[2] -ne 191){$t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8); [IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($true)))}"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-autostart.ps1"
