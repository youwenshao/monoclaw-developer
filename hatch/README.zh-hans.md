# Hatch

> **译本信息**
> **原文：** `hatch/README.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

Hatch 是 MonoClaw 配置安装器，用于技术员操作的 Mac 设置。它专为全新的恢复出厂设置 Mac mini 和 iMac 设计，同时也支持在 CI 或测试机上通过检测并停止现有运行时来进行快速重复测试。

Hatch 有两个面向操作员的标准流程：`./build.sh` 在组装机上创建预置包，而生成的 `dist/install.sh` 则从配置介质在目标 Mac 上安装该包。

## 命令

```bash
# 组装机，从 /Users/admin/Projects/hatch。
bash scripts/build_wheelhouse.sh
./build.sh

# 目标 Mac，从随身碟上复制的 dist/ 目录。
# 将 dist/ 和（构建时的）tool-packs/ 复制到介质上的同一父目录 —— 见下文。
./install.sh
```

底层生命周期命令仍然可用于诊断：

```bash
bash bin/hatch --dry-run preflight
bash bin/hatch --dry-run cleanup-existing
bash bin/hatch --dry-run install
```

Hatch 默认为试运行（dry-run）。仅在打算用于配置的机器上才传入 `--apply`。

## 运行时构件合约

Hatch 以安装包为优先。目标 Mac 安装路径定义于 `docs/runtime-artifacts.md`：组装机创建预备的 `dist/` 包，Hatch 验证 `hatch-manifest.json`，客户 Mac 在 `~/.monoclaw/vendor` 接收托管文件，同时保留 `~/.monoclaw/customer`。Hatch 还会创建托管的运行时 venv、使用 `local-office` 额外包安装捆绑的 wheel、写入 `~/.local/bin/monoclaw` 转发器，并将技术员交给 `monoclaw setup` 进行客户专属初始化。如果 `~/.monoclaw/.env` 或 `~/.monoclaw/config.yaml` 已存在，Hatch 会保留这些文件，而不是覆盖技术员或客户配置。

## 生产安装包输入

`./build.sh` 默认是严格的。它预期 MonoClaw 运行时装出位于 `../monoclaw-runtime`，而生产专用的大型输入位于此检出目录的 `bundle-inputs/` 目录下。对于标准工作区，即 `/Users/admin/Projects/hatch/bundle-inputs/`，它被故意排除在 git 之外：

```text
bundle-inputs/
  vendor/
    python/
      current/
        bin/python3
    support/       # 可选
    browser/       # 可选
    skills/        # 可选
    wheelhouse/    # 离线 local-office 依赖必需
    launchd/       # 可选
    models/        # 可选模型包输入，不预备到核心 dist
      gemma-4-e4b/
        gemma-4-e4b.gguf
```

构建器会将这些文件预备到 `dist/` 中，从 `../monoclaw-runtime` 构建运行时仪表板资产和 Python wheel，写入包含构件大小和 SHA-256 哈希的 `hatch-manifest.json`，并在返回前验证安装包。如果没有精选的 `bundle-inputs/vendor/skills` 目录树，构建器会预备运行时装出的捆绑 `skills/` 目录树。将生成的 `dist/` 目录复制到配置随身碟。默认情况下，构建器还会在 `dist/` 旁边写入一个并排的 `tool-packs/mona-secretary-tools/` 目录（Mona 秘书工具 sidecar，不在 `dist/` 内）。将该并排目录复制到随身碟上 `dist/` 的旁边，以便 `dist/install-mona-tools.sh` 可以在 `./install.sh` 之后运行；只有当你以 `HATCH_INCLUDE_MONA_TOOLS=0` 构建或在目标上用 `HATCH_INSTALL_MONA_TOOLS=0` 跳过安装时的 Mona 时，才省略它。当存在可选的 Gemma 输入时，构建器会在 `dist/` 旁边写入一个并排的 `model-packs/gemma-4-e4b/` 目录，并带有自己的 `model-pack-manifest.json`；如果你想避免在目标 Mac 上下载模型，请将该并排目录复制到随身碟上 `dist/` 的旁边。

在 `./build.sh` 之前填充必需的运行时 wheelhouse：

```bash
bash scripts/build_wheelhouse.sh
```

该辅助工具会为 `pip`、`setuptools`、`wheel` 和 `../monoclaw-runtime[local-office]` 下载/构建 wheel 到 `bundle-inputs/vendor/wheelhouse/`。使用 `HATCH_CLEAN_WHEELHOUSE=1` 从头重建该目录。当 wheelhouse 缺失时 `./build.sh` 会失败，因为目标 Mac 不得发现或修复核心运行时依赖。

## 验证

```bash
bash tests/run_tests.sh
```

发布证据和实体测试预期记载于 `docs/verification-gates.md`。

## 设计目标

- 让可从终端机管理的设置自动化。
- 解释手动前置条件，如 Xcode CLT 提示和 Docker Desktop。
- 将本地模型权重和 vendor 安装包保持在托管目录中。
- 安装捆绑的运行时，以便无需源码检出即可使用 `monoclaw setup`。
- 在替换运行时文件前，停止并卸载现有 MonoClaw 或旧版运行时服务。
- 为技术员生成清晰的就绪检查，而不是要求他们阅读冗长的日志。

## 此脚手架的非目标

- 它尚不下载 LLM 权重。
- 它在需要时使用官方终端机安装器安装 Homebrew，但它不使用 Homebrew Python 作为核心运行时 venv，也不安装任意 Homebrew 包。
- 它不安装 GUI 应用程序如 LM Studio 或 Docker Desktop。技术员在需要时从其官方 `.dmg` 包手动安装这些应用程序。
- 它不收集客户密钥或消息凭证；技术员使用 `monoclaw setup` 来处理这些选择。
- 在最终化 plist 发布且启用服务安装前，它不会修改 launchd 服务。
