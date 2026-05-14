# Hatch 配置部署合約

> **譯本資訊**
> **原文：** `hatch/docs/provisioning-contract.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

Hatch 負責讓一台恢復出廠設定的 Mac 準備好為非技術辦公室職員運行 MonoClaw。

## 由 Hatch 管理

- MonoClaw 執行環境安裝。
- 可選的本地推理就緒檢查，以及當 sidecar 存在於配置介質上時，可選的 Gemma 4 E4B 模型包佈署。
- Agent skills、工具和預設工作區引導。
- 技術員交接至 `monoclaw setup` 以處理密鑰、訊息和客戶專屬設定。
- 最終化 plist 發布後，MonoClaw 管理进程的 launchd 服務生命週期。
- 針對重複基準測試，清理現有 MonoClaw 和舊版執行環境閘道。
- 技術員可讀的就緒檢查。

## 手動或半手動前置條件

- Xcode Command Line Tools 可能觸發 macOS GUI 提示。
- 當 `brew` 缺失時，Homebrew 安裝會使用官方互聯網安裝器，除非為離線基準測試明確略過。Homebrew 並非核心執行環境 Python 提供者；預備好的安裝包必須包含 Python 3.11+。
- LM Studio 是需要手動從官方 `.dmg` 安裝並首次啟動的任務，僅在需要本地推理時才需要。
- Docker Desktop 可能需要 GUI 安裝、首次啟動和權限授權。
- macOS 私隱權限可能需要「系統設定」互動。

Hatch 必須檢測這些狀態並準確告訴技術員該做什麼。它不應假設僅限 GUI 的步驟總能從終端機解決。

## 管理路徑

- 執行環境主目錄：`~/.monoclaw`
- Vendor 管理檔案：`~/.monoclaw/vendor`
- 執行環境 venv：`~/.monoclaw/vendor/runtime/venv`
- 命令轉發器：`~/.local/bin/monoclaw`
- 客戶保留檔案：`~/.monoclaw/customer`
- 日誌與診斷：`~/.monoclaw/logs`
- 未來本地模型快取：`~/.monoclaw/vendor/model-cache`

## 預置包合約

Hatch 從一個經清單驗證的預置包安裝。詳細的構件佈局、清單欄位、目標 Mac 前置條件和驗證檢查記載於 `docs/runtime-artifacts.md`。

目標 Mac 應該接收已捆綁的執行環境構件，而不是依賴 Homebrew、原始碼檢出或網絡下載來進行核心 MonoClaw 安裝。組裝機在創建預置包時可以使用這些工具。對於 `local-office` Python 依賴，`vendor/wheelhouse` 是必需的；網絡解析僅在明確選擇的診斷回退標誌後方可使用。組裝操作員應在 wheelhouse 缺失或過時時，於 `./build.sh` 之前執行 `bash scripts/build_wheelhouse.sh`。可選模型包是經清單驗證的 sidecar，不屬於核心執行環境清單的一部分。

Hatch 負責確定性安裝。設定精靈負責技術員和客戶的選擇。成功的安裝應該以清晰的交接結尾：

```bash
monoclaw --version
monoclaw setup
```

## 安全預設值

- 對每個生命週期指令，試運行（dry-run）是預設模式；真正的主機變更需要明確的 `--apply`。
- 在替換執行環境檔案前，必須先停止現有服務。
- 必須保留現有的 `~/.monoclaw/.env`、`~/.monoclaw/config.yaml`、`~/.monoclaw/customer` 和技術員自建的 skills。
- 密鑰、客戶資料、配置日誌、模型權重和 vendor 安裝包絕對不能提交到 `monoclaw-developer`。
