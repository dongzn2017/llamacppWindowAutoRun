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
        MmprojPath    = ''
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

function ConvertTo-SizeGb {
    param([double]$Bytes)

    if ($Bytes -le 0) {
        return 0
    }

    [math]::Round(($Bytes / 1GB), 2)
}

function Get-NvidiaSmiPath {
    $cmd = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $defaultPath = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    if (Test-Path -LiteralPath $defaultPath) {
        return $defaultPath
    }

    return $null
}

function Get-LlamaHardwareInfo {
    $logicalThreads = [Environment]::ProcessorCount
    $cpuName = 'unknown'
    $totalRamBytes = 0
    $freeRamBytes = 0

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Name) {
            $cpuName = [string]$cpu.Name
        }
    } catch {
    }

    if ($cpuName -eq 'unknown') {
        try {
            $cpuReg = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop
            if ($cpuReg.ProcessorNameString) {
                $cpuName = [string]$cpuReg.ProcessorNameString
            }
        } catch {
        }
    }

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        $totalRamBytes = [double]$computerInfo.TotalPhysicalMemory
        $freeRamBytes = [double]$computerInfo.AvailablePhysicalMemory
    } catch {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $totalRamBytes = [double]$os.TotalVisibleMemorySize * 1KB
            $freeRamBytes = [double]$os.FreePhysicalMemory * 1KB
        } catch {
        }
    }

    $gpus = @()
    $nvidiaSmi = Get-NvidiaSmiPath
    if ($nvidiaSmi) {
        try {
            $lines = & $nvidiaSmi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader,nounits 2>$null
            foreach ($line in @($lines)) {
                $parts = @($line -split ',\s*')
                if ($parts.Count -ge 4) {
                    $gpus += [pscustomobject]@{
                        Name          = [string]$parts[0]
                        TotalVramMb   = [int]$parts[1]
                        FreeVramMb    = [int]$parts[2]
                        DriverVersion = [string]$parts[3]
                    }
                }
            }
        } catch {
        }
    }

    [pscustomobject]@{
        CpuName        = $cpuName
        LogicalThreads = $logicalThreads
        TotalRamGb     = ConvertTo-SizeGb -Bytes $totalRamBytes
        FreeRamGb      = ConvertTo-SizeGb -Bytes $freeRamBytes
        NvidiaSmiPath  = $nvidiaSmi
        Gpus           = $gpus
    }
}

