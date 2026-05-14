# MonoClaw Wiki Translation Glossary

> **版本：** 1.0.0
> **基于提交：** `e909e16`
> **生效日期：** 2026-05-14
> **适用范围：** `docs/` 与 `hatch/docs/` 下所有 Markdown 文档的简体中文（zh-hans）及繁体中文（zh-hant）译本

---

## 1. 通用原则

1. **产品名保留英文**：MonoClaw、Hatch、Mona、Scuttle 永不翻译。
2. **命令与路径保留原文**：`monoclaw setup`、`~/.monoclaw`、`dist/hatch-manifest.json` 等。
3. **环境变量名保留原文**：`HATCH_SKIP_HOMEBREW_INSTALL`、`MONOCLAW_CONFIRM_FRESH_INSTALL_RESET` 等。
4. **代码块整体保留**：块内注释可译，但命令、输出、文件路径保持原样。
5. **品牌名保留英文**：Homebrew、LM Studio、Docker Desktop、Xcode、Telegram、Slack、WhatsApp、Apple Silicon、Gemma、Playwright、Vitest、Next.js、React、Supabase 等。
6. **技术标识符保留原文**：PEP 427、SHA-256、JSON key、launchd 等。
7. **数字与日期**：阿拉伯数字不变；日期格式跟随各语言地区惯例（简体多用 YYYY-MM-DD，香港繁体亦可用 YYYY-MM-DD 或 DD/MM/YYYY）。
8. **标点符号**：
   - 简体中文使用中文全角标点 `，。：；「」`。
   - 繁体中文（香港）使用中文全角标点 `，。：；「」`，括号用 `（）`。

---

## 2. 核心术语对照表

| 英文术语 | 简体中文 (zh-hans) | 繁体中文—香港 (zh-hant) | 备注 |
|---------|-------------------|------------------------|------|
| technician | 技术员 | 技術員 | 指为客户配置 Mac 的技术人员 |
| provisioning | 配置部署 | 配置部署 | 泛指将 Mac 配置为可运行 MonoClaw 的全过程 |
| factory-reset Mac | 恢复出厂设置的 Mac | 恢復出廠設定的 Mac | |
| non-technical office worker | 非技术办公室职员 | 非技術辦公室職員 | 产品的最终用户 |
| customer | 客户 | 客戶 | |
| work order | 工作单 | 工作單 | 技术员的任务指令 |
| handoff | 交接 | 交接 | 由 Hatch 移交给 `monoclaw setup` 的步骤 |
| runtime | 运行时 | 執行環境 | 若上下文强调环境本身，zh-hant 可保留英文 runtime |
| bundle | 预置包 | 預置包 | 亦可称「安装包」但需统一 |
| prepared bundle | 预置安装包 | 預置安裝包 | 强调已准备就绪的离线包 |
| target Mac | 目标 Mac | 目標 Mac | 最终客户的机器 |
| assembly machine | 组装机 | 組裝機 | 构建预置包的技术员机器 |
| assembly environment | 组装环境 | 組裝環境 | |
| provisioning medium | 配置介质 | 配置介質 | 通常为 pendrive / 外置硬盘 |
| manifest | 清单 | 清單 | `hatch-manifest.json` 等 |
| artifact | 构件 | 構件 | 构建产物 |
| sidecar | 附属组件 | 附屬組件 | 与主包并排部署的附加包（如 model pack、tools pack） |
| model pack | 模型包 | 模型包 | |
| tools pack | 工具包 | 工具包 | |
| wheelhouse | wheel 仓库 | wheel 倉庫 | Python wheel 集合，保留 wheel 不译 |
| dry-run | 试运行 | 試運行 | 默认模式，不真正修改系统 |
| apply | 应用变更 | 應用變更 | `--apply` 的实际含义 |
| rerun | 重新运行 | 重新運行 | 强调可重复执行 |
| cleanup | 清理 | 清理 | |
| local inference | 本地推理 | 本地推理 | 在本地运行 AI 模型 |
| hosted provider | 托管服务商 | 托管服務商 | 云端 AI 服务 |
| sandboxed tools | 沙盒工具 | 沙盒工具 | |
| secrets | 密钥 / 机密资料 | 密鑰 / 機密資料 | 指 API key、token 等 |
| credentials | 凭证 | 憑證 | |
| launchd service | launchd 服务 | launchd 服務 | 保留 launchd |
| plist | plist | plist | Property List，保留原文 |
| shim | 命令转发器 | 命令轉發器 | `~/.local/bin/monoclaw` 指向 venv 的轻量脚本 |
| venv / virtual environment | 虚拟环境 | 虛擬環境 | |
| opt-in | 主动选择启用 | 主動選擇啟用 | |
| fallback | 回退方案 | 回退方案 | |
| bench / bench test | 基准测试 | 基準測試 | 文中的 bench 指技术员的反复测试 |
| idempotent | 幂等的 | 冪等的 | 多次执行结果相同 |

