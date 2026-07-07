param(
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path -LiteralPath $script:logDir)) {
    New-Item -ItemType Directory -Path $script:logDir | Out-Null
}
$script:logFile = Join-Path $script:logDir ("gui-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:latestLogFile = Join-Path $script:logDir 'latest-gui.log'

function Write-GuiLog {
    param([AllowEmptyString()][string]$Text)

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$stamp] $Text"
    try {
        [System.IO.File]::AppendAllText($script:logFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        [System.IO.File]::AppendAllText($script:latestLogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host "Failed to write GUI log: $($_.Exception.Message)"
    }
}

function Format-GuiError {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    ($ErrorRecord | Format-List * -Force | Out-String).TrimEnd()
}

Set-Content -LiteralPath $script:latestLogFile -Value "llamacppWindowAutoRun GUI log started: $((Get-Date).ToString('o'))" -Encoding UTF8
Write-GuiLog "Script: $PSCommandPath"
Write-GuiLog "PowerShell: $($PSVersionTable.PSVersion)"

trap {
    $text = "Fatal GUI error: $($_.Exception.Message)`r`n$(Format-GuiError -ErrorRecord $_)"
    Write-GuiLog $text
    Write-Host $text
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [void][System.Windows.Forms.MessageBox]::Show($text, 'llamacppWindowAutoRun fatal error', 'OK', 'Error')
    } catch {
    }
    exit 1
}

. "$PSScriptRoot\scripts\LlamaCppTools.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace LlamaCppWindowAutoRun {
    public static class ProcessBridge {
        public static Thread Pump(StreamReader reader, Control target, Action<string> append) {
            Thread thread = new Thread(() => {
                try {
                    string line;
                    while ((line = reader.ReadLine()) != null) {
                        if (target.IsDisposed || !target.IsHandleCreated) {
                            break;
                        }
                        target.BeginInvoke(append, new object[] { line + Environment.NewLine });
                    }
                } catch (Exception ex) {
                    try {
                        if (!target.IsDisposed && target.IsHandleCreated) {
                            target.BeginInvoke(append, new object[] { "[pipe error] " + ex.Message + Environment.NewLine });
                        }
                    } catch {
                    }
                }
            });
            thread.IsBackground = true;
            thread.Start();
            return thread;
        }

        public static Thread WatchExit(Process process, Control target, Action<int> onExit) {
            Thread thread = new Thread(() => {
                int exitCode = -1;
                try {
                    process.WaitForExit();
                    exitCode = process.ExitCode;
                } catch {
                }

                try {
                    if (!target.IsDisposed && target.IsHandleCreated) {
                        target.BeginInvoke(onExit, new object[] { exitCode });
                    }
                } catch {
                }
            });
            thread.IsBackground = true;
            thread.Start();
            return thread;
        }
    }
}
'@

$script:config = Read-LocalLlamaConfig
$script:serverProcess = $null
$script:toolProcess = $null
$script:paramControls = @{}
$script:processLogs = New-Object System.Collections.ArrayList

if ($SelfTest) {
    Write-GuiLog "SelfTest OK. TargetDir=$($script:config.TargetDir) TmpDir=$($script:config.TmpDir)"
    Write-Host "llamacppWindowAutoRun GUI self-test OK. Log: $script:latestLogFile"
    exit 0
}

function Append-Console {
    param([string]$Text)

    Write-GuiLog ($Text.TrimEnd())

    if ($script:console.InvokeRequired) {
        [void]$script:console.BeginInvoke([Action[string]]{ param($value) Append-Console $value }, $Text)
        return
    }

    $script:console.AppendText($Text)
    $script:console.SelectionStart = $script:console.TextLength
    $script:console.ScrollToCaret()
}

function Set-UiStatus {
    param([string]$Text)

    Write-GuiLog "STATUS: $Text"

    if ($script:statusLabel.InvokeRequired) {
        [void]$script:statusLabel.BeginInvoke([Action[string]]{ param($value) Set-UiStatus $value }, $Text)
        return
    }

    $script:statusLabel.Text = $Text
}