function Read-GgufString {
    param([Parameter(Mandatory = $true)][System.IO.BinaryReader]$Reader)

    $length = [uint64]$Reader.ReadUInt64()
    if ($length -eq 0) {
        return ''
    }

    if ($length -gt 1048576) {
        throw "GGUF string is too large to read: $length bytes"
    }

    $bytes = $Reader.ReadBytes([int]$length)
    [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Skip-GgufBytes {
    param(
        [Parameter(Mandatory = $true)][System.IO.BinaryReader]$Reader,
        [Parameter(Mandatory = $true)][uint64]$Count
    )

    if ($Count -eq 0) {
        return
    }

    if ($Reader.BaseStream.CanSeek) {
        [void]$Reader.BaseStream.Seek([int64]$Count, [System.IO.SeekOrigin]::Current)
    } else {
        [void]$Reader.ReadBytes([int]$Count)
    }
}

function Get-GgufScalarSize {
    param([uint32]$Type)

    switch ($Type) {
        0 { return 1 }
        1 { return 1 }
        2 { return 2 }
        3 { return 2 }
        4 { return 4 }
        5 { return 4 }
        6 { return 4 }
        7 { return 1 }
        10 { return 8 }
        11 { return 8 }
        12 { return 8 }
        default { return 0 }
    }
}

function Read-GgufScalarValue {
    param(
        [Parameter(Mandatory = $true)][System.IO.BinaryReader]$Reader,
        [Parameter(Mandatory = $true)][uint32]$Type
    )

    switch ($Type) {
        0 { return $Reader.ReadByte() }
        1 { return $Reader.ReadSByte() }
        2 { return $Reader.ReadUInt16() }
        3 { return $Reader.ReadInt16() }
        4 { return $Reader.ReadUInt32() }
        5 { return $Reader.ReadInt32() }
        6 { return $Reader.ReadSingle() }
        7 { return $Reader.ReadBoolean() }
        8 { return Read-GgufString -Reader $Reader }
        10 { return $Reader.ReadUInt64() }
        11 { return $Reader.ReadInt64() }
        12 { return $Reader.ReadDouble() }
        default { return $null }
    }
}

function Skip-GgufValue {
    param(
        [Parameter(Mandatory = $true)][System.IO.BinaryReader]$Reader,
        [Parameter(Mandatory = $true)][uint32]$Type
    )

    if ($Type -eq 8) {
        $length = [uint64]$Reader.ReadUInt64()
        Skip-GgufBytes -Reader $Reader -Count $length
        return
    }

    if ($Type -eq 9) {
        $arrayType = [uint32]$Reader.ReadUInt32()
        $arrayLength = [uint64]$Reader.ReadUInt64()
        if ($arrayType -eq 8) {
            for ($i = [uint64]0; $i -lt $arrayLength; $i += 1) {
                $length = [uint64]$Reader.ReadUInt64()
                Skip-GgufBytes -Reader $Reader -Count $length
            }
            return
        }

        $scalarSize = Get-GgufScalarSize -Type $arrayType
        if ($scalarSize -gt 0) {
            Skip-GgufBytes -Reader $Reader -Count ([uint64]($scalarSize * $arrayLength))
            return
        }

        throw "Unsupported GGUF array type: $arrayType"
    }

    $size = Get-GgufScalarSize -Type $Type
    if ($size -gt 0) {
        Skip-GgufBytes -Reader $Reader -Count ([uint64]$size)
        return
    }

    throw "Unsupported GGUF value type: $Type"
}

function Get-GgufFileTypeName {
    param([AllowNull()]$FileType)

    if ($null -eq $FileType) {
        return ''
    }

    $map = @{
        0 = 'F32'; 1 = 'F16'; 2 = 'Q4_0'; 3 = 'Q4_1'; 6 = 'Q5_0'; 7 = 'Q5_1'; 8 = 'Q8_0'
        10 = 'Q2_K'; 11 = 'Q3_K_S'; 12 = 'Q3_K_M'; 13 = 'Q3_K_L'; 14 = 'Q4_K_S'; 15 = 'Q4_K_M'
        16 = 'Q5_K_S'; 17 = 'Q5_K_M'; 18 = 'Q6_K'; 19 = 'IQ2_XXS'; 20 = 'IQ2_XS'; 21 = 'Q2_K_S'
        22 = 'IQ3_XS'; 23 = 'IQ3_XXS'; 24 = 'IQ1_S'; 25 = 'IQ4_NL'; 26 = 'IQ3_S'; 27 = 'IQ3_M'
        28 = 'IQ2_S'; 29 = 'IQ2_M'; 30 = 'IQ4_XS'; 31 = 'IQ1_M'; 32 = 'BF16'; 33 = 'Q4_0_4_4'
        34 = 'Q4_0_4_8'; 35 = 'Q4_0_8_8'; 36 = 'TQ1_0'; 37 = 'TQ2_0'
    }

    $key = [int]$FileType
    if ($map.ContainsKey($key)) {
        return $map[$key]
    }

    return "file_type_$key"
}

function Read-GgufMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $metadata = @{}
    $stream = $null
    $reader = $null

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.BinaryReader($stream, [System.Text.Encoding]::UTF8)
        $magic = $reader.ReadUInt32()
        if ($magic -ne 0x46554747) {
            return [pscustomobject]@{ IsGguf = $false; Metadata = @{}; Error = 'Not a GGUF file' }
        }

        $version = $reader.ReadUInt32()
        $tensorCount = $reader.ReadUInt64()
        $metadataCount = $reader.ReadUInt64()
        $maxItems = [math]::Min([uint64]512, $metadataCount)

        for ($i = [uint64]0; $i -lt $maxItems; $i += 1) {
            if ($stream.Position -gt 16777216) {
                break
            }

            $key = Read-GgufString -Reader $reader
            $type = [uint32]$reader.ReadUInt32()

            if (($key -like 'tokenizer.*') -and $metadata.ContainsKey('general.architecture')) {
                break
            }

            if ($type -eq 9) {
                Skip-GgufValue -Reader $reader -Type $type
                continue
            }

            $value = Read-GgufScalarValue -Reader $reader -Type $type
            $metadata[$key] = $value
        }

        [pscustomobject]@{
            IsGguf        = $true
            Version       = $version
            TensorCount   = $tensorCount
            MetadataCount = $metadataCount
            Metadata      = $metadata
            Error         = ''
        }
    } catch {
        [pscustomobject]@{ IsGguf = $false; Metadata = $metadata; Error = $_.Exception.Message }
    } finally {
        if ($reader) {
            $reader.Close()
        } elseif ($stream) {
            $stream.Close()
        }
    }
}

function Get-ModelQuantFromName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -match '(?i)(IQ[0-9]_[A-Z0-9_]+|TQ[0-9]_[A-Z0-9_]+|Q[0-9]_[A-Z0-9_]+|F16|BF16|F32)') {
        return $Matches[1].ToUpperInvariant()
    }

    return ''
}

