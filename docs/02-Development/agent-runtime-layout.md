# 工作目录与运行入口

日常协作从 `Ship_of_Theseus` 游戏主仓或其任务工作树启动，读取游戏仓的 `AGENTS.md`、`.codex/config.toml` 和 `.agents/skills/`。KB 自 2026-10-29 起是游戏仓的 `docs/`（Ship #90），不再是独立仓库。

```text
<project-root>/
  Ship_of_Theseus/              游戏主仓与默认入口
    docs/                       KB，同时是 Obsidian vault（Obsidian 打开主工作树的这一目录）
    .worktrees/<task>/          游戏任务工作树；KB 文档在其中的 docs/ 随任务修改
  SoT-fyc-space/                结构化设计主仓
    .worktrees/<task>/          设计库任务工作树
```

两个主仓互为同级目录。任务工作树与另一个主仓没有固定相邻关系；跨仓访问不得用当前工作树的 `../` 猜测目标。

## 明确配置根目录

先读取环境变量 `SOT_SHIP_ROOT`、`SOT_DESIGNLIB_ROOT`；未设置时读取当前 checkout 被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots]` 的 `ship_root`、`designlib_root`。旧配置中残留的 `kb_root` 会被忽略。

`[worktrees]` 的 `ship_root`、`designlib_root` 指向各仓工作树分组目录（`<仓库根>/.worktrees`），不能把这些分组目录当成 Git 仓库根。可用对应的 `SOT_SHIP_WORKTREE_ROOT`、`SOT_DESIGNLIB_WORKTREE_ROOT` 覆盖。新建任务工作树时同步这份本机配置；机器路径不写入版本控制文件。

游戏脚本 `scripts/codex/sot-worktree.ps1` 提供 List、Inspect、Create。KB 写入在游戏任务工作树的 `docs/` 中进行，与相关改动同一个 PR（见 `sot-kb-write`）。工作树退役流程见游戏仓 `docs/worktree-lifecycle.md`。

## 运行绑定

- Godot MCP 默认绑定游戏主仓；任务不会自行改变全局绑定。
- Obsidian MCP 绑定主工作树的 `docs/`，只用于浏览与检索；它看不到任务分支上未合并的修改。
- 设计库 gate 使用 `SOT_GODOT_PATH` 和 `SOT_KB_PATH` 明确指定跨仓读取目标（`SOT_KB_PATH` 指向游戏仓的 `docs/`）；`SOT_DESIGNLIB_PATH` 不全局固定，以便默认读取当前设计工作树。
- 规则目录输出使用 `SOT_RULES_CATALOG`；设计书同步来源使用 `SOT_SYNC_SRC`。工作树必须明确设置它们，不能依赖主仓同级目录回退。NAS 设计书同步原由旧 KB 仓库的 post-commit 钩子触发，现已暂停，待设计库并入后重新连接。
- Codex 用户配置位于 `$HOME/.codex/`，当前项目配置与技能位于项目 `.codex/` 和 `.agents/skills/`。
