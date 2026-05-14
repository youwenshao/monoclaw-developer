# Hatch 运行时构件

> **译本信息**
> **原文：** `hatch/docs/runtime-artifacts.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

## 目的

Hatch 从一个预置包安装 MonoClaw。目标客户 Mac 的核心运行时不应依赖 Homebrew、GitHub 克隆或临时包下载。网络访问仅在技术员启用记载的回退方案时才能使用。

## 三种环境

在代码、文档、日志和产品声明中，将这三种环境分开处理：

1. **组装环境**：构建和预备预置包的开发者或技术员 Mac。它可以使用 Homebrew、Python 构建工具、Node、网络下载和本地源代码检出。
2. **预置包**：复制到配置介质的不可变 `dist/` 目录树。Hatch 在修改目标 Mac 前验证其清单。可选的大型 sidecar 负载（如模型包和 Mona 秘书 `tool-packs/`）位于 `dist/` 旁边，并带有自己的清单。
3. **已安装客户运行时**：目标 Mac 上的 `~/.monoclaw/`。它使用安装包提供的运行时文件、支持运行时、skills 和 launchd 配置。Hatch 让捆绑的 `monoclaw` 运行时可运行，然后将技术员/客户专属初始化交给 `monoclaw setup`。

组装时依赖项不是目标 Mac 依赖项，除非安装器在清单验证后明确需要它们。

## 组装标准流程

从 Hatch 源码目录运行生产组装器：

```bash
cd /Users/admin/Projects/hatch
bash scripts/build_wheelhouse.sh
./build.sh
```

组装器预期运行时装出位于 `../monoclaw-runtime`，非 git 输入位于 `/Users/admin/Projects/hatch/bundle-inputs/`。必需的生产输入是 `bundle-inputs/vendor/python/current/bin/python3` 和已填充的 `bundle-inputs/vendor/wheelhouse/`（用于 `local-office` 运行时依赖配置文件）。可选的 vendor 目录如 `support`、`browser`、`skills` 和 `launchd` 在存在时会被复制，并在生成的清单中标示。当 `bundle-inputs/vendor/skills` 缺失时，组装器会从 `../monoclaw-runtime/skills` 预备捆绑的运行时 skills。

如果 `bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf` 存在，组装器会在 `model-packs/gemma-4-e4b/` 创建一个可选的并排 sidecar。该模型包不是核心 `dist/hatch-manifest.json` 的一部分；它有自己的 `model-pack-manifest.json`，并通过 `dist/install-gemma-model.sh` 安装。

默认情况下（`HATCH_INCLUDE_MONA_TOOLS` 未设为 `0`），组装器还会在 `dist/` 旁边构建 `tool-packs/mona-secretary-tools/`。该 Mona 秘书工具包不是 `dist/hatch-manifest.json` 的一部分；它带有自己的 `tools-pack-manifest.json`，并在核心包之后通过 `dist/install-mona-tools.sh` 安装（从 `dist/install.sh` 调用）。将 `tool-packs/` 复制到配置介质上 `dist/` 的旁边，就像复制可选模型包一样。只有当你在构建时停用 Mona，或计划在目标上用 `HATCH_INSTALL_MONA_TOOLS=0` 跳过安装时的 Mona 时，才省略该目录。

`scripts/build_wheelhouse.sh` 是在组装机上填充 `bundle-inputs/vendor/wheelhouse/` 的标准辅助工具。它会为引导工具（`pip`、`setuptools`、`wheel`）和 `../monoclaw-runtime[local-office]` 构建/下载 wheel。当你需要从头刷新该目录时，设定 `HATCH_CLEAN_WHEELHOUSE=1`。目标 Mac 的核心运行时依赖保持离线安装。

将 `dist/` 和（构建时的）并排目录如 `tool-packs/` 和可选的 `model-packs/` 复制到随身碟上的同一父目录下。复制后，目标 Mac 的标准流程是：

```bash
cd /Volumes/<随身碟>/dist
./install.sh
```

`install.sh` 会生成到预置包中，并调用 `bin/hatch --apply --bundle-root <dist> install`，然后在安装时启用 Mona 工具时运行 `install-mona-tools.sh`（除非 `HATCH_INSTALL_MONA_TOOLS=0`）。

## 预置包目录结构

```text
dist/
  hatch-manifest.json
  install.sh
  install-gemma-model.sh
  install-mona-tools.sh
  bin/
    hatch
  lib/
    common.sh
  runtime/
    monoclaw_runtime-<version>-py3-none-any.whl
    constraints.txt
    about.md
  vendor/
    python/
      current/
    support/
      node/
        current/
      clt/
        current/
    browser/
      chromium/
    skills/
    wheelhouse/
      *.whl
    launchd/
  tests/
    run-hatch-dry-run.sh

