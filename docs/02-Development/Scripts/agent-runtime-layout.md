# 三仓工作目录与运行入口

日常三仓协作从 `Ship_of_Theseus` 游戏主仓或其任务工作树启动，读取游戏仓的 `AGENTS.md`、`.codex/config.toml` 和 `.agents/skills/`。

```text
<project-root>/
  Ship_of_Theseus/              游戏主仓与默认入口
  ShipOfTheseus-KB/              唯一固定 Obsidian vault
  SoT-fyc-space/                 结构化设计主仓
  worktrees/
    Ship_of_Theseus/<task>/
    ShipOfTheseus-KB/<task>/
    SoT-fyc-space/<task>/
```

三个主仓互为同级目录。任务工作树与另两个主仓没有固定相邻关系；跨仓访问不得用当前工作树的 `../` 猜测目标。

## 明确配置根目录

先读取环境变量 `SOT_SHIP_ROOT`、`SOT_KB_ROOT`、`SOT_DESIGNLIB_ROOT`、`MERCURY_ROOT`；未设置时读取当前 checkout 被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots]` 的 `ship_root`、`kb_root`、`designlib_root`、`mercury_root`。

`[worktrees]` 的 `ship_root`、`kb_root`、`designlib_root` 指向各仓工作树分组目录，不能把这些分组目录当成 Git 仓库根。可用对应的 `SOT_SHIP_WORKTREE_ROOT`、`SOT_KB_WORKTREE_ROOT`、`SOT_DESIGNLIB_WORKTREE_ROOT` 覆盖。新建任务工作树时同步这份本机配置；机器路径不写入版本控制文件。

游戏脚本 `scripts/codex/sot-worktree.ps1` 提供 List、Inspect、Create；Create 使用指定仓库的分组目录。KB 日常写入仍在固定 vault 的任务分支进行，不通过新增 vault 隔离任务。工作树退役流程见 `03-AI-Context/Handoffs/git-sync-procedure.md`。

## 运行绑定

- Godot MCP 默认绑定游戏主仓；任务不会自行改变全局绑定。
- Obsidian MCP 始终绑定 `kb_root`。已有改动或分支占用按 `sot-kb-write` 处理。
- 设计库 gate 使用 `SOT_GODOT_PATH` 和 `SOT_KB_PATH` 明确指定跨仓读取目标；`SOT_DESIGNLIB_PATH` 不全局固定，以便默认读取当前设计工作树。
- 规则目录输出使用 `SOT_RULES_CATALOG`；设计书同步来源使用 `SOT_SYNC_SRC`。工作树必须明确设置它们，不能依赖主仓同级目录回退。路径检查不代表执行同步或发布。
- Codex 用户配置位于 `$HOME/.codex/`，当前项目配置与技能位于项目 `.codex/` 和 `.agents/skills/`。

## 可选旧版工具

`02-Development/Scripts/new-*-bundle.ps1` 是旧版共享生成器的薄包装，按当前用户目录查找 `$HOME/.agents/ship-kb-tools/`。只有本机安装了对应生成器才可调用；缺失时明确报错。它们不是当前 Codex 原生协作流程的必需组件。
