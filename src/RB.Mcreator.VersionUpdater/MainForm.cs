using System.Diagnostics;
using System.Text;

namespace RB.Mcreator.VersionUpdater;

public sealed class MainForm : Form
{
    private readonly TextBox _txtInput = NewTextBox();
    private readonly TextBox _txtOutput = NewTextBox();
    private readonly TextBox _txtMc = NewTextBox();
    private readonly TextBox _txtNeo = NewTextBox();
    private readonly TextBox _txtModVer = NewTextBox();
    private readonly CheckBox _chkFetch = NewCheck("Fetch Gradle wrapper (recommended)", true);
    private readonly CheckBox _chkCompile = NewCheck("Compile after convert", false);
    private readonly CheckBox _chkBuild = NewCheck("Full build (jar)", false);
    private readonly CheckBox _chkDry = NewCheck("Dry run (preview only)", false);
    private readonly Button _btnBrowseIn = NewButton("Browse...");
    private readonly Button _btnBrowseOut = NewButton("Browse...");
    private readonly Button _btnRun = NewButton("Convert");
    private readonly Button _btnOpenOut = NewButton("Open output");
    private readonly Button _btnClear = NewButton("Clear log");
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Continuous };
    private readonly RichTextBox _log = new();
    private Process? _running;
    private System.Windows.Forms.Timer? _pollTimer;
    private string _lastOutput = "";

    public MainForm()
    {
        Text = "RB MCreator Version Updater - NeoForge 26.2";
        Size = new Size(860, 680);
        MinimumSize = new Size(720, 540);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(32, 34, 40);
        ForeColor = Color.Gainsboro;
        Font = new Font("Segoe UI", 9.5f);

        var title = new Label
        {
            Text = "Convert MCreator / NeoForge 26.1.x  ->  Minecraft 26.2",
            Font = new Font("Segoe UI Semibold", 12f),
            ForeColor = Color.White,
            Location = new Point(16, 12),
            AutoSize = true
        };
        var sub = new Label
        {
            Text = "Always writes to a new output folder. Your original project is never modified.",
            ForeColor = Color.FromArgb(140, 200, 140),
            Location = new Point(16, 40),
            AutoSize = true
        };

        Controls.Add(title);
        Controls.Add(sub);

        AddLabeledRow("Input project", 72, _txtInput, _btnBrowseIn);
        AddLabeledRow("Output folder", 108, _txtOutput, _btnBrowseOut);

        Controls.Add(MakeLabel("Minecraft", 16, 148, 80));
        _txtMc.Location = new Point(100, 146);
        _txtMc.Width = 90;
        _txtMc.Text = "26.2";
        Controls.Add(_txtMc);

        Controls.Add(MakeLabel("NeoForge", 210, 148, 80));
        _txtNeo.Location = new Point(290, 146);
        _txtNeo.Width = 170;
        _txtNeo.Text = "26.2.0.32-beta";
        Controls.Add(_txtNeo);

        Controls.Add(MakeLabel("Mod version", 480, 148, 90));
        _txtModVer.Location = new Point(570, 146);
        _txtModVer.Width = 100;
        Controls.Add(_txtModVer);
        Controls.Add(MakeLabel("(blank = auto)", 675, 148, 110));

        _chkFetch.Location = new Point(16, 186);
        _chkCompile.Location = new Point(320, 186);
        _chkBuild.Location = new Point(500, 186);
        _chkDry.Location = new Point(650, 186);
        _chkDry.ForeColor = Color.Khaki;
        Controls.AddRange(new Control[] { _chkFetch, _chkCompile, _chkBuild, _chkDry });

        _btnRun.Location = new Point(16, 222);
        _btnRun.Width = 120;
        _btnRun.BackColor = Color.FromArgb(46, 120, 80);
        _btnRun.FlatAppearance.BorderColor = Color.FromArgb(70, 160, 100);
        _btnRun.Font = new Font("Segoe UI Semibold", 10f);

        _btnOpenOut.Location = new Point(150, 222);
        _btnOpenOut.Width = 120;
        _btnOpenOut.Enabled = false;

        _btnClear.Location = new Point(280, 222);
        _btnClear.Width = 100;

        _progress.Location = new Point(400, 226);
        _progress.Size = new Size(420, 20);
        _progress.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;

        Controls.AddRange(new Control[] { _btnRun, _btnOpenOut, _btnClear, _progress });

        Controls.Add(MakeLabel("Log", 16, 262, 80));
        _log.Location = new Point(16, 286);
        _log.Size = new Size(810, 320);
        _log.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        _log.BackColor = Color.FromArgb(22, 24, 28);
        _log.ForeColor = Color.Gainsboro;
        _log.Font = new Font("Consolas", 9f);
        _log.ReadOnly = true;
        _log.BorderStyle = BorderStyle.FixedSingle;
        _log.DetectUrls = false;
        Controls.Add(_log);

        _btnBrowseIn.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = "Select MCreator / NeoForge project folder",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = false
            };
            if (!string.IsNullOrWhiteSpace(_txtInput.Text) && Directory.Exists(_txtInput.Text))
                dlg.SelectedPath = _txtInput.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtInput.Text = dlg.SelectedPath;
                if (string.IsNullOrWhiteSpace(_txtOutput.Text) || _txtOutput.Text.Contains("-26.2", StringComparison.OrdinalIgnoreCase))
                    _txtOutput.Text = SuggestOutputPath(dlg.SelectedPath);
            }
        };

        _btnBrowseOut.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = "Select empty output folder (converted copy goes here)",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = true
            };
            var start = !string.IsNullOrWhiteSpace(_txtOutput.Text)
                ? _txtOutput.Text
                : (!string.IsNullOrWhiteSpace(_txtInput.Text) ? Path.GetDirectoryName(_txtInput.Text) : null);
            if (!string.IsNullOrWhiteSpace(start) && Directory.Exists(start))
                dlg.SelectedPath = start!;
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _txtOutput.Text = dlg.SelectedPath;
        };

        _txtInput.Leave += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_txtInput.Text) && string.IsNullOrWhiteSpace(_txtOutput.Text))
                _txtOutput.Text = SuggestOutputPath(_txtInput.Text);
        };

        _btnRun.Click += (_, _) => StartConversion();
        _btnOpenOut.Click += (_, _) =>
        {
            var p = _txtOutput.Text.Trim();
            if (Directory.Exists(p))
                Process.Start(new ProcessStartInfo("explorer.exe", Quote(p)) { UseShellExecute = true });
            else
                MessageBox.Show(this, "Output folder does not exist yet.", "Open output", MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        _btnClear.Click += (_, _) => _log.Clear();

        Resize += (_, _) =>
        {
            _log.Width = ClientSize.Width - 32;
            _log.Height = ClientSize.Height - _log.Top - 16;
            _progress.Width = Math.Max(100, ClientSize.Width - _progress.Left - 16);
        };

        Shown += (_, _) =>
        {
            AppendLog("Ready. Choose an input project and output folder, then click Convert.", Color.Gray);
            AppendLog("Tip: output is suggested as <project>-26.2 next to the original.", Color.Gray);
            var tools = ResolveToolsRoot();
            AppendLog($"Tools root: {tools}", Color.DimGray);
            if (!File.Exists(Path.Combine(tools, "Convert-ToNeoForge262.ps1")))
                AppendLog("WARNING: converter script not found next to this app.", Color.Salmon);
        };

        FormClosing += (_, e) =>
        {
            if (_running is { HasExited: false })
            {
                var r = MessageBox.Show(this, "Conversion is still running. Exit anyway?", "Exit",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (r != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
                try { _running.Kill(entireProcessTree: true); } catch { /* ignore */ }
            }
        };
    }

    private void AddLabeledRow(string label, int y, TextBox text, Button browse)
    {
        Controls.Add(MakeLabel(label, 16, y, 110));
        text.Location = new Point(130, y - 2);
        text.Width = 560;
        text.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        browse.Location = new Point(700, y - 4);
        browse.Width = 110;
        browse.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        Controls.Add(text);
        Controls.Add(browse);
    }

    private static Label MakeLabel(string text, int x, int y, int w) => new()
    {
        Text = text,
        Location = new Point(x, y),
        Size = new Size(w, 22),
        ForeColor = Color.Gainsboro
    };

    private static TextBox NewTextBox() => new()
    {
        BackColor = Color.FromArgb(45, 48, 56),
        ForeColor = Color.White,
        BorderStyle = BorderStyle.FixedSingle
    };

    private static CheckBox NewCheck(string text, bool isChecked) => new()
    {
        Text = text,
        Checked = isChecked,
        AutoSize = true,
        ForeColor = Color.Gainsboro
    };

    private static Button NewButton(string text) => new()
    {
        Text = text,
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.FromArgb(60, 64, 78),
        ForeColor = Color.White,
        Height = 28,
        Cursor = Cursors.Hand
    };

    private static string Quote(string path) => path.Contains(' ') ? $"\"{path}\"" : path;

    private static string SuggestOutputPath(string inputPath)
    {
        try
        {
            var full = Path.GetFullPath(inputPath.Trim());
            var name = Path.GetFileName(full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            var parent = Path.GetDirectoryName(full)!;
            var candidate = Path.Combine(parent, name + "-26.2");
            var i = 2;
            while (Directory.Exists(candidate))
            {
                candidate = Path.Combine(parent, $"{name}-26.2-{i}");
                i++;
            }
            return candidate;
        }
        catch
        {
            return "";
        }
    }

    private static string ResolveToolsRoot()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "tools"),
            baseDir,
            Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", ".."))
        };
        foreach (var c in candidates)
        {
            if (File.Exists(Path.Combine(c, "Convert-ToNeoForge262.ps1")))
                return c;
        }
        return Path.Combine(baseDir, "tools");
    }

    private static bool LooksLikeModProject(string path)
    {
        if (!Directory.Exists(path)) return false;
        if (Directory.Exists(Path.Combine(path, "src"))) return true;
        if (Directory.EnumerateFiles(path, "*.mcreator").Any()) return true;
        if (File.Exists(Path.Combine(path, "gradle.properties"))) return true;
        return false;
    }

    private void SetBusy(bool busy)
    {
        _btnRun.Enabled = !busy;
        _btnBrowseIn.Enabled = !busy;
        _btnBrowseOut.Enabled = !busy;
        _txtInput.Enabled = !busy;
        _txtOutput.Enabled = !busy;
        _txtNeo.Enabled = !busy;
        _txtMc.Enabled = !busy;
        _txtModVer.Enabled = !busy;
        _chkFetch.Enabled = !busy;
        _chkCompile.Enabled = !busy;
        _chkBuild.Enabled = !busy;
        _chkDry.Enabled = !busy;
        _progress.Style = busy ? ProgressBarStyle.Marquee : ProgressBarStyle.Continuous;
        _progress.MarqueeAnimationSpeed = busy ? 30 : 0;
        if (!busy) _progress.Value = 0;
        Cursor = busy ? Cursors.WaitCursor : Cursors.Default;
    }

    private void AppendLog(string text, Color color)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            BeginInvoke(() => AppendLog(text, color));
            return;
        }
        _log.SelectionStart = _log.TextLength;
        _log.SelectionLength = 0;
        _log.SelectionColor = color;
        _log.AppendText(text + Environment.NewLine);
        _log.ScrollToCaret();
    }

    private void StartConversion()
    {
        var inputPath = _txtInput.Text.Trim();
        var outputPath = _txtOutput.Text.Trim();
        var neo = string.IsNullOrWhiteSpace(_txtNeo.Text) ? "26.2.0.32-beta" : _txtNeo.Text.Trim();
        var mc = string.IsNullOrWhiteSpace(_txtMc.Text) ? "26.2" : _txtMc.Text.Trim();
        var modVer = _txtModVer.Text.Trim();

        if (string.IsNullOrWhiteSpace(inputPath))
        {
            MessageBox.Show(this, "Choose an input project folder.", "Missing input", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (!Directory.Exists(inputPath))
        {
            MessageBox.Show(this, $"Input folder does not exist:\n{inputPath}", "Invalid input", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        if (!LooksLikeModProject(inputPath))
        {
            var r = MessageBox.Show(this,
                "This folder does not look like a mod project (no src/, *.mcreator, or gradle.properties).\nContinue anyway?",
                "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return;
        }
        if (string.IsNullOrWhiteSpace(outputPath))
        {
            MessageBox.Show(this, "Choose an output folder (conversion never writes into the input).", "Missing output",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var inFull = Path.GetFullPath(inputPath);
        var outFull = Path.GetFullPath(outputPath);
        if (string.Equals(inFull.TrimEnd('\\'), outFull.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
        {
            MessageBox.Show(this, "Output folder must be different from the input folder.", "Invalid output",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        if (Directory.Exists(outFull) && !_chkDry.Checked)
        {
            if (Directory.EnumerateFileSystemEntries(outFull).Any())
            {
                MessageBox.Show(this,
                    "Output folder already exists and is not empty.\nChoose an empty or new folder.\n\n" + outFull,
                    "Output not empty", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
        }

        var toolsRoot = ResolveToolsRoot();
        var converter = Path.Combine(toolsRoot, "Convert-ToNeoForge262.ps1");
        if (!File.Exists(converter))
        {
            MessageBox.Show(this,
                "Could not find Convert-ToNeoForge262.ps1.\nExpected under:\n" + toolsRoot,
                "Missing tools", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        var args = new List<string>
        {
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", Quote(converter),
            "-Path", Quote(inFull),
            "-OutputPath", Quote(outFull),
            "-MinecraftVersion", Quote(mc),
            "-NeoVersion", Quote(neo)
        };
        if (!string.IsNullOrWhiteSpace(modVer))
            args.AddRange(new[] { "-ModVersion", Quote(modVer) });
        if (_chkFetch.Checked) args.Add("-FetchWrapper");
        if (_chkDry.Checked) args.Add("-DryRun");
        if (_chkCompile.Checked) args.Add("-Compile");
        if (_chkBuild.Checked) args.Add("-Build");

        _log.Clear();
        AppendLog("RB MCreator Version Updater", Color.White);
        AppendLog($"Input : {inFull}", Color.LightSkyBlue);
        AppendLog($"Output: {outFull}  (original will not be modified)", Color.LightGreen);
        AppendLog($"Minecraft {mc} / NeoForge {neo}", Color.Khaki);
        AppendLog("----------------------------------------", Color.Gray);
        AppendLog("Starting...", Color.Gainsboro);

        SetBusy(true);
        _lastOutput = outFull;
        _btnOpenOut.Enabled = false;

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = string.Join(" ", args),
            WorkingDirectory = toolsRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.OutputDataReceived += (_, e) =>
        {
            if (string.IsNullOrEmpty(e.Data)) return;
            var color = Color.Gainsboro;
            if (e.Data.Contains("WARN", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("warning", StringComparison.OrdinalIgnoreCase))
                color = Color.Gold;
            else if (e.Data.Contains("error", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("FAIL", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("Exception", StringComparison.OrdinalIgnoreCase))
                color = Color.Salmon;
            else if (e.Data.Contains("==>") || e.Data.Contains("SUCCESS") || e.Data.Contains("Copied") || e.Data.Contains("Conversion wrote") || e.Data.Contains("original unchanged"))
                color = Color.PaleGreen;
            AppendLog(e.Data, color);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
                AppendLog(e.Data, Color.Salmon);
        };

        try
        {
            if (!proc.Start())
                throw new InvalidOperationException("Failed to start PowerShell.");
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            _running = proc;
        }
        catch (Exception ex)
        {
            SetBusy(false);
            AppendLog("Failed to start conversion: " + ex.Message, Color.Salmon);
            MessageBox.Show(this, ex.Message, "Launch failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _pollTimer?.Stop();
        _pollTimer?.Dispose();
        _pollTimer = new System.Windows.Forms.Timer { Interval = 250 };
        _pollTimer.Tick += (_, _) =>
        {
            if (_running is null || !_running.HasExited) return;
            _pollTimer.Stop();
            _pollTimer.Dispose();
            _pollTimer = null;

            var code = _running.ExitCode;
            SetBusy(false);
            AppendLog("----------------------------------------", Color.Gray);
            if (code == 0)
            {
                AppendLog("Finished successfully (exit 0).", Color.LightGreen);
                if (!_chkDry.Checked)
                {
                    AppendLog("Converted project: " + _lastOutput, Color.LightGreen);
                    AppendLog("Original input was not modified.", Color.LightGreen);
                    _btnOpenOut.Enabled = true;
                }
            }
            else
            {
                AppendLog($"Failed with exit code {code}.", Color.Salmon);
            }
            try { _running.Dispose(); } catch { /* ignore */ }
            _running = null;
        };
        _pollTimer.Start();
    }
}
