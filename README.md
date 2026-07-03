# llamacppWindowAutoRun

English | [中文](README.zh-CN.md)

A small Windows GUI and script wrapper for keeping the official `llama.cpp` Windows CUDA build up to date and running `llama-server.exe` with saved parameters.

This project is intentionally lightweight. It does not bundle `llama.cpp`, CUDA DLLs, or model files. It downloads official release assets from the upstream [`ggml-org/llama.cpp` releases page](https://github.com/ggml-org/llama.cpp/releases).

## Features

- Checks the latest upstream `llama.cpp` release through the GitHub releases API.
- Downloads the selected Windows x64 CUDA build into `tmp`.
- Installs into a stable `llamacpp` target folder.
- Writes installed version metadata to `llamacpp/install.info`, `versions/*.info`, and `install.log`.
- Blocks updates while `llama-server.exe` is running from the target folder.
- Provides a WinForms GUI for selecting a model, toggling parameters, checking updates, installing updates, and running the server with a live console.
- Uses only Windows PowerShell and built-in .NET WinForms.

## Requirements

- Windows x64.
- Windows PowerShell 5.1 or newer.
- Internet access to GitHub releases.
- A local `.gguf` model file.
- A CUDA-compatible GPU and driver if you use a CUDA build.

## Configure CUDA And Paths

Edit [conf/config.json](conf/config.json) before first use, or use the GUI and save your local settings. GUI changes are written to `conf/user.config.json`, which is ignored by Git so private model paths are not committed.

Important fields:

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

All paths above are relative to the cloned repository folder unless you set an absolute path.

You must choose the CUDA version yourself:

- `CudaMajor`: the CUDA major release line in the upstream asset name, for example `13`.
- `CudaDlls`: the exact CUDA runtime DLL package version you want, for example `13.3`.

For CUDA 13.3, the updater looks for assets like:

- `llama-*-bin-win-cuda-13.3-x64.zip`
- `cudart-llama-bin-win-cuda-13.3-x64.zip`

If the exact `CudaDlls` version is not found, the script tries to select the newest matching asset for the configured `CudaMajor`.

Set `ModelPath` in the GUI, `conf/user.config.json`, or `conf/config.json`. It can be absolute or relative to the cloned repository folder. Do not commit private model paths or model files.

## Usage

Open the GUI:

```cmd
LlamaGUI.cmd
```

Check for updates without downloading:

```cmd
Check-LlamaCpp-Update.cmd
```

Install or update `llama.cpp`:

```cmd
Update-LlamaCpp.cmd
```

Start `llama-server.exe` with the saved config:

```cmd
Start-LlamaServer.cmd
```

The GUI can also generate a direct `Start-LlamaServer.generated.cmd` launcher. That generated file is ignored by Git because it may contain local model paths.

## Update Behavior

When a newer upstream release or CUDA DLL package is available, the updater:

1. Downloads the required zip files into `tmp`.
2. Extracts and normalizes the payload.
3. Clears the configured `TargetDir`.
4. Copies the new payload into `TargetDir`.
5. Writes install metadata.

If `llama-server.exe` is already running from `TargetDir`, the update is blocked. Stop the server first, then run the update again.

## GitHub Notes

The repository is prepared so runtime files are ignored:

- downloaded binaries in `llamacpp`
- temporary downloads in `tmp`
- logs in `logs`
- install records in `versions` and `install.log`
- model files such as `.gguf`
- generated local launchers

Only commit source scripts, `conf/config.json`, and documentation. Do not commit `conf/user.config.json`.
