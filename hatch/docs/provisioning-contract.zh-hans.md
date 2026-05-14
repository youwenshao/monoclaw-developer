# Hatch 配置部署合约

> **译本信息**
> **原文：** `hatch/docs/provisioning-contract.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

Hatch 负责让一台恢复出厂设置的 Mac 准备好为非技术办公室职员运行 MonoClaw。

## 由 Hatch 管理

- MonoClaw 运行时安装。
- 可选的本地推理就绪检查，以及当 sidecar 存在于配置介质上时，可选的 Gemma 4 E4B 模型包部署。
- Agent skills、工具和默认工作区引导。
- 技术员交接至 `monoclaw setup` 以处理密钥、消息和客户专属配置。
- 最终化 plist 发布后，MonoClaw 管理进程的 launchd 服务生命周期。
- 针对重复基准测试，清理现有 MonoClaw 和旧版运行时网关。
- 技术员可读的就绪检查。

## 手动或半手动前置条件

- Xcode Command Line Tools 可能触发 macOS GUI 提示。
- 当 `brew` 缺失时，Homebrew 安装会使用官方互联网安装器，除非为离线基准测试明确跳过。Homebrew 并非核心运行时 Python 提供者；预备好的安装包必须包含 Python 3.11+。
- LM Studio 是需要手动从官方 `.dmg` 安装并首次启动的任务，仅在需要本地推理时才需要。
- Docker Desktop 可能需要 GUI 安装、首次启动和权限授权。
- macOS 隐私权限可能需要「系统设置」交互。

Hatch 必须检测这些状态并准确告诉技术员该做什么。它不应假设仅限 GUI 的步骤总能从终端解决。

## 管理路径

- 运行时主目录：`~/.monoclaw`
- Vendor 管理文件：`~/.monoclaw/vendor`
- 运行时 venv：`~/.monoclaw/vendor/runtime/venv`
- 命令转发器：`~/.local/bin/monoclaw`
- 客户保留文件：`~/.monoclaw/customer`
- 日志与诊断：`~/.monoclaw/logs`
- 未来本地模型缓存：`~/.monoclaw/vendor/model-cache`

## 预置包合约

Hatch 从一个经清单验证的预置包安装。详细的构件布局、清单字段、目标 Mac 前置条件和验证检查记载于 `docs/runtime-artifacts.md`。

目标 Mac 应该接收已捆绑的运行时构件，而不是依赖 Homebrew、源代码检出或网络下载来进行核心 MonoClaw 安装。组装机在创建预置包时可以使用这些工具。对于 `local-office` Python 依赖，`vendor/wheelhouse` 是必需的；网络解析仅在明确选择的诊断回退标志后方可使用。组装操作员应在 wheelhouse 缺失或过期时，于 `./build.sh` 之前执行 `bash scripts/build_wheelhouse.sh`。可选模型包是经清单验证的 sidecar，不属于核心运行时清单的一部分。

Hatch 负责确定性安装。设置向导负责技术员和客户的选择。成功的安装应该以清晰的交接结尾：

```bash
monoclaw --version
monoclaw setup
```

## 安全默认值

- 对每个生命周期命令，试运行（dry-run）是默认模式；真正的主机变更需要明确的 `--apply`。
- 在替换运行时文件前，必须先停止现有服务。
- 必须保留现有的 `~/.monoclaw/.env`、`~/.monoclaw/config.yaml`、`~/.monoclaw/customer` 和技术员自建的 skills。
- 密钥、客户数据、配置日志、模型权重和 vendor 安装包绝对不能提交到 `monoclaw-developer`。
