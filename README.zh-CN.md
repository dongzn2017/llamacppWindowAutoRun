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
  "ModelPath": ""
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

GUI 也可以生成一个直接启动 `llama-server.exe` 的 `Start-LlamaServer.generated.cmd`。这个生成文件会被 Git 忽略，因为它可能包含本机模型路径。

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
