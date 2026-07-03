Set-StrictMode -Version 2.0

function Get-LocalLlamaRoot {
    if ((Split-Path -Leaf $PSScriptRoot) -ieq 'scripts') {
        return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    return (Resolve-Path $PSScriptRoot).Path
}

function New-LocalLlamaDefaultConfig {
    [ordered]@{
        ReleaseApiUrl = 'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest'
        ReleasesUrl   = 'https://github.com/ggml-org/llama.cpp/releases'
        TargetDir     = 'llamacpp'
        TmpDir        = 'tmp'
        VersionDir    = 'versions'
        LogPath       = 'install.log'
        System        = 'Windows'
        CudaMajor     = '13'
        CudaDlls      = '13.3'
        ModelPath     = ''
        Params        = @(
            [ordered]@{ Name = '--host';           Enabled = $true;  Value = '127.0.0.1'; Type = 'value'  },
            [ordered]@{ Name = '--port';           Enabled = $true;  Value = '8080';      Type = 'value'  },
            [ordered]@{ Name = '--n-cpu-moe';      Enabled = $true;  Value = '26';        Type = 'value'  },
            [ordered]@{ Name = '--n-gpu-layers';   Enabled = $true;  Value = '22';        Type = 'value'  },
            [ordered]@{ Name = '--no-mmap';        Enabled = $true;  Value = '';          Type = 'switch' },
            [ordered]@{ Name = '--cache-ram';      Enabled = $true;  Value = '0';         Type = 'value'  },
            [ordered]@{ Name = '--ctx-size';       Enabled = $true;  Value = '16384';     Type = 'value'  },
            [ordered]@{ Name = '--batch-size';     Enabled = $true;  Value = '256';       Type = 'value'  },
            [ordered]@{ Name = '--ubatch-size';    Enabled = $true;  Value = '256';       Type = 'value'  },
            [ordered]@{ Name = '--cache-type-k';   Enabled = $true;  Value = 'q4_0';      Type = 'value'  },
            [ordered]@{ Name = '--cache-type-v';   Enabled = $true;  Value = 'q5_0';      Type = 'value'  },
            [ordered]@{ Name = '--flash-attn';     Enabled = $true;  Value = 'on';        Type = 'value'  },
            [ordered]@{ Name = '--jinja';          Enabled = $true;  Value = '';          Type = 'switch' },
            [ordered]@{ Name = '--temp';           Enabled = $true;  Value = '0.1';       Type = 'value'  },
            [ordered]@{ Name = '--top-p';          Enabled = $true;  Value = '0.95';      Type = 'value'  },
            [ordered]@{ Name = '--top-k';          Enabled = $true;  Value = '20';        Type = 'value'  },
            [ordered]@{ Name = '--min-p';          Enabled = $true;  Value = '0.0';       Type = 'value'  },
            [ordered]@{ Name = '--repeat-penalty'; Enabled = $true;  Value = '1.1';       Type = 'value'  },
            [ordered]@{ Name = '--parallel';       Enabled = $true;  Value = '1';         Type = 'value'  },
            [ordered]@{ Name = '--threads';        Enabled = $true;  Value = '6';         Type = 'value'  }
        )
    }
}

function Get-LocalLlamaConfigPath {
    Join-Path (Join-Path (Get-LocalLlamaRoot) 'conf') 'config.json'
}

function Get-LocalLlamaUserConfigPath {
    Join-Path (Join-Path (Get-LocalLlamaRoot) 'conf') 'user.config.json'
}

function Get-LocalLlamaLegacyConfigPath {
    Join-Path (Get-LocalLlamaRoot) 'config.json'
}

function Read-LocalLlamaConfig {
    $defaults = New-LocalLlamaDefaultConfig
    $path = Get-LocalLlamaConfigPath
    $userPath = Get-LocalLlamaUserConfigPath
    $legacyPath = Get-LocalLlamaLegacyConfigPath
    $loadedPrimaryConfig = $false

    if (Test-Path -LiteralPath $path) {
        $loaded = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $defaults[$prop.Name] = $prop.Value
        }
        $loadedPrimaryConfig = $true
    }

    if (Test-Path -LiteralPath $userPath) {
        $loaded = Get-Content -LiteralPath $userPath -Raw | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $defaults[$prop.Name] = $prop.Value
        }
        $loadedPrimaryConfig = $true
    }

    if ((-not $loadedPrimaryConfig) -and (Test-Path -LiteralPath $legacyPath)) {
        $loaded = Get-Content -LiteralPath $legacyPath -Raw | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $defaults[$prop.Name] = $prop.Value
        }
    }

    foreach ($name in @('TargetDir', 'TmpDir', 'VersionDir', 'LogPath')) {
        if (-not $defaults[$name]) {
            $defaults[$name] = (New-LocalLlamaDefaultConfig)[$name]
        }
    }

    return [pscustomobject]$defaults
}

