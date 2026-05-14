# MonoClaw 產品真相與歸屬

> **譯本資訊**
> **原文：** `docs/product-truth-and-attribution.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

## 目的

MonoClaw 是為香港辦公室職員提供的技術員配置行政秘書服務。客戶體驗是在本地運行 MonoClaw 的托管 Mac mini 或 iMac，文件和運營支援專為非技術用戶而設。

本文是本次更新的跨倉庫規則。它在替換舊引擎故事時，保持執行環境、Hatch 安裝器、網站、法律內容和運營文件的一致性。

## 產品真相

- 面向用戶的名稱、指令、文件、截圖、合約、支援文案和運營檢查清單必須顯示 **MonoClaw**。
- Hatch 是更新後服務面向技術員的安裝器和配置工作流程。
- 客戶 Mac 應被描述為本地優先系統：捆綁的執行環境、捆綁的本地推理支援、捆綁的 skills，以及對任何雲端服務商或第三方整合的明確主動選擇啟用（opt-in）。
- 預設客戶故事是實用的辦公室協助：訊息、日曆、文件、研究、瀏覽器輔助工作流程、提醒和引導式行政工作。
- 聲明必須區分組裝時需求與目標 Mac 需求。用於構建預備安裝包的 Homebrew 或網絡拉取並非客戶執行環境依賴。

## 歸屬規則

MonoClaw Runtime 衍生自 Nous Research Hermes Agent，並受 MIT 許可證約束。該來源必須保留在法律和上游歸屬文件中。

允許的 Hermes/Nous 引用：

- `monoclaw-runtime/LICENSE`
- `monoclaw-runtime/NOTICE.md`
- `monoclaw-runtime/UPSTREAM.md`
- 第三方許可證文件和不可變的上游審計筆記

禁止的 Hermes/Nous 引用：

- 營銷頁面、入門引導、文件、截圖、支援文案和運營手冊
- CLI 橫幅、說明文字、設定文案、安裝器提示和閘道訊息
- 網站結帳文案、合約、譯本和管理介面標籤
- 新的 Hatch 日誌，除非檢測到舊版安裝；在面向技術員的訊息中使用 `legacy runtime`

## 倉庫職責

- `monoclaw-developer` 擁有此政策、Hatch 腳手架、運營計劃和跨倉庫協調。
- `monoclaw-runtime` 擁有 MonoClaw 執行環境、CLI、閘道、工具集、包裝元數據、捆綁 skills 和執行環境文件。
- `monoclaw-web` 擁有產品網站、結帳/管理介面、法律 HTML、Supabase 遷移和公開/運營文件。
- `scuttle-reference` 仍為捆綁、launchd、重置和基準測試模式的私有歷史參考。不要在更新的客戶文案中將 Scuttle 暴露為產品名稱。

## 變更控制

當產品聲明、安裝器行為、法律文案或合約形態數據變更時，在同一分支中更新所有受影響的表面：

1. 本政策或更具體的實施合約。
2. 執行環境行為和文件。
3. Hatch 安裝器行為和運營文件。
4. 網站營銷、法律來源 HTML、譯本和 Supabase 種子數據。
5. 驗證該聲明的門控（gates）。

不要發布僅在一個倉庫中為真的聲明。
