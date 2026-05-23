# MonoClaw 技术员配置手册

> **译本信息**
> **原文：** `hatch/docs/technician-handbook.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

---

> **读者：** 为非技术办公室职员配置 Mac mini 或 iMac 的技术员。
> **目标：** 从恢复出厂设置的 Mac 到运作正常的 MonoClaw 运行时，每一步都有清晰的重启方法。
> **本文不是：** 安装包构建说明。如需构建或修改安装包，请参阅 `assembly-internals.md`。

---

## 1. 出发前检查清单（打开终端前先执行）

回答三个问题。答案决定了你在运行安装程序前必须完成的事项。

| 问题 | 如是 | 如否 |
|---|---|---|
| 客户合约是否包含**本地推理**（设备端 AI，非托管服务商）？ | 先从官方 `.dmg` 安装 **LM Studio**，再运行安装程序。 | 跳过 LM Studio。 |
| 客户合约是否包含**沙盒工具**或容器化工作流程？ | 先从官方 `.dmg` 安装 **Docker Desktop** 并启动一次以授权权限。 | 跳过 Docker Desktop。 |
| Mac 是否已连接**互联网**？ | 标准流程。正常进行。 | 在运行 `./install.sh` 前设置 `HATCH_SKIP_HOMEBREW_INSTALL=1`。Homebrew 是可选的技术员工具，并非运行时依赖。 |

**必备项目：**
- **Apple Silicon Mac**（M1 或更新型号）。
- **Xcode Command Line Tools。** 若 `xcode-select -p` 失败，请执行 `xcode-select --install`。这可能触发 macOS GUI 提示——请先完成后再继续。

**你的配置介质上应有的内容：**
```text
<VOLUME>/
  dist/                           ← 必需的核心包
  tool-packs/
    mona-secretary-tools/         ← 默认需要（除非你明确在构建时停用，否则请复制）
  model-packs/
    gemma-4-e4b/                  ← 仅当客户合约包含本地推理时才需要
```

> ⚠️ **重要：** 如果 `tool-packs/mona-secretary-tools/` 缺失，`install.sh` 会发出警告并继续，但客户将没有默认秘书工具（WhatsApp 搜索、Slack 搜索、macOS 自动化）。除非工作单明确要求跳过 Mona 工具，否则请复制它。

---

## 2. 安装（只需一条命令）

在目标 Mac 上打开终端并执行：

```bash
cd /Volumes<你的随身碟>/dist
./install.sh
```

`install.sh` 会自动完成以下步骤：
1. 安装核心 MonoClaw 运行时、skills 和命令转发器（shim）。
2. 安装 Mona 秘书工具附属组件（除非 `HATCH_INSTALL_MONA_TOOLS=0`）。
3. 当 `model-packs/gemma-4-e4b/` 位于 `dist/` 旁时，将 Gemma 4 模型包装载到 LM Studio（除非 `HATCH_INSTALL_GEMMA_MODEL=0`）。若合约包含本地推理，请在运行 `./install.sh` **之前**从官方 `.dmg` 安装 LM Studio。

**你不需要传入 `--apply`。** 生成的 `install.sh` 已经默认应用变更。

### 预期输出

你应该看到一连串 `[install]` 和 `[ok]` 消息，最后以以下内容结尾：

```
[install] Technician handoff
  next: open a new terminal or run: export PATH="$HOME/.local/bin:$PATH"
  next: verify runtime with: monoclaw --version
  next: run monoclaw setup
