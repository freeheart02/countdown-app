# ============================================================
#  桌面倒计时小窗
#  用 Windows 自带的 PowerShell 运行，无需安装任何东西。
#  双击“启动倒计时.bat”即可打开。
# ============================================================
$ErrorActionPreference = 'Stop'

$script:logFile = Join-Path $PSScriptRoot 'countdown-log.txt'
function Write-Log([string]$msg) {
    try {
        $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $msg
        [System.IO.File]::AppendAllText($script:logFile, $line + "`r`n", (New-Object System.Text.UTF8Encoding $true))
    } catch {}
}

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    # ---------- 数据文件（和本脚本放在同一个文件夹） ----------
    $script:dataFile     = Join-Path $PSScriptRoot 'countdown-data.txt'
    $script:settingsFile = Join-Path $PSScriptRoot 'countdown-settings.txt'
    $script:historyFile  = Join-Path $PSScriptRoot 'countdown-history.txt'

    # 数据用最简单的“每行一条，竖线分隔”格式保存，不用 JSON。
    # 每行格式：编号|名字|目标时间|分组   （旧的三字段数据会自动归入“默认”分组）
    function Read-DataFile([string]$file) {
        if (-not (Test-Path $file)) { return @() }
        $lines = $null
        try {
            $lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)
        } catch {
            Write-Log ('读数据文件失败：' + $_.Exception.Message)
            return @()
        }
        $result = @()
        foreach ($line in $lines) {
            $line = $line.Trim()
            if ($line -eq '') { continue }
            $first = $line.IndexOf('|')
            if ($first -lt 0) { continue }
            $last = $line.LastIndexOf('|')
            if ($last -le $first) { continue }
            $id     = $line.Substring(0, $first)
            $tail   = $line.Substring($last + 1)
            $middle = $line.Substring($first + 1, $last - $first - 1)
            $mid2 = $middle.LastIndexOf('|')
            if ($mid2 -lt 0) {
                # 旧格式：编号|名字|目标时间
                $name   = $middle
                $target = $tail
                $group  = '默认'
            } else {
                # 新格式：编号|名字|目标时间|分组
                $name   = $middle.Substring(0, $mid2)
                $target = $middle.Substring($mid2 + 1)
                $group  = $tail
                if ([string]::IsNullOrWhiteSpace($group)) { $group = '默认' }
            }
            $result += [PSCustomObject]@{
                id     = $id
                name   = $name
                target = $target
                group  = $group
            }
        }
        return $result
    }

    function Load-Data { return @(Read-DataFile $script:dataFile) }
    function Load-History { return @(Read-DataFile $script:historyFile) }

    # 按分组归拢（保持组内原有顺序、组间按首次出现顺序）
    function Group-Data($list) {
        $items = @($list)
        $groups = @()
        foreach ($it in $items) {
            $g = [string]$it.group
            if (-not ($groups -contains $g)) { $groups += $g }
        }
        $out = @()
        foreach ($g in $groups) {
            foreach ($it in $items) {
                if ([string]$it.group -eq $g) { $out += $it }
            }
        }
        return $out
    }

    function Write-DataFile([string]$file, $list) {
        $lines = @()
        foreach ($it in @($list)) {
            $lines += ([string]$it.id) + '|' + ([string]$it.name) + '|' + ([string]$it.target) + '|' + ([string]$it.group)
        }
        [System.IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding $false))
    }

    function Save-Data($list) { Write-DataFile $script:dataFile @(Group-Data $list) }
    function Save-History($list) { Write-DataFile $script:historyFile @($list) }

    # ---------- 设置（皮肤 + 声音） ----------
    function Load-Settings {
        $s = @{ theme = '深夜蓝'; sound = $true }
        if (Test-Path $script:settingsFile) {
            try {
                $lines = [System.IO.File]::ReadAllLines($script:settingsFile, [System.Text.Encoding]::UTF8)
                foreach ($line in $lines) {
                    $line = $line.Trim()
                    if ($line -eq '') { continue }
                    $i = $line.IndexOf('=')
                    if ($i -lt 0) { continue }
                    $k = $line.Substring(0, $i).Trim()
                    $v = $line.Substring($i + 1).Trim()
                    if ($k -eq 'theme') { $s.theme = $v }
                    if ($k -eq 'sound') { $s.sound = ($v -eq '1' -or $v -eq 'on' -or $v -eq 'true') }
                }
            } catch {
                Write-Log ('读设置失败：' + $_.Exception.Message)
            }
        }
        return $s
    }

    function Save-Settings {
        $v = if ($script:soundOn) { '1' } else { '0' }
        $lines = @(('theme=' + $script:theme.name), ('sound=' + $v))
        try {
            [System.IO.File]::WriteAllLines($script:settingsFile, $lines, (New-Object System.Text.UTF8Encoding $false))
        } catch {
            Write-Log ('写设置失败：' + $_.Exception.Message)
        }
    }

    # ---------- 皮肤 ----------
    $script:themes = @(
        @{ name = '深夜蓝'; bg = '#1E293B'; accent = '#22D3EE' },
        @{ name = '翡翠绿'; bg = '#0F231C'; accent = '#34D399' },
        @{ name = '紫罗兰'; bg = '#231A38'; accent = '#A78BFA' },
        @{ name = '暖阳橙'; bg = '#2A1D10'; accent = '#FB923C' },
        @{ name = '樱花粉'; bg = '#2A1A24'; accent = '#F472B6' }
    )

    # ---------- 画刷 ----------
    function New-Brush([string]$hex) {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $b = New-Object System.Windows.Media.SolidColorBrush($c)
        $b.Freeze()
        return $b
    }
    $script:brushText   = New-Brush '#E2E8F0'
    $script:brushDim    = New-Brush '#94A3B8'
    $script:brushAccent = New-Brush '#22D3EE'
    $script:brushDanger = New-Brush '#F87171'
    $script:brushCard   = New-Brush '#14FFFFFF'
    $script:brushUnit   = New-Brush '#22000000'

    # ---------- 无边框窗口可拖边缩放 ----------
    $resizeCs = @'
