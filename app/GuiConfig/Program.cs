using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GameAutomationConfig;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class TaskItem
{
    public string Key { get; }
    public string Name { get; }
    public bool Enabled { get; set; }
    public bool CloseAfterFinish { get; set; }
    public int TimeoutMinutes { get; set; }
    public string Exe { get; set; } = "";
    public string AlternateExe { get; set; } = "";
    public string LogDir { get; set; } = "";
    public string DebugDir { get; set; } = "";

    public TaskItem(string key, string name)
    {
        Key = key;
        Name = name;
    }
}

internal sealed class PathCandidate
{
    public string Task { get; init; } = "";
    public string Field { get; init; } = "";
    public string Value { get; init; } = "";
    public string Source { get; init; } = "";
    public int Confidence { get; init; }
}

internal sealed class PathDetectionResult
{
    public Dictionary<string, Dictionary<string, string>> Values { get; } = new();
    public List<string> Messages { get; } = new();
    public int AppliedCount { get; set; }
}

internal sealed class MainForm : Form
{
    private readonly string[] _knownTasks = { "BetterGI", "March7th", "MaaEnd", "MAA" };
    private readonly Dictionary<string, string> _taskNames = new()
    {
        ["BetterGI"] = "BetterGI",
        ["March7th"] = "March7th",
        ["MaaEnd"] = "MaaEnd",
        ["MAA"] = "MAA"
    };

    private readonly Dictionary<string, TaskItem> _tasks = new();
    private readonly List<string> _order = new();
    private readonly Dictionary<string, Dictionary<string, TextBox>> _pathBoxes = new();

    private readonly string _rootDir;
    private readonly string _configDir;

    private DataGridView _taskGrid = null!;
    private Label _status = null!;
    private int _dragRowIndex = -1;

    public MainForm()
    {
        _rootDir = LocateRootDirectory();
        _configDir = Path.Combine(_rootDir, "app", "config");
        Directory.CreateDirectory(_configDir);

        Text = "Game Automation Runner 配置器";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(980, 680);
        Size = new Size(1080, 760);
        Font = new Font("Microsoft YaHei UI", 9F);

        InitializeDefaults();
        LoadConfig();
        BuildUi();
        RefreshTaskGrid();
        LoadPathTextBoxes();
    }