---

## 3. 文档标题专用术语

| 英文标题/章节 | 简体中文 | 繁体中文—香港 |
|--------------|---------|-------------|
| Product Truth And Attribution | 产品真相与归属 | 產品真相與歸屬 |
| Product Truth | 产品真相 | 產品真相 |
| Attribution Rule | 归属规则 | 歸屬規則 |
| Repository Responsibilities | 仓库职责 | 倉庫職責 |
| Change Control | 变更控制 | 變更控制 |
| Hatch Provisioning Contract | Hatch 配置部署合约 | Hatch 配置部署合約 |
| Managed By Hatch | 由 Hatch 管理 | 由 Hatch 管理 |
| Manual Or Semi-Manual Prerequisites | 手动或半手动前置条件 | 手動或半手動前置條件 |
| Managed Paths | 管理路径 | 管理路徑 |
| Prepared Bundle Contract | 预置包合约 | 預置包合約 |
| Safety Defaults | 安全默认值 | 安全預設值 |
| Hatch Runtime Artifacts | Hatch 运行时构件 | Hatch 執行環境構件 |
| Assembly Happy Path | 组装标准流程 | 組裝標準流程 |
| Prepared Bundle Layout | 预置包目录结构 | 預置包目錄結構 |
| Manifest Contract | 清单合约 | 清單合約 |
| Installed Runtime Layout | 已安装运行时目录结构 | 已安裝執行環境目錄結構 |
| Runtime Bootstrap Contract | 运行时引导合约 | 執行環境引導合約 |
| Target Mac Prerequisites | 目标 Mac 前置条件 | 目標 Mac 前置條件 |
| Verification Contract | 验证合约 | 驗證合約 |
| MonoClaw Technician Provisioning Handbook | MonoClaw 技术员配置手册 | MonoClaw 技術員配置手冊 |
| Pre-Flight Checklist | 出发前检查清单 | 出發前檢查清單 |
| Expected Output | 预期输出 | 預期輸出 |
| Post-Install Verification | 安装后验证 | 安裝後驗證 |
| Customer-Specific Setup | 客户专属设置 | 客戶專屬設定 |
| Recovery & Reruns | 恢复与重新运行 | 恢復與重新運行 |
| Handoff Checklist | 交接检查清单 | 交接檢查清單 |
| Quick Reference | 快速参考 | 快速參考 |
| Hatch Verification Gates | Hatch 验证门控 | Hatch 驗證門控 |
| Repo Gate | 仓库门控 | 倉庫門控 |
| Assembly Gate | 组装门控 | 組裝門控 |
| Runtime Gate | 运行时门控 | 執行環境門控 |
| Web Gate | 网站门控 | 網站門控 |
| Physical Bench Gate | 实体测试门控 | 實體測試門控 |

---

## 4. 香港繁体中文特别说明

香港 IT 行业习惯中英夹杂，以下情况可保留英文：

- 无通用中文译名或中文译名反而降低清晰度的技术术语：
  - `bundle` → 可保留 bundle（尤其在口语化说明中）
  - `runtime` → 可保留 runtime
  - `sidecar` → 可保留 sidecar
  - `dry-run` → 可保留 dry-run
  - `wheel` → 保留 wheel
  - `prompt` → 保留 prompt
- 文件扩展名：`.dmg`、`.pkg`、`.gguf`、`.yaml`、`.env` 等不译。
- 路径与命令行片段保持原样。

若保留英文术语，**首次出现**应在括号内给出中文对照，例如：

> 预置包（prepared bundle）须包含所有运行时依赖。

---

## 5. 简体中文特别说明

- 使用中国大陆标准技术用语，避免台湾或香港用词。
- 软件/软件（非軟體）、网络/网络（非網路）、文件/文件（非檔案）。
- 设置/设置（非設定）、默认/默认（非預設）。
- 程序/程序（在 IT 语境下；「程式」为台湾用法）。

---

## 6. 版本控制

| 版本 | 日期 | 变更说明 |
|------|------|---------|
| 1.0.0 | 2026-05-14 | 初始版本，覆盖 P0–P2 文档核心术语 |

新增或修改术语时，请在此文件更新，并同步检查所有正在翻译的文档。
