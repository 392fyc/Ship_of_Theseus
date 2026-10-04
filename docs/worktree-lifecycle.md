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

`Create` 需要明确的新任务名、分支名与本地存在的起点提交。它不会 fetch、重用已有目录、覆盖分支或切换主仓分支。成功后把本次解析出的 roots/worktrees 配置（`memory_root` 仅在已配置时）写入新树被忽略的本地 roots 文件；进程环境中的覆盖值（包括 `SOT_MEMORY_ROOT`）同样会写入，临时指向其他记忆根时应在 Create 前清除。若本地配置写入失败，保留已创建工作树并报告，不能自动强制回滚删除。它不会复制其他 dirty 文件、凭据、数据库或用户资料。

创建后仍应读取目标仓指令与 canonical 合同，遵守既有独立审查、跨仓发布与数据写入授权。KB 日常写入只在固定 vault 当前任务分支中进行：`Create -Repository kb` 明确拒绝，`List/Inspect` 可查看 KB 的已有 Git 工作树；不得把它们另开成 vault 或为释放分支自动删除。

### 测试模式与预演

`sot-worktree.ps1 -IgnoreEnvironment` 只读取 `-RootsFile`，完全忽略 `SOT_*` 环境变量；审查和测试应配合临时 roots 文件使用，避免误写真实仓库。显式传入 `-RootsFile` 但未加该开关时，若有环境变量覆盖，会向 stderr 输出警告并列出变量名。`Create -DryRun` 完成全部校验后只输出计划（路径、分支、起点提交、将写入的本地 roots 内容），不建目录、分支或文件；目标分支已存在时失败，也不检查新树中的本地 roots 文件是否被忽略（该检查需要新树，仅在真实 Create 时执行）。

## 受控同步与活跃记忆

`sot-sync.ps1` 在 ship/designlib 任务工作树（或 KB 固定 vault 的任务分支）内把 `origin/<基准分支>` 以 `merge --no-ff` 合入当前分支，替代裸 `git merge`；只做 merge，不改写历史。基准默认：游戏仓 `develop`，设计库/KB 取 `origin` 的默认分支，解析不出时须传 `-BaseBranch`。`-DryRun` 预测冲突并报告 ahead/behind（脏工作区同样报告并以非零退出），冲突时列出冲突文件并保留合并状态，解决后用普通提交完成，或运行 `-Abort`（仅在合并进行中时执行 `git merge --abort`）。主工作区、`main/master/develop`、detached HEAD 与脏工作区一律拒绝；KB 只放行路径等于配置 `kb_root` 的固定 vault（须在任务分支上），KB 的链接工作树同样拒绝。`-DryRun` 仍会执行 `git fetch origin <基准分支>`（预测需要最新引用），除此之外不写入。显式传 `-RootsFile` 而被 `SOT_*` 覆盖时输出警告，`-IgnoreEnvironment` 可只读 roots 文件。

`sot-memory.ps1` 为活跃记忆提供版本条件（仅支持 Windows：跨进程索引锁依赖 Windows 的独占共享语义）；文件位于 `<记忆根>/projects/<bucket>/`，`index.jsonl` 的 `relative_path` 相对该目录，Windows 上拒绝含 `:` 的分段和 `CON`/`NUL`/`COM1` 等设备保留名。共享文件应读取后记下 sha256，再用 `-Action Write -Path <bucket 内相对路径> -SourceFile <新内容文件> -ExpectedSha256 <读取时哈希>` 一次完成：重算磁盘哈希、一致才原子替换并更新索引行，不一致则拒绝、不写盘并输出当前哈希（退出 1）；新文件用 `Write -CreateNew`，目标已存在即拒绝。若文件已替换但索引更新失败，输出 `written-index-stale` 与新哈希并以退出码 3 结束，随后用 `Record` 补登记。`-Action Verify -Path <路径>` 默认与 `index.jsonl` 比较并输出当前哈希（match / mismatch / unrecorded / missing；mismatch 退出 1，missing 退出 2），加 `-ExpectedSha256` 时改为比较磁盘与该哈希。`-Action Record` 只登记已由其他方式写好的文件，不能发现已登记的并发写入，共享文件不要使用；`-Action Status` 核对 bucket 下全部已登记文件。记忆根解析与 `sot-session-start` 一致，bucket 默认由游戏主工作树路径生成，可用 `-Bucket` 覆盖；同样支持 `-RootsFile` 与 `-IgnoreEnvironment`。

`sot-publish.ps1` 在发布前通过 `gh pr list` 检测当前分支是否叠加在另一开放 PR 之上；检测到时须显式传 `-StackedOn <头分支>` 才能发布，并输出应写入 PR 描述的依赖说明。判定方式：对每个开放 PR 头计算与当前 HEAD 的 merge-base，该点不在任何受保护基准引用中即视为叠加，因此下层 PR 在本分支切出后继续推进仍能检出；下层 rebase 或强推后仍可能漏检。`-DryRun` 同样执行 `git fetch origin` 刷新引用，除此之外不写入。`gh` 不可用或未登录时只警告并继续。

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