function Get-LlamaModelInfo {
    param(
        [string]$ModelPath,
        [string]$MmprojPath
    )

    $resolvedModel = ''
    $exists = $false
    $sizeGb = 0
    $fileName = ''
    $metadata = $null
    $architecture = ''
    $quant = ''
    $blockCount = $null
    $contextLength = $null
    $isLikelyMoe = $false
    $isLikelyVision = $false

    if (-not [string]::IsNullOrWhiteSpace($ModelPath)) {
        $resolvedModel = Resolve-LocalPath -Path $ModelPath
        $exists = Test-Path -LiteralPath $resolvedModel
        $fileName = Split-Path -Leaf $resolvedModel
        $quant = Get-ModelQuantFromName -Name $fileName
        $isLikelyMoe = ($fileName -match '(?i)(moe|mixtral|a\d+b|deepseek|experts)')
        $isLikelyVision = ($fileName -match '(?i)(vision|vl|llava|minicpmv|gemma-?3|qwen2vl|qwen2\.5vl)')

        if ($exists) {
            $item = Get-Item -LiteralPath $resolvedModel
            $sizeGb = ConvertTo-SizeGb -Bytes $item.Length
            $metadata = Read-GgufMetadata -Path $resolvedModel
            if ($metadata.IsGguf) {
                $map = $metadata.Metadata
                if ($map.ContainsKey('general.architecture')) {
                    $architecture = [string]$map['general.architecture']
                }
                if ($map.ContainsKey('general.file_type')) {
                    $metadataQuant = Get-GgufFileTypeName -FileType $map['general.file_type']
                    if ($metadataQuant) {
                        $quant = $metadataQuant
                    }
                }

                if ($architecture -and $map.ContainsKey("$architecture.block_count")) {
                    $blockCount = [int]$map["$architecture.block_count"]
                }
                if ($architecture -and $map.ContainsKey("$architecture.context_length")) {
                    $contextLength = [int]$map["$architecture.context_length"]
                }
            }
        }
    }

    $resolvedMmproj = ''
    $mmprojExists = $false
    if (-not [string]::IsNullOrWhiteSpace($MmprojPath)) {
        $resolvedMmproj = Resolve-LocalPath -Path $MmprojPath
        $mmprojExists = Test-Path -LiteralPath $resolvedMmproj
        $isLikelyVision = $true
    }

    [pscustomobject]@{
        ModelPath       = $resolvedModel
        ModelExists     = $exists
        FileName        = $fileName
        SizeGb          = $sizeGb
        Quantization    = $quant
        Architecture    = $architecture
        BlockCount      = $blockCount
        ContextLength   = $contextLength
        IsLikelyMoe     = $isLikelyMoe
        IsLikelyVision  = $isLikelyVision
        MmprojPath      = $resolvedMmproj
        MmprojExists    = $mmprojExists
        MetadataError   = if ($metadata) { $metadata.Error } else { '' }
    }
}

function Get-LlamaParam {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($param in @($Config.Params)) {
        if ([string]$param.Name -eq $Name) {
            return $param
        }
    }

    return $null
}

function Get-PrimaryGpuInfo {
    param($Hardware)

    $gpus = @($Hardware.Gpus)
    if ($gpus.Count -eq 0) {
        return $null
    }

    $gpus | Sort-Object FreeVramMb -Descending | Select-Object -First 1
}

