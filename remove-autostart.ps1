# 取消开机自启：删除“启动”文件夹里的倒计时快捷方式
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Windows.Forms

    $startup = Join-Path ([Environment]::GetFolderPath('Startup')) '倒计时.lnk'
    if (Test-Path $startup) {
        Remove-Item $startup -Force
        [System.Windows.Forms.MessageBox]::Show('已取消开机自启：以后开机时不再自动显示倒计时。', '倒计时', 'OK', 'Information') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show('当前没有设置开机自启（未找到启动快捷方式）。', '倒计时', 'OK', 'Information') | Out-Null
    }
}
catch {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show('取消失败：' + $_.Exception.Message, '倒计时', 'OK', 'Error') | Out-Null
}
