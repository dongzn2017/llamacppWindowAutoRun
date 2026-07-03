param(
    [switch]$PrintCommand
)

Set-StrictMode -Version 2.0
. "$PSScriptRoot\scripts\LlamaCppTools.ps1"

$config = Read-LocalLlamaConfig
$config.TargetDir = Resolve-LocalPath -Path $config.TargetDir
$exe = Join-Path $config.TargetDir 'llama-server.exe'
$arguments = Get-LlamaServerArguments -Config $config

if ($PrintCommand) {
    Write-Host ((@($exe) + $arguments | ForEach-Object { ConvertTo-WindowsQuotedArgument -Argument $_ }) -join ' ')
    exit 0
}

if ([string]::IsNullOrWhiteSpace([string]$config.ModelPath)) {
    Write-Error "ModelPath is empty. Select a GGUF model in the GUI or set ModelPath in conf\config.json."
    exit 1
}

$modelPath = Resolve-LocalPath -Path ([string]$config.ModelPath)
if (-not (Test-Path -LiteralPath $modelPath)) {
    Write-Error "Model file not found: $modelPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Error "llama-server.exe not found: $exe. Run Update-LlamaCpp.cmd first."
    exit 1
}

Set-Location -LiteralPath $config.TargetDir
& $exe @arguments
exit $LASTEXITCODE
