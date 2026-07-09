# llamacppWindowAutoRun

[English](README.md) | 中文

这是一个轻量 Windows GUI 和脚本工具，用来自动检查、下载和更新官方 `llama.cpp` Windows CUDA 版本，并用保存好的参数启动 `llama-server.exe`。

项目不会包含 `llama.cpp` 二进制文件、CUDA DLL 或模型文件。更新器会从官方 [`ggml-org/llama.cpp` releases 页面](https://github.com/ggml-org/llama.cpp/releases) 下载 release assets。

## 功能

- 通过 GitHub releases API 检查最新 `llama.cpp` release。
- 把选中的 Windows x64 CUDA 包下载到 `tmp`。
- 安装到固定目标目录 `llamacpp`。
- 写入安装信息到 `llamacpp/install.info`、`versions/*.info` 和 `install.log`。
- 如果 `llama-server.exe` 正在从目标目录运行，会阻止更新，避免清空正在使用的目录。
- 提供 WinForms 图形界面，可以选择模型、开关参数、检查更新、安装更新、启动 server，并在下方 console 查看实时输出。
- 提供硬件分析、模型分析、详细参数说明、Balanced 静态推荐，以及基于 `llama-bench.exe` 的实际 benchmark tune。
- 只依赖 Windows PowerShell 和系统自带 .NET WinForms。

## 要求

- Windows x64。
- Windows PowerShell 5.1 或更新版本。
- 能访问 GitHub releases。
- 本地 `.gguf` 模型文件。
- 如果使用 CUDA build，需要 CUDA 兼容显卡和驱动。

## 配置 CUDA 和路径

首次使用前可以编辑 [conf/config.json](conf/config.json)，也可以在 GUI 里保存本机设置。GUI 的本机修改会写入 `conf/user.config.json`，这个文件会被 Git 忽略，避免把私人模型路径提交上去。

重要字段：

```json
{
  "TargetDir": "llamacpp",
  "TmpDir": "tmp",
  "VersionDir": "versions",
  "LogPath": "install.log",
  "CudaMajor": "13",
  "CudaDlls": "13.3",
  "ModelPath": "",
  "MmprojPath": ""
}
```

上面的路径默认都是相对于 clone 下来的项目文件夹。你也可以改成绝对路径。

CUDA 版本需要你自己填写：

- `CudaMajor`：上游 asset 名称里的 CUDA 主版本，例如 `13`。
- `CudaDlls`：你想使用的 CUDA runtime DLL 包版本，例如 `13.3`。

对于 CUDA 13.3，更新器会优先匹配：

- `llama-*-bin-win-cuda-13.3-x64.zip`
- `cudart-llama-bin-win-cuda-13.3-x64.zip`

如果找不到精确的 `CudaDlls` 版本，脚本会尝试在同一个 `CudaMajor` 下选择最新的可用版本。

`ModelPath` 可以在 GUI 中选择，也可以写在 `conf/user.config.json` 或 `conf/config.json` 里。它可以是绝对路径，也可以是相对于项目 clone 目录的路径。不要把私人模型路径或模型文件提交到 GitHub。

`MmprojPath` 是可选项。只有模型需要 multimodal projector 时才填写。填写后启动器会把它传给 `llama-server.exe`：

```cmd
--mmproj <path-to-mmproj>
```

## 使用

打开 GUI：

```cmd
LlamaGUI.cmd
```

只检查更新，不下载：

```cmd
Check-LlamaCpp-Update.cmd
```

安装或更新 `llama.cpp`：

```cmd
Update-LlamaCpp.cmd
```

按保存的配置启动 `llama-server.exe`：

```cmd
Start-LlamaServer.cmd
```

GUI 也可以生成类似 `Start-LlamaServer.<模型名>.generated.cmd` 的直接启动器，并同步刷新 `Start-LlamaServer.generated.cmd` 作为当前配置别名。生成文件会被 Git 忽略，因为它可能包含本机模型路径。

## 硬件分析、模型分析和 Auto Tune

GUI 里有这些工具按钮：

- `Hardware`：检测 CPU 线程数、系统 RAM，并在可用时通过 `nvidia-smi` 检测 NVIDIA GPU 和 VRAM。
- `Model Info`：读取模型大小、文件名里的量化信息，并尽量读取 GGUF metadata，例如架构、层数、原生 context。
- `Auto Tune`：应用 Balanced 静态推荐参数，包括 `--threads`、`--n-gpu-layers`、`--ctx-size`、batch、ubatch、KV cache、flash attention、mmap、parallel 和 MoE 相关 CPU 设置。
- `Benchmark Tune`：调用 `llama-bench.exe`，用几组候选 GPU layers、batch、ubatch、CPU threads、KV cache、flash attention、mmap 和 MoE 参数实际加载模型测试。测试结束后会尝试解析最佳结果并应用到 GUI。
- `Param Help`：输出更详细的 `llama-server.exe` 参数说明，包括什么时候增加、什么时候降低。

Auto Tune 里的速度预测是粗略估算，不是真实 benchmark。它只根据 GPU 名称和模型大小给一个起点。需要真实加载测试时，用 Benchmark Tune。

优化建议：

- 加载后 VRAM 还有余量时，可以增加 `--n-gpu-layers`。
- 如果加载失败或系统不稳定，降低 `--n-gpu-layers`、`--batch-size` 或 `--ubatch-size`。
- 只有确实需要长上下文时再增加 `--ctx-size`，它会增加 KV cache 内存。
- 现代 NVIDIA GPU 通常保持 `--flash-attn on`，除非它导致报错。
- 只有视觉/多模态模型才填写 `MmprojPath`，并确认 mmproj 和模型家族匹配。
- Benchmark Tune 会花时间，也可能因为某个候选参数爆 VRAM 而失败。看 GUI console 输出，再降低 GPU layers 或 batch。
- Benchmark Tune 不会自动调 `--ctx-size`；当前 `llama-bench.exe` 可以测试 prompt/generation 参数，但没有暴露和 server 相同的 context-size 参数。

## 更新行为

当检测到新的上游 release 或 CUDA DLL 包时，更新器会：

1. 下载需要的 zip 文件到 `tmp`。
2. 解压并整理 payload。
3. 清空配置里的 `TargetDir`。
4. 把新版复制到 `TargetDir`。
5. 写入安装信息。

如果 `llama-server.exe` 正在从 `TargetDir` 运行，更新会被阻止。先停止 server，再重新运行更新。

## GitHub 注意事项

仓库已经配置 `.gitignore`，会忽略运行时文件：

- `llamacpp` 里的下载二进制文件
- `tmp` 里的下载缓存
- `logs` 里的日志
- `versions` 和 `install.log` 里的安装记录
- `.gguf` 等模型文件
- 本机生成的启动器

只提交脚本源码、`conf/config.json` 和文档。不要提交 `conf/user.config.json`。
