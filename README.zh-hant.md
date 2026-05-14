# MonoClaw Developer

> **譯本資訊**
> **原文：** `README.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

`monoclaw-developer` 是 MonoClaw 工程協調工作區。它不會納入同層倉庫或使用 git 子模組。相反，它負責管理工作區清單、引導腳本、Hatch 安裝器腳手架、編碼代理 skills，以及協調執行環境、網站和未來工具倉庫的實施計劃。

## 工作區佈局

從此倉庫根目錄運行引導腳本。它會在 `/Users/admin/Projects` 下創建或更新預期的同層檢出。

```text
Projects/
  monoclaw-developer/   # 此協調器倉庫
  monoclaw-runtime/     # MonoClaw 執行環境
  monoclaw-web/         # 網站、結帳、儀表板、文件
  scuttle-reference/    # 舊安裝器的唯讀歷史參考克隆
```

Hatch 最初位於此倉庫內的 `hatch/` 目錄中，以便安裝器規劃、腳本和代理指令可以一起演進。如果 Hatch 日後成為獨立產品倉庫，請將它加入 `workspace.manifest.json` 並更新工作區檔案。

## 首次運行

```bash
bash scripts/bootstrap-workspace.sh --dry-run
bash scripts/bootstrap-workspace.sh
bash scripts/status-workspace.sh
```

引導完成後，在 Cursor 中打開 `monoclaw.code-workspace`，即可在一個視窗中同時處理執行環境、網站、Hatch 和參考安裝器。

## 倉庫角色

- `monoclaw-runtime`：本地優先的 MonoClaw 代理執行環境。
- `monoclaw-web`：現有的 Next.js 16 / React 19 網站、結帳、儀表板、法律內容和 Supabase 架構。
- `scuttle-reference`：捆綁、launchd、就緒檢查和離線包佈局的私有歷史參考。用它來研究配置合約、launchd 處理、就緒檢查和離線包佈局。不要盲目複製舊引擎的假設。
- `hatch`：供技術員在恢復出廠設定的 Mac 上配置 MonoClaw、本地推理依賴、skills、工具和模型權重的新安裝器腳手架。

## 產品真相

刷新政策位於 `docs/product-truth-and-attribution.md`。面向用戶的表面應顯示 MonoClaw；Hermes/Nous 來源僅保留在法律和上游歸屬檔案中。

## 網站指令

當前網站技術棧使用 Next.js 16、React 19、npm、Supabase、Playwright 和 Vitest。在 `../monoclaw-web` 中有用的驗證指令：

```bash
npm ci
npm run test
npm run build
```

Supabase 本地驗證需要 Docker Desktop 和項目環境值，因此將數據庫煙霧測試視為獨立的門控工作流程。

## 公開倉庫安全

此倉庫是公開的。請勿包含客戶數據、密鑰、配置日誌、`.env` 檔案、OpenRouter key、Telegram token、Supabase 憑證、模型權重、vendor 安裝包和機器專屬的運行時輸出。
