param(
    [switch]$DryRun,
    [switch]$SkipBetterGI,
    [switch]$SkipMarch7th,
    [switch]$SkipMaaEnd,
    [switch]$SkipMAA,
    [switch]$IgnoreEnabled
)

$ErrorActionPreference = "Stop"

function S($Base64) {
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64))
}

$Config = @{
    BetterGI = @{
        Exe = "D:\BetterGI\BetterGI.exe"
        WindowTitle = "BetterGI"
        LogDir = "D:\BetterGI\log"
        LogPrefix = "better-genshin-impact"
        LogCompleteMarkers = @((S "5LiA5p2h6b6Z5ZKM6YWN572u57uE5Lu75Yqh57uT5p2f"))
        TimeoutMinutes = 180
        OneDragonFallback = @{ X = 88; Y = 300; BaseW = 1125; BaseH = 750 }
        OneDragonPlayFallback = @{ X = 435; Y = 99; BaseW = 1125; BaseH = 750 }
        ToolProcesses = @("BetterGI")
    }
    March7th = @{
        Exe = "D:\March7thAssistant_full\March7th Launcher.exe"
        AlternateExe = "D:\March7thAssistant_full\March7th Assistant.exe"
        WindowTitle = "March7th"
        LogDir = "D:\March7thAssistant_full\logs"
        TimeoutMinutes = 180
        CompleteMarkers = @((S "5Lu75Yqh5a6M5oiQ77yM6YCA5Ye656CBOiAx"), (S "5Lu75Yqh5a6M5oiQLCDpgIDlh7rnoIE6IDE="))
        StopSectionMarker = (S "5YGc5q2i6L+Q6KGM")
        StopCompleteMarker = (S "LS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLSDlrozmiJAgLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0=")
        DailyFallback = @{ X = 376; Y = 808; BaseW = 1298; BaseH = 921 }
        GameProcess = "StarRail"
        ToolProcesses = @("March7th Launcher", "March7th Assistant")
    }
    MaaEnd = @{
        Exe = "C:\Users\28346\OneDrive\Desktop\MaaEnd-win-x86_64-v1.18.1\MaaEnd.exe"
        WindowTitle = "MaaEnd"
        DebugDir = "C:\Users\28346\OneDrive\Desktop\MaaEnd-win-x86_64-v1.18.1\debug"
        TimeoutMinutes = 120
        CompleteMarkers = @("kind: tasks-completed")
        StartFallback = @{ X = 759; Y = 744; BaseW = 1252; BaseH = 775 }
        WindowBounds = @{ X = 0; Y = 0; W = 1252; H = 775 }
        GameProcess = "Endfield"
        ToolProcesses = @("MaaEnd")
    }
    MAA = @{
        Exe = "F:\MAA-v5.22.2-win-x64\MAA.exe"
        WindowTitle = "MAA -"
        DebugDir = "F:\MAA-v5.22.2-win-x64\debug"
        TimeoutMinutes = 180
        CompleteMarkers = @("AllTasksCompleted")
        StartFallback = @{ X = 183; Y = 675; BaseW = 1000; BaseH = 750 }
        WindowBounds = @{ X = 0; Y = 0; W = 1000; H = 750 }
        GameProcess = $null
        ToolProcesses = @("MAA")
    }
}

$Config.BetterGI.GameProcess = "YuanShen"

$CloseGames = @{
    BetterGI = $false
    March7th = $false
    MaaEnd = $false
    MAA = $true
}

$Enabled = @{
    BetterGI = $true
    March7th = $true
    MaaEnd = $true
    MAA = $true
}

$AutomationOrder = @("BetterGI", "March7th", "MaaEnd", "MAA")

$ConfigDir = Join-Path $PSScriptRoot "config"
$LogRoot = Join-Path $PSScriptRoot "logs"
$MainLogDir = Join-Path $LogRoot "main"
$TaskLogRoot = Join-Path $LogRoot "tasks"
New-Item -ItemType Directory -Force -Path $ConfigDir, $MainLogDir, $TaskLogRoot | Out-Null

$LocalPathsPath = Join-Path $ConfigDir "LocalPaths.json"
if (Test-Path -LiteralPath $LocalPathsPath) {
    try {
        $localPaths = Get-Content -LiteralPath $LocalPathsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($taskName in @("BetterGI", "March7th", "MaaEnd", "MAA")) {
            $taskPaths = $localPaths.PSObject.Properties[$taskName]
            if ($taskPaths -and $Config.ContainsKey($taskName)) {
                foreach ($fieldName in @("Exe", "AlternateExe", "LogDir", "DebugDir")) {
                    $field = $taskPaths.Value.PSObject.Properties[$fieldName]
                    if ($field -and ![string]::IsNullOrWhiteSpace([string]$field.Value)) {
                        $Config[$taskName][$fieldName] = [string]$field.Value
                    }
                }
            }
        }
    }
    catch {
        Write-Host "Could not read LocalPaths.json; using built-in default paths"
    }
}

$RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$MainLogPath = Join-Path $MainLogDir "main-$RunStamp.log"
$script:CurrentTaskLogPath = $null
$script:MainLogPruned = $false
$script:TaskLogJustStarted = $false
$script:FailedTasks = @()

