$ErrorActionPreference = "Stop"

$ConfigDir = Join-Path $PSScriptRoot "config"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$KnownTasks = @("BetterGI", "March7th", "MaaEnd", "MAA")
$AutoClosePath = Join-Path $ConfigDir "AutoCloseGames.json"
$EnabledPath = Join-Path $ConfigDir "AutomationEnabled.json"
$OrderPath = Join-Path $ConfigDir "AutomationOrder.json"
$TimeoutPath = Join-Path $ConfigDir "TaskTimeouts.json"
$LocalPathsPath = Join-Path $ConfigDir "LocalPaths.json"

$TaskLabels = @{
    BetterGI = "BetterGI"
    March7th = "March7th"
    MaaEnd = "MaaEnd"
    MAA = "MAA"
}

$OpenTargets = @{
    BetterGI = @{
        Name = $TaskLabels.BetterGI
        Exe = "C:\Path\To\BetterGI\BetterGI.exe"
    }
    March7th = @{
        Name = $TaskLabels.March7th
        Exe = "C:\Path\To\March7thAssistant\March7th Launcher.exe"
        AlternateExe = "C:\Path\To\March7thAssistant\March7th Assistant.exe"
    }
    MaaEnd = @{
        Name = $TaskLabels.MaaEnd
        Exe = "C:\Path\To\MaaEnd\MaaEnd.exe"
    }
    MAA = @{
        Name = $TaskLabels.MAA
        Exe = "C:\Path\To\MAA\MAA.exe"
    }
}

function Read-JsonOrDefault($Path, $Default) {
    if (Test-Path -LiteralPath $Path) {
        try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
        catch {}
    }
    return $Default
}

function Save-Json($Path, $Object) {
    $Object | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Apply-LocalPathsToOpenTargets {
    if (!(Test-Path -LiteralPath $LocalPathsPath)) { return }
    try {
        $localPaths = Get-Content -LiteralPath $LocalPathsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($task in $KnownTasks) {
            $taskPaths = $localPaths.PSObject.Properties[$task]
            if (!$taskPaths -or !$OpenTargets.ContainsKey($task)) { continue }
            foreach ($fieldName in @("Exe", "AlternateExe")) {
                $field = $taskPaths.Value.PSObject.Properties[$fieldName]
                if ($field -and ![string]::IsNullOrWhiteSpace([string]$field.Value)) {
                    $OpenTargets[$task][$fieldName] = [string]$field.Value
                }
            }
        }
    }
    catch {
        Write-Host "无法读取本地路径配置，将使用默认路径。"
    }
}

Apply-LocalPathsToOpenTargets

function Get-EnabledConfig {
    $default = [pscustomobject]@{ BetterGI = $true; March7th = $true; MaaEnd = $true; MAA = $true }
    return Read-JsonOrDefault $EnabledPath $default
}

function Get-CloseConfig {
    $default = [pscustomobject]@{ BetterGI = $false; March7th = $false; MaaEnd = $false; MAA = $true }
    return Read-JsonOrDefault $AutoClosePath $default
}

function Get-OrderConfig {
    $default = [pscustomobject]@{ Order = $KnownTasks }
    $loaded = Read-JsonOrDefault $OrderPath $default
    $configured = @($loaded.Order) | Where-Object { $KnownTasks -contains $_ } | Select-Object -Unique
    $missing = $KnownTasks | Where-Object { $configured -notcontains $_ }
    return @($configured + $missing)
}

function Get-TimeoutConfig {
    $default = [pscustomobject]@{ BetterGI = 180; March7th = 180; MaaEnd = 120; MAA = 180 }
    return Read-JsonOrDefault $TimeoutPath $default
}

function Get-ConfigBool($Config, $Task, [bool]$Default) {
    $prop = $Config.PSObject.Properties[$Task]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return [bool]$prop.Value
}

function Get-ConfigInt($Config, $Task, [int]$Default) {
    $prop = $Config.PSObject.Properties[$Task]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    $value = 0
    if ([int]::TryParse([string]$prop.Value, [ref]$value) -and $value -gt 0) { return $value }
    return $Default
}

function Ask-YesNo($Question, [bool]$Default) {
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $answer = Read-Host "$Question ($hint)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -match '^(y|Y|yes|YES|1|是|开|开启)$') { return $true }
        if ($answer -match '^(n|N|no|NO|0|否|关|关闭)$') { return $false }
        Write-Host "请输入 y/是 或 n/否。"
    }
}

