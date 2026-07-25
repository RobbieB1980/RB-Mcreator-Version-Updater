<#
.SYNOPSIS
    Graphical frontend for RB MCreator / NeoForge 26.2 converter.

.DESCRIPTION
    Browse for an input MCreator/Gradle mod folder and an output folder.
    The tool always copies to the output directory first, then converts the
    copy so the original project is never overwritten.

.EXAMPLE
    .\Convert-ToNeoForge262-GUI.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
$ConverterScript = Join-Path $ToolRoot 'Convert-ToNeoForge262.ps1'

if (-not (Test-Path -LiteralPath $ConverterScript)) {
    throw "Converter script not found: $ConverterScript"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# -------------------- helpers --------------------

function Append-Log {
    param([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::Gainsboro)
    if ($null -eq $script:txtLog -or $script:txtLog.IsDisposed) { return }
    if ($script:txtLog.InvokeRequired) {
        $script:txtLog.BeginInvoke([Action]{
            Append-Log -Text $Text -Color $Color
        }) | Out-Null
        return
    }
    $script:txtLog.SelectionStart = $script:txtLog.TextLength
    $script:txtLog.SelectionLength = 0
    $script:txtLog.SelectionColor = $Color
    $script:txtLog.AppendText($Text + [Environment]::NewLine)
    $script:txtLog.ScrollToCaret()
}

function Suggest-OutputPath([string]$InputPath) {
    if ([string]::IsNullOrWhiteSpace($InputPath)) { return '' }
    try {
        $full = [System.IO.Path]::GetFullPath($InputPath.Trim())
        $name = Split-Path $full -Leaf
        $parent = Split-Path $full -Parent
        $candidate = Join-Path $parent ($name + '-26.2')
        $i = 2
        while (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $parent ("$name-26.2-$i")
            $i++
        }
        return $candidate
    }
    catch {
        return ''
    }
}

function Set-Busy([bool]$Busy) {
    $btnRun.Enabled = -not $Busy
    $btnBrowseIn.Enabled = -not $Busy
    $btnBrowseOut.Enabled = -not $Busy
    $btnOpenOut.Enabled = -not $Busy
    $txtInput.Enabled = -not $Busy
    $txtOutput.Enabled = -not $Busy
    $txtNeo.Enabled = -not $Busy
    $txtMc.Enabled = -not $Busy
    $txtModVer.Enabled = -not $Busy
    $chkFetch.Enabled = -not $Busy
    $chkCompile.Enabled = -not $Busy
    $chkBuild.Enabled = -not $Busy
    $chkDry.Enabled = -not $Busy
    $progress.Style = if ($Busy) { 'Marquee' } else { 'Continuous' }
    $progress.MarqueeAnimationSpeed = if ($Busy) { 30 } else { 0 }
    if (-not $Busy) { $progress.Value = 0 }
    $form.Cursor = if ($Busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
}

function Browse-Folder([string]$Description, [string]$SelectedPath) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if ($SelectedPath -and (Test-Path -LiteralPath $SelectedPath)) {
        $dlg.SelectedPath = $SelectedPath
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }
    return $null
}

function Test-LooksLikeModProject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Path 'src')) { return $true }
    if (Get-ChildItem -LiteralPath $Path -Filter '*.mcreator' -File -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path -LiteralPath (Join-Path $Path 'gradle.properties')) { return $true }
    return $false
}

