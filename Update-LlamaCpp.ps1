param(
    [switch]$CheckOnly,
    [switch]$Force,
    [switch]$ShowConfig
)

Set-StrictMode -Version 2.0
. "$PSScriptRoot\scripts\LlamaCppTools.ps1"

try {
    $config = Read-LocalLlamaConfig

    if ($ShowConfig) {
        $config | ConvertTo-Json -Depth 8
        exit 0
    }

    $result = Update-LlamaCppInstallation -CheckOnly:$CheckOnly -Force:$Force -LogCallback {
        param([string]$Message)
        Write-Host $Message
    }

    if (-not $CheckOnly) {
        $config = Read-LocalLlamaConfig
        $generated = Export-LlamaServerCmd -Config $config
        Write-Host "Generated launcher: $generated"
    }

    if ($result) {
        if (($result.PSObject.Properties.Name -contains 'UpdateBlocked') -and $result.UpdateBlocked) {
            exit 2
        }
        exit 0
    }

    exit 1
} catch {
    Write-Error $_
    exit 1
}
