# 提交与工作树生命周期

从游戏仓 `Ship_of_Theseus` 的现行 `AGENTS.md` 和项目技能进入三仓协作。主仓同级，任务工作树按仓库分组；实际根目录来自环境变量或被忽略的本地 roots 配置，详见 `02-Development/agent-runtime-layout.md`。

## 创建与使用

使用游戏仓 `scripts/codex/sot-worktree.ps1` 查看和检查工作树。示例中的 `<ship_root>`、`<task-path>`、分支和基线均替换为已确认的实际值：

```powershell
& "<ship_root>/scripts/codex/sot-worktree.ps1" -Action List -Repository all
& "<ship_root>/scripts/codex/sot-worktree.ps1" -Action Inspect -Repository ship -Path "<task-path>" -BaseRef refs/remotes/origin/develop
& "<ship_root>/scripts/codex/sot-worktree.ps1" -Action Create -Repository designlib -Task "<task-name>" -Branch "<task-branch>" -BaseRef "<confirmed-base-ref>"
```

Create 仅用于游戏和设计库，生成的新工作树获得本机 roots 配置。KB 写入保持唯一固定 Obsidian vault，在其任务分支中工作；先确认工作区干净和分支占用情况，遵守 `sot-kb-write`。不为 KB 任务新增第二个 vault。

## 提交与交付

只暂存任务声明范围，保留已有改动，不直接向受保护分支提交或推送。完成必要验证与独立审查后，从目标任务目录调用游戏仓的 `scripts/codex/sot-publish.ps1`。PR 合并后核实交付提交与目标分支，不把 PR 已创建视为完成。

## 退役检查

1. 确认工作树登记、所属仓库、路径、HEAD、分支与当前使用情况。任务仍在进行或无法确认时保留。
2. 检查暂存、未暂存、未跟踪及被忽略的全部本地文件；检查隐藏修改的索引标记、重解析点和受保护文件。工作树看起来干净不能证明没有本地资料。
3. 核对当前 HEAD 的成果已经进入目标长期分支。若采用 squash 合并，核对 PR 的实际 head、合并提交及内容等价，不能只看分支名或曾经合并的 PR。PR 合并后新增的提交另行判断。
4. 对仍需保存的本地资料先归档并校验；保存 HEAD、分支、引用及必要恢复证据。没有明确授权时不删除分支，不用 stash/reset/clean 丢弃内容。
5. 在获授权的清理范围内，操作前再次检查状态和占用，使用正常 `git worktree remove` 退役已确认完成的目录；不使用 `--force`，不按年龄、关闭 PR 或目录名称批量删除。
6. 核验目录与登记均已移除、分支和提交仍可恢复，再更新当前清单。保留项继续在原仓库分组下管理。

无修改、无本地额外文件且交付已核实的工作树可以列为清理候选；有本地资料的先归档；有未交付提交、未提交工作、占用或证据不足的继续保留。检查工具只提供证据，不自动批准删除。