function New-Label {
    param([string]$Text)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Margin = New-Object System.Windows.Forms.Padding(6, 8, 4, 2)
    return $label
}

function New-Button {
    param([string]$Text)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = 126
    $button.Height = 30
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    return $button
}

function Show-GuiError {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)]$ErrorRecord
    )

    $text = "$Context failed: $($ErrorRecord.Exception.Message)"
    $details = Format-GuiError -ErrorRecord $ErrorRecord
    Write-GuiLog "$text`r`n$details"

    if (Get-Variable -Name console -Scope Script -ErrorAction SilentlyContinue) {
        Append-Console ("[ERROR] $text" + [Environment]::NewLine)
        Append-Console ($details + [Environment]::NewLine)
    }

    if (Get-Variable -Name statusLabel -Scope Script -ErrorAction SilentlyContinue) {
        Set-UiStatus "$Context failed"
    }

    [void][System.Windows.Forms.MessageBox]::Show($text + [Environment]::NewLine + "Log: $script:latestLogFile", 'llamacppWindowAutoRun error', 'OK', 'Error')
}

function Invoke-GuiAction {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        Write-GuiLog "ACTION START: $Name"
        & $Action
        Write-GuiLog "ACTION END: $Name"
    } catch {
        Show-GuiError -Context $Name -ErrorRecord $_
    }
}

function Write-UnhandledGuiException {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)]$Exception
    )

    $message = "Unhandled GUI exception in ${Context}: $($Exception.Message)"
    Write-GuiLog ($message + [Environment]::NewLine + $Exception.ToString())

    if (Get-Variable -Name console -Scope Script -ErrorAction SilentlyContinue) {
        Append-Console ("[ERROR] $message" + [Environment]::NewLine)
    }

    if (Get-Variable -Name statusLabel -Scope Script -ErrorAction SilentlyContinue) {
        Set-UiStatus "$Context error"
    }
}

