# 决策登记（Decision Register）

本表只列现行的设计决策，一行一条。规则总表 [rules.md](../00-rules/rules.md) 的「来源」列引用这里的编号。

- 只列仍然有效的决策。被新决策推翻的行直接删除；新行不提旧编号。编号不复用：删除的编号空着，不再分配。
- 同一主题多次裁决，只留最新结论。
- 用户原话不抄在本表，留在来源里：本次会话的裁决在 Issue 正文；原先写在原则分册里的原话，用改写前固定提交的行级永久链接；用户的长期授权在仓库根 `CLAUDE.md` 原文。
- 日期写「未记日期」的两行，来源只写了「用户裁决」，没有日期。
- 架构层面的决策另有 ADR，见 [目录索引](README.md)。

| 编号 | 日期 | 结论 | 来源 |
|---|---|---|---|
| D-001 | 2026-10-31 | 设计纪律以 `00-rules/rules.md` 这一张分级编号总表为唯一正本；新裁决改总表对应行并在本表登记来源，被推翻的行直接删除。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-002 | 2026-10-31 | 声明任何技能时默认包含其升级版本；卡面不写「及其升级版本」，只在排除时写「不包含〔某某〕」。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-003 | 2026-10-31 | 卡面只写本卡自己的效果，不写与其他天赋、技能之间的结算顺序与交互说明，交互由规则表统一规定。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-004 | 2026-10-31 | 其他技能、天赋或装备中写明「命中时」的效果，在整次〔连斩〕中最多发动一次，明确写明逐刀发动的除外；这一〔连斩〕专属例外写在连斩卡面，设计库 R1.10 不变。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-005 | 2026-10-31 | 取消「命中后」时机，原挂在「命中后」的效果改在「命中时」触发。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-006 | 2026-10-31 | 卡片 `rules` 字段不写规则编号，只用平实的话写本卡特有的结算细节；规则表已有的默认口径不复述。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-007 | 2026-10-31 | 同一技能的升级回忆互斥，没有例外。 | [Ship #126](https://github.com/392fyc/Ship_of_Theseus/issues/126) |
| D-008 | 2026-10-22 | 数值、结构细节和 Claude 自己设计的内容由 Claude 决定，数值标尺标「推断」；用户定过的内容不替换；只在缺少影响正确性的关键信息时询问。 | 仓库根 `CLAUDE.md`「用户给 Claude 的长期授权与工作基准」 |
| D-009 | 2026-10-22 | 生产设计库写入授权覆盖自主迭代与扩展设计，仍按 dry-run、独立审查、逐条写入回读执行。 | 仓库根 `CLAUDE.md`「用户给 Claude 的长期授权与工作基准」 |
| D-010 | 2026-10-24 | 天赋稀有度按用户量化定档：传奇接近回忆、一定程度改变玩法；史诗是较强数值、新奇小机制或机制联动；稀有与普通以数值为主，偶尔有改善操作的极小机制。 | [旧天赋设计要点 第 194 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L194) |
| D-011 | 2026-10-24 | 史诗天赋不应只是单一增伤。 | [旧天赋设计要点 第 202 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L202) |
| D-012 | 2026-07-19 | 天赋承载机制、条件与构筑内容，不做纯裸属性件；裸属性强化归装备词缀与经济类遗物。 | [旧内容设计通则 第 26 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L26) |
| D-013 | 2026-07-21 | 乘区选择是定价决策：同样的数值投进拥挤的乘区价值更低。 | [旧内容设计通则 第 33–35 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L33-L35) |
| D-014 | 2026-07-20 | 数学不同的修正通道各自保留，不为整齐统一成一种措辞。 | [旧内容设计通则 第 37 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L37) |
| D-015 | 2026-07-22 | 乘区拥挤度只是定价输入，多张卡可以共用同一乘区。 | [旧内容设计通则 第 39 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L39) |
| D-016 | 2026-08-10 | 估算属性挂钩数值的预期时，基准取成长到 25 级的属性值 × 2。 | [旧内容设计通则 第 41 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L41) |
| D-017 | 2026-07-20 | tag 只从设计库注册表选，按每条的 definition 与 boundary 判定；boundary 是必填字段。 | [旧内容设计通则 第 55 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L55) |
| D-018 | 2026-07-20 | 职业特色资源不设专属 tag：产出资源、改写资源规矩、依托资源数量判定的卡挂「资源」，技能自身的基础消耗不算。 | [旧内容设计通则 第 56 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L56) |
| D-019 | 2026-07-29 | 术语表 `/api/terms` 收窄为纯引用层，不作设计依据。 | [旧设计规则面索引 第 36 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/design-rules-index.md#L36) |
| D-020 | 2026-07-27 | 设计库不存引擎数值副本，`engine_json` 只读镜像退役。 | [旧内容设计通则 第 93 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L93) |
| D-021 | 2026-10-24 | 技能的威力、系数与命中记在伤害条目 `damage_entries`，条目是这些参数的唯一权威。 | [旧技能设计要点 第 14 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L14) |
| D-022 | 2026-07-21 | `is_projectile` 表示技能是否发射可被阻挡的实体，默认为否。 | [旧技能设计要点 第 18 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L18) |
| D-023 | 2026-08-06 | `target_mode` 取值为单位、格子、方向、自身，独立记录。 | [旧技能设计要点 第 19 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L19) |
| D-024 | 2026-10-24 | 剑气的获得、消耗与阈值取 5 的倍数。 | [旧天赋设计要点 第 115 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L115) |
| D-025 | 2026-07-20 | 「奥义」tag 只标一条职业线的终极技能，按身份不按强度；剑士与剑圣的终极技能是〔居合〕。 | [旧技能设计要点 第 60 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L60) |
| D-026 | 2026-07-20 | 下位与上位职业可以各有一张同名技能，靠 `class_id` 区分，不算撞名。 | [旧技能设计要点 第 79 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L79) |
| D-027 | 2026-10-28 | 转职时同名技能可以增加效果，也可以替换原有效果。 | [旧技能设计要点 第 80 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L80) |
| D-028 | 2026-10-28 | 技能以「职业＋技能」组合确定版本。 | [旧技能设计要点 第 81 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L81) |
| D-029 | 2026-10-30 | 同一槽位的升级、替换与恢复形态都要有可辨认的图标，并在实际技能栏尺寸下同屏验收。 | [旧技能设计要点 第 86 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L86) |
| D-030 | 2026-10-30 | 快捷键只按技能顺序排布，不因技能原本是被动而排除。 | [旧技能设计要点 第 87 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L87) |
| D-031 | 2026-07-29 | 武器特效挂在装备本身，不另立词缀实体。 | [旧装备设计要点 第 19 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L19) |
| D-032 | 2026-07-05 | 装备用稀有度加品阶（品阶只给额外数值），遗物只用稀有度。 | [旧装备设计要点 第 38 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L38) |
| D-033 | 2026-07-05 | 遗物不设「唯一」或「可叠加」的去重机制。 | [旧遗物设计要点 第 34 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/relic-design-principles.md#L34) |
| D-034 | 2026-07-05 | 遗物掉落先按稀有度分桶抽取，同羁绊优先当前不做。 | [旧遗物设计要点 第 36 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/relic-design-principles.md#L36) |
| D-035 | 2026-05-25 | 资源系统每职业完全独立；不设计跨职业通用的资源获取率或消耗率效果。 | [旧遗物设计要点 第 33 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/relic-design-principles.md#L33) |
| D-036 | 2026-10-28 | 天赋要区分加威力、加系数、伤害提升与伤害总增等层。 | [旧天赋设计要点 第 32 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L32) |
| D-037 | 2026-10-24 | 增益重点在与属性联动，而不是小百分比增伤。 | [旧天赋设计要点 第 45 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L45) |
| D-038 | 2026-10-28 | 剑气以 50 点划分高低两区，作为独立锚点写在剑气资源里。 | [旧天赋设计要点 第 111 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L111) |
| D-039 | 2026-10-24 | 剑气获取影响基础循环，增加剑气获取的卡可以有但要少。 | [旧天赋设计要点 第 116 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L116) |
| D-040 | 2026-10-24 | 卡面直接写技能名，不造「爆发位」「印记位」一类说法。 | [旧天赋设计要点 第 127 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L127) |
| D-041 | 2026-10-24 | 不是强化技能、而是自身造成伤害的天赋，效果写全威力和系数等伤害参数。 | [旧天赋设计要点 第 128 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L128) |
| D-042 | 2026-07-19 | 同一批命名的字数要有分布。 | [旧天赋设计要点 第 135 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L135) |
| D-043 | 2026-07-20 | 名字须有可指认的文化出处，不用游戏通用机制词。 | [旧天赋设计要点 第 136 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L136) |
| D-044 | 2026-07-21 | 命名优先取动漫、小说等作品中的名称，可以加一点自己的修饰。 | [旧天赋设计要点 第 137 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L137) |
| D-045 | 2026-08-05 | 一张卡默认单触发，只有独立的离散触发点才开附加触发行，附加行不取「永久生效」。 | [旧天赋设计要点 第 226 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L226) |
| D-046 | 2026-08-05 | 「命中时」「暴击时」在判定成立时触发，「造成伤害时」按每段实际伤害触发，「击杀时」在击杀结算后触发。 | [旧天赋设计要点 第 236–244 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L236-L244) |
| D-047 | 2026-10-28 | 减冷却是明显的强度设计；需要时幅度取 −1，或改为加长现有位移技能的冷却。 | [旧天赋设计要点 第 203 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L203) |
| D-048 | 2026-10-30 | 回忆是新技能替代旧技能，升级技能没写的效果就是没有。 | [旧天赋设计要点 第 298 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L298) |
| D-049 | 2026-10-28 | 卡片是否锁定以设计库为准。 | [旧天赋设计要点 第 305 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L305) |
| D-050 | 2026-10-18 | 回忆不能洗点，玩家需要预设玩法方向。 | [旧天赋设计要点 第 415–418 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L415-L418) |
| D-051 | 2026-10-12 | 回忆点经济：击败传奇敌人获得（最终 Boss 除外）、自由分配到回忆本体与专属节点、每个回忆最多 3 个专属节点、三选一固定给普通天赋。 | [旧天赋设计要点 第 421–429 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L421-L429) |
| D-052 | 2026-10-12 | 回忆本体持平或略亏，专属节点给更高的额外收益。 | [旧天赋设计要点 第 437 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L437) |
| D-053 | 2026-10-21 | 回忆本体必须保持自身特色，特色不移到节点。 | [旧天赋设计要点 第 438 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L438) |
| D-054 | 2026-10-21 | 额外回合、额外行动类回忆单资源时低于对位、多资源时相对更高；评估按玩家标准与迅捷动作各最多 2 次、敌人每回合单次行动。 | [旧天赋设计要点 第 439 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L439) |
| D-055 | 2026-10-18 | 回忆节点按功能、数值补足、移动、单体破甲、属性堆叠、技能交互等方向区分。 | [旧天赋设计要点 第 442–451 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L442-L451) |
| D-056 | 2026-10-18 | 技能交互顺着现有回合规则：先移动再攻击，移动机会只有一次。 | [旧天赋设计要点 第 455 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L455) |
| D-057 | 2026-10-19 | 回忆节点要有存在感。 | [旧天赋设计要点 第 459 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L459) |
| D-058 | 2026-10-28 | 回忆节点不提供跨战斗的永久增益，本场战斗内持续的可以。 | [旧天赋设计要点 第 464 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L464) |
| D-059 | 2026-10-28 | 状态没有特殊声明时每个关卡重置。 | [旧天赋设计要点 第 465 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L465) |
| D-060 | 2026-10-28 | 状态与技能可以同名。 | [旧天赋设计要点 第 466 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L466) |
| D-061 | 2026-10-12 | 剑圣兼顾物理输出与闪避坦克，闪避须整局有效。 | [旧天赋设计要点 第 470 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L470) |
| D-062 | 2026-10-13 | 剑圣基础加闪避与天赋加百分比减伤不自洽，护盾与闪避互补。 | [旧天赋设计要点 第 471 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L471) |
| D-063 | 2026-10-22 | 剑圣不以生存能力著称，防御要控制。 | [旧天赋设计要点 第 472 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L472) |
| D-064 | 2026-10-22 | 敌人攻击模型可以大胆，不按属性推算。 | [旧天赋设计要点 第 474 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L474) |
| D-065 | 2026-10-21 | 招架组牺牲一定主动性，换来较为持续的减伤或反击。 | [旧天赋设计要点 第 475 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L475) |
| D-066 | 2026-10-28 | 〔浮生若梦〕确定抵抗少量可预见的高伤害、靠冷却决定时机；〔见切〕是输出端补强，释放更频繁，防御收益更低且不稳定。 | [旧天赋设计要点 第 476 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L476) |
| D-067 | 2026-10-28 | 普通天赋在职业、技能、回忆天赋与回忆节点成立之后再设计。 | [旧天赋设计要点 第 490 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L490) |
| D-068 | 2026-10-24 | 普通天赋要按战棋设计，不偏向肉鸽。 | [旧天赋设计要点 第 492 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L492) |
| D-069 | 2026-10-24 | SoT 没有通用的追击与反击系统，参考火纹时不用依赖它们的机制。 | [旧天赋设计要点 第 493 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L493) |
| D-070 | 2026-10-24 | 流派分输出方向（追加特效与技能威力相反）与技能重心两个维度，两维可以组合。 | [旧天赋设计要点 第 494 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L494) |
| D-071 | 2026-10-24 | 资源加速本身不提高攻击频率，必须配合技能威力或特效兑现。 | [旧天赋设计要点 第 498 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L498) |
| D-072 | 2026-10-24 | 〔二天一流〕〔交刃〕〔二刀开刃〕〔剑气回荡〕〔燕返〕虽然锁定，发现数值或效果问题时可以直接修改。 | [旧天赋设计要点 第 499 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L499) |
| D-073 | 2026-10-13 | 基础配置下剑气花费大于收入；投入后在有利场景里主导是投入的回报。 | [旧技能设计要点 第 65 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L65) |
| D-074 | 2026-10-09 | 挨打扣剑气的惩罚过大。 | [旧技能设计要点 第 66 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L66) |
| D-075 | 2026-10-13 | 标准动作技能以剑气与印记为使用条件，迅捷、移动技能以冷却为使用条件。 | [旧技能设计要点 第 67 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L67) |
| D-076 | 2026-10-14 | 冷却一般给功能性技能，〔太阴剑〕冷却 0 是特例。 | [旧技能设计要点 第 67 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L67) |
| D-077 | 2026-10-13 | 额外标准行动做成每关卡限定次数。 | [旧技能设计要点 第 69 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L69) |
| D-078 | 2026-10-14 | 〔阴阳剑〕阴阳圆满的额外回合不加每关卡上限。 | [旧技能设计要点 第 69 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L69) |
| D-079 | 2026-10-21 | 多行动资源下评估看各方案的相对差异，不追究理论强度上升。 | [旧技能设计要点 第 70 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L70) |
| D-080 | 2026-05-10 | 五层构筑架构：L2 天赋与 L5 遗物承担构筑定义，L4 装备不承担，L1 只做横向解锁。 | [五层架构共识 v2](architecture-consensus-v2.md) |
| D-081 | 2026-07-02 | 遗物的正典名是「遗物 Relic」，Rune 是废案。 | [ADR-010](adr-2026-07-02-relic-canonical-rune-deprecated.md) |
| D-082 | 未记日期 | 职业线由 1 个下位与 2 个上位职业组成，class id 用英文全称并贴合文化原型。 | [旧内容设计通则 第 75 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L75) |
| D-083 | 未记日期 | 印记池不设硬前置，与双刀池相反。 | [旧天赋设计要点 第 89 行](https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L89) |
| D-084 | 2026-10-31 | 仓库公开后，PR 的合并依据是 GitHub Actions 在当前 HEAD 上的结果，不再用本地 CI 代替；做法见 [CI 与合并依据](../02-Development/ci-policy.md)。 | [Ship #126 评论](https://github.com/392fyc/Ship_of_Theseus/issues/126#issuecomment-6542783606) |