function Get-LlamaAutoTuneRecommendation {
    param(
        [Parameter(Mandatory = $true)]$Hardware,
        [Parameter(Mandatory = $true)]$Model,
        [string]$Profile = 'Balanced'
    )

    $gpu = Get-PrimaryGpuInfo -Hardware $Hardware
    $threads = [Math]::Max(1, [int]$Hardware.LogicalThreads)
    $recommendedThreads = if ($threads -le 4) { [Math]::Max(1, $threads - 1) } else { [Math]::Min(16, [Math]::Max(2, $threads - 2)) }
    $freeVramGb = if ($gpu) { [math]::Round($gpu.FreeVramMb / 1024, 2) } else { 0 }
    $totalVramGb = if ($gpu) { [math]::Round($gpu.TotalVramMb / 1024, 2) } else { 0 }
    $modelGb = [double]$Model.SizeGb
    $usableVramGb = [math]::Max(0, ($freeVramGb - 1.5) * 0.88)
    $blockCount = if ($Model.BlockCount) { [int]$Model.BlockCount } else { 0 }

    $gpuLayers = 0
    if ($gpu -and $modelGb -gt 0) {
        if ($modelGb -le $usableVramGb) {
            $gpuLayers = 999
        } elseif ($blockCount -gt 0) {
            $gpuLayers = [math]::Max(0, [math]::Min($blockCount, [math]::Floor($blockCount * ($usableVramGb / $modelGb))))
        } elseif ($usableVramGb -gt 0) {
            $gpuLayers = [math]::Max(0, [math]::Floor(80 * ($usableVramGb / $modelGb)))
        }
    }

    $ctx = 8192
    if (($totalVramGb -ge 16) -and ($Hardware.TotalRamGb -ge 32)) { $ctx = 16384 }
    if (($totalVramGb -ge 24) -and ($Hardware.TotalRamGb -ge 64)) { $ctx = 32768 }
    if ($Model.ContextLength -and $Model.ContextLength -lt $ctx) { $ctx = [int]$Model.ContextLength }

    $batch = 128
    $ubatch = 64
    if ($totalVramGb -ge 12) { $batch = 256; $ubatch = 128 }
    if ($totalVramGb -ge 24) { $batch = 512; $ubatch = 256 }

    $noMmapEnabled = ($Hardware.FreeRamGb -gt ($modelGb * 1.4 + 8))
    $nCpuMoeEnabled = [bool]$Model.IsLikelyMoe
    $nCpuMoe = if ($nCpuMoeEnabled) { [math]::Max(0, [math]::Floor($recommendedThreads / 2)) } else { 0 }

    $speedHint = 'Unknown. Run a short benchmark for a real number.'
    if ($gpu -and $modelGb -gt 0) {
        $name = [string]$gpu.Name
        $tier = 60
        if ($name -match '(?i)5090|4090') { $tier = 180 }
        elseif ($name -match '(?i)5080|4080|3090') { $tier = 125 }
        elseif ($name -match '(?i)5070|4070|3080') { $tier = 85 }
        elseif ($name -match '(?i)5060|4060|3070') { $tier = 55 }
        elseif ($name -match '(?i)3060|2070|2060') { $tier = 35 }
        $center = [math]::Max(1, [math]::Round($tier / [math]::Max(1.5, $modelGb), 1))
        $low = [math]::Max(1, [math]::Round($center * 0.55, 1))
        $high = [math]::Round($center * 1.45, 1)
        $speedHint = "$low-$high tok/s rough decode estimate. Benchmark to calibrate."
    }

    [pscustomobject]@{
        Profile        = $Profile
        GpuName        = if ($gpu) { $gpu.Name } else { 'none' }
        FreeVramGb     = $freeVramGb
        ModelSizeGb    = $modelGb
        SpeedHint      = $speedHint
        Params         = [ordered]@{
            '--threads'        = @{ Enabled = $true; Value = [string]$recommendedThreads }
            '--n-gpu-layers'   = @{ Enabled = ($gpuLayers -gt 0); Value = [string]$gpuLayers }
            '--ctx-size'       = @{ Enabled = $true; Value = [string]$ctx }
            '--batch-size'     = @{ Enabled = $true; Value = [string]$batch }
            '--ubatch-size'    = @{ Enabled = $true; Value = [string]$ubatch }
            '--cache-type-k'   = @{ Enabled = $true; Value = 'q4_0' }
            '--cache-type-v'   = @{ Enabled = $true; Value = 'q5_0' }
            '--flash-attn'     = @{ Enabled = $true; Value = 'on' }
            '--no-mmap'        = @{ Enabled = $noMmapEnabled; Value = '' }
            '--cache-ram'      = @{ Enabled = $true; Value = '0' }
            '--parallel'       = @{ Enabled = $true; Value = '1' }
            '--n-cpu-moe'      = @{ Enabled = $nCpuMoeEnabled; Value = [string]$nCpuMoe }
        }
        Notes          = @(
            'Balanced profile favors stable startup over maximum possible VRAM usage.',
            'Token/s is a rough estimate based on GPU name and model size, not a benchmark.',
            'Increase n-gpu-layers when VRAM remains free; decrease it if loading fails or Windows becomes unstable.',
            'For vision models, select the matching MMProj file manually.'
        )
    }
}

function Format-LlamaHardwareReport {
    param([Parameter(Mandatory = $true)]$Hardware)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Hardware')
    $lines.Add("CPU: $($Hardware.CpuName)")
    $lines.Add("Logical threads: $($Hardware.LogicalThreads)")
    $lines.Add("RAM: $($Hardware.FreeRamGb) GB free / $($Hardware.TotalRamGb) GB total")
    if (@($Hardware.Gpus).Count -eq 0) {
        $lines.Add('GPU: NVIDIA GPU not detected by nvidia-smi')
    } else {
        foreach ($gpu in @($Hardware.Gpus)) {
            $lines.Add("GPU: $($gpu.Name), VRAM $([math]::Round($gpu.FreeVramMb / 1024, 2)) GB free / $([math]::Round($gpu.TotalVramMb / 1024, 2)) GB total, driver $($gpu.DriverVersion)")
        }
    }
    $lines.Add('')
    $lines -join [Environment]::NewLine
}