[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException([System.Threading.ThreadExceptionEventHandler]{
    param($sender, $eventArgs)
    Write-UnhandledGuiException -Context 'UI thread' -Exception $eventArgs.Exception
})
[System.AppDomain]::CurrentDomain.add_UnhandledException([System.UnhandledExceptionEventHandler]{
    param($sender, $eventArgs)
    if ($eventArgs.ExceptionObject -is [System.Exception]) {
        Write-UnhandledGuiException -Context 'AppDomain' -Exception $eventArgs.ExceptionObject
    } else {
        Write-GuiLog "Unhandled AppDomain exception: $($eventArgs.ExceptionObject)"
    }
})

function New-ProcessLogFiles {
    param([Parameter(Mandatory = $true)][string]$Name)

    $safeName = $Name -replace '[^a-zA-Z0-9._-]', '-'
    $base = Join-Path $script:logDir ("process-{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), $safeName)

    [pscustomobject]@{
        StdOut = "$base.out.log"
        StdErr = "$base.err.log"
    }
}

function Read-AppendedText {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    $path = if ($Kind -eq 'stdout') { $Item.StdOutPath } else { $Item.StdErrPath }
    $lengthProperty = if ($Kind -eq 'stdout') { 'StdOutLength' } else { 'StdErrLength' }

    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    try {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::Default)
    } catch {
        Write-GuiLog "Could not read $Kind log for $($Item.Name): $($_.Exception.Message)"
        return
    }

    $oldLength = [int]$Item.$lengthProperty
    if ($text.Length -lt $oldLength) {
        $oldLength = 0
    }

    if ($text.Length -gt $oldLength) {
        $chunk = $text.Substring($oldLength)
        $Item.$lengthProperty = $text.Length
        if ($chunk) {
            Append-Console $chunk
        }
    }
}

function Drain-ProcessLogs {
    foreach ($item in @($script:processLogs)) {
        Read-AppendedText -Item $item -Kind 'stdout'
        Read-AppendedText -Item $item -Kind 'stderr'

        if ((-not $item.Completed) -and $item.Process.HasExited) {
            Read-AppendedText -Item $item -Kind 'stdout'
            Read-AppendedText -Item $item -Kind 'stderr'
            $item.Completed = $true
            Append-Console ("[$($item.Name) exited: $($item.Process.ExitCode)]" + [Environment]::NewLine)

            if ($item.OnExit) {
                try {
                    & $item.OnExit $item.Process.ExitCode
                } catch {
                    Show-GuiError -Context "$($item.Name) exit handler" -ErrorRecord $_
                }
            }
        }
    }
}

function Collect-ConfigFromUi {
    Write-GuiLog 'Collecting config from UI'
    $script:config.ModelPath = $script:modelBox.Text
    if (-not ($script:config.PSObject.Properties.Name -contains 'MmprojPath')) {
        $script:config | Add-Member -NotePropertyName MmprojPath -NotePropertyValue ''
    }
    $script:config.MmprojPath = $script:mmprojBox.Text
    $script:config.TargetDir = $script:targetBox.Text
    $script:config.TmpDir = $script:tmpBox.Text

    foreach ($param in @($script:config.Params)) {
        $key = [string]$param.Name
        if (-not $script:paramControls.ContainsKey($key)) {
            continue
        }

        $controls = $script:paramControls[$key]
        $param.Enabled = [bool]$controls.EnabledBox.Checked
        if ($param.Type -ne 'switch') {
            $param.Value = [string]$controls.ValueBox.Text
        }
    }

    Save-LocalLlamaConfig -Config $script:config
    [void](Export-LlamaServerCmd -Config $script:config)
    Write-GuiLog 'Config saved and generated launcher updated'
}

function Start-ManagedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Name,
        [scriptblock]$OnExit
    )

    Write-GuiLog "Starting process [$Name]: $FileName $(ConvertTo-WindowsArgumentString -Arguments $Arguments)"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    if ($WorkingDirectory) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    Set-ProcessStartInfoArguments -StartInfo $psi -Arguments $Arguments

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    if (-not $process.Start()) {
        throw "Failed to start $FileName"
    }

    $capturedName = [string]$Name
    $capturedOnExit = $OnExit

    $appendAction = [Action[string]]{
        param([string]$Text)
        Append-Console $Text
    }.GetNewClosure()

    $exitAction = [Action[int]]{
        param([int]$ExitCode)
        Append-Console ("[$capturedName exited: $ExitCode]" + [Environment]::NewLine)
        if ($null -ne $capturedOnExit) {
            try {
                & $capturedOnExit $ExitCode
            } catch {
                Show-GuiError -Context "$capturedName exit handler" -ErrorRecord $_
            }
        }
    }.GetNewClosure()

    $stdoutPump = [LlamaCppWindowAutoRun.ProcessBridge]::Pump($process.StandardOutput, $form, $appendAction)
    $stderrPump = [LlamaCppWindowAutoRun.ProcessBridge]::Pump($process.StandardError, $form, $appendAction)
    $exitPump = [LlamaCppWindowAutoRun.ProcessBridge]::WatchExit($process, $form, $exitAction)

    $process | Add-Member -NotePropertyName LlamaCppWindowAutoRunHandlers -NotePropertyValue @($stdoutPump, $stderrPump, $exitPump)
    Write-GuiLog "Started process [$Name] PID=$($process.Id)"
    Append-Console ("[$Name PID=$($process.Id)]" + [Environment]::NewLine)
    return $process
}

function Start-ToolCommand {
    param([string[]]$Arguments, [string]$Title)

    if ($script:toolProcess -and -not $script:toolProcess.HasExited) {
        Append-Console "[tool already running]" + [Environment]::NewLine
        return
    }

    Collect-ConfigFromUi
    $script:console.Clear()
    Append-Console "[$Title]" + [Environment]::NewLine
    $psExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) {
        $psExe = 'powershell.exe'
    }

    $script:toolProcess = Start-ManagedProcess `
        -FileName $psExe `
        -Arguments (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Update-LlamaCpp.ps1')) + $Arguments) `
        -WorkingDirectory $PSScriptRoot `
        -Name $Title `
        -OnExit {
            param($ExitCode)
            if ($ExitCode -eq 2) {
                Set-UiStatus 'Update blocked: stop server first'
            } else {
                Set-UiStatus "Tool exited: $ExitCode"
            }
        }

    Set-UiStatus "$Title running"
}

