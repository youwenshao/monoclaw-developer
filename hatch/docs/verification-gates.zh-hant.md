# Hatch 驗證門控

> **譯本資訊**
> **原文：** `hatch/docs/verification-gates.md`
> **基於提交：** `e909e16`
> **語言：** 繁體中文（香港）
> **最後更新：** 2026-05-14

## 倉庫門控

在移交 Hatch 腳本變更前執行：

```bash
bash tests/run_tests.sh
bash bin/hatch --dry-run preflight
bash -n bin/hatch
```

這會檢查 shell 語法、以清單為基礎的 `preflight`、`install`、`verify`、`verify-local-inference`、`doctor` 的試運行生命週期測試，以及可選的模型包和工具包指令，還有無標誌的 `build.sh` 和使用 fixture bundle 輸入的生成安裝包裝器。

## 組裝門控

在製作生產配置介質前，從 `/Users/admin/Projects/hatch` 運行真正的組裝器，並在 `/Users/admin/Projects/hatch/bundle-inputs/` 中預備生產輸入：

```bash
bash scripts/build_wheelhouse.sh
./build.sh
bash dist/bin/hatch --dry-run --bundle-root dist prepare-bundle
if [[ -d model-packs/gemma-4-e4b ]]; then
  bash dist/bin/hatch --dry-run --bundle-root dist --model-pack-root model-packs/gemma-4-e4b verify-model-pack
fi
if [[ -d tool-packs/mona-secretary-tools ]]; then
  test -f tool-packs/mona-secretary-tools/tools-pack-manifest.json
  bash dist/bin/hatch --dry-run --bundle-root dist --tools-pack-root tool-packs/mona-secretary-tools verify-tools-pack
fi
```

當 Mona 秘書工具啟用時（預設），`./build.sh` 會在 `dist/` 旁邊留下 `tool-packs/mona-secretary-tools/`，其中包含 `tools-pack-manifest.json`。除非你故意以 `HATCH_INCLUDE_MONA_TOOLS=0` 構建，否則在複製介質前確認該目錄存在。

記錄 bundle ID、bundle 版本和 `dist/hatch-manifest.json` 的 SHA-256 作為發布證據。如果存在模型包，也記錄 `model-packs/gemma-4-e4b/model-pack-manifest.json` 的 SHA-256。如果存在 Mona 工具包，也記錄 `tool-packs/mona-secretary-tools/tools-pack-manifest.json` 的 SHA-256。請勿提交 `dist/`、`bundle-inputs/`、`model-packs/`、`tool-packs/`、模型權重或 vendor 安裝包。

## 執行環境門控

在執行環境包裝、依賴配置檔或品牌重塑變更後，從 `../monoclaw-runtime` 運行：

```bash
scripts/run_tests.sh tests/test_project_metadata.py::test_local_office_extra_is_customer_bundle_profile -q
scripts/run_tests.sh tests/monoclaw_cli/test_banner.py::test_build_welcome_banner_uses_monoclaw_branding_not_upstream_vendor -q
```

如果執行環境檢出沒有虛擬環境，請在聲稱這些測試通過前創建或附加標準執行環境 venv。

## 網站門控

在網站、法律、譯本或合約變更後，從 `../monoclaw-web` 運行：

```bash
python3 -m json.tool messages/en.json >/dev/null
python3 -m json.tool messages/zh-hans.json >/dev/null
python3 -m json.tool messages/zh-hant.json >/dev/null
npm run generate-contract-seed
npm run test
npm run build
```

Supabase 重置和數據庫煙霧測試是獨立的門控工作流程，因為它們需要 Docker 和本地 Supabase 服務。

## 文件譯本門控

在新增或修改 `docs/` 或 `hatch/docs/` 中的 wiki 文件後，從 `monoclaw-developer` 根目錄運行：

```bash
# 列出缺少 zh-hans 或 zh-hant 譯本的英文 wiki 文件。
# 豁免文件：README（面向開發者）、TRANSLATION-GLOSSARY.md、TRANSLATION-TEMPLATE.md、.plan.md（實施計劃）。
for f in docs/*.md hatch/docs/*.md; do
  case "$(basename "$f")" in
    README.md|TRANSLATION-*.md|*.plan.md) continue ;;
  esac
  if [[ "$f" == *.zh-hans.md ]] || [[ "$f" == *.zh-hant.md ]]; then
    continue
  fi
  missing=""
  [[ -f "${f%.md}.zh-hans.md" ]] || missing="zh-hans"
  [[ -f "${f%.md}.zh-hant.md" ]] || missing="${missing:+$missing, }zh-hant"
  [[ -n "$missing" ]] && echo "[missing $missing] $f"
done
```

預期：當所有 P0–P2 文件都已完整翻譯時，無輸出。如果新英文文件故意只提供英文版，請將它加入上方豁免清單，或開立標記為 `translation-drift` 的跟進 issue。

## 實體測試門控

在發布前，在一台專用的 Apple Silicon Mac 上使用預置包運行 Hatch，並記錄：

- Hatch 指令、bundle ID、bundle 版本和清單雜湊值。
- `hatch --dry-run --bundle-root <dist> doctor` 輸出。
- 從複製到隨身碟的 `dist/` 目錄執行真正的 `./install.sh` 輸出。
- 當隨身碟包含 `model-packs/gemma-4-e4b/` 時，可選的 `./install-gemma-model.sh` 輸出。
- 當隨身碟在 `dist/` 旁邊包含 `tool-packs/mona-secretary-tools/` 時的 Mona 秘書工具後續步驟（`dist/install-mona-tools.sh`）（從組裝機同時複製兩者）。
- 當本地推理是測試場景的一部分時，手動 LM Studio `.dmg` 安裝和首次啟動/匯入筆記。
- 當在測試機上故意設定 `MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1` 時的恢復出廠設定重新執行輸出。
- 重新啟動後的 `hatch verify` 輸出，以及在配置了本地推理時的 `hatch verify-local-inference` 輸出。
- 經過編輯的 `~/.monoclaw/logs` 尾部和 launchd 摘要。

請勿記錄客戶密鑰、Telegram token、托管服務商 API key、模型權重或原始對話內容。