function Format-LlamaModelReport {
    param([Parameter(Mandatory = $true)]$Model)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Model')
    if (-not $Model.ModelPath) {
        $lines.Add('Model path: not set')
    } else {
        $lines.Add("Model path: $($Model.ModelPath)")
        $lines.Add("Exists: $($Model.ModelExists)")
        $lines.Add("Size: $($Model.SizeGb) GB")
        $lines.Add("Architecture: $(if ($Model.Architecture) { $Model.Architecture } else { 'unknown' })")
        $lines.Add("Quantization: $(if ($Model.Quantization) { $Model.Quantization } else { 'unknown' })")
        $lines.Add("Block count: $(if ($Model.BlockCount) { $Model.BlockCount } else { 'unknown' })")
        $lines.Add("Native context: $(if ($Model.ContextLength) { $Model.ContextLength } else { 'unknown' })")
        $lines.Add("Likely MoE: $($Model.IsLikelyMoe)")
        $lines.Add("Likely vision: $($Model.IsLikelyVision)")
    }

    if ($Model.MmprojPath) {
        $lines.Add("MMProj path: $($Model.MmprojPath)")
        $lines.Add("MMProj exists: $($Model.MmprojExists)")
    } else {
        $lines.Add('MMProj path: not set')
    }

    if ($Model.MetadataError) {
        $lines.Add("Metadata note: $($Model.MetadataError)")
    }

    $lines.Add('')
    $lines -join [Environment]::NewLine
}

function Format-LlamaRecommendationReport {
    param([Parameter(Mandatory = $true)]$Recommendation)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Auto Tune: $($Recommendation.Profile)")
    $lines.Add("Primary GPU: $($Recommendation.GpuName)")
    $lines.Add("Free VRAM: $($Recommendation.FreeVramGb) GB")
    $lines.Add("Model size: $($Recommendation.ModelSizeGb) GB")
    $lines.Add("Speed: $($Recommendation.SpeedHint)")
    $lines.Add('Recommended params:')
    foreach ($key in $Recommendation.Params.Keys) {
        $item = $Recommendation.Params[$key]
        $valueText = if ($item.Value -ne '') { " $($item.Value)" } else { '' }
        $state = if ($item.Enabled) { 'on' } else { 'off' }
        $lines.Add("  $key$valueText [$state]")
    }
    foreach ($note in @($Recommendation.Notes)) {
        $lines.Add("Note: $note")
    }
    $lines.Add('')
    $lines -join [Environment]::NewLine
}

function Get-LlamaBenchPath {
    param([Parameter(Mandatory = $true)]$Config)

    $targetDir = Resolve-LocalPath -Path ([string]$Config.TargetDir)
    Join-Path $targetDir 'llama-bench.exe'
}

function Join-UniqueCsv {
    param([object[]]$Values)

    (@($Values) | Where-Object { $null -ne $_ -and [string]$_ -ne '' } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ','
}

function New-LlamaBenchmarkArguments {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Hardware,
        [Parameter(Mandatory = $true)]$Model
    )

    $recommendation = Get-LlamaAutoTuneRecommendation -Hardware $Hardware -Model $Model -Profile 'Balanced'
    $params = $recommendation.Params
    $modelPath = Resolve-LocalPath -Path ([string]$Config.ModelPath)
    $threads = [int]$params['--threads'].Value
    $batch = [int]$params['--batch-size'].Value
    $ubatch = [int]$params['--ubatch-size'].Value
    $ngl = if ($params['--n-gpu-layers'].Enabled) { [int]$params['--n-gpu-layers'].Value } else { 0 }
    $blockCount = if ($Model.BlockCount) { [int]$Model.BlockCount } else { 0 }

    $nglCandidates = @()
    if ($ngl -ge 999) {
        $nglCandidates += 999
        if ($blockCount -gt 8) {
            $nglCandidates += [math]::Max(0, $blockCount - 4)
        }
    } else {
        $nglCandidates += [math]::Max(0, $ngl)
        $nglCandidates += [math]::Max(0, $ngl - 8)
        if ($blockCount -gt 0) {
            $nglCandidates += [math]::Min($blockCount, $ngl + 8)
        } else {
            $nglCandidates += [math]::Max(0, $ngl + 8)
        }
    }

    $batchCandidates = @($batch)
    if ($batch -gt 128) { $batchCandidates += [math]::Max(64, [int]($batch / 2)) }
    if ($batch -lt 512) { $batchCandidates += [math]::Min(512, $batch * 2) }

    $ubatchCandidates = @($ubatch)
    if ($ubatch -gt 64) { $ubatchCandidates += [math]::Max(32, [int]($ubatch / 2)) }

    $maxThreads = [Math]::Max(1, [int]$Hardware.LogicalThreads)
    $threadCandidates = @($threads)
    if ($threads -gt 4) { $threadCandidates += [math]::Max(1, $threads - 2) }
    if ($threads -lt $maxThreads) { $threadCandidates += [math]::Min($maxThreads, $threads + 2) }

    $mmap = if ($params['--no-mmap'].Enabled) { '0' } else { '1' }
    $nCpuMoe = if ($params['--n-cpu-moe'].Enabled) { [string]$params['--n-cpu-moe'].Value } else { '0' }

    $args = @(
        '-m', $modelPath,
        '-o', 'json',
        '-r', '1',
        '-p', '256',
        '-n', '64',
        '-t', (Join-UniqueCsv -Values $threadCandidates),
        '-ngl', (Join-UniqueCsv -Values $nglCandidates),
        '-b', (Join-UniqueCsv -Values $batchCandidates),
        '-ub', (Join-UniqueCsv -Values $ubatchCandidates),
        '-ctk', [string]$params['--cache-type-k'].Value,
        '-ctv', [string]$params['--cache-type-v'].Value,
        '-fa', [string]$params['--flash-attn'].Value,
        '-mmp', $mmap,
        '-ncmoe', $nCpuMoe
    )

    [pscustomobject]@{
        Arguments      = [string[]]$args
        Recommendation = $recommendation
        CandidateText  = "ngl=$(Join-UniqueCsv -Values $nglCandidates), batch=$(Join-UniqueCsv -Values $batchCandidates), ubatch=$(Join-UniqueCsv -Values $ubatchCandidates), threads=$(Join-UniqueCsv -Values $threadCandidates)"
    }
}