function Save-LocalLlamaConfig {
    param(
        [Parameter(Mandatory = $true)] $Config
    )

    $path = Get-LocalLlamaUserConfigPath
    Ensure-Directory -Path (Split-Path -Parent $path)
    $Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-LocalLlamaRoot) $Path))
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\')
    $parentPrefix = $parentFull + '\'

    if (($full -ine $parentFull) -and (-not $full.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to modify path outside allowed parent. Path=$full Parent=$parentFull"
    }
}

function Clear-DirectorySafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedParent
    )

    Ensure-Directory -Path $Path
    Assert-PathInside -Path $Path -Parent $AllowedParent

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\')
    if (($full -ieq $root) -or ($full.Length -lt 6)) {
        throw "Refusing to clear unsafe directory: $full"
    }

    Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Write-ProgressLine {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [scriptblock]$LogCallback
    )

    if ($LogCallback) {
        & $LogCallback $Message
    } else {
        Write-Host $Message
    }
}

function Get-LlamaCppLatestRelease {
    param([Parameter(Mandatory = $true)]$Config)

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'llamacppWindowAutoRun-Updater' }
    Invoke-RestMethod -Uri $Config.ReleaseApiUrl -Headers $headers
}

function Find-LlamaCppCudaAssets {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)]$Config
    )

    $assets = @($Release.assets)
    $cudaMajor = [regex]::Escape([string]$Config.CudaMajor)
    $preferredDlls = [string]$Config.CudaDlls
    $preferredRegex = [regex]::Escape($preferredDlls)

    $core = $assets | Where-Object { $_.name -match "^llama-(b\d+)-bin-win-cuda-$preferredRegex-x64\.zip$" } | Select-Object -First 1
    $dlls = $assets | Where-Object { $_.name -match "^cudart-llama-bin-win-cuda-$preferredRegex-x64\.zip$" } | Select-Object -First 1
    $selectedDllVersion = $preferredDlls
    $selectionNote = $null

    if (-not ($core -and $dlls)) {
        $pairs = @()
        foreach ($asset in $assets) {
            if ($asset.name -match "^llama-(b\d+)-bin-win-cuda-($cudaMajor(?:\.\d+)+)-x64\.zip$") {
                $candidateVersion = $Matches[2]
                $dllCandidate = $assets | Where-Object { $_.name -eq "cudart-llama-bin-win-cuda-$candidateVersion-x64.zip" } | Select-Object -First 1
                if ($dllCandidate) {
                    $pairs += [pscustomobject]@{
                        Core       = $asset
                        Dlls       = $dllCandidate
                        CudaDlls   = $candidateVersion
                        SortKey    = [version]$candidateVersion
                    }
                }
            }
        }

        $best = $pairs | Sort-Object SortKey -Descending | Select-Object -First 1
        if ($best) {
            $core = $best.Core
            $dlls = $best.Dlls
            $selectedDllVersion = $best.CudaDlls
            $selectionNote = "Preferred CUDA DLLs $preferredDlls were not found. Selected CUDA DLLs $selectedDllVersion."
        }
    }

    if (-not ($core -and $dlls)) {
        throw "Could not find matching Windows x64 CUDA $($Config.CudaMajor) llama.cpp assets in latest release $($Release.tag_name)."
    }

    $version = [string]$Release.tag_name
    if ($core.name -match '^llama-(b\d+)-') {
        $version = $Matches[1]
    }

    [pscustomobject]@{
        Version       = $version
        CudaMajor     = [string]$Config.CudaMajor
        CudaDlls      = $selectedDllVersion
        CoreAsset     = $core
        DllAsset      = $dlls
        Note          = $selectionNote
        ReleaseUrl    = [string]$Release.html_url
        PublishedAt   = [string]$Release.published_at
    }
}

