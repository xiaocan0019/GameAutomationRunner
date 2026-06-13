# 游戏自动化一键启动器

## 项目概述

本项目用于按指定顺序启动多个游戏自动化软件，并在当前任务完成后自动进入下一个任务。当前内置支持：

- BetterGI
- March7th
- MaaEnd
- MAA

主流程支持任务排序、启用/禁用、失败重试、失败跳过、任务超时、运行日志、任务完成后关闭软件等功能。

## 适用范围

本项目可以分享给其他人使用，但前提是目标电脑上的自动化软件仍保持默认窗口标题、默认按钮文字、默认日志格式和默认任务完成标志。

在这个前提下，其他用户通常只需要修改本机路径，例如：

- 自动化软件 `.exe` 路径
- 日志目录
- debug 日志目录

窗口大小、程序标题、按钮文字和日志完成标志如果保持软件默认设置，通常不需要修改脚本。

## 首次使用

建议按以下顺序操作：

1. 运行 `SetupLocalConfig.bat`
2. 按提示填写或确认本机路径
3. 运行 `Configure.bat`
4. 设置运行顺序、启用状态、超时时间和完成后关闭行为
5. 运行 `StartGameAutomation.bat`

## 本地路径初始化

`SetupLocalConfig.bat` 是给新电脑或分享用户使用的本地初始化入口。

它会依次询问：

- BetterGI 主程序路径
- BetterGI 日志目录
- March7th Launcher 路径
- March7th Assistant 备用路径
- March7th 日志目录
- MaaEnd 主程序路径
- MaaEnd debug 日志目录
- MAA 主程序路径
- MAA debug 日志目录

输入规则：

- 直接回车：保留当前默认值
- 粘贴路径：保存为新的本机路径
- 路径带双引号也可以
- 路径不存在时会提示确认，确认后仍可保存

本地路径会保存到：

`app\config\LocalPaths.json`

主程序和配置菜单都会优先读取这个文件。这样分享项目时，使用者不需要直接修改 `.ps1` 脚本。

## 常用入口

- `StartGameAutomation.bat`  
  按配置顺序运行所有启用的自动化任务。

- `Configure.bat`  
  打开配置菜单。

- `SetupLocalConfig.bat`  
  初始化或修改本机路径。

## 单独运行入口

以下入口会忽略“启用/禁用”配置，只运行对应任务，适合调试：

- `shortcuts\RunBetterGI.bat`
- `shortcuts\RunMarch7th.bat`
- `shortcuts\RunMaaEnd.bat`
- `shortcuts\RunMAA.bat`

## 配置菜单

`Configure.bat` 中包含两类功能。

配置管理：

- 查看当前配置
- 设置运行顺序
- 启用或禁用自动化
- 设置完成后关闭行为
- 设置任务超时时间
- 恢复默认配置

快速打开软件：

- 打开 BetterGI
- 打开 March7th
- 打开 MaaEnd
- 打开 MAA

快速打开软件只会启动软件本体，不会点击开始任务，也不会等待日志。

## 配置文件

配置文件位于：

`app\config`

主要文件：

- `LocalPaths.json`：本机路径配置
- `AutomationOrder.json`：运行顺序
- `AutomationEnabled.json`：启用/禁用
- `AutoCloseGames.json`：完成后是否关闭游戏和自动化软件
- `TaskTimeouts.json`：任务超时时间

普通用户优先使用 `SetupLocalConfig.bat` 和 `Configure.bat` 修改配置，不建议直接编辑 JSON。

## 失败处理逻辑

主程序会在启动时检查管理员权限、路径和日志目录。

管理员权限是全局要求。如果没有管理员权限，主程序会停止，因为窗口控制和点击操作可能无法正常执行。

如果某个自动化软件或日志目录不存在，主程序不会直接停止全部流程，而是记录警告。运行到该任务时：

1. 任务失败后等待 10 秒
2. 最多重试 3 次
3. 仍失败则跳过该任务
4. 继续执行下一个启用任务

因此，分享给别人时，即使对方没有安装其中某个自动化软件，也不会阻塞其它任务。

## 当前任务完成判断

- BetterGI：读取 BetterGI 当天日志中的一条龙完成标志
- March7th：读取 March7th 当天日志中的最终停止完成段
- MaaEnd：读取 debug 日志中的 `kind: tasks-completed`
- MAA：读取 `debug\asst*.log` 中的 `AllTasksCompleted`

日志判断只读取本次任务启动后的新增内容，避免被旧日志误判。

## 当前关闭策略

完成后关闭行为由 `Configure.bat` 控制。

- BetterGI：可配置是否关闭原神和 BetterGI
- March7th：可配置是否关闭星铁和 March7th
- MaaEnd：可配置是否关闭终末地和 MaaEnd
- MAA：默认只关闭 MAA，不关闭模拟器或游戏

## 分享给其他人时的建议

建议分享整个 `outputs` 文件夹，并提醒使用者先运行：

`SetupLocalConfig.bat`

如果希望提供一份干净版本，可以保留脚本和示例配置，但让使用者重新生成本机路径配置。

分享时应提醒对方：

- 使用 Windows 系统
- 使用 Windows PowerShell 5 或更高版本
- 主程序需要管理员权限
- 自动化软件尽量保持默认窗口标题和默认日志格式
- 如果软件版本变化导致日志完成标志变化，需要调整脚本
- 如果窗口布局变化导致兜底坐标失效，需要重新校准坐标

## 新增自动化软件

新增其它自动化软件时，建议遵循以下顺序：

1. 优先使用日志判断任务完成
2. 优先使用 UI 文字识别点击按钮
3. 文字识别失败时再使用固定坐标兜底
4. 为任务设置独立超时时间
5. 加入启用/禁用配置
6. 加入完成后关闭配置
7. 加入单独运行快捷入口
8. 加入本地路径初始化配置

需要修改的主要文件：

- `app\GameAutomationRunner.ps1`
- `app\Configure.ps1`
- `app\SetupLocalConfig.ps1`
- `shortcuts`
- `README.md`

## 编码注意事项

`.ps1` 文件建议保存为 UTF-8 with BOM。这样可以避免 Windows PowerShell 5 在读取中文菜单、中文按钮文字和中文提示时出现乱码或语法解析错误。