function Get-PropertyValueByName {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }

    return $null
}

function Get-BenchmarkScore {
    param([Parameter(Mandatory = $true)]$Row)

    foreach ($name in @('tg_avg', 'avg_ts', 'tokens_per_second', 'tok_s', 'generation_tokens_per_second')) {
        if ($Row.PSObject.Properties.Name -contains $name) {
            $value = $Row.$name
            if ($value -is [ValueType]) {
                return [double]$value
            }
        }
    }

    foreach ($prop in $Row.PSObject.Properties) {
        if (($prop.Name -match '(?i)(tg|gen|token).*?(s|sec|ts|avg)') -and ($prop.Value -is [ValueType])) {
            return [double]$prop.Value
        }
    }

    return $null
}

function Get-JsonPayloadFromText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    $arrayMatch = [regex]::Match($Text, '(?s)\[\s*\{.*\}\s*\]')
    if ($arrayMatch.Success) {
        return $arrayMatch.Value
    }

    $objectMatch = [regex]::Match($Text, '(?s)\{\s*".*"\s*:.*\}')
    if ($objectMatch.Success) {
        return $objectMatch.Value
    }

    $arrayStart = $Text.IndexOf('[')
    $arrayEnd = $Text.LastIndexOf(']')
    if (($arrayStart -ge 0) -and ($arrayEnd -gt $arrayStart)) {
        return $Text.Substring($arrayStart, $arrayEnd - $arrayStart + 1)
    }

    $objectStart = $Text.IndexOf('{')
    $objectEnd = $Text.LastIndexOf('}')
    if (($objectStart -ge 0) -and ($objectEnd -gt $objectStart)) {
        return $Text.Substring($objectStart, $objectEnd - $objectStart + 1)
    }

    return ''
}

function ConvertFrom-LlamaBenchmarkOutput {
    param([AllowEmptyString()][string]$Text)

    $json = Get-JsonPayloadFromText -Text $Text
    if (-not $json) {
        return [pscustomobject]@{ Parsed = $false; Error = 'No JSON payload found in llama-bench output.'; Rows = @(); Best = $null }
    }

    try {
        $parsed = $json | ConvertFrom-Json
        $rows = @($parsed)
        $best = $null
        $bestScore = -1.0
        foreach ($row in $rows) {
            $score = Get-BenchmarkScore -Row $row
            if (($null -ne $score) -and ($score -gt $bestScore)) {
                $best = $row
                $bestScore = $score
            }
        }

        [pscustomobject]@{
            Parsed    = ($null -ne $best)
            Error     = if ($null -ne $best) { '' } else { 'JSON parsed, but no token/s score field was recognized.' }
            Rows      = $rows
            Best      = $best
            BestScore = if ($null -ne $best) { $bestScore } else { $null }
        }
    } catch {
        [pscustomobject]@{ Parsed = $false; Error = $_.Exception.Message; Rows = @(); Best = $null }
    }
}

