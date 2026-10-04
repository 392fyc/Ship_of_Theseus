# SoT 工作区与工作树

日常 Codex 入口是游戏主仓 `Ship_of_Theseus`。三个主仓平级，任务工作树按所属仓库分组；这是目录关系，实际根路径由本机配置提供：

```text
<project-root>/
  Ship_of_Theseus/             游戏主仓，日常入口
  ShipOfTheseus-KB/            固定 Obsidian vault
  SoT-fyc-space/               设计库主仓
  worktrees/
    Ship_of_Theseus/<task>/
    SoT-fyc-space/<task>/
    ShipOfTheseus-KB/<task>/   历史/显式只读隔离用途；不是第二个 vault
```

任务工作树不能用父目录或 `../<另一个仓库>` 猜测跨仓位置。先解析环境变量，再回退到当前游戏工作区被忽略的 `.codex/project/sot-roots.local.toml`。若环境仍指向旧位置，应修正进程环境或重启客户端，不能因旧路径不存在而猜另一个位置。

| 用途 | 配置键 | 优先环境变量 |
|---|---|---|
| 游戏主仓/共享脚本入口 | `[roots].ship_root` | `SOT_SHIP_ROOT` |
| 设计库主仓 | `[roots].designlib_root` | `SOT_DESIGNLIB_ROOT` |
| 固定 KB vault | `[roots].kb_root` | `SOT_KB_ROOT` |
| 活跃记忆根（可选；未配置时使用游戏仓主 Git 工作树的 `.sot/memory`） | `[roots].memory_root` | `SOT_MEMORY_ROOT` |
| 游戏任务目录组 | `[worktrees].ship_root` | `SOT_SHIP_WORKTREE_ROOT` |
| 设计库任务目录组 | `[worktrees].designlib_root` | `SOT_DESIGNLIB_WORKTREE_ROOT` |
| KB 历史工作树目录组 | `[worktrees].kb_root` | `SOT_KB_WORKTREE_ROOT` |

参照 `../.codex/project/sot-roots.example.toml` 填写本地配置，不提交实际路径。已有旧分支可能没有新脚本，可从解析出的游戏主仓调用同一入口；不要为了获取脚本切换或覆盖任务分支。

## 列出、检查与创建

PowerShell 7 中，从当前游戏工作区调用以下入口，或使用已解析游戏主仓中的同一脚本：

```powershell
./scripts/codex/sot-worktree.ps1 -Action List
./scripts/codex/sot-worktree.ps1 -Action Inspect -Repository ship -Task example-task -BaseRef refs/remotes/origin/develop
./scripts/codex/sot-worktree.ps1 -Action Create -Repository ship -Task example-task -Branch codex/example-task -BaseRef refs/remotes/origin/develop
./scripts/codex/sot-worktree.ps1 -Action Create -Repository designlib -Task example-task -Branch codex/example-task -BaseRef refs/remotes/origin/master
```

`List` 返回三库实际 Git 登记，包括未处于预期目录组的工作树。`Inspect` 只读显示 HEAD、分支、普通状态、ignored 文件、隐藏修改的索引标志，以及指定基准之后的提交数。它不联网，也不把上述信息自动解释成删除许可。

`Create` 需要明确的新任务名、分支名与本地存在的起点提交。它不会 fetch、重用已有目录、覆盖分支或切换主仓分支。成功后把本次解析出的 roots/worktrees 配置（`memory_root` 仅在已配置时）写入新树被忽略的本地 roots 文件；若本地配置写入失败，保留已创建工作树并报告，不能自动强制回滚删除。它不会复制其他 dirty 文件、凭据、数据库或用户资料。

创建后仍应读取目标仓指令与 canonical 合同，遵守既有独立审查、跨仓发布与数据写入授权。KB 日常写入只在固定 vault 当前任务分支中进行：`Create -Repository kb` 明确拒绝，`List/Inspect` 可查看 KB 的已有 Git 工作树；不得把它们另开成 vault 或为释放分支自动删除。

## 收尾与退役

任务完成与工作树可以删除应分别判断。收尾记录 HEAD、实际分支、PR/任务状态、未提交内容和下一步。工作树继续承载任务或存在需保留成果时保留，不因会话结束自动清理。

确定要退役的精确清单后，至少核对：

1. 无活跃使用、锁定或其他任务占用，路径属于正确仓库，主工作树不在清理清单。
2. staged/unstaged/untracked 均无需保留内容；检查 assume-unchanged/skip-worktree，不能只看普通状态。
3. ignored 文件逐项分类。图像原料、数据库、UID、审查记录等不能按目录名当缓存；需保留的内容先归档，逐文件核验哈希。
4. 当前 HEAD 已进入实际集成分支；squash/rebase 场景核对 PR head、合并提交及内容等价，检查 PR 合并后有无新增本地提交。工作树年龄、分支名字、没有开放 PR、PR 关闭或合并单独都不是足够依据。
5. 保留所有分支/迁移 refs，并记录原值；归档必要内容及 Git bundle 后验证可恢复性。工作树退役不自动授权删除分支。
6. 获准执行具体清单后，删除前重检状态，逐树使用非 force 的 `git worktree remove`；出现保护属性、链接、占用或新改动时停止。只允许核实身份的 Git 管理元数据由 Git 正常处理，不把例外扩展到普通隐藏文件。
7. 回读目录和 Git 登记，核对 refs、保留工作树、dirty 与归档哈希。未完成的项不能报告为已清理。

本脚本不提供删除、force、prune 或按年龄自动清理入口；退役按上述人工可审查清单执行。现有发布仍使用 `sot-publish.ps1`，不要绕过受控入口直接推送。