function Show-Config {
    $enabled = Get-EnabledConfig
    $close = Get-CloseConfig
    $order = Get-OrderConfig
    $timeouts = Get-TimeoutConfig
    Write-Host ""
    Write-Host "当前配置"
    Write-Host "运行顺序：$($order -join ' -> ')"
    foreach ($task in $KnownTasks) {
        Write-Host ("{0}: 启用={1}, 完成后关闭={2}, 超时={3} 分钟" -f $task, (Get-ConfigBool $enabled $task $true), (Get-ConfigBool $close $task $false), (Get-ConfigInt $timeouts $task 180))
    }
}

function Configure-Order {
    Write-Host ""
    Write-Host "设置自动化运行顺序"
    Write-Host "1. BetterGI"
    Write-Host "2. March7th"
    Write-Host "3. MaaEnd"
    Write-Host "4. MAA"
    Write-Host "当前顺序：$((Get-OrderConfig) -join ' -> ')"
    while ($true) {
        $answer = Read-Host "请输入顺序编号，例如 1,2,3,4"
        $parts = $answer -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($parts.Count -ne $KnownTasks.Count) {
            Write-Host "请把所有编号都输入一次。"
            continue
        }
        $seen = @{}
        $order = @()
        $valid = $true
        foreach ($part in $parts) {
            if ($part -notmatch '^[1-4]$' -or $seen.ContainsKey($part)) {
                $valid = $false
                break
            }
            $seen[$part] = $true
            $order += $KnownTasks[[int]$part - 1]
        }
        if ($valid) {
            Save-Json $OrderPath ([ordered]@{ Order = $order })
            Write-Host "已保存顺序：$($order -join ' -> ')"
            return
        }
        Write-Host "顺序无效。请确保每个编号只出现一次。"
    }
}

function Configure-Enabled {
    $current = Get-EnabledConfig
    $next = [ordered]@{
        BetterGI = $(Ask-YesNo "启用 BetterGI 自动化" (Get-ConfigBool $current "BetterGI" $true))
        March7th = $(Ask-YesNo "启用 March7th 自动化" (Get-ConfigBool $current "March7th" $true))
        MaaEnd = $(Ask-YesNo "启用 MaaEnd 自动化" (Get-ConfigBool $current "MaaEnd" $true))
        MAA = $(Ask-YesNo "启用 MAA 自动化" (Get-ConfigBool $current "MAA" $true))
    }
    Save-Json $EnabledPath $next
    Write-Host "已保存启用/禁用设置。"
}

function Configure-AutoClose {
    $current = Get-CloseConfig
    $next = [ordered]@{
        BetterGI = $(Ask-YesNo "BetterGI 完成后关闭原神和 BetterGI" (Get-ConfigBool $current "BetterGI" $false))
        March7th = $(Ask-YesNo "March7th 完成后关闭星铁和 March7th" (Get-ConfigBool $current "March7th" $false))
        MaaEnd = $(Ask-YesNo "MaaEnd 完成后关闭终末地和 MaaEnd" (Get-ConfigBool $current "MaaEnd" $false))
        MAA = $(Ask-YesNo "MAA 完成后只关闭 MAA，不关闭模拟器/游戏" (Get-ConfigBool $current "MAA" $true))
    }
    Save-Json $AutoClosePath $next
    Write-Host "已保存完成后关闭设置。"
}