function Convert-LlamaBenchmarkBestToParams {
    param([Parameter(Mandatory = $true)]$Best)

    $result = [ordered]@{}
    $ngl = Get-PropertyValueByName -Object $Best -Names @('n_gpu_layers', 'ngl')
    $batch = Get-PropertyValueByName -Object $Best -Names @('n_batch', 'batch_size', 'batch')
    $ubatch = Get-PropertyValueByName -Object $Best -Names @('n_ubatch', 'ubatch_size', 'ubatch')
    $threads = Get-PropertyValueByName -Object $Best -Names @('n_threads', 'threads')
    $ctk = Get-PropertyValueByName -Object $Best -Names @('type_k', 'cache_type_k', 'cache-type-k')
    $ctv = Get-PropertyValueByName -Object $Best -Names @('type_v', 'cache_type_v', 'cache-type-v')
    $fa = Get-PropertyValueByName -Object $Best -Names @('flash_attn', 'flash-attn', 'fa')
    $ncmoe = Get-PropertyValueByName -Object $Best -Names @('n_cpu_moe', 'n-cpu-moe', 'ncmoe')
    $mmap = Get-PropertyValueByName -Object $Best -Names @('mmap', 'mmap_enabled')

    if ($null -ne $ngl) { $result['--n-gpu-layers'] = @{ Enabled = ([int]$ngl -gt 0); Value = [string]$ngl } }
    if ($null -ne $batch) { $result['--batch-size'] = @{ Enabled = $true; Value = [string]$batch } }
    if ($null -ne $ubatch) { $result['--ubatch-size'] = @{ Enabled = $true; Value = [string]$ubatch } }
    if ($null -ne $threads) { $result['--threads'] = @{ Enabled = $true; Value = [string]$threads } }
    if ($null -ne $ctk) { $result['--cache-type-k'] = @{ Enabled = $true; Value = [string]$ctk } }
    if ($null -ne $ctv) { $result['--cache-type-v'] = @{ Enabled = $true; Value = [string]$ctv } }
    if ($null -ne $fa) { $result['--flash-attn'] = @{ Enabled = $true; Value = [string]$fa } }
    if ($null -ne $ncmoe) { $result['--n-cpu-moe'] = @{ Enabled = ([int]$ncmoe -gt 0); Value = [string]$ncmoe } }
    if ($null -ne $mmap) {
        $mmapBool = ([string]$mmap -eq '1') -or ([string]$mmap -match '(?i)^true$')
        $result['--no-mmap'] = @{ Enabled = (-not $mmapBool); Value = '' }
    }

    [pscustomobject]@{ Params = $result }
}