function Get-CurrentModelInfo {
    $mmprojPath = ''
    if ($script:config.PSObject.Properties.Name -contains 'MmprojPath') {
        $mmprojPath = [string]$script:config.MmprojPath
    }

    Get-LlamaModelInfo -ModelPath ([string]$script:config.ModelPath) -MmprojPath $mmprojPath
}

function Set-ParamUiValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [AllowEmptyString()][string]$Value
    )

    $param = Get-LlamaParam -Config $script:config -Name $Name
    if ($param) {
        $param.Enabled = $Enabled
        if ([string]$param.Type -ne 'switch') {
            $param.Value = $Value
        }
    }

    if ($script:paramControls.ContainsKey($Name)) {
        $controls = $script:paramControls[$Name]
        $controls.EnabledBox.Checked = $Enabled
        if ($controls.ValueBox -and ($controls.ValueBox.Enabled -or ($controls.ValueBox -is [System.Windows.Forms.ComboBox]))) {
            $controls.ValueBox.Text = $Value
        }
    }
}

function Apply-RecommendationToUi {
    param([Parameter(Mandatory = $true)]$Recommendation)

    foreach ($name in $Recommendation.Params.Keys) {
        $item = $Recommendation.Params[$name]
        Set-ParamUiValue -Name $name -Enabled ([bool]$item.Enabled) -Value ([string]$item.Value)
    }

    Save-LocalLlamaConfig -Config $script:config
    [void](Export-LlamaServerCmd -Config $script:config)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'llamacppWindowAutoRun'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1120, 780)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.ColumnCount = 1
$main.RowCount = 4
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 148))) | Out-Null
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 92))) | Out-Null
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 48))) | Out-Null
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 52))) | Out-Null
$form.Controls.Add($main)

$paths = New-Object System.Windows.Forms.TableLayoutPanel
$paths.Dock = 'Fill'
$paths.ColumnCount = 4
$paths.RowCount = 4
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 100))) | Out-Null
$paths.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 220))) | Out-Null
$main.Controls.Add($paths, 0, 0)

$script:modelBox = New-Object System.Windows.Forms.TextBox
$script:modelBox.Dock = 'Fill'
$script:modelBox.Text = [string]$script:config.ModelPath
$script:modelBox.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 2)
$browseModelButton = New-Button 'Browse'
$browseModelButton.Width = 88

$script:mmprojBox = New-Object System.Windows.Forms.TextBox
$script:mmprojBox.Dock = 'Fill'
$script:mmprojBox.Text = if ($script:config.PSObject.Properties.Name -contains 'MmprojPath') { [string]$script:config.MmprojPath } else { '' }
$script:mmprojBox.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 2)
$browseMmprojButton = New-Button 'Browse'
$browseMmprojButton.Width = 88

$script:targetBox = New-Object System.Windows.Forms.TextBox
$script:targetBox.Dock = 'Fill'
$script:targetBox.Text = [string]$script:config.TargetDir
$script:targetBox.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 2)

$script:tmpBox = New-Object System.Windows.Forms.TextBox
$script:tmpBox.Dock = 'Fill'
$script:tmpBox.Text = [string]$script:config.TmpDir
$script:tmpBox.Margin = New-Object System.Windows.Forms.Padding(4, 6, 4, 2)

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Text = 'Ready'
$script:statusLabel.AutoSize = $true
$script:statusLabel.Dock = 'Fill'
$script:statusLabel.Margin = New-Object System.Windows.Forms.Padding(8)