using System;
using System.Windows;
using System.Windows.Interop;

public static class BorderlessResize
{
    private const int WM_NCHITTEST = 0x0084;

    public static void Attach(Window window, double border)
    {
        IntPtr hwnd = new WindowInteropHelper(window).Handle;
        HwndSource src = HwndSource.FromHwnd(hwnd);
        if (src == null) return;
        src.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
        {
            if (msg != WM_NCHITTEST) return IntPtr.Zero;
            int x = (short)((long)l & 0xffff);
            int y = (short)(((long)l >> 16) & 0xffff);
            Point p = window.PointFromScreen(new Point(x, y));
            double wpx = window.ActualWidth;
            double hpx = window.ActualHeight;
            bool left = p.X < border;
            bool right = p.X > wpx - border;
            bool top = p.Y < border;
            bool bottom = p.Y > hpx - border;
            int result = 0;
            if (top && left) result = 13;
            else if (top && right) result = 14;
            else if (bottom && left) result = 16;
            else if (bottom && right) result = 17;
            else if (left) result = 10;
            else if (right) result = 11;
            else if (top) result = 12;
            else if (bottom) result = 15;
            else return IntPtr.Zero;
            handled = true;
            return new IntPtr(result);
        });
    }
}
'@
    try {
        Add-Type -TypeDefinition $resizeCs -ReferencedAssemblies @(
            [System.Windows.Window].Assembly.Location,
            [System.Windows.DependencyObject].Assembly.Location,
            [System.Windows.Media.ColorConverter].Assembly.Location,
            [System.Windows.Markup.IQueryAmbient].Assembly.Location
        )
    } catch {
        Write-Log ('加载缩放功能失败（不影响其它功能）：' + $_.Exception.Message)
    }

    # ---------- 界面 ----------
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="倒计时" Width="340" Height="560" MinWidth="320" MinHeight="240"
        WindowStyle="None" AllowsTransparency="True" Background="#01000000"
        Topmost="True" ResizeMode="CanResize" ShowInTaskbar="True"
        FontFamily="Microsoft YaHei, Segoe UI">
  <Border x:Name="Root" CornerRadius="16" Background="#FF1E293B" BorderBrush="#33FFFFFF" BorderThickness="1" Margin="10">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Grid x:Name="Header" Grid.Row="0" Background="#14000000">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="倒计时" FontSize="15" FontWeight="Bold" Foreground="#E2E8F0" Margin="16,14,0,14" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,10,0">
          <Button x:Name="BtnToggleForm" Content="＋ 添加" Width="52" Height="28" FontSize="12" Foreground="#22D3EE" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="添加倒计时"/>
          <Button x:Name="BtnSet" Content="设置" Width="40" Height="28" FontSize="12" Foreground="#E2E8F0" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="皮肤和声音设置"/>
          <Button x:Name="BtnHistory" Content="历史" Width="40" Height="28" FontSize="12" Foreground="#E2E8F0" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="查看已归档的倒计时"/>
          <Button x:Name="BtnPin" Content="取消置顶" Width="56" Height="28" FontSize="12" Foreground="#E2E8F0" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="固定/取消置顶"/>
          <Button x:Name="BtnMin" Content="—" Width="30" Height="28" FontSize="14" Foreground="#94A3B8" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="最小化"/>
          <Button x:Name="BtnClose" Content="×" Width="30" Height="28" FontSize="15" Foreground="#94A3B8" Background="Transparent" BorderThickness="0" Cursor="Hand" ToolTip="关闭"/>
        </StackPanel>
      </Grid>

      <Border x:Name="FormPanel" Grid.Row="1" Background="#12000000" CornerRadius="10" Margin="16,12,16,10" Padding="12">
        <StackPanel>
          <TextBlock Text="名字" FontSize="12" Foreground="#94A3B8"/>
          <TextBox x:Name="NameBox" FontSize="14" Foreground="#E2E8F0" Background="#22000000" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="8,6" Margin="0,4,0,8"/>
          <TextBlock Text="日期" FontSize="12" Foreground="#94A3B8"/>
          <DatePicker x:Name="DatePick" FontSize="13" Foreground="#E2E8F0" Background="#22000000" BorderBrush="#33FFFFFF" BorderThickness="1" Margin="0,4,0,8"/>
          <TextBlock Text="时间（时:分，24 小时制）" FontSize="12" Foreground="#94A3B8"/>
          <TextBox x:Name="TimeBox" Text="09:00" FontSize="14" Foreground="#E2E8F0" Background="#22000000" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="8,6" Margin="0,4,0,8"/>
          <TextBlock Text="分组（留空则为“默认”）" FontSize="12" Foreground="#94A3B8"/>
          <TextBox x:Name="GroupBox" FontSize="14" Foreground="#E2E8F0" Background="#22000000" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="8,6" Margin="0,4,0,8"/>
          <Button x:Name="BtnAdd" Content="＋ 添加倒计时" FontSize="14" FontWeight="Bold" Foreground="#0B1120" Background="#22D3EE" BorderThickness="0" Padding="0,9" Cursor="Hand" Margin="0,4,0,0"/>
        </StackPanel>
      </Border>

      <Border x:Name="SettingsPanel" Grid.Row="1" Background="#12000000" CornerRadius="10" Margin="16,12,16,10" Padding="12" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Text="皮肤" FontSize="12" Foreground="#94A3B8"/>
          <WrapPanel x:Name="ThemePanel" Margin="0,6,0,2"/>
          <TextBlock Text="声音提醒" FontSize="12" Foreground="#94A3B8" Margin="0,10,0,0"/>
          <CheckBox x:Name="SoundCheck" Content="倒计时结束时响铃" FontSize="13" Foreground="#E2E8F0" Margin="0,4,0,0"/>
        </StackPanel>
      </Border>

      <Border x:Name="HistoryPanel" Grid.Row="1" Background="#12000000" CornerRadius="10" Margin="16,12,16,10" Padding="12" Visibility="Collapsed">
        <StackPanel>
          <TextBlock Text="已归档的倒计时（点“重新启用”改日期后再启动）" FontSize="12" Foreground="#94A3B8" TextWrapping="Wrap"/>
          <ScrollViewer MaxHeight="240" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,6,0,0">
            <StackPanel x:Name="HistoryList"/>
          </ScrollViewer>
        </StackPanel>
      </Border>

      <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="8,2,8,10">
        <StackPanel x:Name="CardPanel"/>
      </ScrollViewer>
    </Grid>
  </Border>
