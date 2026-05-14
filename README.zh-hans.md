# MonoClaw Developer

> **译本信息**
> **原文：** `README.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

`monoclaw-developer` 是 MonoClaw 工程协调工作区。它不会纳入同层仓库或使用 git 子模块。相反，它负责管理工作区清单、引导脚本、Hatch 安装器脚手架、编码代理 skills，以及协调运行时、网站和未来工具仓库的实施计划。

## 工作区布局

从此仓库根目录运行引导脚本。它会在 `/Users/admin/Projects` 下创建或更新预期的同层检出。

```text
Projects/
  monoclaw-developer/   # 此协调器仓库
  monoclaw-runtime/     # MonoClaw 运行时
  monoclaw-web/         # 网站、结账、仪表板、文档
  scuttle-reference/    # 旧安装器的只读历史参考克隆
```

Hatch 最初位于此仓库内的 `hatch/` 目录中，以便安装器规划、脚本和代理指令可以一起演进。如果 Hatch 日后成为独立产品仓库，请将它加入 `workspace.manifest.json` 并更新工作区文件。

## 首次运行

```bash
bash scripts/bootstrap-workspace.sh --dry-run
bash scripts/bootstrap-workspace.sh
bash scripts/status-workspace.sh
```

引导完成后，在 Cursor 中打开 `monoclaw.code-workspace`，即可在一个窗口中同时处理运行时、网站、Hatch 和参考安装器。

## 仓库角色

- `monoclaw-runtime`：本地优先的 MonoClaw 代理运行时。
- `monoclaw-web`：现有的 Next.js 16 / React 19 网站、结账、仪表板、法律内容和 Supabase 架构。
- `scuttle-reference`：捆绑、launchd、就绪检查和离线包布局的私有历史参考。用它来研究配置合约、launchd 处理、就绪检查和离线包布局。不要盲目复制旧引擎的假设。
- `hatch`：供技术员在恢复出厂设置的 Mac 上配置 MonoClaw、本地推理依赖、skills、工具和模型权重的新安装器脚手架。

## 产品真相

刷新政策位于 `docs/product-truth-and-attribution.md`。面向用户的表面应显示 MonoClaw；Hermes/Nous 来源仅保留在法律和上游归属文件中。

## 网站命令

当前网站技术栈使用 Next.js 16、React 19、npm、Supabase、Playwright 和 Vitest。在 `../monoclaw-web` 中有用的验证命令：

```bash
npm ci
npm run test
npm run build
```

Supabase 本地验证需要 Docker Desktop 和项目环境值，因此将数据库冒烟测试视为独立的门控工作流程。

## 公开仓库安全

此仓库是公开的。请勿包含客户数据、密钥、配置日志、`.env` 文件、OpenRouter key、Telegram token、Supabase 凭证、模型权重、vendor 安装包和机器专属的运行时输出。