model-packs/
  gemma-4-e4b/
    model-pack-manifest.json
    gemma-4-e4b.gguf

tool-packs/
  mona-secretary-tools/
    tools-pack-manifest.json
    bin/
    plugins/
    ...
```

当清单将匹配功能标记为停用时，布局可以省略可选目录。安装器不得默默假设省略的可选资产可用。

## 清单合约

`dist/hatch-manifest.json` 是必需的。Hatch 必须在清理、安装、更新或修改目标 Mac 的服务启动步骤之前验证它。

必需的顶层字段：

- `schema_version`：整数清单架构版本。
- `bundle_id`：预置包的稳定标识符。
- `bundle_version`：人类可读的版本或发布标签。
- `created_at`：来自组装环境的 ISO-8601 时间戳。
- `target`：包含 `platform`、`arch` 和 `minimum_macos` 的对象。
- `runtime`：包含 MonoClaw 包名称、版本、wheel 路径和入口点路径的对象。
- `capabilities`：声明启用的可选表面的对象，如 `local_inference`、`lm_studio`、`telegram_gateway`、`browser_automation`、`sandbox_worker` 和 `voice`。
- `models`：带有 `id`、`provider`、`role`、`path` 和 `required` 的捆绑核心包模型描述符列表。此列表可以为空；可选 sidecar 模型包由其自己的清单表示。
- `artifacts`：带有相对 `path`、`kind`、`sha256` 和 `bytes` 的文件列表。未来的清单可能还包含目录条目，但文件条目是生成 Hatch 包的完整性边界。

每个列出的路径在符号链接解析后必须保持在安装包根目录内。安装器必须拒绝绝对路径、`..` 遍历、缺失的必需构件、SHA 不匹配和架构不匹配。

闭包验证仅忽略已知可在安装包复制到随身碟后创建的 macOS 传输元数据：`.DS_Store`、AppleDouble `._*` 文件，以及 `__MACOSX/`、`.Spotlight-V100/`、`.fseventsd/` 或 `.Trashes/` 下的文件。这些文件如果在清单生成期间存在，也会被省略。任何其他未列出的文件，包括生成的字节码、日志或意外的负载文件，仍然是验证失败。

## 已安装运行时目录结构

```text
~/.monoclaw/
  .env
  customer/
  logs/
  skills/
  vendor/
    runtime/
      monoclaw_runtime-<version>-py3-none-any.whl
      venv/
    python/
    support/
    models/
    browser/
    skills/
    wheelhouse/
    launchd/