$paths.Controls.Add((New-Label 'Model'), 0, 0)
$paths.Controls.Add($script:modelBox, 1, 0)
$paths.Controls.Add($browseModelButton, 2, 0)
$paths.Controls.Add($script:statusLabel, 3, 0)
$paths.Controls.Add((New-Label 'MMProj'), 0, 1)
$paths.Controls.Add($script:mmprojBox, 1, 1)
$paths.Controls.Add($browseMmprojButton, 2, 1)
$paths.Controls.Add((New-Label 'Target'), 0, 2)
$paths.Controls.Add($script:targetBox, 1, 2)
$paths.SetColumnSpan($script:targetBox, 2)
$paths.Controls.Add((New-Label 'Temp'), 0, 3)
$paths.Controls.Add($script:tmpBox, 1, 3)
$paths.SetColumnSpan($script:tmpBox, 2)

$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = 'Fill'
$buttonPanel.FlowDirection = 'LeftToRight'
$buttonPanel.WrapContents = $true
$buttonPanel.Padding = New-Object System.Windows.Forms.Padding(4)
$main.Controls.Add($buttonPanel, 0, 1)

$hardwareButton = New-Button 'Hardware'
$modelButton = New-Button 'Model Info'
$autoTuneButton = New-Button 'Auto Tune'
$helpButton = New-Button 'Param Help'
$checkButton = New-Button 'Check Update'
$updateButton = New-Button 'Install/Update'
$startButton = New-Button 'Start Server'
$stopButton = New-Button 'Stop Server'
$saveButton = New-Button 'Save'
$cmdButton = New-Button 'Generate CMD'
$clearConsoleButton = New-Button 'Clear Console'

@($hardwareButton, $modelButton, $autoTuneButton, $helpButton, $checkButton, $updateButton, $startButton, $stopButton, $saveButton, $cmdButton, $clearConsoleButton) | ForEach-Object {
    $buttonPanel.Controls.Add($_)
}

$paramPanel = New-Object System.Windows.Forms.Panel
$paramPanel.Dock = 'Fill'
$paramPanel.AutoScroll = $true
$main.Controls.Add($paramPanel, 0, 2)

$paramGrid = New-Object System.Windows.Forms.TableLayoutPanel
$paramGrid.Dock = 'Top'
$paramGrid.AutoSize = $true
$paramGrid.ColumnCount = 4
$paramGrid.RowCount = @($script:config.Params).Count
$paramGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 42))) | Out-Null
$paramGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 170))) | Out-Null
$paramGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$paramGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 86))) | Out-Null
$paramPanel.Controls.Add($paramGrid)

$row = 0
foreach ($param in @($script:config.Params)) {
    $enabled = New-Object System.Windows.Forms.CheckBox
    $enabled.Checked = [bool]$param.Enabled
    $enabled.Margin = New-Object System.Windows.Forms.Padding(12, 7, 4, 2)

    $name = New-Label ([string]$param.Name)

    $value = New-Object System.Windows.Forms.TextBox
    $value.Dock = 'Fill'
    $value.Text = [string]$param.Value
    $value.Enabled = ([string]$param.Type -ne 'switch')
    $value.Margin = New-Object System.Windows.Forms.Padding(4, 5, 4, 2)

    if ($param.Name -in @('--cache-type-k', '--cache-type-v')) {
        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Dock = 'Fill'
        $combo.DropDownStyle = 'DropDown'
        [void]$combo.Items.AddRange(@('q4_0', 'q4_1', 'q5_0', 'q5_1', 'q8_0', 'f16'))
        $combo.Text = [string]$param.Value
        $combo.Margin = New-Object System.Windows.Forms.Padding(4, 5, 4, 2)
        $value = $combo
    }

    if ($param.Name -eq '--flash-attn') {
        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Dock = 'Fill'
        $combo.DropDownStyle = 'DropDownList'
        [void]$combo.Items.AddRange(@('on', 'off', 'auto'))
        $combo.Text = [string]$param.Value
        $combo.Margin = New-Object System.Windows.Forms.Padding(4, 5, 4, 2)
        $value = $combo
    }

    $kind = New-Label ([string]$param.Type)

    $paramGrid.Controls.Add($enabled, 0, $row)
    $paramGrid.Controls.Add($name, 1, $row)
    $paramGrid.Controls.Add($value, 2, $row)
    $paramGrid.Controls.Add($kind, 3, $row)

    $script:paramControls[[string]$param.Name] = [pscustomobject]@{
        EnabledBox = $enabled
        ValueBox   = $value
    }

    $row += 1
}

