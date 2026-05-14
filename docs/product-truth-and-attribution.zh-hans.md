# MonoClaw 产品真相与归属

> **译本信息**
> **原文：** `docs/product-truth-and-attribution.md`
> **基于提交：** `e909e16`
> **语言：** 简体中文（中国大陆）
> **最后更新：** 2026-05-14

## 目的

MonoClaw 是为香港办公室职员提供的技术员配置行政秘书服务。客户体验是在本地运行 MonoClaw 的托管 Mac mini 或 iMac，文档和运营支持专为非技术用户而设。

本文是本次刷新的跨仓库规则。它在替换旧引擎故事时，保持运行时、Hatch 安装器、网站、法律内容和运营文档的一致性。

## 产品真相

- 面向用户的名称、命令、文档、截图、合约、支持文案和运营检查清单必须显示 **MonoClaw**。
- Hatch 是刷新后服务面向技术员的安装器和配置工作流程。
- 客户 Mac 应被描述为本地优先系统：捆绑的运行时、捆绑的本地推理支持、捆绑的 skills，以及对任何云服务商或第三方集成的明确主动选择启用（opt-in）。
- 默认客户故事是实用的办公室协助：消息、日历、文档、研究、浏览器辅助工作流程、提醒和引导式行政工作。
- 声明必须区分组装时需求与目标 Mac 需求。用于构建预备安装包的 Homebrew 或网络拉取并非客户运行时依赖。

## 归属规则

MonoClaw Runtime 衍生自 Nous Research Hermes Agent，并受 MIT 许可证约束。该来源必须保留在法律和上游归属文件中。

允许的 Hermes/Nous 引用：

- `monoclaw-runtime/LICENSE`
- `monoclaw-runtime/NOTICE.md`
- `monoclaw-runtime/UPSTREAM.md`
- 第三方许可证文件和不可变的上游审计笔记

禁止的 Hermes/Nous 引用：

- 营销页面、入门引导、文档、截图、支持文案和运营手册
- CLI 横幅、帮助文本、设置文案、安装器提示和网关消息
- 网站结账文案、合约、译本和管理界面标签
- 新的 Hatch 日志，除非检测到旧版安装；在面向技术员的消息中使用 `legacy runtime`

## 仓库职责

- `monoclaw-developer` 拥有此政策、Hatch 脚手架、运营计划和跨仓库协调。
- `monoclaw-runtime` 拥有 MonoClaw 运行时、CLI、网关、工具集、包装元数据、捆绑 skills 和运行时文档。
- `monoclaw-web` 拥有产品网站、结账/管理界面、法律 HTML、Supabase 迁移和公开/运营文档。
- `scuttle-reference` 仍为捆绑、launchd、重置和基准测试模式的私有历史参考。不要在刷新的客户文案中将 Scuttle 暴露为产品名称。

## 变更控制

当产品声明、安装器行为、法律文案或合约形态数据变更时，在同一分支中更新所有受影响的表面：

1. 本政策或更具体的实施合约。
2. 运行时行为和文档。
3. Hatch 安装器行为和运营文档。
4. 网站营销、法律来源 HTML、译本和 Supabase 种子数据。
5. 验证该声明的门控（gates）。

不要发布仅在一个仓库中为真的声明。