```

如果你看到 `[warn]` 而非 `[ok]`，请阅读警告。常见的无害警告：
- "Homebrew missing; installing with the official Homebrew installer"——新 Mac 正常现象。
- "No bundled skills staged"——安装包构建时没有包含精选 skills；将使用运行时默认值。
- "launchd service installation is not enabled until bundle plists are finalized"——预期行为。服务稍后才会启动。

如果你看到 `[fail]`，请停止。在故障解决前不要运行 `monoclaw setup`。请参阅第 5 节：恢复。

---

## 3. 安装后验证（切勿跳过）

打开一个**新的终端窗口**（让 `~/.local/bin` 加入 PATH），然后执行：

```bash
monoclaw --version
```

预期结果：会印出版本字符串。如果你看到 `command not found`，请执行：

```bash
export PATH="$HOME/.local/bin:$PATH"
monoclaw --version
```

如果仍然失败，命令转发器没有正确写入。请参阅第 5 节：恢复。

**完整诊断扫描（可选但建议在首次基准测试或感觉异常时执行）：**

```bash
bash /Volumes/<你的随身碟>/dist/bin/hatch doctor
```

这会一次运行 `preflight` + `verify` + `verify-local-inference`，并准确告诉你缺少什么。

---

## 4. 客户专属设置

运行设置向导：

```bash
monoclaw setup
```

在这里，你或客户可以选择：
- AI 服务商（托管服务商 vs LM Studio 本地推理）。
- 消息平台（Telegram、Slack、WhatsApp）。
- 密钥和 API key。
- 客户专属配置。

**Hatch 不会收集密钥。** 请不要在 `monoclaw setup` 之外的终端粘贴 token，也不要将 `.env` 或 `config.yaml` 提交到 git。

### 如果已配置本地推理

1. 在运行 `./install.sh` **之前**从官方 `.dmg` 安装 LM Studio（当模型包在随身碟上时为必需步骤）。
2. 照常运行 `./install.sh`。当 `model-packs/gemma-4-e4b/` 位于 `dist/` 旁时，安装程序会将聊天 GGUF 与视觉投影（mmproj）复制到 LM Studio 原生模型目录：
   ```
   ~/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/
     gemma-4-E4B-it-Q4_K_M.gguf
     mmproj-gemma-4-E4B-it-f16.gguf
   ```
3. 启动 LM Studio 一次并完成首次设置；应自动发现已装载的模型（无需手动导入）。
4. 再次运行 `monoclaw setup`（或编辑 `~/.monoclaw/.env`）以指向本地端点：
   ```
   LM_BASE_URL=http://127.0.0.1:1234/v1
   LM_API_KEY=dummy-lm-api-key
   MONOCLAW_MODEL=local:gemma4:e4b
   ```

若模型装载步骤失败且无需重新运行完整安装，可使用 `./install-gemma-model.sh` 恢复。

### 如果已安装 Mona 秘书工具

在启用主机自动化前，请先审阅权限范围：

```bash
cat ~/.monoclaw/vendor/mona-tools/docs/permissions.md
```

只有在审阅路径和权限范围后，才复制 MCP 配置示例：

```bash
cp ~/.monoclaw/vendor/mona-tools/config/mcp_servers.mona.example.yaml ~/.monoclaw/mcp_servers.mona.yaml
```

然后手动或通过 `monoclaw setup` 合并到 `~/.monoclaw/config.yaml`。

---

## 5. 恢复与重新运行 {#recovery--reruns}

### 可安全重新运行

`./install.sh` 对运行时构件是幂等的。它会保留：
- `~/.monoclaw/.env`
- `~/.monoclaw/config.yaml`
- `~/.monoclaw/customer/`
- `~/.monoclaw/skills/` 中的技术员自建 skills

如果安装中断或安装后检查失败，只需重新执行 `./install.sh`。

### 完整重置（清除所有内容）

只有当工作单明确要求重新安装，或你怀疑 vendor 文件损坏时才执行：

```bash
export MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1
./install.sh
```

这会移除并替换 `~/.monoclaw/vendor/`，但仍会保留 `customer/`、`.env` 和 `config.yaml`，除非它们已被手动删除。

### 常见故障

| 症状 | 原因 | 修复方法 |
|---|---|---|
| 安装后提示 `monoclaw: command not found` | 当前 shell 的 PATH 未包含 `~/.local/bin` | 打开一个新终端，或执行 `export PATH="$HOME/.local/bin:$PATH"` |
| `Python 3.11+ runtime interpreter missing` | 安装包复制时没有包含 `vendor/python/` | 从组装机重新构建或重新复制安装包 |
| `Bundled wheelhouse is required for production runtime bootstrap` | 构建时没有执行 `bash scripts/build_wheelhouse.sh` | 返回组装机重新构建 |
| `Mona secretary tools installation failed; core MonoClaw runtime remains installed` | `tool-packs/mona-secretary-tools/` 没有复制到随身碟 | 复制附属组件并重新执行 `./install.sh`，或设置 `HATCH_INSTALL_MONA_TOOLS=0` 以故意跳过 |
| `Gemma model pack installation failed (HATCH_INSTALL_STRICT=1)` | `model-packs/gemma-4-e4b/` 存在但 LM Studio 未安装（或模型包验证失败） | 从 `.dmg` 安装 LM Studio 后重新执行 `./install.sh`，或仅在故意部分安装时设置 `HATCH_INSTALL_STRICT=0` |
| `Xcode Command Line Tools are missing` | CLT 未安装或 macOS 提示未完成 | 执行 `xcode-select --install`，完成 GUI 提示，然后重新执行 `./install.sh` |
| `LM Studio app is missing` | 客户合约包含本地推理但 LM Studio 未安装 | 从 `.dmg` 安装 LM Studio，然后重新执行 `./install.sh` |

### 离线或隔离网络的 Mac

如果目标 Mac 没有互联网：
1. 确保 Xcode CLT 在你到达前已安装（或从本地 `.pkg` 安装）。
2. 设置 `HATCH_SKIP_HOMEBREW_INSTALL=1`，让 Hatch 不尝试下载 Homebrew：
   ```bash
   export HATCH_SKIP_HOMEBREW_INSTALL=1
   ./install.sh
   ```
3. 安装包必须包含已填充的 `vendor/wheelhouse/`（这是组装操作员的责任）。如果安装因 wheelhouse 错误而失败，表示安装包构建不正确——请不要在客户 Mac 上尝试网络回退方案。

### 何时联系组装 / 工程团队

请勿在目标 Mac 上即兴修复。在以下情况升级：
- 安装包清单验证失败（`hatch-manifest.json` SHA 不匹配）。
- `vendor/python/current/bin/python3` 缺失或不是 Python 3.11+。
- wheelhouse 为空或缺失。
- 两次安装尝试后 `monoclaw --version` 仍然失败。

---

## 6. 交接检查清单（离开前签核）

- [ ] 在新终端窗口中，`monoclaw --version` 能印出版本号。
- [ ] `monoclaw setup` 已执行，且客户能再次启动它。
- [ ] 若使用本地推理：LM Studio 已安装、模型已导入，且 `hatch verify-local-inference` 通过。
- [ ] 若使用 Mona 工具：已与客户一起审阅 `~/.monoclaw/vendor/mona-tools/docs/permissions.md`。
- [ ] 没有密钥被贴到公开 issue tracker、commit 或聊天记录中。
- [ ] `~/.monoclaw/logs/` 存在且可写入（用 `touch ~/.monoclaw/logs/test && rm ~/.monoclaw/logs/test` 检查）。
- [ ] 客户知道如何重新启动 MonoClaw（相关功能会在未来版本中 launchd plist 定稿后生效）。

---

## 快速参考：技术员命令

| 命令 | 使用时机 |
|---|---|
| `./install.sh` | 每次配置或重新执行。 |
| `monoclaw --version` | 验证运行时是否可达。 |
| `monoclaw setup` | 配置服务商、消息平台和密钥。 |
| `bash dist/bin/hatch doctor` | 感觉异常时的完整诊断。 |
| `bash dist/bin/hatch verify` | 仅检查核心运行时完整性。 |
| `bash dist/bin/hatch verify-local-inference` | 检查 LM Studio + 模型就绪状态。 |
| `./install-gemma-model.sh` | 在模型装载步骤失败后重新运行，或在不重新执行完整 `./install.sh` 的情况下恢复。 |