$KnownTasks = @("BetterGI", "March7th", "MaaEnd", "MAA")

function Get-SettingBool($Settings, $Name, [bool]$Default) {
    if ($null -eq $Settings) { return $Default }
    $prop = $Settings.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return [bool]$prop.Value
}

function Get-SettingInt($Settings, $Name, [int]$Default) {
    if ($null -eq $Settings) { return $Default }
    $prop = $Settings.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    $value = 0
    if ([int]::TryParse([string]$prop.Value, [ref]$value) -and $value -gt 0) { return $value }
    return $Default
}

function Remove-OldLogs($Dir, $Pattern = "*.log", $Keep = 10) {
    if (!(Test-Path -LiteralPath $Dir)) { return }
    Get-ChildItem -LiteralPath $Dir -Filter $Pattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Remove-OldLogs $MainLogDir

$SettingsPath = Join-Path $ConfigDir "AutoCloseGames.json"
if (Test-Path -LiteralPath $SettingsPath) {
    try {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        foreach ($name in $KnownTasks) {
            $CloseGames[$name] = Get-SettingBool $settings $name ([bool]$CloseGames[$name])
        }
    }
    catch {
        Write-Host "Could not read AutoCloseGames.json; using all false"
    }
}

$EnabledSettingsPath = Join-Path $ConfigDir "AutomationEnabled.json"
if (Test-Path -LiteralPath $EnabledSettingsPath) {
    try {
        $settings = Get-Content -LiteralPath $EnabledSettingsPath -Raw | ConvertFrom-Json
        foreach ($name in $KnownTasks) {
            $Enabled[$name] = Get-SettingBool $settings $name ([bool]$Enabled[$name])
        }
    }
    catch {
        Write-Host "Could not read AutomationEnabled.json; using all true"
    }
}

$OrderSettingsPath = Join-Path $ConfigDir "AutomationOrder.json"
if (Test-Path -LiteralPath $OrderSettingsPath) {
    try {
        $settings = Get-Content -LiteralPath $OrderSettingsPath -Raw | ConvertFrom-Json
        $configured = @($settings.Order) | Where-Object { $KnownTasks -contains $_ } | Select-Object -Unique
        $missing = $KnownTasks | Where-Object { $configured -notcontains $_ }
        $AutomationOrder = @($configured + $missing)
    }
    catch {
        Write-Host "Could not read AutomationOrder.json; using default order"
    }
}

$TimeoutSettingsPath = Join-Path $ConfigDir "TaskTimeouts.json"
if (Test-Path -LiteralPath $TimeoutSettingsPath) {
    try {
        $settings = Get-Content -LiteralPath $TimeoutSettingsPath -Raw | ConvertFrom-Json
        foreach ($name in $KnownTasks) {
            $Config[$name].TimeoutMinutes = Get-SettingInt $settings $name ([int]$Config[$name].TimeoutMinutes)
        }
    }
    catch {
        Write-Host "Could not read TaskTimeouts.json; using default timeouts"
    }
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int INPUT_MOUSE = 0;
}
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct INPUT {
    public int type;
    public MOUSEINPUT mi;
}
[StructLayout(LayoutKind.Sequential)]
public struct MOUSEINPUT {
    public int dx;
    public int dy;
    public uint mouseData;
    public uint dwFlags;
    public uint time;
    public IntPtr dwExtraInfo;
}
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DetachedProcess {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public Int32 cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public Int32 dwX;
        public Int32 dwY;
        public Int32 dwXSize;
        public Int32 dwYSize;
        public Int32 dwXCountChars;
        public Int32 dwYCountChars;
        public Int32 dwFillAttribute;
        public Int32 dwFlags;
        public Int16 wShowWindow;
        public Int16 cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public Int32 dwProcessId;
        public Int32 dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        UInt32 dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
"@

function Write-Step($Message) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    Write-Host $line
    Add-Content -LiteralPath $MainLogPath -Value $line -Encoding UTF8
    if (!$script:MainLogPruned) {
        Remove-OldLogs $MainLogDir
        $script:MainLogPruned = $true
    }
    if ($script:CurrentTaskLogPath -and $script:CurrentTaskLogPath -ne $MainLogPath) {
        Add-Content -LiteralPath $script:CurrentTaskLogPath -Value $line -Encoding UTF8
        if ($script:TaskLogJustStarted) {
            Remove-OldLogs ([System.IO.Path]::GetDirectoryName($script:CurrentTaskLogPath))
            $script:TaskLogJustStarted = $false
        }
    }
}

function Start-TaskLog($Name) {
    $dir = Join-Path $TaskLogRoot $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $script:CurrentTaskLogPath = Join-Path $dir "$Name-$RunStamp.log"
    $script:TaskLogJustStarted = $true
    Write-Step "Task log started: $script:CurrentTaskLogPath"
}

function Stop-TaskLog {
    if ($script:CurrentTaskLogPath) {
        Write-Step "Task log ended"
    }
    $script:CurrentTaskLogPath = $null
}

function Get-TodayLogPath($Dir, $Prefix, $Suffix = ".log") {
    $date = Get-Date -Format "yyyyMMdd"
    if ($Prefix) {
        return Join-Path $Dir "$Prefix$date$Suffix"
    }
    $dashDate = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $Dir "$dashDate$Suffix"
}

function Get-FileLength($Path) {
    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).Length
    }
    return 0
}