function Ask-PositiveInt($Question, [int]$Default) {
    while ($true) {
        $answer = Read-Host "$Question [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $value = 0
        if ([int]::TryParse($answer, [ref]$value) -and $value -gt 0) {
            return $value
        }
        Write-Host "请输入正整数。"
    }
}

function Configure-Timeouts {
    $current = Get-TimeoutConfig
    Write-Host ""
    Write-Host "设置每个任务的超时时间，单位：分钟。"
    $next = [ordered]@{
        BetterGI = $(Ask-PositiveInt "BetterGI 超时分钟数" (Get-ConfigInt $current "BetterGI" 180))
        March7th = $(Ask-PositiveInt "March7th 超时分钟数" (Get-ConfigInt $current "March7th" 180))
        MaaEnd = $(Ask-PositiveInt "MaaEnd 超时分钟数" (Get-ConfigInt $current "MaaEnd" 120))
        MAA = $(Ask-PositiveInt "MAA 超时分钟数" (Get-ConfigInt $current "MAA" 180))
    }
    Save-Json $TimeoutPath $next
    Write-Host "已保存超时设置。"
}

function Reset-Defaults {
    Save-Json $OrderPath ([ordered]@{ Order = $KnownTasks })
    Save-Json $EnabledPath ([ordered]@{ BetterGI = $true; March7th = $true; MaaEnd = $true; MAA = $true })
    Save-Json $AutoClosePath ([ordered]@{ BetterGI = $false; March7th = $false; MaaEnd = $false; MAA = $true })
    Save-Json $TimeoutPath ([ordered]@{ BetterGI = 180; March7th = 180; MaaEnd = 120; MAA = 180 })
    Write-Host "已恢复默认配置。"
}

function Start-ConfiguredSoftware($Exe, $Name) {
    if (!(Test-Path -LiteralPath $Exe)) {
        Write-Host "未找到程序：$Exe"
        return $false
    }
    $workDir = [System.IO.Path]::GetDirectoryName($Exe)
    Start-Process -FilePath $Exe -WorkingDirectory $workDir
    Write-Host "已打开 $Name：$Exe"
    return $true
}

function Open-Software($Task) {
    $target = $OpenTargets[$Task]
    if (!$target) {
        Write-Host "未知软件：$Task"
        return
    }
    $opened = Start-ConfiguredSoftware $target.Exe $target.Name
    if (!$opened -and $target.AlternateExe) {
        Write-Host "正在尝试备用路径。"
        [void](Start-ConfiguredSoftware $target.AlternateExe $target.Name)
    }
}

while ($true) {
    Write-Host ""
    Write-Host "游戏自动化配置"
    Write-Host ""
    Write-Host "配置管理"
    Write-Host "1. 查看当前配置"
    Write-Host "2. 设置运行顺序"
    Write-Host "3. 启用或禁用自动化"
    Write-Host "4. 设置完成后关闭行为"
    Write-Host "5. 设置任务超时时间"
    Write-Host "6. 恢复默认配置"
    Write-Host ""
    Write-Host "快速打开软件"
    Write-Host "7. 打开 BetterGI"
    Write-Host "8. 打开 March7th"
    Write-Host "9. 打开 MaaEnd"
    Write-Host "10. 打开 MAA"
    Write-Host ""
    Write-Host "0. 退出"
    $choice = Read-Host "请选择"
    switch ($choice) {
        "1" { Show-Config }
        "2" { Configure-Order }
        "3" { Configure-Enabled }
        "4" { Configure-AutoClose }
        "5" { Configure-Timeouts }
        "6" { Reset-Defaults }
        "7" { Open-Software "BetterGI" }
        "8" { Open-Software "March7th" }
        "9" { Open-Software "MaaEnd" }
        "10" { Open-Software "MAA" }
        "0" { return }
        default { Write-Host "未知选项。" }
    }
}