</Window>
'@

    $window = [System.Windows.Markup.XamlReader]::Parse($xaml)
    $NameBox       = $window.FindName('NameBox')
    $DatePick      = $window.FindName('DatePick')
    $TimeBox       = $window.FindName('TimeBox')
    $GroupBox      = $window.FindName('GroupBox')
    $CardPanel     = $window.FindName('CardPanel')
    $BtnAdd        = $window.FindName('BtnAdd')
    $BtnPin        = $window.FindName('BtnPin')
    $BtnMin        = $window.FindName('BtnMin')
    $BtnClose      = $window.FindName('BtnClose')
    $BtnToggleForm = $window.FindName('BtnToggleForm')
    $BtnSet        = $window.FindName('BtnSet')
    $BtnHistory    = $window.FindName('BtnHistory')
    $FormPanel     = $window.FindName('FormPanel')
    $SettingsPanel = $window.FindName('SettingsPanel')
    $HistoryPanel  = $window.FindName('HistoryPanel')
    $HistoryList   = $window.FindName('HistoryList')
    $ThemePanel    = $window.FindName('ThemePanel')
    $SoundCheck    = $window.FindName('SoundCheck')
    $Root          = $window.FindName('Root')
    $Header        = $window.FindName('Header')

    $script:data = @()
    $script:refs = @{}
    $script:renderedOnce = $false
    $script:soundOn = $true
    $script:theme = $script:themes[0]
    $script:themeButtons = @{}

    # ---------- 应用皮肤 ----------
    function Apply-Theme($t) {
        $script:theme = $t
        $script:brushAccent = New-Brush $t.accent
        $Root.Background = New-Brush ('#FF' + $t.bg.TrimStart('#'))
        $BtnAdd.Background = $script:brushAccent
        $BtnToggleForm.Foreground = $script:brushAccent
        Render
        foreach ($k in @($script:themeButtons.Keys)) {
            $b = $script:themeButtons[$k]
            if ($k -eq $t.name) {
                $b.Foreground = $script:brushAccent
                $b.FontWeight = [System.Windows.FontWeights]::Bold
                $b.BorderBrush = $script:brushAccent
            } else {
                $b.Foreground = $script:brushText
                $b.FontWeight = [System.Windows.FontWeights]::Normal
                $b.BorderBrush = New-Brush '#33FFFFFF'
            }
        }
    }

    function Set-Theme([string]$name) {
        $t = $script:themes | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $t) { return }
        Apply-Theme $t
        Save-Settings
    }

    # ---------- 结束响铃 ----------
    function Play-Alarm {
        try {
            [System.Console]::Beep(1000, 180)
            [System.Console]::Beep(1300, 180)
            [System.Console]::Beep(1000, 240)
        } catch {
            try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}
        }
    }

    # ---------- 一个“数字”小块 ----------
    function New-Unit([string]$label) {
        $ub = New-Object System.Windows.Controls.Border
        $ub.Background = $script:brushUnit
        $ub.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $ub.Padding = New-Object System.Windows.Thickness(4, 8, 4, 8)
        $ub.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $ub.Width = 62
        $us = New-Object System.Windows.Controls.StackPanel
        $num = New-Object System.Windows.Controls.TextBlock
        $num.FontSize = 22
        $num.FontWeight = [System.Windows.FontWeights]::Bold
        $num.Foreground = $script:brushAccent
        $num.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $num.Text = '0'
        $lab = New-Object System.Windows.Controls.TextBlock
        $lab.Text = $label
        $lab.FontSize = 11
        $lab.Foreground = $script:brushDim
        $lab.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $lab.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        $us.Children.Add($num) | Out-Null
        $us.Children.Add($lab) | Out-Null
        $ub.Child = $us
        return [PSCustomObject]@{ Border = $ub; Num = $num }
    }

    # ---------- 卡片上的小图标按钮 ----------
    function New-IconButton([string]$text, [string]$tip) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $text
        $b.Width = 26
        $b.Height = 26
        $b.FontSize = 14
        $b.Foreground = $script:brushDim
        $b.Background = [System.Windows.Media.Brushes]::Transparent
        $b.BorderThickness = New-Object System.Windows.Thickness(0)
        $b.Cursor = [System.Windows.Input.Cursors]::Hand
        $b.ToolTip = $tip
        return $b
    }

    # ---------- 一张倒计时卡片 ----------
    function New-Card($item) {
        if (-not $item -or $null -eq $item.target) { return $null }
        $target = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$item.target, 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$target)) {
            return $null
        }
        $id = $item.id

        $card = New-Object System.Windows.Controls.Border
        $card.Background = $script:brushCard
        $card.CornerRadius = New-Object System.Windows.CornerRadius(12)
        $card.Padding = New-Object System.Windows.Thickness(14)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
        # 卡片宽度固定 = 下方“天时分秒”四格宽度(272) + 左右内边距(28)，
        # 这样名字行里的上移/下移/删除按钮永远落在数字行范围内，不会把窗口撑宽
        $card.Width = 300

        $stack = New-Object System.Windows.Controls.StackPanel

        # 第一行：名字 + 上移/下移/删除
        $row1 = New-Object System.Windows.Controls.DockPanel
        $actions = New-Object System.Windows.Controls.StackPanel
        $actions.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $up = New-IconButton '↑' '上移'
        $up.Tag = $id
        $up.Add_Click({ param($s, $e) Move-Countdown $s.Tag 'up' })

        $down = New-IconButton '↓' '下移'
        $down.Tag = $id
        $down.Add_Click({ param($s, $e) Move-Countdown $s.Tag 'down' })

        $del = New-IconButton '×' '归档（可从历史恢复）'
        $del.Tag = $id
        $del.Add_Click({ param($s, $e) Remove-Countdown $s.Tag })

        $actions.Children.Add($up) | Out-Null
        $actions.Children.Add($down) | Out-Null
        $actions.Children.Add($del) | Out-Null
        [System.Windows.Controls.DockPanel]::SetDock($actions, [System.Windows.Controls.Dock]::Right)
        $row1.Children.Add($actions) | Out-Null

        $nameTb = New-Object System.Windows.Controls.TextBlock
        $nameTb.Text = [string]$item.name
        $nameTb.FontSize = 15
        $nameTb.FontWeight = [System.Windows.FontWeights]::Bold
        $nameTb.Foreground = $script:brushText
        $nameTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $nameTb.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        $row1.Children.Add($nameTb) | Out-Null
        $stack.Children.Add($row1) | Out-Null

        # 目标时间
        $targetTb = New-Object System.Windows.Controls.TextBlock
        $targetTb.Text = '目标：' + [string]$item.target
        $targetTb.FontSize = 11
        $targetTb.Foreground = $script:brushDim
        $targetTb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        $stack.Children.Add($targetTb) | Out-Null

        # 数字区
        $unitsRow = New-Object System.Windows.Controls.StackPanel
        $unitsRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $unitsRow.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
        $d = New-Unit '天'; $h = New-Unit '时'; $m = New-Unit '分'; $s = New-Unit '秒'
        $unitsRow.Children.Add($d.Border) | Out-Null
        $unitsRow.Children.Add($h.Border) | Out-Null
        $unitsRow.Children.Add($m.Border) | Out-Null
        $unitsRow.Children.Add($s.Border) | Out-Null
        $stack.Children.Add($unitsRow) | Out-Null

        # 已到时间
        $expired = New-Object System.Windows.Controls.TextBlock
        $expired.Text = '已到时间！'
        $expired.FontSize = 20
        $expired.FontWeight = [System.Windows.FontWeights]::Bold
        $expired.Foreground = $script:brushDanger
        $expired.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $expired.Margin = New-Object System.Windows.Thickness(0, 12, 0, 0)
        $expired.Visibility = [System.Windows.Visibility]::Collapsed
        $stack.Children.Add($expired) | Out-Null

        $card.Child = $stack

        $script:refs[[string]$id] = [PSCustomObject]@{
            target   = $target
            unitsRow = $unitsRow
            expired  = $expired
            day      = $d.Num
            hour     = $h.Num
            min      = $m.Num
            sec      = $s.Num
            alerted  = ($target -le [datetime]::Now)
        }
        return $card
    }

    # ---------- 刷新数字 ----------
    function Update-Timers {
        $now = [datetime]::Now
        $playSound = $false
        foreach ($k in @($script:refs.Keys)) {
            $r = $script:refs[$k]
            $remain = $r.target - $now
            if ($remain.TotalSeconds -gt 0) {
                $r.unitsRow.Visibility = [System.Windows.Visibility]::Visible
                $r.expired.Visibility  = [System.Windows.Visibility]::Collapsed
                $days = [math]::Floor($remain.TotalDays)
                $r.day.Text   = [string]$days
                $r.hour.Text  = '{0:D2}' -f $remain.Hours
                $r.min.Text   = '{0:D2}' -f $remain.Minutes
                $r.sec.Text   = '{0:D2}' -f $remain.Seconds
                $r.alerted = $false
            } else {
                $r.unitsRow.Visibility = [System.Windows.Visibility]::Collapsed
                $r.expired.Visibility  = [System.Windows.Visibility]::Visible
                if (-not $r.alerted) {
                    $r.alerted = $true
                    $playSound = $true
                }
            }
        }
        if ($playSound -and $script:soundOn) { Play-Alarm }
    }

    function Render {
        $script:data = @(Load-Data)
        $script:refs = @{}
        if (-not $script:renderedOnce) {
            $script:renderedOnce = $true
            Write-Log ('启动加载：' + @($script:data).Count + ' 条')
        }
        $CardPanel.Children.Clear()
        if ($script:data.Count -eq 0) {
            $empty = New-Object System.Windows.Controls.TextBlock
            $empty.Text = '还没有倒计时，点右上角“＋ 添加”新建一个'
            $empty.FontSize = 13
            $empty.Foreground = $script:brushDim
            $empty.TextAlignment = [System.Windows.TextAlignment]::Center
            $empty.Margin = New-Object System.Windows.Thickness(0, 30, 0, 0)
            $CardPanel.Children.Add($empty) | Out-Null
        } else {
            $grouped = @(Group-Data $script:data)
            $curGroup = $null
            foreach ($item in $grouped) {
                $g = [string]$item.group
                if ($g -ne $curGroup) {
                    $gh = New-Object System.Windows.Controls.TextBlock
                    $gh.Text = $g
                    $gh.FontSize = 12
                    $gh.FontWeight = [System.Windows.FontWeights]::Bold
                    $gh.Foreground = $script:brushDim
                    $gh.Margin = New-Object System.Windows.Thickness(2, 4, 0, 6)
                    $CardPanel.Children.Add($gh) | Out-Null
                    $curGroup = $g
                }
                $card = New-Card $item
                if ($null -ne $card) { $CardPanel.Children.Add($card) | Out-Null }
            }
        }
        Update-Timers
    }

    function Show-Msg([string]$msg) {
        [System.Windows.MessageBox]::Show($msg, '倒计时', 'OK', 'Information') | Out-Null
    }

    function Add-Countdown {
        $name = $NameBox.Text.Trim()
        if ([string]::IsNullOrEmpty($name)) { Show-Msg '请先填写倒计时的名字'; return }
        if (-not $DatePick.SelectedDate) { Show-Msg '请选择日期'; return }
        $timeStr = $TimeBox.Text.Trim()
        if ($timeStr -notmatch '^\d{1,2}:\d{2}$') { Show-Msg '时间格式不对，请写成 时:分，例如 08:30'; return }
        $parts = $timeStr -split ':'
        $hh = [int]$parts[0]; $mm = [int]$parts[1]
        if ($hh -gt 23 -or $mm -gt 59) { Show-Msg '时间范围不对（时 0-23，分 0-59）'; return }

        $group = $GroupBox.Text.Trim()
        if ([string]::IsNullOrEmpty($group)) { $group = '默认' }

        $target = $DatePick.SelectedDate.Date.AddHours($hh).AddMinutes($mm)
        $targetStr = $target.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        $item = [PSCustomObject]@{ id = ([string](Get-Date).Ticks); name = $name; target = $targetStr; group = $group }
        $script:data = @($script:data) + $item
        Save-Data $script:data
        Render
        $NameBox.Text = ''
        $TimeBox.Text = '09:00'
        $GroupBox.Text = ''
        # 添加成功后收起设置面板，只显示倒计时
        $FormPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    function Remove-Countdown($id) {
        $id = [string]$id
        $item = $null
        foreach ($it in @($script:data)) {
            if ([string]$it.id -eq $id) { $item = $it; break }
        }
        if ($item) {
            # 归档到历史（不是彻底删除），方便以后再启用
            $hist = @(Load-History) + $item
            Save-History $hist
        }
        $script:data = @($script:data | Where-Object { [string]$_.id -ne $id })
        Save-Data $script:data
        Render
    }

    function Move-Countdown($id, [string]$way) {
        $items = @(Group-Data $script:data)
        $idx = -1
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ([string]$items[$i].id -eq [string]$id) { $idx = $i; break }
        }
        if ($idx -lt 0) { return }
        $step = if ($way -eq 'up') { -1 } else { 1 }
        $j = $idx + $step
        if ($j -lt 0 -or $j -ge $items.Count) { return }
        $tmp = $items[$idx]
        $items[$idx] = $items[$j]
        $items[$j] = $tmp
        $script:data = @(Group-Data $items)
        Save-Data $script:data
        Render
    }

    # ---------- 历史归档 ----------
    function Render-History {
        $HistoryList.Children.Clear()
        $hist = @(Load-History)
        if ($hist.Count -eq 0) {
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = '还没有归档的倒计时'
            $t.FontSize = 12
            $t.Foreground = $script:brushDim
            $t.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
            $HistoryList.Children.Add($t) | Out-Null
            return
        }
        [array]::Reverse($hist)
        foreach ($it in $hist) {
            $row = New-Object System.Windows.Controls.Border
            $row.Background = $script:brushCard
            $row.CornerRadius = New-Object System.Windows.CornerRadius(8)
            $row.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
            $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)

            $stack = New-Object System.Windows.Controls.StackPanel

            $r1 = New-Object System.Windows.Controls.DockPanel
            $acts = New-Object System.Windows.Controls.StackPanel
            $acts.Orientation = [System.Windows.Controls.Orientation]::Horizontal

            $btnUse = New-Object System.Windows.Controls.Button
            $btnUse.Content = '重新启用'
            $btnUse.FontSize = 12
            $btnUse.Foreground = $script:brushAccent
            $btnUse.Background = [System.Windows.Media.Brushes]::Transparent
            $btnUse.BorderThickness = New-Object System.Windows.Thickness(0)
            $btnUse.Cursor = [System.Windows.Input.Cursors]::Hand
            $btnUse.Tag = [string]$it.id
            $btnUse.Add_Click({ param($s, $e) Reuse-Countdown ([string]$s.Tag) })

            $btnDel = New-Object System.Windows.Controls.Button
            $btnDel.Content = '删除'
            $btnDel.FontSize = 12
            $btnDel.Foreground = $script:brushDim
            $btnDel.Background = [System.Windows.Media.Brushes]::Transparent
            $btnDel.BorderThickness = New-Object System.Windows.Thickness(0)
            $btnDel.Cursor = [System.Windows.Input.Cursors]::Hand
            $btnDel.Tag = [string]$it.id
            $btnDel.Add_Click({ param($s, $e) Remove-HistoryItem ([string]$s.Tag) })

            $acts.Children.Add($btnUse) | Out-Null
            $acts.Children.Add($btnDel) | Out-Null
            [System.Windows.Controls.DockPanel]::SetDock($acts, [System.Windows.Controls.Dock]::Right)
            $r1.Children.Add($acts) | Out-Null

            $nameTb = New-Object System.Windows.Controls.TextBlock
            $nameTb.Text = [string]$it.name
            $nameTb.FontSize = 14
            $nameTb.FontWeight = [System.Windows.FontWeights]::Bold
            $nameTb.Foreground = $script:brushText
            $nameTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $nameTb.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
            $r1.Children.Add($nameTb) | Out-Null
            $stack.Children.Add($r1) | Out-Null

            $infoTb = New-Object System.Windows.Controls.TextBlock
            $infoTb.Text = '原目标：' + [string]$it.target + '　组：' + [string]$it.group
            $infoTb.FontSize = 11
            $infoTb.Foreground = $script:brushDim
            $infoTb.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
            $stack.Children.Add($infoTb) | Out-Null

            $row.Child = $stack
            $HistoryList.Children.Add($row) | Out-Null
        }
    }

    function Reuse-Countdown($id) {
        $item = $null
        foreach ($it in @(Load-History)) {
            if ([string]$it.id -eq [string]$id) { $item = $it; break }
        }
        if (-not $item) { return }
        $NameBox.Text = [string]$item.name
        $GroupBox.Text = [string]$item.group
        $DatePick.SelectedDate = Get-Date
        $dt = [datetime]::MinValue
        if ([datetime]::TryParseExact([string]$item.target, 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
            $TimeBox.Text = $dt.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        } else {
            $TimeBox.Text = '09:00'
        }
        $HistoryPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $FormPanel.Visibility = [System.Windows.Visibility]::Visible
    }

    function Remove-HistoryItem($id) {
        $hist = @(Load-History | Where-Object { [string]$_.id -ne [string]$id })
        Save-History $hist
        Render-History
    }

    # ---------- 事件 ----------
    $BtnAdd.Add_Click({ Add-Countdown })
    $BtnClose.Add_Click({ $window.Close() })
    $BtnMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

    function Set-PinLabel {
        if ($window.Topmost) { $BtnPin.Content = '取消置顶' } else { $BtnPin.Content = '置顶' }
    }
    $BtnPin.Add_Click({ $window.Topmost = -not $window.Topmost; Set-PinLabel })

    function Toggle-Add {
        if ($FormPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $FormPanel.Visibility = [System.Windows.Visibility]::Collapsed
        } else {
            $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $FormPanel.Visibility = [System.Windows.Visibility]::Visible
        }
    }
    $BtnToggleForm.Add_Click({ Toggle-Add })

    function Toggle-Settings {
        if ($SettingsPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed
        } else {
            $FormPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $SettingsPanel.Visibility = [System.Windows.Visibility]::Visible
        }
    }
    $BtnSet.Add_Click({ Toggle-Settings })

    function Toggle-History {
        if ($HistoryPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $HistoryPanel.Visibility = [System.Windows.Visibility]::Collapsed
        } else {
            $FormPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed
            Render-History
            $HistoryPanel.Visibility = [System.Windows.Visibility]::Visible
        }
    }
    $BtnHistory.Add_Click({ Toggle-History })

    $Header.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

    # ---------- 启动初始化 ----------
    $settings = Load-Settings
    $script:soundOn = $settings.sound
    $script:theme = $script:themes | Where-Object { $_.name -eq $settings.theme } | Select-Object -First 1
    if (-not $script:theme) { $script:theme = $script:themes[0] }

    # 皮肤按钮
    foreach ($t in $script:themes) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $t.name
        $b.Tag = [string]$t.name
        $b.FontSize = 12
        $b.Foreground = $script:brushText
        $b.Background = $script:brushCard
        $b.BorderBrush = New-Brush '#33FFFFFF'
        $b.BorderThickness = New-Object System.Windows.Thickness(1)
        $b.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
        $b.Margin = New-Object System.Windows.Thickness(0, 0, 8, 8)
        $b.Cursor = [System.Windows.Input.Cursors]::Hand
        $b.Add_Click({ param($s, $e) Set-Theme ([string]$s.Tag) })
        $script:themeButtons[[string]$t.name] = $b
        $ThemePanel.Children.Add($b) | Out-Null
    }

    # 声音开关
    $SoundCheck.IsChecked = $script:soundOn
    $SoundCheck.Add_Checked({ $script:soundOn = $true; Save-Settings })
    $SoundCheck.Add_Unchecked({ $script:soundOn = $false; Save-Settings })

    # 默认日期设为今天
    $DatePick.SelectedDate = Get-Date

    # 放到屏幕右上角
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Right - $window.Width - 16
    $window.Top  = $wa.Top + 16

    # 应用皮肤（内含首次渲染）
    Apply-Theme $script:theme

    # 已有数据就收起添加面板，只显示倒计时列表
    if ($script:data.Count -eq 0) {
        $FormPanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $FormPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed

    # 允许拖动窗口边缘缩放
    $window.Add_SourceInitialized({
        param($s, $e)
        try { [BorderlessResize]::Attach($window, 10) }
        catch { Write-Log ('启用缩放失败：' + $_.Exception.Message) }
    })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [System.TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({ Update-Timers })
    $timer.Start()

    # 自动化测试用：设置 COUNTDOWN_TEST=1 时不弹窗，验证后立即退出
    if ($env:COUNTDOWN_TEST -eq '1') {
        Write-Log ('测试通过：加载 ' + @($script:data).Count + ' 条数据')
        Write-Host 'TEST-OK'
        return
    }

    $window.ShowDialog() | Out-Null
}
catch {
    Write-Log ('启动出错：' + $_.Exception.Message)
    if ($env:COUNTDOWN_TEST -eq '1') { Write-Host ('启动出错：' + $_.Exception.Message); return }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $m = '出错了：' + $_.Exception.Message
    try { [System.Windows.Forms.MessageBox]::Show($m, '倒计时', 'OK', 'Error') | Out-Null }
    catch { Write-Host $m }
}