$script:console = New-Object System.Windows.Forms.RichTextBox
$script:console.Dock = 'Fill'
$script:console.ReadOnly = $true
$script:console.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
$script:console.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
$script:console.Font = New-Object System.Drawing.Font('Consolas', 10)
$script:console.WordWrap = $false
$main.Controls.Add($script:console, 0, 3)
Append-Console ("GUI log: $script:latestLogFile" + [Environment]::NewLine)

$script:processTimer = New-Object System.Windows.Forms.Timer
$script:processTimer.Interval = 500
$script:processTimer.Add_Tick({
    try {
        Drain-ProcessLogs
    } catch {
        $script:processTimer.Stop()
        Show-GuiError -Context 'Read process logs' -ErrorRecord $_
    }
})
$script:processTimer.Start()

$hardwareButton.Add_Click({
    Invoke-GuiAction 'Analyze hardware' {
    $script:console.Clear()
    $hardware = Get-LlamaHardwareInfo
    Append-Console (Format-LlamaHardwareReport -Hardware $hardware)
    Set-UiStatus 'Hardware analyzed'
    }
})

$modelButton.Add_Click({
    Invoke-GuiAction 'Analyze model' {
    Collect-ConfigFromUi
    $script:console.Clear()
    $model = Get-CurrentModelInfo
    Append-Console (Format-LlamaModelReport -Model $model)
    Set-UiStatus 'Model analyzed'
    }
})

$autoTuneButton.Add_Click({
    Invoke-GuiAction 'Auto tune balanced' {
    Collect-ConfigFromUi
    $script:console.Clear()
    $hardware = Get-LlamaHardwareInfo
    $model = Get-CurrentModelInfo
    Append-Console (Format-LlamaHardwareReport -Hardware $hardware)
    Append-Console (Format-LlamaModelReport -Model $model)
    if (-not $model.ModelPath) {
        Append-Console "Auto Tune skipped: select a model first." + [Environment]::NewLine
        Set-UiStatus 'Model path required'
        return
    }
    if (-not $model.ModelExists) {
        Append-Console "Auto Tune skipped: model file was not found." + [Environment]::NewLine
        Set-UiStatus 'Model not found'
        return
    }
    $recommendation = Get-LlamaAutoTuneRecommendation -Hardware $hardware -Model $model -Profile 'Balanced'
    Apply-RecommendationToUi -Recommendation $recommendation
    Append-Console (Format-LlamaRecommendationReport -Recommendation $recommendation)
    Append-Console "Applied Balanced recommendation and saved local config." + [Environment]::NewLine
    Set-UiStatus 'Auto tune applied'
    }
})

$helpButton.Add_Click({
    Invoke-GuiAction 'Parameter help' {
    $script:console.Clear()
    Append-Console (Format-LlamaParameterHelp)
    Set-UiStatus 'Parameter help'
    }
})

$browseModelButton.Add_Click({
    Invoke-GuiAction 'Browse model' {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'GGUF models (*.gguf)|*.gguf|All files (*.*)|*.*'
    $dialog.Title = 'Select model'
    if ($script:modelBox.Text -and (Test-Path -LiteralPath (Split-Path $script:modelBox.Text -Parent))) {
        $dialog.InitialDirectory = Split-Path $script:modelBox.Text -Parent
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:modelBox.Text = $dialog.FileName
    }
    }
})

$browseMmprojButton.Add_Click({
    Invoke-GuiAction 'Browse MMProj' {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'MMProj files (*.gguf)|*.gguf|All files (*.*)|*.*'
    $dialog.Title = 'Select MMProj'
    if ($script:mmprojBox.Text -and (Test-Path -LiteralPath (Split-Path $script:mmprojBox.Text -Parent))) {
        $dialog.InitialDirectory = Split-Path $script:mmprojBox.Text -Parent
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:mmprojBox.Text = $dialog.FileName
    }
    }
})