function Start-Conversion {
    $inputPath = $txtInput.Text.Trim()
    $outputPath = $txtOutput.Text.Trim()
    $neo = $txtNeo.Text.Trim()
    $mc = $txtMc.Text.Trim()
    $modVer = $txtModVer.Text.Trim()

    if (-not $inputPath) {
        [System.Windows.Forms.MessageBox]::Show('Choose an input project folder.', 'Missing input', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $inputPath -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Input folder does not exist:`n$inputPath", 'Invalid input', 'OK', 'Error') | Out-Null
        return
    }
    if (-not (Test-LooksLikeModProject $inputPath)) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "This folder does not look like a mod project (no src/, *.mcreator, or gradle.properties).`nContinue anyway?",
            'Confirm',
            'YesNo',
            'Question'
        )
        if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    if (-not $outputPath) {
        [System.Windows.Forms.MessageBox]::Show('Choose an output folder (conversion never writes into the input).', 'Missing output', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $neo) { $neo = '26.2.0.32-beta' }
    if (-not $mc) { $mc = '26.2' }

    $inFull = [System.IO.Path]::GetFullPath($inputPath)
    $outFull = [System.IO.Path]::GetFullPath($outputPath)
    if ($inFull.TrimEnd('\') -ieq $outFull.TrimEnd('\')) {
        [System.Windows.Forms.MessageBox]::Show('Output folder must be different from the input folder.', 'Invalid output', 'OK', 'Error') | Out-Null
        return
    }

    if ((Test-Path -LiteralPath $outFull) -and -not $chkDry.Checked) {
        $items = @(Get-ChildItem -LiteralPath $outFull -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Output folder already exists and is not empty.`nChoose an empty or new folder so the original project is not mixed with previous results.`n`n$outFull",
                'Output not empty',
                'OK',
                'Warning'
            ) | Out-Null
            return
        }
    }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $ConverterScript
        '-Path', $inFull
        '-OutputPath', $outFull
        '-MinecraftVersion', $mc
        '-NeoVersion', $neo
        '-FetchWrapper'
    )
    if ($modVer) { $argList += @('-ModVersion', $modVer) }
    if ($chkDry.Checked) { $argList += '-DryRun' }
    if ($chkCompile.Checked) { $argList += '-Compile' }
    if ($chkBuild.Checked) { $argList += '-Build' }
    # FetchWrapper always on for GUI convenience when building/compiling; always pass it
    # (already added). User can uncheck via not compiling - still useful for scaffold.

    if (-not $chkFetch.Checked) {
        # Remove the FetchWrapper we always added
        $argList = @($argList | Where-Object { $_ -ne '-FetchWrapper' })
    }

    $txtLog.Clear()
    Append-Log "RB MCreator Version Updater" ([System.Drawing.Color]::White)
    Append-Log "Input : $inFull" ([System.Drawing.Color]::LightSkyBlue)
    Append-Log "Output: $outFull  (original will not be modified)" ([System.Drawing.Color]::LightGreen)
    Append-Log "Minecraft $mc / NeoForge $neo" ([System.Drawing.Color]::Khaki)
    Append-Log "----------------------------------------" ([System.Drawing.Color]::Gray)
    Append-Log "Starting..." ([System.Drawing.Color]::Gainsboro)

    Set-Busy $true
    $script:lastOutput = $outFull
    $script:runFailed = $false

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    # Quote args properly
    $quoted = foreach ($a in $argList) {
        if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
    }
    $psi.Arguments = ($quoted -join ' ')
    $psi.WorkingDirectory = $ToolRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true

    $proc.add_OutputDataReceived({
        param($sender, $e)
        if ($null -ne $e.Data -and $e.Data.Length -gt 0) {
            $line = $e.Data
            $color = [System.Drawing.Color]::Gainsboro
            if ($line -match 'WARN|warning') { $color = [System.Drawing.Color]::Gold }
            elseif ($line -match 'error|FAIL|Exception') { $color = [System.Drawing.Color]::Salmon }
            elseif ($line -match '==>|SUCCESS|Copied|Conversion wrote|original unchanged') { $color = [System.Drawing.Color]::PaleGreen }
            Append-Log $line $color
        }
    })
    $proc.add_ErrorDataReceived({
        param($sender, $e)
        if ($null -ne $e.Data -and $e.Data.Length -gt 0) {
            Append-Log $e.Data ([System.Drawing.Color]::Salmon)
        }
    })

    $script:runningProc = $proc

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    # Poll completion on UI timer so we stay on the WinForms thread
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick({
        if ($script:runningProc -and $script:runningProc.HasExited) {
            $timer.Stop()
            $timer.Dispose()
            $code = $script:runningProc.ExitCode
            Set-Busy $false
            Append-Log "----------------------------------------" ([System.Drawing.Color]::Gray)
            if ($code -eq 0) {
                Append-Log "Finished successfully (exit 0)." ([System.Drawing.Color]::LightGreen)
                if (-not $chkDry.Checked) {
                    Append-Log "Converted project: $script:lastOutput" ([System.Drawing.Color]::LightGreen)
                    Append-Log "Original input was not modified." ([System.Drawing.Color]::LightGreen)
                    $btnOpenOut.Enabled = $true
                }
            }
            else {
                Append-Log "Failed with exit code $code." ([System.Drawing.Color]::Salmon)
            }
            try { $script:runningProc.Dispose() } catch {}
            $script:runningProc = $null
        }
    })
    $timer.Start()
}

# -------------------- UI --------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = 'RB MCreator Version Updater - NeoForge 26.2'
$form.Size = New-Object System.Drawing.Size(820, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 520)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(32, 34, 40)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

function New-Label([string]$Text, [int]$X, [int]$Y, [int]$W = 120) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 22)
    $l.ForeColor = [System.Drawing.Color]::Gainsboro
    return $l
}

function New-TextBox([int]$X, [int]$Y, [int]$W) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, 24)
    $t.BackColor = [System.Drawing.Color]::FromArgb(45, 48, 56)
    $t.ForeColor = [System.Drawing.Color]::White
    $t.BorderStyle = 'FixedSingle'
    return $t
}

function New-Button([string]$Text, [int]$X, [int]$Y, [int]$W = 90) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, 28)
    $b.FlatStyle = 'Flat'
    $b.BackColor = [System.Drawing.Color]::FromArgb(60, 64, 78)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(90, 96, 112)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Convert MCreator / NeoForge 26.1.x  ->  Minecraft 26.2'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
$lblTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblTitle.Size = New-Object System.Drawing.Size(700, 28)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = 'Always writes to a new output folder. Your original project is never modified.'
$lblSub.Location = New-Object System.Drawing.Point(16, 40)
$lblSub.Size = New-Object System.Drawing.Size(760, 20)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(140, 200, 140)
$form.Controls.Add($lblSub)

# Input
$form.Controls.Add((New-Label 'Input project' 16 72 110))
$txtInput = New-TextBox 130 70 540
$form.Controls.Add($txtInput)
$btnBrowseIn = New-Button 'Browse...' 680 68 100
$form.Controls.Add($btnBrowseIn)

# Output
$form.Controls.Add((New-Label 'Output folder' 16 108 110))
$txtOutput = New-TextBox 130 106 540
$form.Controls.Add($txtOutput)
$btnBrowseOut = New-Button 'Browse...' 680 104 100
$form.Controls.Add($btnBrowseOut)

# Versions row
$form.Controls.Add((New-Label 'Minecraft' 16 148 80))
$txtMc = New-TextBox 100 146 90
$txtMc.Text = '26.2'
$form.Controls.Add($txtMc)

$form.Controls.Add((New-Label 'NeoForge' 210 148 80))
$txtNeo = New-TextBox 290 146 160
$txtNeo.Text = '26.2.0.32-beta'
$form.Controls.Add($txtNeo)

$form.Controls.Add((New-Label 'Mod version' 470 148 90))
$txtModVer = New-TextBox 560 146 100
$txtModVer.Text = ''
$form.Controls.Add($txtModVer)
$form.Controls.Add((New-Label '(blank = auto)' 665 148 110))

# Options
$chkFetch = New-Object System.Windows.Forms.CheckBox
$chkFetch.Text = 'Fetch Gradle wrapper (recommended)'
$chkFetch.Checked = $true
$chkFetch.Location = New-Object System.Drawing.Point(16, 186)
$chkFetch.Size = New-Object System.Drawing.Size(280, 22)
$chkFetch.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($chkFetch)

$chkCompile = New-Object System.Windows.Forms.CheckBox
$chkCompile.Text = 'Compile after convert'
$chkCompile.Checked = $false
$chkCompile.Location = New-Object System.Drawing.Point(310, 186)
$chkCompile.Size = New-Object System.Drawing.Size(170, 22)
$chkCompile.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($chkCompile)

$chkBuild = New-Object System.Windows.Forms.CheckBox
$chkBuild.Text = 'Full build (jar)'
$chkBuild.Checked = $false
$chkBuild.Location = New-Object System.Drawing.Point(490, 186)
$chkBuild.Size = New-Object System.Drawing.Size(140, 22)
$chkBuild.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($chkBuild)

$chkDry = New-Object System.Windows.Forms.CheckBox
$chkDry.Text = 'Dry run (preview only)'
$chkDry.Checked = $false
$chkDry.Location = New-Object System.Drawing.Point(640, 186)
$chkDry.Size = New-Object System.Drawing.Size(150, 22)
$chkDry.ForeColor = [System.Drawing.Color]::Khaki
$form.Controls.Add($chkDry)

# Actions
$btnRun = New-Button 'Convert' 16 222 120
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(46, 120, 80)
$btnRun.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 160, 100)
$btnRun.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$form.Controls.Add($btnRun)

$btnOpenOut = New-Button 'Open output' 150 222 120
$btnOpenOut.Enabled = $false
$form.Controls.Add($btnOpenOut)

$btnClear = New-Button 'Clear log' 280 222 100
$form.Controls.Add($btnClear)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(400, 226)
$progress.Size = New-Object System.Drawing.Size(380, 20)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

# Log
$lblLog = New-Label 'Log' 16 262 80
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(16, 286)
$txtLog.Size = New-Object System.Drawing.Size(764, 290)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(22, 24, 28)
$txtLog.ForeColor = [System.Drawing.Color]::Gainsboro
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = 'FixedSingle'
$txtLog.DetectUrls = $false
$form.Controls.Add($txtLog)
$script:txtLog = $txtLog

# Events
$btnBrowseIn.Add_Click({
    $picked = Browse-Folder 'Select MCreator / NeoForge project folder' $txtInput.Text
    if ($picked) {
        $txtInput.Text = $picked
        if ([string]::IsNullOrWhiteSpace($txtOutput.Text) -or $txtOutput.Text -match '-26\.2') {
            $txtOutput.Text = Suggest-OutputPath $picked
        }
    }
})

$btnBrowseOut.Add_Click({
    $start = if ($txtOutput.Text) { $txtOutput.Text } elseif ($txtInput.Text) { Split-Path $txtInput.Text -Parent } else { '' }
    $picked = Browse-Folder 'Select empty output folder (converted copy goes here)' $start
    if ($picked) { $txtOutput.Text = $picked }
})

$txtInput.Add_Leave({
    if ($txtInput.Text -and [string]::IsNullOrWhiteSpace($txtOutput.Text)) {
        $txtOutput.Text = Suggest-OutputPath $txtInput.Text
    }
})

$btnRun.Add_Click({ Start-Conversion })

$btnOpenOut.Add_Click({
    $p = $txtOutput.Text.Trim()
    if ($p -and (Test-Path -LiteralPath $p)) {
        Start-Process explorer.exe -ArgumentList $p
    }
    else {
        [System.Windows.Forms.MessageBox]::Show('Output folder does not exist yet.', 'Open output', 'OK', 'Information') | Out-Null
    }
})

$btnClear.Add_Click({ $txtLog.Clear() })

$form.Add_Shown({
    Append-Log "Ready. Choose an input project and output folder, then click Convert." ([System.Drawing.Color]::Gray)
    Append-Log "Tip: output is suggested as <project>-26.2 next to the original." ([System.Drawing.Color]::Gray)
})

# Keep log anchored on resize
$form.Add_Resize({
    $margin = 16
    $txtLog.Width = $form.ClientSize.Width - ($margin * 2)
    $txtLog.Height = $form.ClientSize.Height - $txtLog.Top - $margin
    $progress.Width = [Math]::Max(100, $form.ClientSize.Width - $progress.Left - $margin)
})

[void]$form.ShowDialog()
