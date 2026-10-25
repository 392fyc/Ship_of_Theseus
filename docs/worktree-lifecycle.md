# SoT 工作区与工作树

日常 Codex 入口是游戏主仓 `Ship_of_Theseus`。三个主仓平级；任务工作树只建在所属仓库根的 `.worktrees/<task>/`，不在仓库外另建目录组。这是目录关系，实际根路径由本机配置提供：

```text
<project-root>/
  Ship_of_Theseus/             游戏主仓，日常入口
    .worktrees/<task>/         游戏任务树；目录内有 .gdignore，避免 Godot 把任务树导入主项目
  SoT-fyc-space/               设计库主仓
    .worktrees/<task>/         设计库任务树
  ShipOfTheseus-KB/            固定 Obsidian vault；日常不建任务树
```

`.worktrees/` 必须被所在仓库的 Git 忽略（`/.worktrees/`），否则 `Create` 拒绝创建。Obsidian 不索引以点开头的目录，KB 的 `.worktrees/` 只用于历史或显式只读隔离，不是第二个 vault。

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

本节适用于 Codex 与 Claude 的本地和云端工作。任务结束时记录 HEAD、实际分支、PR/任务状态、未提交内容和下一步；工作树继续承载未完成任务时保留。

`main`、`master`、`develop` 和 origin 的默认分支（`gh repo view --json defaultBranchRef`）在本地和远端都永不删除。GitHub 上这些分支不一定配置了分支保护，不能依赖远端拒绝。

### PR 合并后：立即清理，无需再询问

逐项核对后，删除 worktree 与本地分支：

1. 存在已合并的 PR，且本地分支末端等于该 PR 的头提交（`headRefOid`）或是它的祖先；或者分支有自己的提交，并已全部进入基准分支。没有自己提交、也没有已合并 PR 的分支（例如刚从 develop 切出的分支）不算已合并，按下一节处理。
2. staged、unstaged、untracked 都没有需要保留的内容；检查 assume-unchanged/skip-worktree，不能只看普通状态。
3. ignored 文件逐项分类：Godot 导入缓存（`.godot/`、`*.import`、`*.uid`）、`__pycache__`、本地 roots 文件、可重新生成的测试日志可以随树删除；图像原料、数据库、审查证据等需保留的内容先复制到主 checkout 的 `.tmp/<任务>/`，逐文件比对哈希一致后再删除工作树。非 force 的 `git worktree remove` 会连同 ignored 文件一起删除，这一步是它们唯一的保护。
4. 无锁定或其他会话占用，路径属于正确仓库，主工作树不在清单内。

执行：非 force 的 `git worktree remove <path>`，再 `git branch -d <分支>`。只有在第 1 项核实了 PR 头提交、而 squash 合并使 `-d` 认不出时，才用 `-D`。远端分支由 GitHub 的合并后自动删除处理，用 `git fetch --prune origin` 回读确认，仍存在时报告。出现保护属性、链接、占用或新改动时停止。

### 未合入就废弃：先列清单，经用户确认后删除

列出分支名、末端提交、相对基准的未合入提交数、远端分支与 PR 状态，等用户确认。确认后删除 worktree 与本地分支；远端删除前先用 `gh api repos/<owner>/<repo>/git/ref/heads/<分支>` 回读 SHA，与清单里的末端提交一致才执行 `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<分支>`，不一致就停止。不用裸 `git push --delete`。

工作树年龄、分支名字或没有开放 PR 单独都不是合并或废弃的依据。完成后回读目录与 `git worktree list`，未完成的项不能报告为已清理。本脚本不提供删除入口；按上述清单执行。发布仍使用 `sot-publish.ps1`。