    private string LocateRootDirectory()
    {
        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 5 && dir != null; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "app", "config")) ||
                File.Exists(Path.Combine(dir, "StartGameAutomation.bat")))
            {
                return dir;
            }
            dir = Directory.GetParent(dir)?.FullName;
        }
        return AppContext.BaseDirectory;
    }

    private void InitializeDefaults()
    {
        _tasks["BetterGI"] = new TaskItem("BetterGI", "BetterGI")
        {
            Enabled = true,
            CloseAfterFinish = false,
            TimeoutMinutes = 180,
            Exe = @"C:\Path\To\BetterGI\BetterGI.exe",
            LogDir = @"C:\Path\To\BetterGI\log"
        };
        _tasks["March7th"] = new TaskItem("March7th", "March7th")
        {
            Enabled = true,
            CloseAfterFinish = false,
            TimeoutMinutes = 180,
            Exe = @"C:\Path\To\March7thAssistant\March7th Launcher.exe",
            AlternateExe = @"C:\Path\To\March7thAssistant\March7th Assistant.exe",
            LogDir = @"C:\Path\To\March7thAssistant\logs"
        };
        _tasks["MaaEnd"] = new TaskItem("MaaEnd", "MaaEnd")
        {
            Enabled = true,
            CloseAfterFinish = false,
            TimeoutMinutes = 120,
            Exe = @"C:\Path\To\MaaEnd\MaaEnd.exe",
            DebugDir = @"C:\Path\To\MaaEnd\debug"
        };
        _tasks["MAA"] = new TaskItem("MAA", "MAA")
        {
            Enabled = true,
            CloseAfterFinish = true,
            TimeoutMinutes = 180,
            Exe = @"C:\Path\To\MAA\MAA.exe",
            DebugDir = @"C:\Path\To\MAA\debug"
        };
        _order.Clear();
        _order.AddRange(_knownTasks);
    }

    private void LoadConfig()
    {
        var orderPath = Path.Combine(_configDir, "AutomationOrder.json");
        var enabledPath = Path.Combine(_configDir, "AutomationEnabled.json");
        var closePath = Path.Combine(_configDir, "AutoCloseGames.json");
        var timeoutPath = Path.Combine(_configDir, "TaskTimeouts.json");
        var localPath = Path.Combine(_configDir, "LocalPaths.json");

        var orderNode = ReadJson(orderPath);
        var configuredOrder = orderNode?["Order"]?.AsArray()
            .Select(x => x?.GetValue<string>() ?? "")
            .Where(x => _tasks.ContainsKey(x))
            .Distinct()
            .ToList();
        if (configuredOrder is { Count: > 0 })
        {
            _order.Clear();
            _order.AddRange(configuredOrder);
            foreach (var task in _knownTasks)
            {
                if (!_order.Contains(task)) _order.Add(task);
            }
        }

        ApplyBoolConfig(ReadJson(enabledPath), (task, value) => _tasks[task].Enabled = value);
        ApplyBoolConfig(ReadJson(closePath), (task, value) => _tasks[task].CloseAfterFinish = value);
        ApplyIntConfig(ReadJson(timeoutPath), (task, value) => _tasks[task].TimeoutMinutes = Math.Max(1, value));
        ApplyLocalPaths(ReadJson(localPath));
    }

    private static JsonNode? ReadJson(string path)
    {
        if (!File.Exists(path)) return null;
        try
        {
            return JsonNode.Parse(File.ReadAllText(path));
        }
        catch
        {
            return null;
        }
    }

    private void ApplyBoolConfig(JsonNode? node, Action<string, bool> setter)
    {
        if (node is null) return;
        foreach (var task in _knownTasks)
        {
            var value = node[task];
            if (value is not null && bool.TryParse(value.ToString(), out var parsed))
            {
                setter(task, parsed);
            }
        }
    }

    private void ApplyIntConfig(JsonNode? node, Action<string, int> setter)
    {
        if (node is null) return;
        foreach (var task in _knownTasks)
        {
            var value = node[task];
            if (value is not null && int.TryParse(value.ToString(), out var parsed))
            {
                setter(task, parsed);
            }
        }
    }

    private void ApplyLocalPaths(JsonNode? node)
    {
        if (node is null) return;
        foreach (var task in _knownTasks)
        {
            if (node[task] is not JsonObject item) continue;
            if (item["Exe"] is not null) _tasks[task].Exe = item["Exe"]!.ToString();
            if (item["AlternateExe"] is not null) _tasks[task].AlternateExe = item["AlternateExe"]!.ToString();
            if (item["LogDir"] is not null) _tasks[task].LogDir = item["LogDir"]!.ToString();
            if (item["DebugDir"] is not null) _tasks[task].DebugDir = item["DebugDir"]!.ToString();
        }
    }

    private void BuildUi()
    {
        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(BuildTaskPage());
        tabs.TabPages.Add(BuildPathPage());
        tabs.TabPages.Add(BuildActionsPage());

        _status = new Label
        {
            Dock = DockStyle.Bottom,
            Height = 30,
            TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(10, 0, 0, 0),
            Text = $"配置目录：{_configDir}"
        };

        Controls.Add(tabs);
        Controls.Add(_status);
    }

    private TabPage BuildTaskPage()
    {
        var page = new TabPage("任务设置");
        var panel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Padding = new Padding(12)
        };
        panel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));

        _taskGrid = new DataGridView
        {
            Dock = DockStyle.Fill,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            AllowDrop = true,
            RowHeadersVisible = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill
        };
        _taskGrid.MouseDown += TaskGrid_MouseDown;
        _taskGrid.MouseMove += TaskGrid_MouseMove;
        _taskGrid.DragOver += TaskGrid_DragOver;
        _taskGrid.DragDrop += TaskGrid_DragDrop;
        _taskGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "任务", Name = "Task", ReadOnly = true });
        _taskGrid.Columns.Add(new DataGridViewCheckBoxColumn { HeaderText = "启用", Name = "Enabled" });
        _taskGrid.Columns.Add(new DataGridViewCheckBoxColumn { HeaderText = "完成后关闭", Name = "CloseAfterFinish" });
        _taskGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "超时分钟", Name = "Timeout" });

        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
        buttons.Controls.Add(MakeButton("上移", (_, _) => MoveSelected(-1)));
        buttons.Controls.Add(MakeButton("下移", (_, _) => MoveSelected(1)));
        buttons.Controls.Add(MakeButton("保存任务设置", (_, _) => SaveAll()));
        buttons.Controls.Add(MakeButton("恢复默认任务设置", (_, _) => ResetTaskSettings()));

        panel.Controls.Add(_taskGrid, 0, 0);
        panel.Controls.Add(buttons, 0, 1);
        page.Controls.Add(panel);
        return page;
    }

    private TabPage BuildPathPage()
    {
        var page = new TabPage("本地路径");
        var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true };
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 1,
            Padding = new Padding(12)
        };

        foreach (var task in _knownTasks)
        {
            layout.Controls.Add(BuildPathGroup(_tasks[task]));
        }

        var savePanel = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 48 };
        savePanel.Controls.Add(MakeButton("自动检测路径", async (_, _) => await AutoDetectPathsAsync()));
        savePanel.Controls.Add(MakeButton("保存本地路径", (_, _) => SaveAll()));
        savePanel.Controls.Add(MakeButton("从配置重新载入", (_, _) => { LoadConfig(); RefreshTaskGrid(); LoadPathTextBoxes(); SetStatus("已重新载入配置。"); }));
        layout.Controls.Add(savePanel);
        scroll.Controls.Add(layout);
        page.Controls.Add(scroll);
        return page;
    }

    private GroupBox BuildPathGroup(TaskItem task)
    {
        var group = new GroupBox
        {
            Text = task.Name,
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(10)
        };
        var table = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 3
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
        _pathBoxes[task.Key] = new Dictionary<string, TextBox>();

        AddPathRow(table, task.Key, "Exe", "主程序", false);
        if (task.Key == "March7th") AddPathRow(table, task.Key, "AlternateExe", "备用程序", false);
        if (task.Key is "BetterGI" or "March7th") AddPathRow(table, task.Key, "LogDir", "日志目录", true);
        if (task.Key is "MaaEnd" or "MAA") AddPathRow(table, task.Key, "DebugDir", "debug目录", true);

        group.Controls.Add(table);
        return group;
    }

    private void AddPathRow(TableLayoutPanel table, string task, string field, string label, bool directory)
    {
        var row = table.RowCount++;
        table.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        table.Controls.Add(new Label { Text = label, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, row);
        var box = new TextBox { Dock = DockStyle.Fill };
        _pathBoxes[task][field] = box;
        table.Controls.Add(box, 1, row);
        table.Controls.Add(MakeButton("浏览", (_, _) => BrowsePath(box, directory)), 2, row);
    }

    private TabPage BuildActionsPage()
    {
        var page = new TabPage("快捷操作");
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2,
            Padding = new Padding(20)
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));

        AddActionButton(layout, "打开 BetterGI", () => OpenSoftware("BetterGI"));
        AddActionButton(layout, "打开 March7th", () => OpenSoftware("March7th"));
        AddActionButton(layout, "打开 MaaEnd", () => OpenSoftware("MaaEnd"));
        AddActionButton(layout, "打开 MAA", () => OpenSoftware("MAA"));
        AddActionButton(layout, "运行主程序", RunMainScript);
        AddActionButton(layout, "打开配置文件夹", () => Process.Start(new ProcessStartInfo(_configDir) { UseShellExecute = true }));

        page.Controls.Add(layout);
        return page;
    }

    private void AddActionButton(TableLayoutPanel layout, string text, Action action)
    {
        var row = layout.RowCount / 2;
        var col = layout.RowCount % 2;
        if (col == 0) layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
        layout.Controls.Add(MakeButton(text, (_, _) => action()), col, row);
        layout.RowCount++;
    }

    private Button MakeButton(string text, EventHandler onClick)
    {
        var button = new Button
        {
            Text = text,
            Width = 160,
            Height = 32,
            Margin = new Padding(6)
        };
        button.Click += onClick;
        return button;
    }

    private void RefreshTaskGrid()
    {
        _taskGrid.Rows.Clear();
        foreach (var key in _order)
        {
            var task = _tasks[key];
            _taskGrid.Rows.Add(task.Name, task.Enabled, task.CloseAfterFinish, task.TimeoutMinutes);
            _taskGrid.Rows[^1].Tag = key;
        }
    }

    private void LoadPathTextBoxes()
    {
        foreach (var key in _knownTasks)
        {
            var task = _tasks[key];
            SetBox(key, "Exe", task.Exe);
            SetBox(key, "AlternateExe", task.AlternateExe);
            SetBox(key, "LogDir", task.LogDir);
            SetBox(key, "DebugDir", task.DebugDir);
        }
    }

    private void SetBox(string task, string field, string value)
    {
        if (_pathBoxes.TryGetValue(task, out var fields) && fields.TryGetValue(field, out var box))
        {
            box.Text = value;
        }
    }

    private string GetBox(string task, string field)
    {
        if (_pathBoxes.TryGetValue(task, out var fields) && fields.TryGetValue(field, out var box))
        {
            return box.Text.Trim();
        }
        return "";
    }

    private void MoveSelected(int delta)
    {
        if (_taskGrid.SelectedRows.Count == 0) return;
        SaveGridToTasks();
        var index = _taskGrid.SelectedRows[0].Index;
        var next = index + delta;
        if (next < 0 || next >= _order.Count) return;
        (_order[index], _order[next]) = (_order[next], _order[index]);
        RefreshTaskGrid();
        _taskGrid.Rows[next].Selected = true;
    }

    private void TaskGrid_MouseDown(object? sender, MouseEventArgs e)
    {
        var hit = _taskGrid.HitTest(e.X, e.Y);
        _dragRowIndex = hit.RowIndex >= 0 ? hit.RowIndex : -1;
    }

    private void TaskGrid_MouseMove(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left || _dragRowIndex < 0) return;
        var row = _taskGrid.Rows[_dragRowIndex];
        _taskGrid.DoDragDrop(row, DragDropEffects.Move);
    }

    private void TaskGrid_DragOver(object? sender, DragEventArgs e)
    {
        e.Effect = e.Data?.GetDataPresent(typeof(DataGridViewRow)) == true
            ? DragDropEffects.Move
            : DragDropEffects.None;
    }

    private void TaskGrid_DragDrop(object? sender, DragEventArgs e)
    {
        if (_dragRowIndex < 0 || e.Data?.GetDataPresent(typeof(DataGridViewRow)) != true) return;

        var clientPoint = _taskGrid.PointToClient(new Point(e.X, e.Y));
        var hit = _taskGrid.HitTest(clientPoint.X, clientPoint.Y);
        var targetIndex = hit.RowIndex;
        if (targetIndex < 0) targetIndex = _taskGrid.Rows.Count - 1;
        if (targetIndex == _dragRowIndex) return;

        SaveGridToTasks();
        var draggedTask = _order[_dragRowIndex];
        _order.RemoveAt(_dragRowIndex);
        if (targetIndex > _dragRowIndex) targetIndex--;
        targetIndex = Math.Max(0, Math.Min(targetIndex, _order.Count));
        _order.Insert(targetIndex, draggedTask);

        RefreshTaskGrid();
        _taskGrid.ClearSelection();
        _taskGrid.Rows[targetIndex].Selected = true;
        SetStatus("已调整运行顺序，点击保存后生效。");
        _dragRowIndex = -1;
    }

    private void SaveGridToTasks()
    {
        _order.Clear();
        foreach (DataGridViewRow row in _taskGrid.Rows)
        {
            if (row.Tag is not string key) continue;
            var task = _tasks[key];
            task.Enabled = Convert.ToBoolean(row.Cells["Enabled"].Value ?? false);
            task.CloseAfterFinish = Convert.ToBoolean(row.Cells["CloseAfterFinish"].Value ?? false);
            if (!int.TryParse(Convert.ToString(row.Cells["Timeout"].Value), out var timeout) || timeout <= 0) timeout = 1;
            task.TimeoutMinutes = timeout;
            _order.Add(key);
        }
    }

    private void SavePathBoxesToTasks()
    {
        foreach (var key in _knownTasks)
        {
            var task = _tasks[key];
            task.Exe = GetBox(key, "Exe");
            task.AlternateExe = GetBox(key, "AlternateExe");
            task.LogDir = GetBox(key, "LogDir");
            task.DebugDir = GetBox(key, "DebugDir");
        }
    }

    private void SaveAll()
    {
        try
        {
            SaveGridToTasks();
            SavePathBoxesToTasks();
            WriteJson("AutomationOrder.json", new JsonObject { ["Order"] = new JsonArray(_order.Select(x => JsonValue.Create(x)).ToArray<JsonNode?>()) });
            WriteJson("AutomationEnabled.json", BuildBoolObject(x => x.Enabled));
            WriteJson("AutoCloseGames.json", BuildBoolObject(x => x.CloseAfterFinish));
            WriteJson("TaskTimeouts.json", BuildIntObject(x => x.TimeoutMinutes));
            WriteJson("LocalPaths.json", BuildLocalPathsObject());
            SetStatus("配置已保存。");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "保存失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private JsonObject BuildBoolObject(Func<TaskItem, bool> getter)
    {
        var obj = new JsonObject();
        foreach (var key in _knownTasks) obj[key] = getter(_tasks[key]);
        return obj;
    }

    private JsonObject BuildIntObject(Func<TaskItem, int> getter)
    {
        var obj = new JsonObject();
        foreach (var key in _knownTasks) obj[key] = getter(_tasks[key]);
        return obj;
    }

    private JsonObject BuildLocalPathsObject()
    {
        var root = new JsonObject();
        foreach (var key in _knownTasks)
        {
            var task = _tasks[key];
            var obj = new JsonObject { ["Exe"] = task.Exe };
            if (!string.IsNullOrWhiteSpace(task.AlternateExe)) obj["AlternateExe"] = task.AlternateExe;
            if (!string.IsNullOrWhiteSpace(task.LogDir)) obj["LogDir"] = task.LogDir;
            if (!string.IsNullOrWhiteSpace(task.DebugDir)) obj["DebugDir"] = task.DebugDir;
            root[key] = obj;
        }
        return root;
    }

    private void WriteJson(string fileName, JsonNode node)
    {
        var options = new JsonSerializerOptions { WriteIndented = true };
        File.WriteAllText(Path.Combine(_configDir, fileName), node.ToJsonString(options));
    }

    private void ResetTaskSettings()
    {
        foreach (var key in _knownTasks)
        {
            _tasks[key].Enabled = true;
            _tasks[key].CloseAfterFinish = key == "MAA";
            _tasks[key].TimeoutMinutes = key == "MaaEnd" ? 120 : 180;
        }
        _order.Clear();
        _order.AddRange(_knownTasks);
        RefreshTaskGrid();
        SetStatus("已恢复界面中的默认任务设置，点击保存后生效。");
    }

    private void BrowsePath(TextBox box, bool directory)
    {
        if (directory)
        {
            using var dialog = new FolderBrowserDialog { SelectedPath = Directory.Exists(box.Text) ? box.Text : _rootDir };
            if (dialog.ShowDialog(this) == DialogResult.OK) box.Text = dialog.SelectedPath;
        }
        else
        {
            using var dialog = new OpenFileDialog { Filter = "程序文件 (*.exe)|*.exe|所有文件 (*.*)|*.*" };
            if (File.Exists(box.Text)) dialog.FileName = box.Text;
            if (dialog.ShowDialog(this) == DialogResult.OK) box.Text = dialog.FileName;
        }
    }

    private async Task AutoDetectPathsAsync()
    {
        SavePathBoxesToTasks();
        SetStatus("正在自动检测路径，请稍等...");
        var oldCursor = Cursor.Current;
        Cursor.Current = Cursors.WaitCursor;

        try
        {
            var snapshot = SnapshotTasks();
            var result = await Task.Run(() => DetectLocalPaths(snapshot));
            ApplyDetectedPaths(result);
            SavePathBoxesToTasks();

            var text = result.Messages.Count == 0
                ? "没有检测到可用路径。请手动选择对应程序和日志目录。"
                : string.Join(Environment.NewLine, result.Messages);

            MessageBox.Show(this, text, "自动检测路径", MessageBoxButtons.OK, MessageBoxIcon.Information);
            SetStatus($"自动检测完成：已填入 {result.AppliedCount} 项，点击保存后生效。");
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "自动检测失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatus("自动检测失败。");
        }
        finally
        {
            Cursor.Current = oldCursor;
        }
    }

    private Dictionary<string, TaskItem> SnapshotTasks()
    {
        var snapshot = new Dictionary<string, TaskItem>();
        foreach (var key in _knownTasks)
        {
            var task = _tasks[key];
            snapshot[key] = new TaskItem(task.Key, task.Name)
            {
                Enabled = task.Enabled,
                CloseAfterFinish = task.CloseAfterFinish,
                TimeoutMinutes = task.TimeoutMinutes,
                Exe = task.Exe,
                AlternateExe = task.AlternateExe,
                LogDir = task.LogDir,
                DebugDir = task.DebugDir
            };
        }
        return snapshot;
    }

    private PathDetectionResult DetectLocalPaths(Dictionary<string, TaskItem> current)
    {
        var candidates = new List<PathCandidate>();

        foreach (var task in current.Values)
        {
            AddExistingCandidate(candidates, task.Key, "Exe", task.Exe, false);
            AddExistingCandidate(candidates, task.Key, "AlternateExe", task.AlternateExe, false);
            AddExistingCandidate(candidates, task.Key, "LogDir", task.LogDir, true);
            AddExistingCandidate(candidates, task.Key, "DebugDir", task.DebugDir, true);
        }

        AddProcessCandidates(candidates);
        AddSearchCandidates(candidates, current);

        var result = new PathDetectionResult();
        foreach (var group in candidates
                     .Where(x => !string.IsNullOrWhiteSpace(x.Value))
                     .GroupBy(x => $"{x.Task}|{x.Field}"))
        {
            var best = group
                .OrderByDescending(x => x.Confidence)
                .ThenBy(x => x.Value.Length)
                .First();

            if (!result.Values.TryGetValue(best.Task, out var fields))
            {
                fields = new Dictionary<string, string>();
                result.Values[best.Task] = fields;
            }
            fields[best.Field] = best.Value;

            var sameFieldCount = group.Select(x => x.Value).Distinct(StringComparer.OrdinalIgnoreCase).Count();
            var suffix = sameFieldCount > 1 ? $"（另有 {sameFieldCount - 1} 个候选）" : "";
            result.Messages.Add($"{_taskNames[best.Task]} {FieldDisplayName(best.Field)}：{best.Value}，来源：{best.Source}{suffix}");
        }

        foreach (var task in _knownTasks)
        {
            if (!result.Values.TryGetValue(task, out var fields) || !fields.ContainsKey("Exe"))
            {
                result.Messages.Add($"{_taskNames[task]} 主程序：未检测到，请手动选择。");
            }
        }

        return result;
    }

    private static void AddExistingCandidate(List<PathCandidate> candidates, string task, string field, string value, bool directory)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        var exists = directory ? Directory.Exists(value) : File.Exists(value);
        if (!exists) return;
        candidates.Add(new PathCandidate
        {
            Task = task,
            Field = field,
            Value = value,
            Source = "现有配置有效",
            Confidence = 95
        });
    }

    private void AddProcessCandidates(List<PathCandidate> candidates)
    {
        foreach (var process in Process.GetProcesses())
        {
            string? exePath = null;
            try
            {
                exePath = process.MainModule?.FileName;
            }
            catch
            {
                continue;
            }

            if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath)) continue;
            AddExeCandidate(candidates, exePath, "正在运行的进程", 100);
        }
    }

    private void AddSearchCandidates(List<PathCandidate> candidates, Dictionary<string, TaskItem> current)
    {
        var exeNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "BetterGI.exe",
            "March7th Launcher.exe",
            "March7th Assistant.exe",
            "MaaEnd.exe",
            "MAA.exe"
        };

        var roots = BuildSearchRoots(current);
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots)
        {
            foreach (var exePath in FindExeFiles(root, exeNames, maxDepth: 5, maxDirectories: 25000))
            {
                if (!found.Add(exePath)) continue;
                AddExeCandidate(candidates, exePath, "本机目录扫描", 80);
            }
        }
    }

    private List<string> BuildSearchRoots(Dictionary<string, TaskItem> current)
    {
        var roots = new List<string>();
        void AddRoot(string? path)
        {
            if (string.IsNullOrWhiteSpace(path)) return;
            try
            {
                if (Directory.Exists(path) && !roots.Contains(path, StringComparer.OrdinalIgnoreCase))
                {
                    roots.Add(path);
                }
            }
            catch
            {
                // Ignore inaccessible roots.
            }
        }

        AddRoot(_rootDir);
        AddRoot(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory));
        AddRoot(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        AddRoot(Path.Combine(userProfile, "Downloads"));
        AddRoot(Path.Combine(userProfile, "OneDrive", "Desktop"));
        AddRoot(Path.Combine(userProfile, "OneDrive", "Documents"));
        AddRoot(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));
        AddRoot(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));

        foreach (var task in current.Values)
        {
            AddRoot(SafeParent(task.Exe));
            AddRoot(SafeParent(task.AlternateExe));
            AddRoot(task.LogDir);
            AddRoot(task.DebugDir);
        }

        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (drive.DriveType == DriveType.Fixed && drive.IsReady)
                {
                    AddRoot(drive.RootDirectory.FullName);
                }
            }
            catch
            {
                // Ignore unreadable drives.
            }
        }

        return roots;
    }

    private static string? SafeParent(string path)
    {
        try
        {
            return string.IsNullOrWhiteSpace(path) ? null : Path.GetDirectoryName(path);
        }
        catch
        {
            return null;
        }
    }

    private static IEnumerable<string> FindExeFiles(string root, HashSet<string> exeNames, int maxDepth, int maxDirectories)
    {
        var queue = new Queue<(string Path, int Depth)>();
        queue.Enqueue((root, 0));
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var checkedDirectories = 0;

        while (queue.Count > 0 && checkedDirectories < maxDirectories)
        {
            var (dir, depth) = queue.Dequeue();
            if (!visited.Add(dir)) continue;
            checkedDirectories++;

            foreach (var exeName in exeNames)
            {
                string candidate;
                try
                {
                    candidate = Path.Combine(dir, exeName);
                }
                catch
                {
                    continue;
                }
                if (File.Exists(candidate)) yield return candidate;
            }

            if (depth >= maxDepth) continue;

            string[] children;
            try
            {
                children = Directory.EnumerateDirectories(dir).ToArray();
            }
            catch
            {
                continue;
            }

            foreach (var child in children)
            {
                if (ShouldSkipDirectory(child)) continue;
                queue.Enqueue((child, depth + 1));
            }
        }
    }

    private static bool ShouldSkipDirectory(string path)
    {
        var name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        return name.Equals("Windows", StringComparison.OrdinalIgnoreCase)
            || name.Equals("ProgramData", StringComparison.OrdinalIgnoreCase)
            || name.Equals("$Recycle.Bin", StringComparison.OrdinalIgnoreCase)
            || name.Equals("System Volume Information", StringComparison.OrdinalIgnoreCase)
            || name.Equals("Recovery", StringComparison.OrdinalIgnoreCase)
            || name.Equals("node_modules", StringComparison.OrdinalIgnoreCase)
            || name.Equals(".git", StringComparison.OrdinalIgnoreCase);
    }

    private void AddExeCandidate(List<PathCandidate> candidates, string exePath, string source, int baseConfidence)
    {
        var fileName = Path.GetFileName(exePath);
        var dir = Path.GetDirectoryName(exePath) ?? "";
        if (fileName.Equals("BetterGI.exe", StringComparison.OrdinalIgnoreCase))
        {
            AddCandidate(candidates, "BetterGI", "Exe", exePath, source, baseConfidence + 8);
            AddDirectoryCandidate(candidates, "BetterGI", "LogDir", Path.Combine(dir, "log"), "BetterGI 日志目录", "better-genshin-impact*.log", baseConfidence + 6);
        }
        else if (fileName.Equals("March7th Launcher.exe", StringComparison.OrdinalIgnoreCase))
        {
            AddCandidate(candidates, "March7th", "Exe", exePath, source, baseConfidence + 8);
            AddCandidateIfFileExists(candidates, "March7th", "AlternateExe", Path.Combine(dir, "March7th Assistant.exe"), "同目录备用程序", baseConfidence + 5);
            AddDirectoryCandidate(candidates, "March7th", "LogDir", Path.Combine(dir, "logs"), "March7th 日志目录", "*.log", baseConfidence + 6);
        }
        else if (fileName.Equals("March7th Assistant.exe", StringComparison.OrdinalIgnoreCase))
        {
            AddCandidate(candidates, "March7th", "AlternateExe", exePath, source, baseConfidence + 8);
            AddCandidateIfFileExists(candidates, "March7th", "Exe", Path.Combine(dir, "March7th Launcher.exe"), "同目录启动器", baseConfidence + 5);
            AddDirectoryCandidate(candidates, "March7th", "LogDir", Path.Combine(dir, "logs"), "March7th 日志目录", "*.log", baseConfidence + 6);
        }
        else if (fileName.Equals("MaaEnd.exe", StringComparison.OrdinalIgnoreCase))
        {
            AddCandidate(candidates, "MaaEnd", "Exe", exePath, source, baseConfidence + 8);
            AddDirectoryCandidate(candidates, "MaaEnd", "DebugDir", Path.Combine(dir, "debug"), "MaaEnd debug目录", "*.log", baseConfidence + 6);
        }
        else if (fileName.Equals("MAA.exe", StringComparison.OrdinalIgnoreCase))
        {
            AddCandidate(candidates, "MAA", "Exe", exePath, source, baseConfidence + 8);
            AddDirectoryCandidate(candidates, "MAA", "DebugDir", Path.Combine(dir, "debug"), "MAA debug目录", "asst*.log", baseConfidence + 6);
        }
    }

    private static void AddCandidateIfFileExists(List<PathCandidate> candidates, string task, string field, string value, string source, int confidence)
    {
        if (File.Exists(value)) AddCandidate(candidates, task, field, value, source, confidence);
    }

    private static void AddDirectoryCandidate(List<PathCandidate> candidates, string task, string field, string value, string source, string marker, int confidence)
    {
        if (!Directory.Exists(value)) return;
        var hasMarker = false;
        try
        {
            hasMarker = Directory.EnumerateFiles(value, marker).Any();
        }
        catch
        {
            // Existing directory is still useful even if marker scanning fails.
        }
        AddCandidate(candidates, task, field, value, source, hasMarker ? confidence + 8 : confidence);
    }

    private static void AddCandidate(List<PathCandidate> candidates, string task, string field, string value, string source, int confidence)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        candidates.Add(new PathCandidate
        {
            Task = task,
            Field = field,
            Value = value,
            Source = source,
            Confidence = confidence
        });
    }

    private void ApplyDetectedPaths(PathDetectionResult result)
    {
        var count = 0;
        foreach (var (task, fields) in result.Values)
        {
            foreach (var (field, value) in fields)
            {
                if (!_pathBoxes.TryGetValue(task, out var boxes) || !boxes.TryGetValue(field, out var box)) continue;
                if (string.Equals(box.Text.Trim(), value, StringComparison.OrdinalIgnoreCase)) continue;
                box.Text = value;
                count++;
            }
        }
        result.AppliedCount = count;
    }

    private static string FieldDisplayName(string field)
    {
        return field switch
        {
            "Exe" => "主程序",
            "AlternateExe" => "备用程序",
            "LogDir" => "日志目录",
            "DebugDir" => "debug目录",
            _ => field
        };
    }

    private void OpenSoftware(string key)
    {
        SavePathBoxesToTasks();
        var task = _tasks[key];
        var exe = task.Exe;
        if (!File.Exists(exe) && key == "March7th" && File.Exists(task.AlternateExe))
        {
            exe = task.AlternateExe;
        }
        if (!File.Exists(exe))
        {
            MessageBox.Show(this, $"未找到程序：{exe}", "无法打开", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = Path.GetDirectoryName(exe), UseShellExecute = true });
        SetStatus($"已打开 {task.Name}");
    }

    private void RunMainScript()
    {
        var bat = Path.Combine(_rootDir, "StartGameAutomation.bat");
        if (!File.Exists(bat))
        {
            MessageBox.Show(this, $"未找到：{bat}", "无法运行", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        Process.Start(new ProcessStartInfo(bat) { WorkingDirectory = _rootDir, UseShellExecute = true });
        SetStatus("已启动主程序。");
    }

    private void SetStatus(string text)
    {
        _status.Text = text;
    }
}
