# Hatch 验证门控

> **译本信息**
> **原文：** `hatch/docs/verification-gates.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

## 仓库门控

在移交 Hatch 脚本变更前执行：

```bash
bash tests/run_tests.sh
bash bin/hatch --dry-run preflight
bash -n bin/hatch
```

这会检查 shell 语法、以清单为基础的 `preflight`、`install`、`verify`、`verify-local-inference`、`doctor` 的试运行生命周期测试，以及可选的模型包和工具包命令，还有无标志的 `build.sh` 和使用 fixture bundle 输入的生成安装包装器。

## 组装门控

在制作生产配置介质前，从 `/Users/admin/Projects/hatch` 运行真正的组装器，并在 `/Users/admin/Projects/hatch/bundle-inputs/` 中预备生产输入：

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

当 Mona 秘书工具启用时（默认），`./build.sh` 会在 `dist/` 旁边留下 `tool-packs/mona-secretary-tools/`，其中包含 `tools-pack-manifest.json`。除非你故意以 `HATCH_INCLUDE_MONA_TOOLS=0` 构建，否则在复制介质前确认该目录存在。

记录 bundle ID、bundle 版本和 `dist/hatch-manifest.json` 的 SHA-256 作为发布证据。如果存在模型包，也记录 `model-packs/gemma-4-e4b/model-pack-manifest.json` 的 SHA-256。如果存在 Mona 工具包，也记录 `tool-packs/mona-secretary-tools/tools-pack-manifest.json` 的 SHA-256。请勿提交 `dist/`、`bundle-inputs/`、`model-packs/`、`tool-packs/`、模型权重或 vendor 安装包。

## 运行时门控

在运行时包装、依赖配置文件或品牌重塑变更后，从 `../monoclaw-runtime` 运行：

```bash
scripts/run_tests.sh tests/test_project_metadata.py::test_local_office_extra_is_customer_bundle_profile -q
scripts/run_tests.sh tests/monoclaw_cli/test_banner.py::test_build_welcome_banner_uses_monoclaw_branding_not_upstream_vendor -q
```

如果运行时尚无虚拟环境，请在声称这些测试通过前创建或附加标准运行时 venv。

## 网站门控

在网站、法律、译本或合约变更后，从 `../monoclaw-web` 运行：

```bash
python3 -m json.tool messages/en.json >/dev/null
python3 -m json.tool messages/zh-hans.json >/dev/null
python3 -m json.tool messages/zh-hant.json >/dev/null
npm run generate-contract-seed
npm run test
npm run build
```

Supabase 重置和数据库冒烟测试是独立的门控工作流程，因为它们需要 Docker 和本地 Supabase 服务。

## 文档译本门控

在新增或修改 `docs/` 或 `hatch/docs/` 中的 wiki 文档后，从 `monoclaw-developer` 根目录运行：

```bash
# 列出缺少 zh-hans 或 zh-hant 译本的英文 wiki 文件。
# 豁免文件：README（面向开发者）、TRANSLATION-GLOSSARY.md、TRANSLATION-TEMPLATE.md、.plan.md（实施计划）。
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

预期：当所有 P0–P2 文档都已完整翻译时，无输出。如果新英文文档故意只提供英文版，请将它加入上方豁免清单，或开立标记为 `translation-drift` 的跟进 issue。

## 实体测试门控

在发布前，在一台专用的 Apple Silicon Mac 上使用预置包运行 Hatch，并记录：

- Hatch 命令、bundle ID、bundle 版本和清单哈希值。
- `hatch --dry-run --bundle-root <dist> doctor` 输出。
- 从复制到随身碟的 `dist/` 目录执行真正的 `./install.sh` 输出。
- 当随身碟包含 `model-packs/gemma-4-e4b/` 时，可选的 `./install-gemma-model.sh` 输出。
- 当随身碟在 `dist/` 旁边包含 `tool-packs/mona-secretary-tools/` 时的 Mona 秘书工具后续步骤（`dist/install-mona-tools.sh`）（从组装机同时复制两者）。
- 当本地推理是测试场景的一部分时，手动 LM Studio `.dmg` 安装和首次启动/导入笔记。
- 当在测试机上故意设定 `MONOCLAW_CONFIRM_FRESH_INSTALL_RESET=1` 时的恢复出厂设置重新执行输出。
- 重新启动后的 `hatch verify` 输出，以及在配置了本地推理时的 `hatch verify-local-inference` 输出。
- 经过编辑的 `~/.monoclaw/logs` 尾部和 launchd 摘要。

请勿记录客户密钥、Telegram token、托管服务商 API key、模型权重或原始对话内容。