```

`vendor/` 由 Hatch 拥有，可以在安装或更新期间替换。
`customer/` 除非技术员明确确认全新重置，否则会被保留。日志可以被轮转或捕获，但不得提交到源码控制。重新执行时会保留现有的 `~/.monoclaw/.env` 和 `~/.monoclaw/config.yaml`；Hatch 让缺失的配置文件留给 `monoclaw setup` 处理，而不是强制使用本地推理默认值。
面向用户的命令转发器安装在 `~/.local/bin/monoclaw`，并指向 `~/.monoclaw/vendor/runtime/venv/bin/monoclaw`。

## 运行时引导合约

复制经验证的资产后，Hatch 在 `~/.monoclaw/vendor/runtime/venv` 下创建一个托管 Python 虚拟环境，并安装：

```bash
~/.monoclaw/vendor/runtime/monoclaw_runtime-<version>-py3-none-any.whl[local-office]
```

Hatch 使用 `--no-index --find-links ~/.monoclaw/vendor/wheelhouse` 进行安装。
wheelhouse 是生产运行时引导必需的；如果省略，Hatch 会失败，除非为诊断明确设定 `HATCH_ALLOW_RUNTIME_NETWORK_FALLBACK=1`。运行时 wheel 必须保持其 PEP 427 文件名（`monoclaw_runtime-...-py3-none-any.whl`），以便 pip 可以验证和安装它们。对于使用旧版 `monoclaw-runtime.whl` 暂存名称的较旧包，Hatch 会在调用 pip 前将文件复制到临时的有效 wheel 文件名。
运行时需要捆绑的 Python 3.11 或更新版本。Hatch 优先使用设定的 `HATCH_RUNTIME_PYTHON`，然后是 `~/.monoclaw/vendor/python/current/bin/` 下的捆绑解释器。只有当为诊断明确设定 `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` 时，才会使用系统或 Homebrew Python。如果没有可用的捆绑 Python 3.11+ 解释器，Hatch 会在创建运行时 venv 前失败，以便修复组装包。如果在 `ensurepip` 期间 venv 创建失败，Hatch 会失败而不是获取 `get-pip.py`；预置包必须使用可用的 Python 运行时重新构建。
Hatch 会在禁用字节码写入的情况下探测捆绑 Python；在清单生成后不要在 `dist/` 内运行 Python 冒烟测试，因为 Python 可能会重写 `__pycache__` 文件并使清单失效。

新配置不会以 LM Studio 默认值播种。技术员运行 `monoclaw setup` 来选择 LM Studio、托管服务商、消息平台和客户专属密钥。

## 目标 Mac 前置条件

- Apple Silicon Mac。
- 清单声明的受支持 macOS 版本。
- Xcode Command Line Tools 已安装或可从捆绑的 CLT 负载安装。如果 macOS 打开 GUI 提示，Hatch 必须准确告诉技术员该做什么。
- 当 Homebrew 缺失时，会使用官方互联网安装器自动安装。设定 `HATCH_SKIP_HOMEBREW_INSTALL=1` 以在离线基准测试或技术员管理的安装中跳过此步骤。Homebrew 不是运行时 Python 提供者；预置包必须包含 `vendor/python/current/bin/python3`。
- 当需要本地推理时，从官方 `.dmg` 手动安装 LM Studio。Hatch 检查并报告就绪状态，但不运行 LM Studio 的安装器或 CLI 导入命令。
- 当需要沙盒工具时，从官方 `.dmg` 手动安装 Docker Desktop。除非启用的功能将其标记为必需，否则缺失或未启动的 Docker 应发出警告。
- macOS 隐私权限用于自动化功能，作为技术员检查清单项目处理，而不是隐藏的终端假设。

## 验证合约

`hatch verify` 必须检查：

- 已为安装的核心包验证清单。
- `~/.monoclaw/vendor` 存在，并具有启用的核心功能预期的运行时、支持、skill 和非模型资产。
- `~/.monoclaw/vendor/runtime/venv/bin/monoclaw` 和 `~/.local/bin/monoclaw` 存在。
- 命令转发器加入 PATH 后，`monoclaw --version` 可以从已安装的运行时解析。
- 捆绑的 skills 存在于 `~/.monoclaw/skills` 中，且不会删除技术员自建的 skills。
- 仅在最终化 bundle plist 且启用服务安装后，才加载启用服务的 launchd agents。
- 日志可写入。
- 面向技术员的诊断避免打印密钥、token 或客户内容。

可选的本地推理就绪状态会使用 `hatch verify-local-inference` 单独检查。可选的 Gemma 模型包会使用 `hatch --model-pack-root <pack> verify-model-pack` 验证，并使用 `hatch --model-pack-root <pack> install-model` 或生成的 `dist/install-gemma-model.sh` 包装器部署。Hatch 会将模型复制到 `~/.monoclaw/vendor/models/gemma-4-e4b/` 并打印手动 LM Studio 导入说明。