function Convert-AssetDigest {
    param($Asset)

    if ($Asset.PSObject.Properties.Name -contains 'digest') {
        return [string]$Asset.digest
    }

    return ''
}

function Read-LlamaInstallInfo {
    param([Parameter(Mandatory = $true)]$Config)

    $infoPath = Join-Path $Config.TargetDir 'install.info'
    if (-not (Test-Path -LiteralPath $infoPath)) {
        return $null
    }

    $map = @{}
    foreach ($line in (Get-Content -LiteralPath $infoPath)) {
        if ($line -match '^\s*([^=]+)=(.*)$') {
            $map[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    [pscustomobject]$map
}

function Test-LlamaInstallCurrent {
    param(
        [AllowNull()]$Info,
        [Parameter(Mandatory = $true)]$Selection
    )

    if (-not $Info) {
        return $false
    }

    $checks = @{
        version       = $Selection.Version
        CUDA          = $Selection.CudaMajor
        CUDADlls      = $Selection.CudaDlls
        coreAsset     = $Selection.CoreAsset.name
        dllAsset      = $Selection.DllAsset.name
        coreUpdatedAt = [string]$Selection.CoreAsset.updated_at
        dllUpdatedAt  = [string]$Selection.DllAsset.updated_at
        coreSize      = [string]$Selection.CoreAsset.size
        dllSize       = [string]$Selection.DllAsset.size
    }

    foreach ($key in $checks.Keys) {
        $value = ''
        if ($Info.PSObject.Properties.Name -contains $key) {
            $value = [string]$Info.$key
        }

        if ($value -ne [string]$checks[$key]) {
            return $false
        }
    }

    return $true
}

function Get-LlamaInstallInfoValue {
    param(
        [AllowNull()]$Info,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ''
    )

    if (($null -ne $Info) -and ($Info.PSObject.Properties.Name -contains $Name)) {
        return [string]$Info.$Name
    }

    return $Default
}

function Save-LlamaAsset {
    param(
        [Parameter(Mandatory = $true)]$Asset,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [scriptblock]$LogCallback
    )

    if (Test-Path -LiteralPath $OutputPath) {
        $existing = Get-Item -LiteralPath $OutputPath
        if ($existing.Length -eq [int64]$Asset.size) {
            Write-ProgressLine -Message "Using cached $($Asset.name)" -LogCallback $LogCallback
            return
        }
    }

    Write-ProgressLine -Message "Downloading $($Asset.name)" -LogCallback $LogCallback
    $headers = @{ 'User-Agent' = 'llamacppWindowAutoRun-Updater' }
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $OutputPath -Headers $headers
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Ensure-Directory -Path $Destination
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Expand-LlamaCppPayload {
    param(
        [Parameter(Mandatory = $true)][string]$CoreZip,
        [Parameter(Mandatory = $true)][string]$DllZip,
        [Parameter(Mandatory = $true)][string]$StageDir,
        [scriptblock]$LogCallback
    )

    $coreDir = Join-Path $StageDir 'core'
    $dllDir = Join-Path $StageDir 'dlls'
    $payloadDir = Join-Path $StageDir 'payload'

    Clear-DirectorySafe -Path $coreDir -AllowedParent $StageDir
    Clear-DirectorySafe -Path $dllDir -AllowedParent $StageDir
    Clear-DirectorySafe -Path $payloadDir -AllowedParent $StageDir

    Write-ProgressLine -Message "Extracting llama.cpp package" -LogCallback $LogCallback
    Expand-Archive -LiteralPath $CoreZip -DestinationPath $coreDir -Force

    $server = Get-ChildItem -LiteralPath $coreDir -Recurse -Filter 'llama-server.exe' | Select-Object -First 1
    if (-not $server) {
        throw "llama-server.exe was not found after extracting $CoreZip."
    }

    Copy-DirectoryContents -Source $server.Directory.FullName -Destination $payloadDir

    Write-ProgressLine -Message "Extracting CUDA runtime DLL package" -LogCallback $LogCallback
    Expand-Archive -LiteralPath $DllZip -DestinationPath $dllDir -Force
    Copy-DirectoryContents -Source $dllDir -Destination $payloadDir

    $finalServer = Join-Path $payloadDir 'llama-server.exe'
    if (-not (Test-Path -LiteralPath $finalServer)) {
        throw "Normalized payload does not contain llama-server.exe."
    }

    return $payloadDir
}

function Write-LlamaInstallInfo {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Selection
    )

    Ensure-Directory -Path $Config.VersionDir

    $installedAt = (Get-Date).ToString('o')
    $lines = @(
        "version=$($Selection.Version)",
        "system=$($Config.System)",
        "CUDA=$($Selection.CudaMajor)",
        "CUDADlls=$($Selection.CudaDlls)",
        "coreAsset=$($Selection.CoreAsset.name)",
        "dllAsset=$($Selection.DllAsset.name)",
        "coreSize=$($Selection.CoreAsset.size)",
        "dllSize=$($Selection.DllAsset.size)",
        "coreUpdatedAt=$($Selection.CoreAsset.updated_at)",
        "dllUpdatedAt=$($Selection.DllAsset.updated_at)",
        "coreDigest=$(Convert-AssetDigest -Asset $Selection.CoreAsset)",
        "dllDigest=$(Convert-AssetDigest -Asset $Selection.DllAsset)",
        "releaseUrl=$($Selection.ReleaseUrl)",
        "publishedAt=$($Selection.PublishedAt)",
        "installedAt=$installedAt"
    )

    $targetInfo = Join-Path $Config.TargetDir 'install.info'
    $versionInfo = Join-Path $Config.VersionDir "$($Selection.Version)-cuda$($Selection.CudaDlls).info"
    $lines | Set-Content -LiteralPath $targetInfo -Encoding ASCII
    $lines | Set-Content -LiteralPath $versionInfo -Encoding ASCII

    $summary = "$installedAt version=$($Selection.Version) system=$($Config.System) CUDA=$($Selection.CudaMajor) CUDADlls=$($Selection.CudaDlls) coreAsset=$($Selection.CoreAsset.name) dllAsset=$($Selection.DllAsset.name)"
    Add-Content -LiteralPath $Config.LogPath -Value $summary -Encoding UTF8
}

function Test-LlamaServerRunningFromTarget {
    param([Parameter(Mandatory = $true)]$Config)

    $target = [System.IO.Path]::GetFullPath($Config.TargetDir).TrimEnd('\') + '\'
    try {
        $processes = Get-CimInstance Win32_Process -Filter "name = 'llama-server.exe'"
    } catch {
        return $false
    }

    foreach ($process in $processes) {
        if ($process.ExecutablePath -and $process.ExecutablePath.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Update-LlamaCppInstallation {
    param(
        [switch]$CheckOnly,
        [switch]$Force,
        [scriptblock]$LogCallback
    )

    $config = Read-LocalLlamaConfig
    $config.TargetDir = Resolve-LocalPath -Path $config.TargetDir
    $config.TmpDir = Resolve-LocalPath -Path $config.TmpDir
    $config.VersionDir = Resolve-LocalPath -Path $config.VersionDir
    $config.LogPath = Resolve-LocalPath -Path $config.LogPath

    Ensure-Directory -Path $config.TargetDir
    Ensure-Directory -Path $config.TmpDir
    Ensure-Directory -Path $config.VersionDir

    Write-ProgressLine -Message "Checking $($config.ReleaseApiUrl)" -LogCallback $LogCallback
    $release = Get-LlamaCppLatestRelease -Config $config
    $selection = Find-LlamaCppCudaAssets -Release $release -Config $config

    Write-ProgressLine -Message "Latest release: $($selection.Version)" -LogCallback $LogCallback
    Write-ProgressLine -Message "Core: $($selection.CoreAsset.name)" -LogCallback $LogCallback
    Write-ProgressLine -Message "CUDA DLLs: $($selection.DllAsset.name)" -LogCallback $LogCallback
    if ($selection.Note) {
        Write-ProgressLine -Message $selection.Note -LogCallback $LogCallback
    }

    $current = Read-LlamaInstallInfo -Config $config
    $isCurrent = Test-LlamaInstallCurrent -Info $current -Selection $selection
    $installedVersion = Get-LlamaInstallInfoValue -Info $current -Name 'version' -Default 'none'
    $installedDlls = Get-LlamaInstallInfoValue -Info $current -Name 'CUDADlls' -Default 'none'

    Write-ProgressLine -Message "Installed: $installedVersion CUDA DLLs $installedDlls" -LogCallback $LogCallback

    if ($CheckOnly) {
        if ($isCurrent) {
            Write-ProgressLine -Message "Status: already current" -LogCallback $LogCallback
        } else {
            Write-ProgressLine -Message "Status: update available ($installedVersion -> $($selection.Version))" -LogCallback $LogCallback
        }
        return $selection
    }

    if ($isCurrent -and (-not $Force)) {
        Write-ProgressLine -Message "Already installed: $($selection.Version) CUDA DLLs $($selection.CudaDlls)" -LogCallback $LogCallback
        return $selection
    }

    if (Test-LlamaServerRunningFromTarget -Config $config) {
        Write-ProgressLine -Message "Update blocked: llama-server.exe is running from $($config.TargetDir)." -LogCallback $LogCallback
        Write-ProgressLine -Message "Stop Server first, then run Install/Update again." -LogCallback $LogCallback
        $selection | Add-Member -NotePropertyName UpdateBlocked -NotePropertyValue $true -Force
        return $selection
    }

    $versionTmp = Join-Path $config.TmpDir "$($selection.Version)-cuda$($selection.CudaDlls)"
    Ensure-Directory -Path $versionTmp
    Assert-PathInside -Path $versionTmp -Parent $config.TmpDir

    $coreZip = Join-Path $versionTmp $selection.CoreAsset.name
    $dllZip = Join-Path $versionTmp $selection.DllAsset.name
    Save-LlamaAsset -Asset $selection.CoreAsset -OutputPath $coreZip -LogCallback $LogCallback
    Save-LlamaAsset -Asset $selection.DllAsset -OutputPath $dllZip -LogCallback $LogCallback

    $stageDir = Join-Path $versionTmp 'stage'
    Ensure-Directory -Path $stageDir
    Assert-PathInside -Path $stageDir -Parent $versionTmp
    $payloadDir = Expand-LlamaCppPayload -CoreZip $coreZip -DllZip $dllZip -StageDir $stageDir -LogCallback $LogCallback

    Write-ProgressLine -Message "Replacing target folder $($config.TargetDir)" -LogCallback $LogCallback
    $targetParent = Split-Path -Parent $config.TargetDir
    if (-not $targetParent) {
        throw "Target directory has no parent: $($config.TargetDir)"
    }
    Clear-DirectorySafe -Path $config.TargetDir -AllowedParent $targetParent
    Copy-DirectoryContents -Source $payloadDir -Destination $config.TargetDir

    Write-LlamaInstallInfo -Config $config -Selection $selection
    Write-ProgressLine -Message "Installed $($selection.Version) to $($config.TargetDir)" -LogCallback $LogCallback

    return $selection
}

function Get-LlamaServerArguments {
    param([Parameter(Mandatory = $true)]$Config)

    $args = New-Object System.Collections.Generic.List[string]
    if ($Config.ModelPath) {
        $modelPath = Resolve-LocalPath -Path ([string]$Config.ModelPath)
        $args.Add('-m')
        $args.Add($modelPath)
    }

    foreach ($param in @($Config.Params)) {
        if (-not [bool]$param.Enabled) {
            continue
        }

        $name = [string]$param.Name
        $type = [string]$param.Type
        $value = [string]$param.Value
        if (-not $name) {
            continue
        }

        $args.Add($name)
        if ($type -ne 'switch') {
            $args.Add($value)
        }
    }

    return [string[]]$args.ToArray()
}

function ConvertTo-WindowsQuotedArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($Argument -eq '') {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $result = '"'
    $backslashes = 0
    foreach ($char in $Argument.ToCharArray()) {
        if ($char -eq '\') {
            $backslashes += 1
            continue
        }

        if ($char -eq '"') {
            $result += ('\' * (($backslashes * 2) + 1))
            $result += '"'
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            $result += ('\' * $backslashes)
            $backslashes = 0
        }
        $result += $char
    }

    if ($backslashes -gt 0) {
        $result += ('\' * ($backslashes * 2))
    }

    $result += '"'
    return $result
}

function ConvertTo-WindowsArgumentString {
    param([string[]]$Arguments)

    (($Arguments | ForEach-Object { ConvertTo-WindowsQuotedArgument -Argument $_ }) -join ' ')
}

function Set-ProcessStartInfoArguments {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [string[]]$Arguments
    )

    $argumentListProperty = $StartInfo.GetType().GetProperty('ArgumentList')
    if ($argumentListProperty) {
        foreach ($arg in $Arguments) {
            [void]$StartInfo.ArgumentList.Add($arg)
        }
        return
    }

    $StartInfo.Arguments = ConvertTo-WindowsArgumentString -Arguments $Arguments
}

function ConvertTo-CmdQuotedArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($Argument -eq '') {
        return '""'
    }

    if ($Argument -notmatch '[\s&()^|<>%"]') {
        return $Argument
    }

    '"' + ($Argument -replace '"', '\"') + '"'
}

function Export-LlamaServerCmd {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$OutputPath = (Join-Path (Get-LocalLlamaRoot) 'Start-LlamaServer.generated.cmd')
    )

    $root = Get-LocalLlamaRoot
    $targetDir = Resolve-LocalPath -Path $Config.TargetDir
    $defaultTarget = [System.IO.Path]::GetFullPath((Join-Path $root 'llamacpp')).TrimEnd('\')

    if ($targetDir.TrimEnd('\') -ieq $defaultTarget) {
        $exeForCmd = '%~dp0llamacpp\llama-server.exe'
    } else {
        $exeForCmd = Join-Path $targetDir 'llama-server.exe'
    }

    $args = Get-LlamaServerArguments -Config $Config
    $parts = @((ConvertTo-CmdQuotedArgument -Argument $exeForCmd))
    foreach ($arg in $args) {
        $parts += (ConvertTo-CmdQuotedArgument -Argument $arg)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('setlocal')
    $lines.Add('if not exist "' + $exeForCmd + '" (')
    $lines.Add('  echo llama-server.exe not found: ' + $exeForCmd)
    $lines.Add('  echo Run Update-LlamaCpp.cmd first.')
    $lines.Add('  exit /b 1')
    $lines.Add(')')

    for ($i = 0; $i -lt $parts.Count; $i += 1) {
        $prefix = if ($i -eq 0) { '' } else { '  ' }
        if ($i -lt ($parts.Count - 1)) {
            $lines.Add($prefix + $parts[$i] + ' ^')
        } else {
            $lines.Add($prefix + $parts[$i])
        }
    }

    $lines | Set-Content -LiteralPath $OutputPath -Encoding ASCII
    return $OutputPath
}
