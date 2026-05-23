# MonoClaw 技術員配置手冊

> **譯本資訊**
> **原文：** `hatch/docs/technician-handbook.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

---

> **讀者：** 為非技術辦公室職員配置 Mac mini 或 iMac 的技術員。
> **目標：** 從恢復出廠設定的 Mac 到運作正常的 MonoClaw 執行環境，每一步都有清晰的重啟方法。
> **本文不是：** 安裝包構建說明。如需構建或修改安裝包，請參閱 `assembly-internals.md`。

---

## 1. 出發前檢查清單（打開終端機前先做）

回答三個問題。答案決定了你在運行安裝程式前必須完成的事項。

| 問題 | 如是 | 如否 |
|---|---|---|
| 客戶合約是否包含**本地推理**（裝置端 AI，非托管服務商）？ | 先從官方 `.dmg` 安裝 **LM Studio**，再運行安裝程式。 | 略過 LM Studio。 |
| 客戶合約是否包含**沙盒工具**或容器化工作流程？ | 先從官方 `.dmg` 安裝 **Docker Desktop** 並啟動一次以授權權限。 | 略過 Docker Desktop。 |
| Mac 是否已連接**互聯網**？ | 標準流程。正常進行。 | 在運行 `./install.sh` 前設定 `HATCH_SKIP_HOMEBREW_INSTALL=1`。Homebrew 是選用的技術員工具，並非執行環境依賴。 |

**必備項目：**
- **Apple Silicon Mac**（M1 或更新型號）。
- **Xcode Command Line Tools。** 若 `xcode-select -p` 失敗，請執行 `xcode-select --install`。這可能觸發 macOS GUI 提示——請先完成後再繼續。

**你的配置介質上應有的內容：**
```text
<VOLUME>/
  dist/                           ← 必需的核心包
  tool-packs/
    mona-secretary-tools/         ← 預設需要（除非你明確在構建時停用，否則請複製）
  model-packs/
    gemma-4-e4b/                  ← 僅當客戶合約包含本地推理時才需要
```

> ⚠️ **重要：** 如果 `tool-packs/mona-secretary-tools/` 缺失，`install.sh` 會發出警告並繼續，但客戶將沒有預設秘書工具（WhatsApp 搜尋、Slack 搜尋、macOS 自動化）。除非工作單明確要求略過 Mona 工具，否則請複製它。

---

## 2. 安裝（只需一條指令）

在目標 Mac 上打開終端機並執行：

```bash
cd /Volumes/<你的隨身碟>/dist
./install.sh
```

`install.sh` 會自動完成以下步驟：
1. 安裝核心 MonoClaw 執行環境、skills 和命令轉發器（shim）。
2. 安裝 Mona 秘書工具附屬組件（除非 `HATCH_INSTALL_MONA_TOOLS=0`）。
3. 當 `model-packs/gemma-4-e4b/` 位於 `dist/` 旁時，將 Gemma 4 模型包裝載到 LM Studio（除非 `HATCH_INSTALL_GEMMA_MODEL=0`）。若合約包含本地推理，請在執行 `./install.sh` **之前**從官方 `.dmg` 安裝 LM Studio。

**你不需要傳入 `--apply`。** 產生的 `install.sh` 已經預設應用變更。

### 預期輸出

你應該看到一連串 `[install]` 和 `[ok]` 訊息，最後以以下內容結尾：

```
[install] Technician handoff
  next: open a new terminal or run: export PATH="$HOME/.local/bin:$PATH"
  next: verify runtime with: monoclaw --version
  next: run monoclaw setup
