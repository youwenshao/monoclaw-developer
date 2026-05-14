# Hatch 執行環境構件

> **譯本資訊**
> **原文：** `hatch/docs/runtime-artifacts.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

## 目的

Hatch 從一個預置包安裝 MonoClaw。目標客戶 Mac 的核心執行環境不應依賴 Homebrew、GitHub 克隆或臨時套件下載。網絡存取僅在技術員啟用記載的回退方案時才能使用。

## 三種環境

在代碼、文件、日誌和產品聲明中，將這三種環境分開處理：

1. **組裝環境**：構建和預備預置包的開發者或技術員 Mac。它可以使用 Homebrew、Python 構建工具、Node、網絡下載和本地原始碼檢出。
2. **預置包**：複製到配置介質的不可變 `dist/` 目錄樹。Hatch 在修改目標 Mac 前驗證其清單。可選的大型 sidecar 負載（如模型包和 Mona 秘書 `tool-packs/`）位於 `dist/` 旁邊，並帶有自己的清單。
3. **已安裝客戶執行環境**：目標 Mac 上的 `~/.monoclaw/`。它使用安裝包提供的執行環境檔案、支援執行環境、skills 和 launchd 設定。Hatch 讓捆綁的 `monoclaw` 執行環境可運行，然後將技術員/客戶專屬初始化交給 `monoclaw setup`。

組裝時依賴項不是目標 Mac 依賴項，除非安裝器在清單驗證後明確需要它們。

## 組裝標準流程

從 Hatch 原始碼目錄運行生產組裝器：

```bash
cd /Users/admin/Projects/hatch
bash scripts/build_wheelhouse.sh
./build.sh
```

組裝器預期執行環境檢出位於 `../monoclaw-runtime`，非 git 輸入位於 `/Users/admin/Projects/hatch/bundle-inputs/`。必需的生產輸入是 `bundle-inputs/vendor/python/current/bin/python3` 和已填充的 `bundle-inputs/vendor/wheelhouse/`（用於 `local-office` 執行環境依賴配置檔）。可選的 vendor 目錄如 `support`、`browser`、`skills` 和 `launchd` 在存在時會被複製，並在生成的清單中標示。當 `bundle-inputs/vendor/skills` 缺失時，組裝器會從 `../monoclaw-runtime/skills` 預備捆綁的執行環境 skills。

如果 `bundle-inputs/vendor/models/gemma-4-e4b/gemma-4-e4b.gguf` 存在，組裝器會在 `model-packs/gemma-4-e4b/` 創建一個可選的並排 sidecar。該模型包不是核心 `dist/hatch-manifest.json` 的一部分；它有自己的 `model-pack-manifest.json`，並透過 `dist/install-gemma-model.sh` 安裝。

預設情況下（`HATCH_INCLUDE_MONA_TOOLS` 未設為 `0`），組裝器還會在 `dist/` 旁邊構建 `tool-packs/mona-secretary-tools/`。該 Mona 秘書工具包不是 `dist/hatch-manifest.json` 的一部分；它帶有自己的 `tools-pack-manifest.json`，並在核心包之後透過 `dist/install-mona-tools.sh` 安裝（從 `dist/install.sh` 呼叫）。將 `tool-packs/` 複製到配置介質上 `dist/` 的旁邊，就像複製可選模型包一樣。只有當你在構建時停用 Mona，或計劃在目標上用 `HATCH_INSTALL_MONA_TOOLS=0` 略過安裝時的 Mona 時，才省略該目錄。

`scripts/build_wheelhouse.sh` 是在組裝機上填充 `bundle-inputs/vendor/wheelhouse/` 的標準輔助工具。它會為引導工具（`pip`、`setuptools`、`wheel`）和 `../monoclaw-runtime[local-office]` 構建/下載 wheel。當你需要從頭刷新該目錄時，設定 `HATCH_CLEAN_WHEELHOUSE=1`。目標 Mac 的核心執行環境依賴保持離線安裝。

將 `dist/` 和（構建時的）並排目錄如 `tool-packs/` 和可選的 `model-packs/` 複製到隨身碟上的同一父目錄下。複製後，目標 Mac 的標準流程是：

```bash
cd /Volumes/<隨身碟>/dist
./install.sh
```

`install.sh` 會生成到預置包中，並呼叫 `bin/hatch --apply --bundle-root <dist> install`，然後在安裝時啟用 Mona 工具時運行 `install-mona-tools.sh`（除非 `HATCH_INSTALL_MONA_TOOLS=0`）。

## 預置包目錄結構

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

當清單將匹配功能標記為停用時，佈局可以省略可選目錄。安裝器不得默默假設省略的可選資產可用。

## 清單合約

`dist/hatch-manifest.json` 是必需的。Hatch 必須在清理、安裝、更新或修改目標 Mac 的服務啟動步驟之前驗證它。

必需的頂層欄位：

- `schema_version`：整數清單架構版本。
- `bundle_id`：預置包的穩定識別碼。
- `bundle_version`：人類可讀的版本或發布標籤。
- `created_at`：來自組裝環境的 ISO-8601 時間戳。
- `target`：包含 `platform`、`arch` 和 `minimum_macos` 的物件。
- `runtime`：包含 MonoClaw 套件名稱、版本、wheel 路徑和進入點路徑的物件。
- `capabilities`：宣告啟用的可選表面的物件，如 `local_inference`、`lm_studio`、`telegram_gateway`、`browser_automation`、`sandbox_worker` 和 `voice`。
- `models`：帶有 `id`、`provider`、`role`、`path` 和 `required` 的捆綁核心包模型描述符列表。此列表可以為空；可選 sidecar 模型包由其自己的清單表示。
- `artifacts`：帶有相對 `path`、`kind`、`sha256` 和 `bytes` 的檔案列表。未來的清單可能還包含目錄條目，但檔案條目是生成 Hatch 包的完整性邊界。

每個列出的路徑在符號連結解析後必須保持在安裝包根目錄內。安裝器必須拒絕絕對路徑、`..` 遍歷、缺失的必需構件、SHA 不匹配和架構不匹配。

閉包驗證僅忽略已知可在安裝包複製到隨身碟後創建的 macOS 傳輸元數據：`.DS_Store`、AppleDouble `._*` 檔案，以及 `__MACOSX/`、`.Spotlight-V100/`、`.fseventsd/` 或 `.Trashes/` 下的檔案。這些檔案如果在清單生成期間存在，也會被省略。任何其他未列出的檔案，包括生成的字節碼、日誌或意外的負載檔案，仍然是驗證失敗。

## 已安裝執行環境目錄結構

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

`vendor/` 由 Hatch 擁有，可以在安裝或更新期間替換。
`customer/` 除非技術員明確確認全新重置，否則會被保留。日誌可以被輪換或擷取，但不得提交到原始碼控制。重新執行時會保留現有的 `~/.monoclaw/.env` 和 `~/.monoclaw/config.yaml`；Hatch 讓缺失的設定檔留給 `monoclaw setup` 處理，而不是強制使用本地推理預設值。
面向用戶的命令轉發器安裝在 `~/.local/bin/monoclaw`，並指向 `~/.monoclaw/vendor/runtime/venv/bin/monoclaw`。

## 執行環境引導合約

複製經驗證的資產後，Hatch 在 `~/.monoclaw/vendor/runtime/venv` 下創建一個托管 Python 虛擬環境，並安裝：

```bash
~/.monoclaw/vendor/runtime/monoclaw_runtime-<version>-py3-none-any.whl[local-office]
```

Hatch 使用 `--no-index --find-links ~/.monoclaw/vendor/wheelhouse` 進行安裝。
wheelhouse 是生產執行環境引導必需的；如果省略，Hatch 會失敗，除非為診斷明確設定 `HATCH_ALLOW_RUNTIME_NETWORK_FALLBACK=1`。執行環境 wheel 必須保持其 PEP 427 檔案名（`monoclaw_runtime-...-py3-none-any.whl`），以便 pip 可以驗證和安裝它們。對於使用舊版 `monoclaw-runtime.whl` 暫存名稱的較舊包，Hatch 會在呼叫 pip 前將檔案複製到臨時的有效 wheel 檔案名。
執行環境需要捆綁的 Python 3.11 或更新版本。Hatch 優先使用設定的 `HATCH_RUNTIME_PYTHON`，然後是 `~/.monoclaw/vendor/python/current/bin/` 下的捆綁解譯器。只有當為診斷明確設定 `HATCH_ALLOW_SYSTEM_RUNTIME_PYTHON=1` 時，才會使用系統或 Homebrew Python。如果沒有可用的捆綁 Python 3.11+ 解譯器，Hatch 會在創建執行環境 venv 前失敗，以便修復組裝包。如果在 `ensurepip` 期間 venv 創建失敗，Hatch 會失敗而不是獲取 `get-pip.py`；預置包必須使用可用的 Python 執行環境重新構建。
Hatch 會在禁用字節碼寫入的情況下探測捆綁 Python；在清單生成後不要在 `dist/` 內運行 Python 煙霧測試，因為 Python 可能會重寫 `__pycache__` 檔案並使清單失效。

新配置不會以 LM Studio 預設值播種。技術員運行 `monoclaw setup` 來選擇 LM Studio、托管服務商、訊息平台和客戶專屬密鑰。

## 目標 Mac 前置條件

- Apple Silicon Mac。
- 清單宣告的支援 macOS 版本。
- Xcode Command Line Tools 已安裝或可從捆綁的 CLT 負載安裝。如果 macOS 打開 GUI 提示，Hatch 必須準確告訴技術員該做什麼。
- 當 Homebrew 缺失時，會使用官方互聯網安裝器自動安裝。設定 `HATCH_SKIP_HOMEBREW_INSTALL=1` 以在離線基準測試或技術員管理的安裝中略過此步驟。Homebrew 不是執行環境 Python 提供者；預置包必須包含 `vendor/python/current/bin/python3`。
- 當需要本地推理時，從官方 `.dmg` 手動安裝 LM Studio。Hatch 檢查並報告就緒狀態，但不運行 LM Studio 的安裝器或 CLI 匯入指令。
- 當需要沙盒工具時，從官方 `.dmg` 手動安裝 Docker Desktop。除非啟用的功能將其標記為必需，否則缺失或未啟動的 Docker 應發出警告。
- macOS 私隱權限用於自動化功能，作為技術員檢查清單項目處理，而不是隱藏的終端機假設。

## 驗證合約

`hatch verify` 必須檢查：

- 已為安裝的核心包驗證清單。
- `~/.monoclaw/vendor` 存在，並具有啟用的核心功能預期的執行環境、支援、skill 和非模型資產。
- `~/.monoclaw/vendor/runtime/venv/bin/monoclaw` 和 `~/.local/bin/monoclaw` 存在。
- 命令轉發器加入 PATH 後，`monoclaw --version` 可以從已安裝的執行環境解析。
- 捆綁的 skills 存在於 `~/.monoclaw/skills` 中，且不會刪除技術員自建的 skills。
- 僅在最終化 bundle plist 且啟用服務安裝後，才載入啟用服務的 launchd agents。
- 日誌可寫入。
- 面向技術員的診斷避免列印密鑰、token 或客戶內容。

可選的本地推理就緒狀態會使用 `hatch verify-local-inference` 單獨檢查。可選的 Gemma 模型包會使用 `hatch --model-pack-root <pack> verify-model-pack` 驗證，並使用 `hatch --model-pack-root <pack> install-model` 或生成的 `dist/install-gemma-model.sh` 包裝器佈署。Hatch 會將模型複製到 `~/.monoclaw/vendor/models/gemma-4-e4b/` 並列印手動 LM Studio 匯入說明。
