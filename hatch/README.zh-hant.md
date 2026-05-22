# Hatch

> **譯本資訊**
> **原文：** `hatch/README.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

Hatch 是 MonoClaw 配置安裝器，用於技術員操作的 Mac 設定。它專為全新的恢復出廠設定 Mac mini 和 iMac 設計，同時也支援在 CI 或測試機上透過檢測並停止現有執行環境來進行快速重複測試。

Hatch 有兩個面向操作員的標準流程：`./build.sh` 在組裝機上創建預置包，而生成的 `dist/install.sh` 則從配置介質在目標 Mac 上安裝該包。

## 指令

```bash
# 組裝機，從 /Users/admin/Projects/hatch。
bash scripts/build_wheelhouse.sh
./build.sh

# 目標 Mac，從隨身碟上複製的 dist/ 目錄。
# 將 dist/ 和（構建時的）tool-packs/ 複製到介質上的同一父目錄 —— 見下文。
./install.sh
```

底層生命週期指令仍然可用於診斷：

```bash
bash bin/hatch --dry-run preflight
bash bin/hatch --dry-run cleanup-existing
bash bin/hatch --dry-run install
```

Hatch 預設為試運行（dry-run）。僅在打算用於配置的機器上才傳入 `--apply`。

## 執行環境構件合約

Hatch 以安裝包為優先。目標 Mac 安裝路徑定義於 `docs/runtime-artifacts.md`：組裝機創建預備的 `dist/` 包，Hatch 驗證 `hatch-manifest.json`，客戶 Mac 在 `~/.monoclaw/vendor` 接收托管檔案，同時保留 `~/.monoclaw/customer`。Hatch 還會創建托管的執行環境 venv、使用 `local-office` 額外套件安裝捆綁的 wheel、寫入 `~/.local/bin/monoclaw` 轉發器，並將技術員交給 `monoclaw setup` 進行客戶專屬初始化。如果 `~/.monoclaw/.env` 或 `~/.monoclaw/config.yaml` 已存在，Hatch 會保留這些檔案，而不是覆寫技術員或客戶配置。

## 生產安裝包輸入

`./build.sh` 預設是嚴格的。它預期 MonoClaw 執行環境檢出位於 `../monoclaw-runtime`，而生產專用的大型輸入位於此檢出目錄的 `bundle-inputs/` 目錄下。對於標準工作區，即 `/Users/admin/Projects/hatch/bundle-inputs/`，它被故意排除在 git 之外：

```text
bundle-inputs/
  vendor/
    python/
      current/
        bin/python3
    support/       # 可選
    browser/       # 可選
    skills/        # 可選
    wheelhouse/    # 離線 local-office 依賴必需
    launchd/       # 可選
    models/        # 可選模型包輸入，不預備到核心 dist
      gemma-4-e4b/
        gemma-4-E4B-it-Q4_K_M.gguf
        mmproj-gemma-4-E4B-it-f16.gguf
```

構建器會將這些檔案預備到 `dist/` 中，從 `../monoclaw-runtime` 構建執行環境儀表板資產和 Python wheel，寫入包含構件大小和 SHA-256 雜湊的 `hatch-manifest.json`，並在返回前驗證安裝包。如果沒有精選的 `bundle-inputs/vendor/skills` 目錄樹，構建器會預備執行環境檢出的捆綁 `skills/` 目錄樹。將生成的 `dist/` 目錄複製到配置隨身碟。預設情況下，構建器還會在 `dist/` 旁邊寫入一個並排的 `tool-packs/mona-secretary-tools/` 目錄（Mona 秘書工具 sidecar，不在 `dist/` 內）。將該並排目錄複製到隨身碟上 `dist/` 的旁邊，以便 `dist/install-mona-tools.sh` 可以在 `./install.sh` 之後運行；只有當你以 `HATCH_INCLUDE_MONA_TOOLS=0` 構建或在目標上用 `HATCH_INSTALL_MONA_TOOLS=0` 略過安裝時的 Mona 時，才省略它。當存在可選的 Gemma 輸入時，構建器會在 `dist/` 旁邊寫入一個並排的 `model-packs/gemma-4-e4b/` 目錄，並帶有自己的 `model-pack-manifest.json`；如果你想避免在目標 Mac 上下載模型，請將該並排目錄複製到隨身碟上 `dist/` 的旁邊。

在 `./build.sh` 之前填充必需的執行環境 wheelhouse：

```bash
bash scripts/build_wheelhouse.sh
```

該輔助工具會為 `pip`、`setuptools`、`wheel` 和 `../monoclaw-runtime[local-office]` 下載/構建 wheel 到 `bundle-inputs/vendor/wheelhouse/`。使用 `HATCH_CLEAN_WHEELHOUSE=1` 從頭重建該目錄。當 wheelhouse 缺失時 `./build.sh` 會失敗，因為目標 Mac 不得發現或修復核心執行環境依賴。

## 驗證

```bash
bash tests/run_tests.sh
```

發布證據和實體測試預期記載於 `docs/verification-gates.md`。

## 設計目標

- 讓可從終端機管理的設定自動化。
- 解釋手動前置條件，如 Xcode CLT 提示和 Docker Desktop。
- 將本地模型權重和 vendor 安裝包保持在托管目錄中。
- 安裝捆綁的執行環境，以便無需原始碼檢出即可使用 `monoclaw setup`。
- 在替換執行環境檔案前，停止並卸載現有 MonoClaw 或舊版執行環境服務。
- 為技術員生成清晰的就緒檢查，而不是要求他們閱讀冗長的日誌。

## 此腳手架的非目標

- 它尚不下載 LLM 權重。
- 它在需要時使用官方終端機安裝器安裝 Homebrew，但它不使用 Homebrew Python 作為核心執行環境 venv，也不安裝任意 Homebrew 套件。
- 它不安裝 GUI 應用程式如 LM Studio 或 Docker Desktop。技術員在需要時從其官方 `.dmg` 套件手動安裝這些應用程式。
- 它不收集客戶密鑰或訊息憑證；技術員使用 `monoclaw setup` 來處理這些選擇。
- 在最終化 plist 發布且啟用服務安裝前，它不會修改 launchd 服務。
