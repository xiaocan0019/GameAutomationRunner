$ErrorActionPreference = "Stop"

$ConfigDir = Join-Path $PSScriptRoot "config"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$LocalPathsPath = Join-Path $ConfigDir "LocalPaths.json"

$DefaultPaths = [ordered]@{
    BetterGI = [ordered]@{
        Exe = "C:\Path\To\BetterGI\BetterGI.exe"
        LogDir = "C:\Path\To\BetterGI\log"
    }
    March7th = [ordered]@{
        Exe = "C:\Path\To\March7thAssistant\March7th Launcher.exe"
        AlternateExe = "C:\Path\To\March7thAssistant\March7th Assistant.exe"
        LogDir = "C:\Path\To\March7thAssistant\logs"
    }
    MaaEnd = [ordered]@{
        Exe = "C:\Path\To\MaaEnd\MaaEnd.exe"
        DebugDir = "C:\Path\To\MaaEnd\debug"
    }
    MAA = [ordered]@{
        Exe = "C:\Path\To\MAA\MAA.exe"
        DebugDir = "C:\Path\To\MAA\debug"
    }
}

function Read-JsonOrDefault($Path, $Default) {
    if (Test-Path -LiteralPath $Path) {
        try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch {}
    }
    return $Default
}

function Get-ObjectValue($Object, $Name, $Default) {
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return $Default }
    return [string]$prop.Value
}

function Get-TaskConfig($Object, $TaskName) {
    if ($null -ne $Object) {
        $prop = $Object.PSObject.Properties[$TaskName]
        if ($prop -and $prop.Value) { return $prop.Value }
    }
    return [pscustomobject]$DefaultPaths[$TaskName]
}

function Normalize-InputPath($Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $text = $Value.Trim()
    if ($text.StartsWith('"') -and $text.EndsWith('"') -and $text.Length -ge 2) {
        $text = $text.Substring(1, $text.Length - 2)
    }
    return $text.Trim()
}

function Confirm-YesNo($Question, [bool]$Default) {
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $answer = Read-Host "$Question ($hint)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -match '^(y|Y|yes|YES|1|是|开|开启)$') { return $true }
        if ($answer -match '^(n|N|no|NO|0|否|关|关闭)$') { return $false }
        Write-Host "请输入 y/是 或 n/否。"
    }
}

function Ask-Path($Title, $Default, [bool]$MustBeDirectory) {
    while ($true) {
        Write-Host ""
        Write-Host $Title
        Write-Host "当前值：$Default"
        $inputValue = Read-Host "请输入新路径，直接回车保留当前值"
        $path = Normalize-InputPath $inputValue
        if ([string]::IsNullOrWhiteSpace($path)) { $path = $Default }

        $exists = if ($MustBeDirectory) {
            Test-Path -LiteralPath $path -PathType Container
        }
        else {
            Test-Path -LiteralPath $path -PathType Leaf
        }

        if ($exists) { return $path }

        Write-Host "警告：该路径当前不存在：$path"
        if (Confirm-YesNo "仍然保存这个路径吗" $false) { return $path }
    }
}

function Get-ChildDirFromExe($Exe, $ChildName, $Fallback) {
    try {
        if (![string]::IsNullOrWhiteSpace($Exe)) {
            return Join-Path ([System.IO.Path]::GetDirectoryName($Exe)) $ChildName
        }
    }
    catch {}
    return $Fallback
}

$current = Read-JsonOrDefault $LocalPathsPath ([pscustomobject]$DefaultPaths)
$result = [ordered]@{}

Write-Host ""
Write-Host "本地路径初始化配置"
Write-Host "这个工具只配置每台电脑不同的路径。窗口标题、按钮文字和完成标志沿用程序默认设置。"
Write-Host "路径可以直接从资源管理器复制，带双引号也可以。"

$betterCurrent = Get-TaskConfig $current "BetterGI"
$betterExe = Ask-Path "BetterGI 主程序路径，例如 C:\Path\To\BetterGI\BetterGI.exe" (Get-ObjectValue $betterCurrent "Exe" $DefaultPaths.BetterGI.Exe) $false
$betterLogDefault = Get-ObjectValue $betterCurrent "LogDir" (Get-ChildDirFromExe $betterExe "log" $DefaultPaths.BetterGI.LogDir)
$betterLog = Ask-Path "BetterGI 日志目录，例如 C:\Path\To\BetterGI\log" $betterLogDefault $true
$result.BetterGI = [ordered]@{ Exe = $betterExe; LogDir = $betterLog }

$marchCurrent = Get-TaskConfig $current "March7th"
$marchExe = Ask-Path "March7th Launcher 路径，例如 C:\Path\To\March7thAssistant\March7th Launcher.exe" (Get-ObjectValue $marchCurrent "Exe" $DefaultPaths.March7th.Exe) $false
$marchAlt = Ask-Path "March7th Assistant 备用路径，例如 C:\Path\To\March7thAssistant\March7th Assistant.exe" (Get-ObjectValue $marchCurrent "AlternateExe" $DefaultPaths.March7th.AlternateExe) $false
$marchLogDefault = Get-ObjectValue $marchCurrent "LogDir" (Get-ChildDirFromExe $marchExe "logs" $DefaultPaths.March7th.LogDir)
$marchLog = Ask-Path "March7th 日志目录，例如 C:\Path\To\March7thAssistant\logs" $marchLogDefault $true
$result.March7th = [ordered]@{ Exe = $marchExe; AlternateExe = $marchAlt; LogDir = $marchLog }

$maaEndCurrent = Get-TaskConfig $current "MaaEnd"
$maaEndExe = Ask-Path "MaaEnd 主程序路径，例如 C:\...\MaaEnd.exe" (Get-ObjectValue $maaEndCurrent "Exe" $DefaultPaths.MaaEnd.Exe) $false
$maaEndDebugDefault = Get-ObjectValue $maaEndCurrent "DebugDir" (Get-ChildDirFromExe $maaEndExe "debug" $DefaultPaths.MaaEnd.DebugDir)
$maaEndDebug = Ask-Path "MaaEnd debug 日志目录，例如 C:\...\debug" $maaEndDebugDefault $true
$result.MaaEnd = [ordered]@{ Exe = $maaEndExe; DebugDir = $maaEndDebug }

$maaCurrent = Get-TaskConfig $current "MAA"
$maaExe = Ask-Path "MAA 主程序路径，例如 C:\Path\To\MAA\MAA.exe" (Get-ObjectValue $maaCurrent "Exe" $DefaultPaths.MAA.Exe) $false
$maaDebugDefault = Get-ObjectValue $maaCurrent "DebugDir" (Get-ChildDirFromExe $maaExe "debug" $DefaultPaths.MAA.DebugDir)
$maaDebug = Ask-Path "MAA debug 日志目录，例如 C:\Path\To\MAA\debug" $maaDebugDefault $true
$result.MAA = [ordered]@{ Exe = $maaExe; DebugDir = $maaDebug }

$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LocalPathsPath -Encoding UTF8

Write-Host ""
Write-Host "本地路径配置已保存：$LocalPathsPath"
Write-Host "下一步可以运行 Configure.bat 调整启用状态、顺序、超时和完成后关闭行为。"