function Read-NewText($Path, [long]$Offset) {
    if (!(Test-Path -LiteralPath $Path)) { return "" }
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($Offset -gt $fs.Length) { $Offset = 0 }
        $fs.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $buffer = New-Object byte[] ($fs.Length - $Offset)
        [void]$fs.Read($buffer, 0, $buffer.Length)
        $utf8 = [System.Text.Encoding]::UTF8.GetString($buffer)
        $ansi = [System.Text.Encoding]::Default.GetString($buffer)
        return "$utf8`n$ansi"
    }
    finally {
        $fs.Dispose()
    }
}

function Get-WindowInfo($Process) {
    if (!$Process -or $Process.MainWindowHandle -eq 0) { return $null }
    $rect = New-Object RECT
    [NativeWin]::GetWindowRect($Process.MainWindowHandle, [ref]$rect) | Out-Null
    $w = [Math]::Max(0, $rect.Right - $rect.Left)
    $h = [Math]::Max(0, $rect.Bottom - $rect.Top)
    return [pscustomobject]@{
        Process = $Process
        Width = $w
        Height = $h
        Area = $w * $h
        Title = $Process.MainWindowTitle
    }
}

function Select-UsableWindow($Processes) {
    $windows = @()
    foreach ($p in $Processes) {
        $info = Get-WindowInfo $p
        if ($info -and $info.Width -ge 300 -and $info.Height -ge 200) {
            $windows += $info
        }
    }
    return ($windows | Sort-Object Area -Descending | Select-Object -First 1).Process
}

function Wait-ProcessWindow($TitlePart, $TimeoutSeconds = 45, $Exe = $null, $ProcessId = $null) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $processName = $null
    if ($Exe) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
    }
    while ((Get-Date) -lt $deadline) {
        $candidates = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
        $proc = Select-UsableWindow ($candidates | Where-Object { $_.MainWindowTitle -like "*$TitlePart*" })
        if (!$proc -and $ProcessId) {
            $proc = Select-UsableWindow ($candidates | Where-Object { $_.Id -eq $ProcessId })
        }
        if (!$proc -and $processName) {
            $proc = Select-UsableWindow ($candidates | Where-Object { $_.ProcessName -eq $processName })
        }
        if ($proc) {
            [NativeWin]::ShowWindow($proc.MainWindowHandle, [NativeWin]::SW_RESTORE) | Out-Null
            [NativeWin]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 500
            return $proc
        }
        Start-Sleep -Milliseconds 500
    }
    $visible = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 30 ProcessName, MainWindowTitle
    Write-Host "Visible windows:"
    $visible | ForEach-Object { Write-Host ("- {0}: {1}" -f $_.ProcessName, $_.MainWindowTitle) }
    throw "Window not found: $TitlePart"
}

function Find-ProcessWindow($TitlePart, $Exe = $null, $ProcessId = $null) {
    $processName = $null
    if ($Exe) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($Exe)
    }
    $candidates = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
    $proc = Select-UsableWindow ($candidates | Where-Object { $_.MainWindowTitle -like "*$TitlePart*" })
    if (!$proc -and $ProcessId) {
        $proc = Select-UsableWindow ($candidates | Where-Object { $_.Id -eq $ProcessId })
    }
    if (!$proc -and $processName) {
        $proc = Select-UsableWindow ($candidates | Where-Object { $_.ProcessName -eq $processName })
    }
    if ($proc) {
        [NativeWin]::ShowWindow($proc.MainWindowHandle, [NativeWin]::SW_RESTORE) | Out-Null
        [NativeWin]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 500
    }
    return $proc
}

function Maximize-AppWindow($Process) {
    [NativeWin]::ShowWindow($Process.MainWindowHandle, [NativeWin]::SW_MAXIMIZE) | Out-Null
    [NativeWin]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 800
}

function Set-AppWindowBounds($Process, $Bounds) {
    [NativeWin]::ShowWindow($Process.MainWindowHandle, [NativeWin]::SW_RESTORE) | Out-Null
    [NativeWin]::MoveWindow($Process.MainWindowHandle, $Bounds.X, $Bounds.Y, $Bounds.W, $Bounds.H, $true) | Out-Null
    [NativeWin]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 800
}

function Get-WindowElement($Process, $TitlePart = $null, $Exe = $null, $ProcessId = $null, $TimeoutSeconds = 20) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            if (!$Process -or $Process.HasExited -or $Process.MainWindowHandle -eq 0) {
                $Process = Wait-ProcessWindow $TitlePart 5 $Exe $ProcessId
            }
            $Process.Refresh()
            if ($Process.MainWindowHandle -ne 0) {
                $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
                if ($root) { return $root }
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 800
            if ($TitlePart -or $Exe -or $ProcessId) {
                $Process = Find-ProcessWindow $TitlePart $Exe $ProcessId
            }
        }
    }
    throw "Could not read window UI tree: $lastError"
}