```

如果你看到 `[warn]` 而非 `[ok]`，請閱讀警告。常見的無害警告：
- "Homebrew missing; installing with the official Homebrew installer"——新 Mac 正常現象。
- "No bundled skills staged"——安裝包構建時沒有包含精選 skills；將使用執行環境預設值。
- "launchd service installation is not enabled until bundle plists are finalized"——預期行為。服務稍後才會啟動。

如果你看到 `[fail]`，請停止。在故障解決前不要運行 `monoclaw setup`。請參閱第 5 節：恢復。

---

## 3. 安裝後驗證（切勿略過）

打開一個**新的終端機視窗**（讓 `~/.local/bin` 加入 PATH），然後執行：

```bash
monoclaw --version
```

預期結果：會印出版本字串。如果你看到 `command not found`，請執行：

```bash
export PATH="$HOME/.local/bin:$PATH"
monoclaw --version
```

如果仍然失敗，命令轉發器沒有正確寫入。請參閱第 5 節：恢復。

**完整診斷掃描（可選但建議在首次基準測試或感覺異常時執行）：**

```bash
bash /Volumes/<你的隨身碟>/dist/bin/hatch doctor
```

這會一次運行 `preflight` + `verify` + `verify-local-inference`，並準確告訴你缺少什麼。

---

## 4. 客戶專屬設定

運行設定精靈：

```bash
monoclaw setup
```

在這裡，你或客戶可以選擇：
- AI 服務商（托管服務商 vs LM Studio 本地推理）。
- 訊息平台（Telegram、Slack、WhatsApp）。
- 密鑰和 API key。
- 客戶專屬設定。

**Hatch 不會收集密鑰。** 請不要在 `monoclaw setup` 之外的終端機貼上 token，也不要將 `.env` 或 `config.yaml` 提交到 git。

### 如果已配置本地推理

1. 在執行 `./install.sh` **之前**從官方 `.dmg` 安裝 LM Studio（當模型包在隨身碟上時為必需步驟）。
2. 照常執行 `./install.sh`。當 `model-packs/gemma-4-e4b/` 位於 `dist/` 旁時，安裝程式會將聊天 GGUF 與視覺投影（mmproj）複製到 LM Studio 原生模型目錄：
   ```
   ~/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/
     gemma-4-E4B-it-Q4_K_M.gguf
     mmproj-gemma-4-E4B-it-f16.gguf
   ```
3. 啟動 LM Studio 一次並完成首次設定；應自動發現已裝載的模型（無需手動匯入）。
4. 再次運行 `monoclaw setup`（或編輯 `~/.monoclaw/.env`）以指向本地端點：
   ```
   LM_BASE_URL=http://127.0.0.1:1234/v1
   LM_API_KEY=dummy-lm-api-key
   MONOCLAW_MODEL=local:gemma4:e4b
   ```

若模型裝載步驟失敗且無需重新執行完整安裝，可使用 `./install-gemma-model.sh` 恢復。

### 如果已安裝 Mona 秘書工具

在啟用主機自動化前，請先審閱權限範圍：

```bash
cat ~/.monoclaw/vendor/mona-tools/docs/permissions.md
```

只有在審閱路徑和權限範圍後，才複製 MCP 設定範例：

```bash
cp ~/.monoclaw/vendor/mona-tools/config/mcp_servers.mona.example.yaml ~/.monoclaw/mcp_servers.mona.yaml
```

然後手動或透過 `monoclaw setup` 合併到 `~/.monoclaw/config.yaml`。

---

## 5. 恢復與重新運行 {#recovery--reruns}

### 可安全重新運行

`./install.sh` 對執行環境構件是冪等的。它會保留：
- `~/.monoclaw/.env`
- `~/.monoclaw/config.yaml`
- `~/.monoclaw/customer/`
- `~/.monoclaw/skills/` 中的技術員自建 skills

如果安裝中斷或安裝後檢查失敗，只需重新執行 `./install.sh`。

### 完整重置（清除所有內容）

只有當工作單明確要求重新安裝，或你懷疑 vendor 檔案損壞時才執行：

```bash
export MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1
./install.sh
```

這會移除並替換 `~/.monoclaw/vendor/`，但仍會保留 `customer/`、`.env` 和 `config.yaml`，除非它們已被手動刪除。

### 常見故障

| 症狀 | 原因 | 修復方法 |
|---|---|---|
| 安裝後提示 `monoclaw: command not found` | 目前 shell 的 PATH 未包含 `~/.local/bin` | 開啟一個新終端機，或執行 `export PATH="$HOME/.local/bin:$PATH"` |
| `Python 3.11+ runtime interpreter missing` | 安裝包複製時沒有包含 `vendor/python/` | 從組裝機重新構建或重新複製安裝包 |
| `Bundled wheelhouse is required for production runtime bootstrap` | 構建時沒有執行 `bash scripts/build_wheelhouse.sh` | 返回組裝機重新構建 |
| `Mona secretary tools installation failed; core MonoClaw runtime remains installed` | `tool-packs/mona-secretary-tools/` 沒有複製到隨身碟 | 複製附屬組件並重新執行 `./install.sh`，或設定 `HATCH_INSTALL_MONA_TOOLS=0` 以故意略過 |
| `Gemma model pack installation failed (HATCH_INSTALL_STRICT=1)` | `model-packs/gemma-4-e4b/` 存在但 LM Studio 未安裝（或模型包驗證失敗） | 從 `.dmg` 安裝 LM Studio 後重新執行 `./install.sh`，或僅在故意部分安裝時設定 `HATCH_INSTALL_STRICT=0` |
| `Xcode Command Line Tools are missing` | CLT 未安裝或 macOS 提示未完成 | 執行 `xcode-select --install`，完成 GUI 提示，然後重新執行 `./install.sh` |
| `LM Studio app is missing` | 客戶合約包含本地推理但 LM Studio 未安裝 | 從 `.dmg` 安裝 LM Studio，然後重新執行 `./install.sh` |

### 離線或隔離網絡的 Mac

如果目標 Mac 沒有互聯網：
1. 確保 Xcode CLT 在你到達前已安裝（或從本地 `.pkg` 安裝）。
2. 設定 `HATCH_SKIP_HOMEBREW_INSTALL=1`，讓 Hatch 不嘗試下載 Homebrew：
   ```bash
   export HATCH_SKIP_HOMEBREW_INSTALL=1
   ./install.sh
   ```
3. 安裝包必須包含已填充的 `vendor/wheelhouse/`（這是組裝操作員的責任）。如果安裝因 wheelhouse 錯誤而失敗，表示安裝包構建不正確——請不要在客戶 Mac 上嘗試網絡回退方案。

### 何時聯繫組裝 / 工程團隊

請勿在目標 Mac 上即興修復。在以下情況升級：
- 安裝包清單驗證失敗（`hatch-manifest.json` SHA 不匹配）。
- `vendor/python/current/bin/python3` 缺失或不是 Python 3.11+。
- wheelhouse 為空或缺失。
- 兩次安裝嘗試後 `monoclaw --version` 仍然失敗。

---

## 6. 交接檢查清單（離開前簽核）

- [ ] 在新終端機視窗中，`monoclaw --version` 能印出版本號。
- [ ] `monoclaw setup` 已執行，且客戶能再次啟動它。
- [ ] 若使用本地推理：LM Studio 已安裝、模型已匯入，且 `hatch verify-local-inference` 通過。
- [ ] 若使用 Mona 工具：已與客戶一起審閱 `~/.monoclaw/vendor/mona-tools/docs/permissions.md`。
- [ ] 沒有密鑰被貼到公開 issue tracker、commit 或聊天記錄中。
- [ ] `~/.monoclaw/logs/` 存在且可寫入（用 `touch ~/.monoclaw/logs/test && rm ~/.monoclaw/logs/test` 檢查）。
- [ ] 客戶知道如何重新啟動 MonoClaw（相關功能會在未來版本中 launchd plist 定稿後生效）。

---

## 快速參考：技術員指令

| 指令 | 使用時機 |
|---|---|
| `./install.sh` | 每次配置或重新執行。 |
| `monoclaw --version` | 驗證執行環境是否可達。 |
| `monoclaw setup` | 配置服務商、訊息平台和密鑰。 |
| `bash dist/bin/hatch doctor` | 感覺異常時的完整診斷。 |
| `bash dist/bin/hatch verify` | 僅檢查核心執行環境完整性。 |
| `bash dist/bin/hatch verify-local-inference` | 檢查 LM Studio + 模型就緒狀態。 |
| `./install-gemma-model.sh` | 在模型裝載步驟失敗後重新執行，或在不重新執行完整 `./install.sh` 的情況下恢復。 |
