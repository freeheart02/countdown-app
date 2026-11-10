# 设置开机自启：把倒计时加到“启动”文件夹，下次开机自动显示
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Windows.Forms

    $script = Join-Path $PSScriptRoot 'countdown.ps1'
    if (-not (Test-Path $script)) { throw "找不到倒计时脚本：$script" }

    $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $startup = Join-Path ([Environment]::GetFolderPath('Startup')) '倒计时.lnk'

    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($startup)
    $sc.TargetPath = $ps
    $sc.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '"'
    $sc.WorkingDirectory = $PSScriptRoot
    $sc.Description = '桌面倒计时'
    $sc.Save()

    [System.Windows.Forms.MessageBox]::Show('已设置开机自启：下次开机时会自动显示倒计时。', '倒计时', 'OK', 'Information') | Out-Null
}
catch {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show('设置失败：' + $_.Exception.Message, '倒计时', 'OK', 'Error') | Out-Null
}