function Format-LlamaParameterHelp {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Parameter help')
    $lines.Add('')
    $lines.Add('--n-gpu-layers')
    $lines.Add('  What: number of transformer layers placed on GPU.')
    $lines.Add('  More: usually faster decode/prompt processing, higher VRAM use.')
    $lines.Add('  Less: safer when loading fails, Windows becomes laggy, or VRAM is nearly full.')
    $lines.Add('  Tip: 999 means try full offload. If it fails, reduce in steps of 4-8 layers.')
    $lines.Add('')
    $lines.Add('--ctx-size')
    $lines.Add('  What: maximum context window for prompt + history + generated tokens.')
    $lines.Add('  More: longer conversations/documents, but KV cache memory grows roughly linearly.')
    $lines.Add('  Less: lower VRAM/RAM use and often higher throughput.')
    $lines.Add('  Tip: 8192/16384 are practical starts. Use 32768+ only when you need it.')
    $lines.Add('')
    $lines.Add('--batch-size')
    $lines.Add('  What: logical batch size for prompt/prefill processing.')
    $lines.Add('  More: can improve prompt ingestion speed, especially on GPU.')
    $lines.Add('  Risk: too high can spike VRAM and fail during long prompts.')
    $lines.Add('  Tip: try 128/256/512. Benchmark prompt processing, not only generation.')
    $lines.Add('')
    $lines.Add('--ubatch-size')
    $lines.Add('  What: physical micro-batch size used internally.')
    $lines.Add('  More: can improve GPU utilization.')
    $lines.Add('  Less: safer for VRAM fragmentation and stability.')
    $lines.Add('  Tip: if batch-size fails, lower ubatch first: 256 -> 128 -> 64.')
    $lines.Add('')
    $lines.Add('--cache-type-k and --cache-type-v')
    $lines.Add('  What: precision/quantization for KV cache.')
    $lines.Add('  Lower precision: saves VRAM, enables larger ctx-size, may slightly affect quality.')
    $lines.Add('  Higher precision: f16 uses more memory and may be safer for quality-sensitive tasks.')
    $lines.Add('  Tip: q4_0 for K and q5_0 for V is a good memory-saving start.')
    $lines.Add('')
    $lines.Add('--flash-attn')
    $lines.Add('  What: use flash attention kernels when supported.')
    $lines.Add('  On/auto: usually faster and lower memory on modern NVIDIA GPUs.')
    $lines.Add('  Off: use when the model/backend has compatibility errors.')
    $lines.Add('  Tip: auto is safest; on is fine when it is known to work.')
    $lines.Add('')
    $lines.Add('--no-mmap')
    $lines.Add('  What: disable memory-mapped model loading and load into RAM.')
    $lines.Add('  On: can reduce disk paging surprises and be stable when RAM is abundant.')
    $lines.Add('  Off: usually better when RAM is tight; mmap can avoid loading the full file eagerly.')
    $lines.Add('  Tip: turn on only when free RAM is comfortably larger than model size.')
    $lines.Add('')
    $lines.Add('--threads')
    $lines.Add('  What: CPU worker threads.')
    $lines.Add('  More: helps CPU work, but too many threads can slow down from contention.')
    $lines.Add('  Less: leaves room for Windows, browser, and GPU driver work.')
    $lines.Add('  Tip: logical_threads - 2 is a good start; benchmark around that value.')
    $lines.Add('')
    $lines.Add('--n-cpu-moe')
    $lines.Add('  What: MoE-specific setting for expert work kept on CPU.')
    $lines.Add('  Useful: when MoE model does not fit fully in VRAM.')
    $lines.Add('  Risk: too much CPU expert work can reduce token/s.')
    $lines.Add('  Tip: only enable for MoE models; benchmark model-specific values.')
    $lines.Add('')
    $lines.Add('--cache-ram')
    $lines.Add('  What: llama.cpp cache RAM budget/control for supported builds.')
    $lines.Add('  More: can reduce repeated loading/cache pressure in some workflows.')
    $lines.Add('  Risk: reserves host RAM; not a universal speed knob.')
    $lines.Add('  Tip: keep 0 unless you know the model/server build benefits from it.')
    $lines.Add('')
    $lines.Add('--parallel')
    $lines.Add('  What: number of parallel server slots/sequences.')
    $lines.Add('  More: supports more concurrent requests.')
    $lines.Add('  Risk: increases KV cache memory and can reduce single-user speed.')
    $lines.Add('  Tip: keep 1 for local single-user chat.')
    $lines.Add('')
    $lines.Add('--jinja')
    $lines.Add('  What: enables model chat template rendering with Jinja templates.')
    $lines.Add('  On: usually needed for modern chat GGUF models with embedded templates.')
    $lines.Add('  Off: useful when you provide your own prompt formatting.')
    $lines.Add('')
    $lines.Add('--temp, --top-p, --top-k, --min-p, --repeat-penalty')
    $lines.Add('  What: sampling controls. They affect output style, not load speed.')
    $lines.Add('  Lower temp: more deterministic. Higher temp: more varied.')
    $lines.Add('  top-p/top-k/min-p: restrict token choices. repeat-penalty discourages repeated text.')
    $lines.Add('  Tip: tune these for behavior after performance is stable.')
    $lines.Add('')
    $lines.Add('--mmproj')
    $lines.Add('  What: multimodal projector file for vision models.')
    $lines.Add('  Required: for LLaVA/Qwen-VL/MiniCPM-V style models that need image input.')
    $lines.Add('  Risk: mismatched mmproj can load but produce bad vision results or fail.')
    $lines.Add('  Tip: keep mmproj in the same model family/version as the GGUF model.')
    $lines.Add('')
    $lines.Add('Real tuning')
    $lines.Add('  Auto Tune is a static recommendation. Benchmark Tune actually runs llama-bench candidates.')
    $lines.Add('  Trust Benchmark Tune more than the rough token/s estimate.')
    $lines.Add('  It tests small ranges around GPU layers, batch, ubatch, and CPU threads.')
    $lines.Add('  It does not tune ctx-size because this llama-bench build has no server ctx-size option.')
    $lines.Add('')
    $lines -join [Environment]::NewLine
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

    if (($Config.PSObject.Properties.Name -contains 'MmprojPath') -and $Config.MmprojPath) {
        $mmprojPath = Resolve-LocalPath -Path ([string]$Config.MmprojPath)
        $args.Add('--mmproj')
        $args.Add($mmprojPath)
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

function Get-LlamaLauncherModelName {
    param([Parameter(Mandatory = $true)]$Config)

    $modelPath = [string]$Config.ModelPath
    if ([string]::IsNullOrWhiteSpace($modelPath)) {
        return 'default'
    }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($modelPath)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'default'
    }

    $invalidChars = [regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()))
    $name = [regex]::Replace($name, "[$invalidChars]+", '-')
    $name = [regex]::Replace($name, '\s+', '-')
    $name = $name.Trim(' ', '.', '-', '_')

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'default'
    }

    if ($name.Length -gt 96) {
        $name = $name.Substring(0, 96).Trim(' ', '.', '-', '_')
    }

    return $name
}

function Get-LlamaServerGeneratedCmdPath {
    param([Parameter(Mandatory = $true)]$Config)

    $modelName = Get-LlamaLauncherModelName -Config $Config
    Join-Path (Get-LocalLlamaRoot) "Start-LlamaServer.$modelName.generated.cmd"
}

function Export-LlamaServerCmd {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$OutputPath = '',
        [switch]$SkipDefaultAlias
    )

    $root = Get-LocalLlamaRoot
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Get-LlamaServerGeneratedCmdPath -Config $Config
    }

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
    $defaultAliasPath = Join-Path $root 'Start-LlamaServer.generated.cmd'
    if ((-not $SkipDefaultAlias) -and ($OutputPath -ine $defaultAliasPath)) {
        $lines | Set-Content -LiteralPath $defaultAliasPath -Encoding ASCII
    }

    return $OutputPath
}
