# 人物棋子与森林入口：当前 MVP 记录

## 当前状态（2026-10-28）

当前展示入口为 scenes/tactical/character_pipeline/portrait_token_battle.tscn。可直接启动该 MVP 场景：

    godot --path . --rendering-method gl_compatibility res://scenes/tactical/character_pipeline/portrait_token_battle.tscn

这条命令直接运行原画棋子入口，不改变项目默认主场景。outside-calm-r1 复用真实 TacticalScene、Unit、Grid、GameAction、EnemyAI 和 HUD，在 1280×720、30 fps、zoom 1.36 下录制了 360 帧、12 秒的进场、停留和离场过程。

- 保持正式庭院地面、镜头和石材。树木与森林呈现使用当前候选配置，不从截屏拼接战斗背景。
- 玩家剑士使用短衣四向棋子，剑圣使用原长衣四向棋子。敌方枪兵沿用当前场景中的共用剑圣图占位，以阵营色和长枪徽章标识；本版没有独立敌方外形。
- 原半径脚环为普通 18/8、选中 22/10 世界单位，中心在足点；职业徽章保留原尺寸与位置。
- 用户在 2026-10-28 答复“当前允许”，允许当前 MVP 中徽章与原半径脚环局部重叠。该决定仅适用于本 MVP，不代表整体视觉定稿。
- 独立画面审阅只看了进入、停留、离开途中和离开后四张静帧。它不是对 360 帧逐帧人工审查；自动几何跟踪也不能替代该审查。
- 外围大树与灌木分离，灌木与草地可辨；灌木体量的立体感部分达到。深色靴底细节未测清楚，静帧无法确认每格的邻接边缘。
- 自动 UI 诊断仍有头顶血条与其他身体重叠记录；四帧审阅还发现黄色悬停格盖住一段友军血条。遮挡未全部消除。整体美术仍未最终定稿。

详细结果见 .tmp/art-pipeline-20261027/forest-cell-mvp/outside-calm-r1/delivery/claude-review.md、receipt-local.json，以及 .sot/lane-work/ui-ux/cloud-replacement-20261028/outside-calm-r1/cloud-evidence/receipt.json。回执里的环徽章相交诊断保留原始观察；现行用户决定把这项局部重叠作为当前 MVP 允许项。

## 2026-10-27 人物战斗原型 v1 记录（历史阶段）

以下运行与停止/重开测试属于当时的人物战斗原型版本，不能替代 2026-10-28 outside-calm-r1 的当前镜头、森林、徽章重叠决定和视觉结论。

### 入口与表现范围

当时入口为 scenes/tactical/character_pipeline/portrait_token_battle.tscn。它使用正式 TacticalScene、Unit、Grid、GameAction、EnemyAI 和 HUD，不是独立动画预览或截图背景。

- 地图使用原 assets/units/kensei/map_token_clean_v2.png 第一行四方向和原配置足点，初始 fit 下约 72px 高；原 PNG 未改写。
- 四名单位共用已有剑圣棋子，仅验证组合方式；未制作四套职业外形。
- 选中剑士/剑圣时，原 M2 人物信息区读取已有肖像 .tres 与原画 PNG。
- 静态棋子沿真实移动 tween 移动、按 Grid 方向转向；攻击表现由既有包装器短突进、斩痕和受击闪光组成，没有骨骼或逐帧行走动画。
- 当时 TacticalManager 的战斗规则与数值未改。

### 当时的运行记录

旧 .tmp/portrait-token-battle-20261027/run02 保存 400 张 1280×720 PNG、30 fps/13.333 秒实录和逐帧/事件 JSON。录制器通过真实指针、攻击和结束回合入口推进战斗；该段过程记录仅适用于当时原型版本。

旧 focused 测试记录包含人物方向、移动、攻击、输入锁、停止复位和重开检查。它们是当时提交前的局部结果，不构成本次 forest MVP 的完整回归，也不构成整体视觉批准。

### 当时的限制

当时四名单位共用一套棋子；首次静帧审查不能可靠识别剑和枪，原预测窗也有局部遮挡。旧失败日志、被中断的采集和最终候选均按原始历史保留，不将旧阶段结果改写为当前验收结论。