function Invoke-ElementByName($Root, [string[]]$Names) {
    foreach ($name in $Names) {
        $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
        $element = $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if (!$element) {
            $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($candidate in $all) {
                if ($candidate.Current.Name -and $candidate.Current.Name.Contains($name)) {
                    $element = $candidate
                    break
                }
            }
        }
        if ($element) {
            Write-Step "Found UI text: $($element.Current.Name)"
            $pattern = $null
            if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
                if (-not $DryRun) { $pattern.Invoke() }
                return $true
            }
            try {
                $point = $element.GetClickablePoint()
                if (-not $DryRun) { Click-ScreenPoint $point.X $point.Y }
                return $true
            }
            catch {
                Write-Step "UI text found but not clickable directly"
            }
        }
    }
    return $false
}

function Click-ScreenPoint([int]$X, [int]$Y) {
    Write-Step "Clicking screen point: $X,$Y"
    [NativeWin]::SetCursorPos($X, $Y) | Out-Null
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($X, $Y)
    Start-Sleep -Milliseconds 250
    $pos = [System.Windows.Forms.Cursor]::Position
    Write-Step "Cursor is now at: $($pos.X),$($pos.Y)"
    $inputs = New-Object INPUT[] 2
    $inputs[0].type = [NativeWin]::INPUT_MOUSE
    $inputs[0].mi.dwFlags = [NativeWin]::MOUSEEVENTF_LEFTDOWN
    $inputs[1].type = [NativeWin]::INPUT_MOUSE
    $inputs[1].mi.dwFlags = [NativeWin]::MOUSEEVENTF_LEFTUP
    [void][NativeWin]::SendInput(2, $inputs, [Runtime.InteropServices.Marshal]::SizeOf([type][INPUT]))
    [NativeWin]::mouse_event([NativeWin]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [NativeWin]::mouse_event([NativeWin]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}

function Click-RelativeFallback($Process, $Fallback) {
    $rect = New-Object RECT
    [NativeWin]::GetWindowRect($Process.MainWindowHandle, [ref]$rect) | Out-Null
    $w = [Math]::Max(1, $rect.Right - $rect.Left)
    $h = [Math]::Max(1, $rect.Bottom - $rect.Top)
    $x = [int]($rect.Left + ($Fallback.X / $Fallback.BaseW) * $w)
    $y = [int]($rect.Top + ($Fallback.Y / $Fallback.BaseH) * $h)
    Write-Step "Window rect: left=$($rect.Left), top=$($rect.Top), width=$w, height=$h"
    if (-not $DryRun) { Click-ScreenPoint $x $y }
}

function Click-GreenButtonInWindowRegion($Process, $Label) {
    $rect = New-Object RECT
    [NativeWin]::GetWindowRect($Process.MainWindowHandle, [ref]$rect) | Out-Null
    $w = [Math]::Max(1, $rect.Right - $rect.Left)
    $h = [Math]::Max(1, $rect.Bottom - $rect.Top)
    $regionLeft = [int]($rect.Left + $w * 0.52)
    $regionTop = [int]($rect.Top + $h * 0.82)
    $regionW = [int]($w * 0.46)
    $regionH = [int]($h * 0.16)
    Write-Step "Scanning $Label green button region: left=$regionLeft, top=$regionTop, width=$regionW, height=$regionH"

    $bmp = New-Object System.Drawing.Bitmap($regionW, $regionH)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gfx.CopyFromScreen($regionLeft, $regionTop, 0, 0, $bmp.Size)
        $sumX = 0
        $sumY = 0
        $count = 0
        $minX = $regionW
        $minY = $regionH
        $maxX = 0
        $maxY = 0
        for ($y = 0; $y -lt $regionH; $y += 2) {
            for ($x = 0; $x -lt $regionW; $x += 2) {
                $p = $bmp.GetPixel($x, $y)
                if ($p.G -ge 120 -and $p.R -le 60 -and $p.B -le 120 -and ($p.G - $p.R) -ge 60) {
                    $sumX += $x
                    $sumY += $y
                    $count++
                    if ($x -lt $minX) { $minX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
        if ($count -lt 80) {
            Write-Step "$Label green button not found by visual scan; green pixels=$count"
            return $false
        }
        $centerX = [int]($regionLeft + (($minX + $maxX) / 2))
        $centerY = [int]($regionTop + (($minY + $maxY) / 2))
        Write-Step "$Label green button visual hit: pixels=$count, bounds=($minX,$minY)-($maxX,$maxY)"
        if (-not $DryRun) { Click-ScreenPoint $centerX $centerY }
        return $true
    }
    finally {
        $gfx.Dispose()
        $bmp.Dispose()
    }
}

function Send-Key($Key) {
    if (-not $DryRun) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SendKeys]::SendWait($Key)
    }
}

function Wait-LogMarker($Path, [long]$Offset, [string[]]$Markers, [int]$TimeoutMinutes) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $text = Read-NewText $Path $Offset
        foreach ($marker in $Markers) {
            if ($text.Contains($marker)) {
                return $marker
            }
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for log marker: $Path"
}

function Wait-March7thComplete($Path, [long]$Offset, $ConfigItem) {
    $deadline = (Get-Date).AddMinutes($ConfigItem.TimeoutMinutes)
    $lastStatus = Get-Date
    while ((Get-Date) -lt $deadline) {
        $text = Read-NewText $Path $Offset
        foreach ($marker in $ConfigItem.CompleteMarkers) {
            if ($text.Contains($marker)) {
                return $marker
            }
        }
        $stopIndex = $text.LastIndexOf($ConfigItem.StopSectionMarker)
        if ($stopIndex -ge 0) {
            $afterStop = $text.Substring($stopIndex)
            if ($afterStop.Contains($ConfigItem.StopCompleteMarker)) {
                return "$($ConfigItem.StopSectionMarker) -> $($ConfigItem.StopCompleteMarker)"
            }
        }
        if (((Get-Date) - $lastStatus).TotalSeconds -ge 60) {
            Write-Step "Still waiting for March7th final stop section"
            $lastStatus = Get-Date
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for March7th final completion marker: $Path"
}

function Get-LogFileOffsets($Dir, $Filter) {
    $offsets = @{}
    if (!(Test-Path -LiteralPath $Dir)) { return $offsets }
    Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -ErrorAction SilentlyContinue | ForEach-Object {
        $offsets[$_.FullName] = $_.Length
    }
    return $offsets
}

function Wait-LogMarkerInFiles($Dir, $Filter, $Offsets, [string[]]$Markers, [int]$TimeoutMinutes, $Label) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastStatus = Get-Date
    while ((Get-Date) -lt $deadline) {
        $files = @(Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($file in $files) {
            $offset = 0
            if ($Offsets.ContainsKey($file.FullName)) {
                $offset = [long]$Offsets[$file.FullName]
            }
            $text = Read-NewText $file.FullName $offset
            foreach ($marker in $Markers) {
                if ($text.Contains($marker)) {
                    return "$marker in $($file.Name)"
                }
            }
        }
        if (((Get-Date) - $lastStatus).TotalSeconds -ge 60) {
            Write-Step "Still waiting for $Label log marker in $Filter"
            $lastStatus = Get-Date
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for $Label log marker in $Dir"
}

function Get-AllWindowText($Root) {
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $items = New-Object System.Collections.Generic.List[string]
    function Walk($el) {
        if ($null -eq $el) { return }
        $name = $el.Current.Name
        if (![string]::IsNullOrWhiteSpace($name)) { $items.Add($name) }
        $child = $walker.GetFirstChild($el)
        while ($child) {
            Walk $child
            $child = $walker.GetNextSibling($child)
        }
    }
    Walk $Root
    return ($items -join "`n")
}

function Wait-WindowTextMarker($TitlePart, [string[]]$Markers, [int]$TimeoutMinutes) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $proc = Wait-ProcessWindow $TitlePart 5
        $root = Get-WindowElement $proc $TitlePart $null $null
        $text = Get-AllWindowText $root
        foreach ($marker in $Markers) {
            if ($text.Contains($marker)) {
                return $marker
            }
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for window marker: $TitlePart"
}

function Wait-WindowTextMarkerFromProcess($Process, [string[]]$Markers, [int]$TimeoutMinutes, $Label) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastStatus = Get-Date
    $readErrors = 0
    while ((Get-Date) -lt $deadline) {
        try {
            if ($Process.HasExited) {
                throw "$Label process exited before completion marker was detected"
            }
            $Process.Refresh()
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
            $text = Get-AllWindowText $root
            foreach ($marker in $Markers) {
                if ($text.Contains($marker)) {
                    return $marker
                }
            }
        }
        catch {
            $readErrors++
        }
        if (((Get-Date) - $lastStatus).TotalSeconds -ge 60) {
            Write-Step "Still waiting for $Label completion marker in background; readErrors=$readErrors"
            $lastStatus = Get-Date
        }
        Start-Sleep -Seconds 3
    }
    throw "Timed out waiting for $Label window marker in background"
}

function Start-DetachedApp($Exe) {
    $workDir = [System.IO.Path]::GetDirectoryName($Exe)
    $si = New-Object DetachedProcess+STARTUPINFO
    $si.cb = [Runtime.InteropServices.Marshal]::SizeOf([type][DetachedProcess+STARTUPINFO])
    $pi = New-Object DetachedProcess+PROCESS_INFORMATION
    $cmd = '"' + $Exe + '"'
    $createNewConsole = 0x00000010
    $createNewProcessGroup = 0x00000200
    $createBreakawayFromJob = 0x01000000
    $flags = [uint32]($createNewProcessGroup -bor $createBreakawayFromJob)
    $ok = [DetachedProcess]::CreateProcessW($Exe, $cmd, [IntPtr]::Zero, [IntPtr]::Zero, $false, $flags, [IntPtr]::Zero, $workDir, [ref]$si, [ref]$pi)
    if (!$ok) {
        $flags = [uint32]($createNewConsole -bor $createNewProcessGroup -bor $createBreakawayFromJob)
        $ok = [DetachedProcess]::CreateProcessW($Exe, $cmd, [IntPtr]::Zero, [IntPtr]::Zero, $false, $flags, [IntPtr]::Zero, $workDir, [ref]$si, [ref]$pi)
    }
    if (!$ok) {
        $flags = [uint32]($createNewConsole -bor $createNewProcessGroup)
        $ok = [DetachedProcess]::CreateProcessW($Exe, $cmd, [IntPtr]::Zero, [IntPtr]::Zero, $false, $flags, [IntPtr]::Zero, $workDir, [ref]$si, [ref]$pi)
    }
    if (!$ok) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Detached launch failed for $Exe, Win32 error: $errorCode"
    }
    try {
        return Get-Process -Id $pi.dwProcessId -ErrorAction SilentlyContinue
    }
    finally {
        if ($pi.hThread -ne [IntPtr]::Zero) { [DetachedProcess]::CloseHandle($pi.hThread) | Out-Null }
        if ($pi.hProcess -ne [IntPtr]::Zero) { [DetachedProcess]::CloseHandle($pi.hProcess) | Out-Null }
    }
}

function Start-App($Exe) {
    if (!(Test-Path -LiteralPath $Exe)) { throw "Program not found: $Exe" }
    if (-not $DryRun) {
        try {
            return Start-DetachedApp $Exe
        }
        catch {
            Write-Step "Detached launch failed; using standard launch: $($_.Exception.Message)"
            $workDir = [System.IO.Path]::GetDirectoryName($Exe)
            return Start-Process -FilePath $Exe -WorkingDirectory $workDir -WindowStyle Normal -PassThru
        }
    }
    return $null
}

function Open-AppWindow($Name, $Exe, $TitlePart) {
    $existing = Find-ProcessWindow $TitlePart $Exe
    if ($existing) {
        Write-Step "$Name is already open; reusing existing window"
        return @{ Process = $existing; StartedId = $existing.Id }
    }
    Write-Step "Starting $Name"
    $started = Start-App $Exe
    $startedId = if ($started) { $started.Id } else { $null }
    $proc = Wait-ProcessWindow $TitlePart 90 $Exe $startedId
    return @{ Process = $proc; StartedId = $startedId }
}

function Open-AppWindowWithFallback($Name, $Exe, $AlternateExe, $TitlePart) {
    try {
        return Open-AppWindow $Name $Exe $TitlePart
    }
    catch {
        if ($AlternateExe -and (Test-Path -LiteralPath $AlternateExe)) {
            Write-Step "$Name did not open with primary exe; trying alternate exe"
            return Open-AppWindow $Name $AlternateExe $TitlePart
        }
        throw
    }
}

function Open-ValidatedAppWindow($Name, $Exe, $AlternateExe, $TitlePart) {
    $attempts = @($Exe)
    if ($AlternateExe) { $attempts += $AlternateExe }
    $lastError = $null
    foreach ($attempt in $attempts) {
        if (!(Test-Path -LiteralPath $attempt)) {
            $lastError = "Program not found: $attempt"
            continue
        }
        try {
            Write-Step "Trying $Name with: $attempt"
            $opened = Open-AppWindow $Name $attempt $TitlePart
            Start-Sleep -Seconds 3
            $root = Get-WindowElement $opened.Process $TitlePart $attempt $opened.StartedId 12
            return @{ Process = $opened.Process; StartedId = $opened.StartedId; Exe = $attempt; Root = $root }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Step "$Name attempt failed: $lastError"
        }
    }
    $matching = Get-Process | Where-Object { $_.ProcessName -like "*March7th*" -or $_.ProcessName -like "*March*" } | Select-Object ProcessName, Id, MainWindowTitle
    if ($matching) {
        Write-Host "Matching March processes:"
        $matching | ForEach-Object { Write-Host ("- {0} pid={1} title={2}" -f $_.ProcessName, $_.Id, $_.MainWindowTitle) }
    }
    throw "$Name did not open a readable window: $lastError"
}

function Close-GameProcess($ProcessName, $Label) {
    if (!$ProcessName) { return }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if (!$procs) {
        Write-Step "$Label game process is not running: $ProcessName"
        return
    }
    Write-Step "Closing $Label game: $ProcessName"
    foreach ($p in $procs) {
        try {
            if ($p.MainWindowHandle -ne 0) {
                [NativeWin]::ShowWindow($p.MainWindowHandle, [NativeWin]::SW_RESTORE) | Out-Null
                [NativeWin]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
                Start-Sleep -Milliseconds 300
                $p.CloseMainWindow() | Out-Null
            }
        }
        catch {}
    }
    Start-Sleep -Seconds 8
    $remaining = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Step "$Label game is still running; forcing close"
        $remaining | Stop-Process -Force
    }
}

function Close-ProcessNames([string[]]$ProcessNames, $Label) {
    foreach ($processName in $ProcessNames) {
        if (!$processName) { continue }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($processName)
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (!$procs) { continue }
        Write-Step "Closing $Label automation process: $name"
        foreach ($p in $procs) {
            try {
                if ($p.MainWindowHandle -ne 0) {
                    $p.CloseMainWindow() | Out-Null
                }
            }
            catch {}
        }
        Start-Sleep -Seconds 2
        $remaining = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($remaining) {
            $remaining | Stop-Process -Force
        }
    }
}

function Close-GameAndAutomation($ConfigItem, $Label) {
    Close-GameProcess $ConfigItem.GameProcess $Label
    Close-ProcessNames $ConfigItem.ToolProcesses $Label
}

function Complete-TaskCleanup($ConfigItem, $Label, [bool]$ShouldClose) {
    if ($ShouldClose) {
        if ($ConfigItem.GameProcess) {
            Write-Step "$Label close-after-finish is enabled; closing game and automation"
        }
        else {
            Write-Step "$Label close-after-finish is enabled; closing automation only"
        }
        Close-GameAndAutomation $ConfigItem $Label
    }
    else {
        if ($ConfigItem.GameProcess) {
            Write-Step "$Label close-after-finish is disabled; keeping game and automation running"
        }
        else {
            Write-Step "$Label close-after-finish is disabled; keeping automation running"
        }
    }
}

function Wait-TaskBuffer($PreviousLabel) {
    Write-Step "$PreviousLabel finished; waiting 10 seconds before next automation"
    Start-Sleep -Seconds 10
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TaskRunnable($Name) {
    if ($Name -eq "BetterGI") { return (!$SkipBetterGI -and ($IgnoreEnabled -or $Enabled.BetterGI)) }
    if ($Name -eq "March7th") { return (!$SkipMarch7th -and ($IgnoreEnabled -or $Enabled.March7th)) }
    if ($Name -eq "MaaEnd") { return (!$SkipMaaEnd -and ($IgnoreEnabled -or $Enabled.MaaEnd)) }
    if ($Name -eq "MAA") { return (!$SkipMAA -and ($IgnoreEnabled -or $Enabled.MAA)) }
    return $false
}

function Invoke-AutomationTask($Name) {
    if ($Name -eq "BetterGI") { Run-BetterGI; return }
    if ($Name -eq "March7th") { Run-March7th; return }
    if ($Name -eq "MaaEnd") { Run-MaaEnd; return }
    if ($Name -eq "MAA") { Run-MAA; return }
    throw "Unknown automation task: $Name"
}

function Test-Environment {
    Write-Step "Environment check started"
    if (!$DryRun -and !(Test-IsAdmin)) {
        throw "Administrator permission is required. Please run StartGameAutomation.bat."
    }
    foreach ($name in $AutomationOrder) {
        if (!(Test-TaskRunnable $name)) { continue }
        $c = $Config[$name]
        $exeAvailable = Test-Path -LiteralPath $c.Exe
        if (!$exeAvailable -and $c.AlternateExe) {
            $exeAvailable = Test-Path -LiteralPath $c.AlternateExe
        }
        if (!$exeAvailable) {
            Write-Step "$name warning: executable not found now; this task will retry later and skip if still missing"
        }
        if ($c.LogDir -and !(Test-Path -LiteralPath $c.LogDir)) {
            Write-Step "$name warning: log directory not found now; this task may fail and retry later: $($c.LogDir)"
        }
        if ($c.DebugDir -and !(Test-Path -LiteralPath $c.DebugDir)) {
            Write-Step "$name warning: debug directory not found now; this task may fail and retry later: $($c.DebugDir)"
        }
        if ([int]$c.TimeoutMinutes -le 0) {
            throw "$name timeout must be greater than 0"
        }
        Write-Step "$name checked: timeout=$($c.TimeoutMinutes) minutes"
    }
    Write-Step "Environment check passed"
}

function Invoke-TaskWithRetry($Name, $MaxAttempts = 3) {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Start-TaskLog $Name
        try {
            Write-Step "$Name attempt $attempt/$MaxAttempts"
            Invoke-AutomationTask $Name
            Write-Step "$Name succeeded"
            return $true
        }
        catch {
            Write-Step "$Name failed on attempt $attempt/$($MaxAttempts): $($_.Exception.Message)"
            if ($attempt -lt $MaxAttempts) {
                Write-Step "$Name will retry after 10 seconds"
                Start-Sleep -Seconds 10
            }
            else {
                Write-Step "$Name failed after $MaxAttempts attempts; skipping"
                $script:FailedTasks += $Name
                return $false
            }
        }
        finally {
            Stop-TaskLog
        }
    }
    return $false
}

function Run-BetterGI {
    $c = $Config.BetterGI
    $log = Get-TodayLogPath $c.LogDir $c.LogPrefix
    $offset = Get-FileLength $log
    $opened = Open-AppWindow "BetterGI" $c.Exe $c.WindowTitle
    $proc = $opened.Process
    $startedId = $opened.StartedId
    $root = Get-WindowElement $proc $c.WindowTitle $c.Exe $startedId
    Write-Step "Opening BetterGI one-dragon page"
    if (!(Invoke-ElementByName $root @((S "5LiA5p2h6b6Z")))) {
        Write-Step "One-dragon page not clickable by UI text; using fallback click"
        Click-RelativeFallback $proc $c.OneDragonFallback
    }
    Start-Sleep -Seconds 1
    $proc = Wait-ProcessWindow $c.WindowTitle 30 $c.Exe $startedId
    Write-Step "Starting BetterGI one-dragon task"
    Click-RelativeFallback $proc $c.OneDragonPlayFallback
    Write-Step "Waiting for BetterGI log marker"
    $marker = Wait-LogMarker $log $offset $c.LogCompleteMarkers $c.TimeoutMinutes
    Write-Step "BetterGI done: $marker"
    Complete-TaskCleanup $c "BetterGI" ([bool]$CloseGames.BetterGI)
}

function Run-March7th {
    $c = $Config.March7th
    $log = Get-TodayLogPath $c.LogDir $null
    $offset = Get-FileLength $log
    Write-Step "Starting March7th command runner"
    Start-App $c.AlternateExe | Out-Null
    Write-Step "Waiting for March7th final stop section"
    $marker = Wait-March7thComplete $log $offset $c
    Write-Step "March7th done: $marker"
    Complete-TaskCleanup $c "March7th" ([bool]$CloseGames.March7th)
}

function Run-MaaEnd {
    $c = $Config.MaaEnd
    $maaLogFilter = "$(Get-Date -Format 'yyyy-MM-dd')-*.log"
    $maaOffsets = Get-LogFileOffsets $c.DebugDir $maaLogFilter
    $opened = Open-AppWindow "MaaEnd" $c.Exe $c.WindowTitle
    $proc = $opened.Process
    Start-Sleep -Seconds 3
    Set-AppWindowBounds $proc $c.WindowBounds
    $root = Get-WindowElement $proc $c.WindowTitle $c.Exe $opened.StartedId
    if (!(Invoke-ElementByName $root @((S "5byA5aeL5Lu75Yqh"), (S "4pa3IOW8gOWni+S7u+WKoQ=="), (S "4pa2IOW8gOWni+S7u+WKoQ==")))) {
        Write-Step "MaaEnd start button not found by UI text; trying visual green-button scan"
        if (!(Click-GreenButtonInWindowRegion $proc "MaaEnd start")) {
            Write-Step "MaaEnd visual scan failed; using final coordinate fallback"
            Click-RelativeFallback $proc $c.StartFallback
        }
    }
    Write-Step "Waiting for MaaEnd debug log marker"
    $marker = Wait-LogMarkerInFiles $c.DebugDir $maaLogFilter $maaOffsets $c.CompleteMarkers $c.TimeoutMinutes "MaaEnd"
    Write-Step "MaaEnd done: $marker"
    Complete-TaskCleanup $c "MaaEnd" ([bool]$CloseGames.MaaEnd)
}

function Run-MAA {
    $c = $Config.MAA
    $maaOffsets = Get-LogFileOffsets $c.DebugDir "asst*.log"
    $opened = Open-AppWindow "MAA" $c.Exe $c.WindowTitle
    $proc = $opened.Process
    Start-Sleep -Seconds 3
    Set-AppWindowBounds $proc $c.WindowBounds
    $root = Get-WindowElement $proc $c.WindowTitle $c.Exe $opened.StartedId
    Write-Step "Opening MAA one-click page"
    [void](Invoke-ElementByName $root @((S "5LiA6ZSu6ZW/6I2J")))
    Start-Sleep -Seconds 1
    $root = Get-WindowElement $proc $c.WindowTitle $c.Exe $opened.StartedId
    Write-Step "Starting MAA one-click task"
    if (!(Invoke-ElementByName $root @("Link Start!"))) {
        Write-Step "MAA Link Start button not found by UI text; using fallback click"
        Click-RelativeFallback $proc $c.StartFallback
    }
    Write-Step "Waiting for MAA debug log marker"
    $marker = Wait-LogMarkerInFiles $c.DebugDir "asst*.log" $maaOffsets $c.CompleteMarkers $c.TimeoutMinutes "MAA"
    Write-Step "MAA done: $marker"
    Complete-TaskCleanup $c "MAA" ([bool]$CloseGames.MAA)
}

try {
    Write-Step "Automation order: $($AutomationOrder -join ' -> ')"
    Write-Step "Main log: $MainLogPath"
    Test-Environment
    $runnable = @($AutomationOrder | Where-Object { Test-TaskRunnable $_ })
    foreach ($name in $AutomationOrder) {
        if (!(Test-TaskRunnable $name)) {
            Write-Step "Skipping $name"
            continue
        }
        [void](Invoke-TaskWithRetry $name 3)
        $currentIndex = [array]::IndexOf($runnable, $name)
        if ($currentIndex -ge 0 -and $currentIndex -lt ($runnable.Count - 1)) {
            Wait-TaskBuffer $name
        }
    }
    if ($script:FailedTasks.Count -gt 0) {
        Write-Step "All runnable tasks finished, with failures: $($script:FailedTasks -join ', ')"
    }
    else {
        Write-Step "All tasks completed"
    }
}
catch {
    Write-Host ""
    Write-Host "Run stopped: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Send this output to me and I can tune recognition or fallback positions."
    exit 1
}