$checkButton.Add_Click({
    Invoke-GuiAction 'Check update' {
    Start-ToolCommand -Arguments @('-CheckOnly') -Title 'Check update'
    }
})

$updateButton.Add_Click({
    Invoke-GuiAction 'Install update' {
    Start-ToolCommand -Arguments @() -Title 'Install update'
    }
})

$saveButton.Add_Click({
    Invoke-GuiAction 'Save config' {
    Collect-ConfigFromUi
    Set-UiStatus 'Saved'
    Append-Console ("Saved config and generated Start-LlamaServer.generated.cmd" + [Environment]::NewLine)
    }
})

$cmdButton.Add_Click({
    Invoke-GuiAction 'Generate CMD' {
    Collect-ConfigFromUi
    $generated = Export-LlamaServerCmd -Config $script:config
    Set-UiStatus 'CMD generated'
    Append-Console ("Generated: $generated" + [Environment]::NewLine)
    }
})

$clearConsoleButton.Add_Click({
    Invoke-GuiAction 'Clear console' {
    $script:console.Clear()
    }
})

$startButton.Add_Click({
    Invoke-GuiAction 'Start server' {
    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        Append-Console "[server already running]" + [Environment]::NewLine
        return
    }

    Collect-ConfigFromUi
    if ([string]::IsNullOrWhiteSpace([string]$script:config.ModelPath)) {
        Append-Console "Select a GGUF model before starting the server." + [Environment]::NewLine
        Set-UiStatus 'Model path required'
        return
    }

    $modelPath = Resolve-LocalPath -Path ([string]$script:config.ModelPath)
    if (-not (Test-Path -LiteralPath $modelPath)) {
        Append-Console ("Model file not found: $modelPath" + [Environment]::NewLine)
        Set-UiStatus 'Model not found'
        return
    }

    if (($script:config.PSObject.Properties.Name -contains 'MmprojPath') -and -not [string]::IsNullOrWhiteSpace([string]$script:config.MmprojPath)) {
        $mmprojPath = Resolve-LocalPath -Path ([string]$script:config.MmprojPath)
        if (-not (Test-Path -LiteralPath $mmprojPath)) {
            Append-Console ("MMProj file not found: $mmprojPath" + [Environment]::NewLine)
            Set-UiStatus 'MMProj not found'
            return
        }
    }

    $targetDir = Resolve-LocalPath -Path $script:config.TargetDir
    $exe = Join-Path $targetDir 'llama-server.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Append-Console "llama-server.exe not found: $exe" + [Environment]::NewLine
        Append-Console "Run Install/Update first." + [Environment]::NewLine
        Set-UiStatus 'Server not installed'
        return
    }

    $args = Get-LlamaServerArguments -Config $script:config
    Append-Console ("Starting: " + ((@($exe) + $args | ForEach-Object { ConvertTo-WindowsQuotedArgument -Argument $_ }) -join ' ') + [Environment]::NewLine)

    $script:serverProcess = Start-ManagedProcess `
        -FileName $exe `
        -Arguments $args `
        -WorkingDirectory $targetDir `
        -Name 'server' `
        -OnExit {
            param($ExitCode)
            Set-UiStatus "Server exited: $ExitCode"
        }

    Set-UiStatus 'Server running'
    }
})

$stopButton.Add_Click({
    Invoke-GuiAction 'Stop server' {
    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        Append-Console "[stopping server]" + [Environment]::NewLine
        $script:serverProcess.Kill()
        Set-UiStatus 'Stopping server'
        return
    }

    Set-UiStatus 'Server not running'
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:processTimer) {
        $script:processTimer.Stop()
    }

    if ($script:serverProcess -and -not $script:serverProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show($form, 'Stop running llama-server.exe?', 'Server running', 'YesNo', 'Question')
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:serverProcess.Kill()
        } else {
            $eventArgs.Cancel = $true
        }
    }
})

[void]$form.ShowDialog()
