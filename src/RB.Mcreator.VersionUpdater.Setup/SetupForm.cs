using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using Microsoft.Win32;

namespace RB.Mcreator.VersionUpdater.Setup;

public sealed class SetupForm : Form
{
    private readonly TextBox _txtDir = new();
    private readonly CheckBox _chkDesktop = new() { Text = "Create desktop shortcut", Checked = true, AutoSize = true };
    private readonly CheckBox _chkStartMenu = new() { Text = "Create Start Menu shortcut", Checked = true, AutoSize = true };
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Continuous, Minimum = 0, Maximum = 100 };
    private readonly Button _btnInstall = new() { Text = "Install", Height = 32, Width = 120 };
    private readonly Button _btnBrowse = new() { Text = "Browse...", Height = 28, Width = 100 };
    private readonly Button _btnCancel = new() { Text = "Close", Height = 32, Width = 100 };
    private readonly Label _status = new() { AutoSize = false, Height = 40 };
    private bool _busy;

    public SetupForm()
    {
        Text = "Install RB All Updater";
        // ClientSize (not outer Size) so DPI/title-bar never clips the bottom buttons
        ClientSize = new Size(580, 380);
        MinimumSize = new Size(560, 360);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(32, 34, 40);
        ForeColor = Color.Gainsboro;
        Font = new Font("Segoe UI", 9.5f);
        Padding = new Padding(0, 0, 0, 12);
        AutoScaleMode = AutoScaleMode.Dpi;

        var title = new Label
        {
            Text = "RB All Updater",
            Font = new Font("Segoe UI Semibold", 14f),
            ForeColor = Color.White,
            Location = new Point(24, 18),
            AutoSize = true
        };
        var sub = new Label
        {
            Text = "Installs a portable toolset for MCreator, ModDevGradle, and NeoGradle 26.1 → 26.2.",
            ForeColor = Color.FromArgb(160, 200, 160),
            Location = new Point(24, 52),
            Size = new Size(530, 36)
        };

        var lbl = new Label { Text = "Install folder:", Location = new Point(24, 100), AutoSize = true };
        _txtDir.Location = new Point(24, 126);
        _txtDir.Width = 420;
        _txtDir.Height = 26;
        _txtDir.BackColor = Color.FromArgb(45, 48, 56);
        _txtDir.ForeColor = Color.White;
        _txtDir.BorderStyle = BorderStyle.FixedSingle;
        _txtDir.Text = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RB-All-Updater");

        _btnBrowse.Location = new Point(454, 124);
        _btnBrowse.FlatStyle = FlatStyle.Flat;
        _btnBrowse.BackColor = Color.FromArgb(60, 64, 78);
        _btnBrowse.ForeColor = Color.White;

        _chkDesktop.Location = new Point(24, 170);
        _chkDesktop.ForeColor = Color.Gainsboro;
        _chkStartMenu.Location = new Point(24, 200);
        _chkStartMenu.ForeColor = Color.Gainsboro;

        _progress.Location = new Point(24, 242);
        _progress.Size = new Size(532, 22);

        // Status left; Install + Close fully visible on the right with room below
        _status.Location = new Point(24, 282);
        _status.Size = new Size(300, 48);
        _status.ForeColor = Color.Gainsboro;

        _btnInstall.Location = new Point(320, 288);
        _btnInstall.Size = new Size(120, 36);
        _btnInstall.FlatStyle = FlatStyle.Flat;
        _btnInstall.BackColor = Color.FromArgb(46, 120, 80);
        _btnInstall.ForeColor = Color.White;
        _btnInstall.FlatAppearance.BorderColor = Color.FromArgb(70, 160, 100);

        _btnCancel.Location = new Point(452, 288);
        _btnCancel.Size = new Size(104, 36);
        _btnCancel.FlatStyle = FlatStyle.Flat;
        _btnCancel.BackColor = Color.FromArgb(60, 64, 78);
        _btnCancel.ForeColor = Color.White;

        Controls.AddRange(new Control[]
        {
            title, sub, lbl, _txtDir, _btnBrowse, _chkDesktop, _chkStartMenu,
            _progress, _status, _btnInstall, _btnCancel
        });

        _btnBrowse.Click += (_, _) =>
        {
            using var dlg = new FolderBrowserDialog
            {
                Description = "Choose install folder",
                UseDescriptionForTitle = true,
                ShowNewFolderButton = true
            };
            if (Directory.Exists(_txtDir.Text))
                dlg.SelectedPath = _txtDir.Text;
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _txtDir.Text = dlg.SelectedPath;
        };

        _btnCancel.Click += (_, _) => Close();
        _btnInstall.Click += async (_, _) => await InstallAsync();
    }

    private async Task InstallAsync()
    {
        if (_busy) return;
        var dest = _txtDir.Text.Trim();
        if (string.IsNullOrWhiteSpace(dest))
        {
            MessageBox.Show(this, "Choose an install folder.", "Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        try
        {
            dest = Path.GetFullPath(dest);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "Invalid folder: " + ex.Message, "Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        _busy = true;
        _btnInstall.Enabled = false;
        _btnBrowse.Enabled = false;
        _txtDir.Enabled = false;
        _status.Text = "Installing...";
        _progress.Value = 5;

        try
        {
            await Task.Run(() => InstallCore(dest));
            _progress.Value = 100;
            _status.Text = "Installation complete.";
            _status.ForeColor = Color.LightGreen;

            var exe = Path.Combine(dest, "RB-All-Updater.exe");
            if (!File.Exists(exe))
                exe = Path.Combine(dest, "RB-Mcreator-Version-Updater.exe"); // legacy package name
            var r = MessageBox.Show(this,
                "Installed successfully to:\n" + dest + "\n\nLaunch RB All Updater now?",
                "Setup complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (r == DialogResult.Yes && File.Exists(exe))
            {
                Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = dest });
            }
        }
        catch (Exception ex)
        {
            _status.Text = "Install failed.";
            _status.ForeColor = Color.Salmon;
            MessageBox.Show(this, ex.Message, "Setup failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _busy = false;
            _btnInstall.Enabled = true;
            _btnBrowse.Enabled = true;
            _txtDir.Enabled = true;
        }
    }

    private void InstallCore(string dest)
    {
        Directory.CreateDirectory(dest);
        Report(10, "Locating package...");

        var payloadZip = FindPayloadZip();
        if (payloadZip is null)
            throw new InvalidOperationException(
                "Could not find portable package.\n\nPlace 'portable-payload.zip' next to this installer,\nor run Build-Release.ps1 to produce the full distribution.");

        Report(20, "Extracting tools...");
        // Clear previous install files carefully (only our known names if folder was used before)
        ExtractZip(payloadZip, dest, progress => Report(20 + (int)(progress * 60), "Extracting..."));

        var exe = Path.Combine(dest, "RB-All-Updater.exe");
        if (!File.Exists(exe))
            exe = Path.Combine(dest, "RB-Mcreator-Version-Updater.exe");
        if (!File.Exists(exe))
            throw new InvalidOperationException("Package extracted but RB-All-Updater.exe is missing.");

        Report(85, "Creating shortcuts...");
        if (_chkDesktop.Checked)
            CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                "RB All Updater.lnk"), exe, dest);
        if (_chkStartMenu.Checked)
        {
            var sm = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs",
                "RB All Updater");
            Directory.CreateDirectory(sm);
            CreateShortcut(Path.Combine(sm, "RB All Updater.lnk"), exe, dest);
            CreateShortcut(Path.Combine(sm, "Uninstall (delete folder).lnk"), "explorer.exe", dest, dest);
        }

        Report(92, "Writing uninstaller helper...");
        File.WriteAllText(Path.Combine(dest, "UNINSTALL.txt"),
            "To uninstall RB All Updater:\r\n" +
            "1. Close the application if it is running.\r\n" +
            "2. Delete this folder:\r\n   " + dest + "\r\n" +
            "3. Remove desktop / Start Menu shortcuts if present.\r\n");

        // Optional registry App Paths (HKCU - no admin)
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\App Paths\RB-All-Updater.exe");
            key?.SetValue("", exe);
            key?.SetValue("Path", dest);
        }
        catch
        {
            // non-fatal
        }

        Report(100, "Done.");
    }

    private static string? FindPayloadZip()
    {
        var baseDir = AppContext.BaseDirectory;
        var names = new[]
        {
            "portable-payload.zip",
            "RB-All-Updater-Portable.zip",
            "RB-Mcreator-Version-Updater-Portable.zip",
            "payload.zip"
        };
        foreach (var n in names)
        {
            var p = Path.Combine(baseDir, n);
            if (File.Exists(p)) return p;
        }

        // Embedded resource (self-contained single-file installer)
        var asm = Assembly.GetExecutingAssembly();
        var resourceName = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("portable-payload.zip", StringComparison.OrdinalIgnoreCase)
                                 || n.Equals("portable-payload.zip", StringComparison.OrdinalIgnoreCase));
        if (resourceName is not null)
        {
            var temp = Path.Combine(Path.GetTempPath(), "RB-All-Updater-payload-" + Guid.NewGuid().ToString("N") + ".zip");
            using (var stream = asm.GetManifestResourceStream(resourceName)!)
            using (var fs = File.Create(temp))
                stream.CopyTo(fs);
            return temp;
        }

        // Dev layout: dist next to repo
        var dev = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "dist", "portable-payload.zip"));
        if (File.Exists(dev)) return dev;

        return null;
    }

    private static void ExtractZip(string zipPath, string dest, Action<double> progress)
    {
        using var zip = ZipFile.OpenRead(zipPath);
        var entries = zip.Entries.Where(e => !string.IsNullOrEmpty(e.Name) || e.FullName.EndsWith('/') || e.FullName.EndsWith('\\')).ToList();
        // Prefer extracting contents if zip has a single root folder
        var rootPrefix = DetectSingleRootPrefix(zip.Entries.Select(e => e.FullName));
        var total = Math.Max(1, zip.Entries.Count(e => !string.IsNullOrEmpty(e.Name)));
        var done = 0;

        foreach (var entry in zip.Entries)
        {
            var name = entry.FullName.Replace('\\', '/');
            if (!string.IsNullOrEmpty(rootPrefix) && name.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
                name = name[rootPrefix.Length..];
            if (string.IsNullOrWhiteSpace(name)) continue;

            var target = Path.Combine(dest, name.Replace('/', Path.DirectorySeparatorChar));
            if (name.EndsWith('/'))
            {
                Directory.CreateDirectory(target);
                continue;
            }

            var dir = Path.GetDirectoryName(target);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);

            entry.ExtractToFile(target, overwrite: true);
            done++;
            progress(done / (double)total);
        }
    }

    private static string DetectSingleRootPrefix(IEnumerable<string> names)
    {
        var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var n in names)
        {
            var norm = n.Replace('\\', '/').TrimStart('/');
            if (string.IsNullOrEmpty(norm)) continue;
            var slash = norm.IndexOf('/');
            if (slash <= 0) return "";
            roots.Add(norm[..(slash + 1)]);
            if (roots.Count > 1) return "";
        }
        return roots.Count == 1 ? roots.First() : "";
    }

    private void Report(int value, string status)
    {
        if (IsDisposed) return;
        if (InvokeRequired)
        {
            BeginInvoke(() => Report(value, status));
            return;
        }
        _progress.Value = Math.Clamp(value, 0, 100);
        _status.Text = status;
    }

    private static void CreateShortcut(string lnkPath, string target, string workingDir, string? args = null)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lnkPath)!);
        // Use PowerShell to create .lnk without extra COM packages
        var ps = $@"
$w = New-Object -ComObject WScript.Shell
$s = $w.CreateShortcut('{EscapePs(lnkPath)}')
$s.TargetPath = '{EscapePs(target)}'
$s.WorkingDirectory = '{EscapePs(workingDir)}'
{(args is null ? "" : $"$s.Arguments = '{EscapePs(args)}'")}
$s.Description = 'RB All Updater'
$s.Save()
";
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -Command " + Quote(ps),
            UseShellExecute = false,
            CreateNoWindow = true
        };
        using var p = Process.Start(psi);
        p?.WaitForExit(15000);
    }

    private static string EscapePs(string s) => s.Replace("'", "''");
    private static string Quote(string s) => "\"" + s.Replace("\"", "\\\"") + "\"";
}
