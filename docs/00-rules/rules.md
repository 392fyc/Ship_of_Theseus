# 设计规则总表（Design Rules）

本表是 SoT 设计纪律的唯一正本：职业、技能、回忆、天赋、装备、遗物怎么设计，卡面和字段怎么写，设计工作按什么步骤做。要知道「现在必须怎么做」，查本表的编号即可。

- **系统结算规则不在本表。** 伤害、命中、暴击、触发次数、行动点、冷却等结算规则的正本是设计库规则表（R1.x–R4.x，离线目录见 [规则总目录](../01-Game-Design/rules-catalog.md)）。本表不复述，需要时写「见设计库 R1.10」。两边冲突时以设计库规则表为准。
- **怎么读一行**：编号 = 前缀 + 两位数；级别见下表；「适用」写这条管什么；「来源」写它来自哪条决策（[决策登记](../03-decisions/register.md) 的 `D-` 编号），或「设计库 R…」（从规则表推出），或「沿用：」加行级链接（改写前文档里已有的现行纪律，没有单独的用户决策记录；链接指向改写前固定提交 `8b517dd` 中的原句，链接文字里「通则」「天赋册」「技能册」「装备册」「遗物册」「索引」指 `00-rules/` 下改写前的对应分册，「呈现技能」指 `.agents/skills/sot-design-present/SKILL.md`）。一条规则可以同时有几个来源。
- **怎么改**：新裁决来了，改本表对应那一行（没有对应行就在该节末尾新增一行），并在决策登记里登记来源；被推翻的旧行直接删除。编号不复用：删除的编号空着，新增的规则取该节下一个没用过的编号。理由、日期、原话和案例不写进本表，留在决策来源或各实体指引里。

| 级别 | 含义 | 审查 |
|---|---|---|
| 一级 | 必须或禁止，违反即错 | 审查必查 |
| 二级 | 默认做法；例外必须在记录里写明 | 审查查例外是否写明 |
| 三级 | 推荐做法 | 不作为审查不通过的依据 |

写法示例、案例与检查清单在 [设计规则面索引](design-rules-index.md) 路由到的各实体指引里。指引只解释本表，不另立规则；与本表不一致时以本表为准。

术语：**机制池**是围绕一个核心机制组织的一组天赋，例如双刀池（副手、双击）、印记池（剑圣的印记）；**通用层**是不依赖任何机制池、整条职业线都能取用的天赋；**提案页面**是按 `sot-design-present` 技能交给用户审阅的可视化设计提案页面，不是设计库字段。

前缀：G 通用 · W 卡面与字段写法 · T 天赋 · S 技能 · M 回忆升级 · E 装备 · L 遗物 · N 数值与稀有度 · P 设计工作流程。

## G 通用

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| G01 | 一级 | 设计纪律以本表为准，系统结算规则以设计库规则表为准；叙述性文档与设计库的规则表、注册表或实体记录冲突时以设计库为准；规则冲突按「设计库规则表 > 较新的用户裁决 > 较旧的用户裁决」消解。 | 全部设计工作 | D-001 |
| G02 | 一级 | 只有已上架（`shelf_state=已上架`）且状态为待审阅、待优化或锁定的设计库记录可作设计材料；草稿、待删除、已归档的记录不作依据，也不作参考。 | 设计库记录 | 沿用：[通则 L80][g80]、[通则 L100][g100] |
| G03 | 一级 | 锁定记录只作参考、不进日常审计；只有规则依据改变或发现有具体证据的矛盾时，才按实体 ID 重新审计。记录是否锁定以设计库 `status` 为准。 | 设计库记录 | D-049 |
| G04 | 一级 | 用户点名修改的草稿只是本次的修改对象，不升格为审计样本或设计先例。 | 草稿记录 | 沿用：[通则 L102][g102] |
| G05 | 一级 | 用户定过的内容（包括回忆与回忆节点）不替换、不删除；偏弱时列为观察项。 | 全部设计内容 | D-008 |
| G06 | 一级 | 特例：〔二天一流〕〔交刃〕〔二刀开刃〕〔剑气回荡〕〔燕返〕发现数值或效果问题时直接修改，不受 G03、G05 限制。 | 仅这五张天赋 | D-072 |
| G07 | 一级 | 数值、数值标尺、结构细节和代理自己设计的内容由代理决定；只在缺少影响正确性的关键信息时询问用户。 | 全部设计工作 | D-008 |
| G08 | 一级 | 规则表条文的增删改、枚举合法集的增删（例如 `damage_type`、稀有度档位、触发事件）、新职业线与占位职业的设计、新实体类型、新机制轴由用户裁决，代理可以起草；供给不设上限、由人工管理，代理不为腾位自行删除内容、跨池搬移或整卡废弃。 | 规则、结构与供给 | 沿用：[通则 L97][g97]、[通则 L104–111][g104-111] |
| G09 | 一级 | 设计任何内容前先定它落在五层架构的哪一层：L2 天赋与 L5 遗物承担构筑定义，L4 装备不承担，L1 只做横向解锁、不做纵向变强。 | 全部实体 | D-080 |
| G10 | 一级 | 设计侧只写设计库的设计层字段；设计库不存引擎数值副本，设计层与引擎层字段各自维护，落地须经明确的跨仓实现。 | 全部实体 | D-020 |
| G11 | 一级 | 各职业的特色资源完全独立设计：不引入跨职业的统一资源抽象，装备特效与遗物不做跨职业通用的资源获取率或消耗率效果；跨职业遗物可以触碰属性、状态和行动经济。 | 职业资源、装备、遗物 | D-035 |
| G12 | 一级 | 术语表 `/api/terms` 只是引用层，不作设计依据；机制事实查资源、状态、判定三张注册表。 | 全部设计工作 | D-019 |
| G13 | 二级 | 状态没有特殊声明时每个关卡（一场战斗）重置，跨关卡保留必须写明；状态与技能可以同名。 | 状态、资源 | D-059、D-060 |

## W 卡面与字段写法

「卡面」指玩家能看到的字段：`name`、`effect`、`description`、`rules`。

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| W01 | 一级 | 卡面用自然、完整、清楚的简体中文，能直接进游戏；不用网络黑话、小圈子简称、翻译腔、机械化措辞和箭头记号，不要求玩家先懂开发者的内部语境。 | 全部卡面 | 沿用：[通则 L61][g61]、[通则 L63][g63] |
| W02 | 一级 | 卡面只写本卡自己的效果；不写与其他天赋、技能之间的结算顺序与交互说明，交互由规则表统一规定；S17 除外。 | 全部卡面 | D-003 |
| W03 | 一级 | 声明一个技能时默认包含其升级版本；卡面不写「及其升级版本」，只在排除时写「不包含〔某某〕」。 | 全部卡面 | D-002、设计库 R2.5 |
| W04 | 一级 | 点名技能直接写技能名，不造「普攻位」「爆发位」「印记位」一类说法。 | 全部卡面 | D-040 |
| W05 | 一级 | `effect` 写效果本身，一两句能读懂；`rules` 只写本卡特有的结算细节，不写规则编号、内部字段名、计算步骤或「参照某规则」，不复述规则表已有的默认口径，不堆叠防御性条款；`notes` 写设计意图与开发说明，可以含字段名，但不被卡面引用。 | 天赋、技能、装备 | D-006 |
| W06 | 一级 | 只写存在的条件、效果与数值；不写「无冷却」「不消耗剑气」这类描述不存在条件的话，确实存在的限制写成正面的使用条件。 | 全部卡面 | 沿用：[呈现技能 L30][p30] |
| W07 | 一级 | 设计库字段与规则表条文只陈述当前事实：不写日期、「原X」、否定式自辩、作废说明和变更记录；`notes` 不保存旧方案与改版经过。 | 设计库字段、规则表条文 | 沿用：[通则 L67][g67]、[天赋册 L370][t370] |
| W08 | 一级 | 已由结构化字段承载的信息（触发时机、目标、冷却、射程、伤害参数等）不在设计库 `effect` 里重复，也不从文案反推执行关系。 | 设计库 `effect` 字段 | D-021 |
| W09 | 一级 | 提案页面展示技能时写完整卡面：行动类型、冷却、消耗、射程与目标、效果；迅捷技能写明冷却。 | 提案页面 | 沿用：[呈现技能 L34][p34] |
| W10 | 一级 | 伤害写明类型（物理、魔法或纯粹），写成「对……造成……伤害」，需要时写明计算属性。 | 全部卡面 | 沿用：[呈现技能 L31][p31] |
| W11 | 一级 | 不是强化技能、而是自身造成伤害的天赋，效果写全伤害类型、计算属性、威力、系数，必要时写命中与暴击；不为天赋另建通用伤害字段。 | 天赋 | D-041 |
| W12 | 一级 | 状态写清层数的增加、减少与重置，以及持续时间、可否驱散。 | 状态与给出状态的卡 | 沿用：[呈现技能 L33][p33] |
| W13 | 一级 | 游戏内名称（技能、状态、回忆、节点）用〔〕；引用已注册状态写「处于〔状态名〕状态」，不另造说法。 | 全部卡面 | 沿用：[呈现技能 L32][p32]、[天赋册 L251][t251] |
| W14 | 一级 | 数值修正按设计库 R1.8 的写法区分固定点数、「提升／降低」百分比和在此前结果上再次提高或降低的修正，写法必须能判定归层。 | 全部卡面 | 设计库 R1.8 |
| W15 | 一级 | 涉及资源、状态、判定时，名称与措辞对齐设计库对应注册表；需要新机制名时先提请用户把它加入对应注册表，入表后再引用；不自造内部黑话或简写。 | 全部卡面 | 沿用：[通则 L13][g13]、[通则 L57][g57] |
| W16 | 一级 | tag 只从设计库 tag 注册表选，挂之前读该条的 definition 与 boundary 并按它判定；被动由「被动」tag 表达，不写「被动·…」「被动（…）」。 | 天赋、技能、装备 | D-017 |
| W17 | 一级 | 产出资源、改写资源规矩（上限、获得方式、兑换比例）或依托资源当前数量做判定的卡挂「资源」tag；技能自身的基础消耗不算。 | 天赋、技能、装备 | D-018 |
| W18 | 一级 | 名字须有可指认的文化出处（具体作品的招式、流派、人物、术语，或成体系的武学、兵法语汇）；不用「连击」「强化」这类游戏通用机制词做卡名。 | 全部命名 | D-043 |
| W19 | 二级 | 命名优先取动漫、小说等作品中的名称，武学语汇次之；不想照搬时在原名上加修饰。 | 全部命名 | D-044 |
| W20 | 一级 | 同一批命名的字数要有分布；单批全部同长时重排。 | 批量命名 | D-042 |
| W21 | 一级 | 职业线由 1 个下位与 2 个上位职业组成，class id 用英文全称（不用拼音或缩写），贴合文化原型并优先用业界成熟职业名。 | 职业 | D-082 |

## T 天赋

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| T01 | 一级 | 天赋承载机制、条件与构筑内容，不做纯裸属性加算件。 | 天赋 | D-012 |
| T02 | 一级 | 机制池的卡必须以该池的核心机制立足；拿掉核心机制后仍然完整成立的卡放通用层。 | 天赋 | 沿用：[通则 L115][g115] |
| T03 | 一级 | 双刀池的卡以副手、双击、双目标或两把不同武器为核心；剑气经济和按剑气高低给收益的卡属剑士线通用层。 | 剑士线天赋 | 沿用：[天赋册 L81][t81]、[天赋册 L83][t83] |
| T04 | 一级 | 印记池不设硬前置；每张印记池卡先在没有〔离形〕时成立并完成定标。 | 剑圣印记池 | D-083 |
| T05 | 一级 | 印记本身不提供属性，只有技能或天赋明确读取时才产生收益；设计前确认当前技能是否仍读取印记。纳刀印是资源特性，与状态〔纳刀〕不是同一对象。 | 剑圣印记池 | 沿用：[天赋册 L87][t87]、[天赋册 L90][t90]、[天赋册 L91][t91] |
| T06 | 一级 | trigger 只回答「什么时候生效」，不写效果内容与数值；新卡填事件、对象、来源、条件、频次五段，取值与校验以设计库 `TriggerEvent`、`TriggerFrequency` 为准；常驻效果的事件取「永久生效」，不在事件段拼后缀；频次没有「本回合首次」，用「每单位回合」。 | 天赋、装备特效 | 沿用：[天赋册 L209][t209]、[天赋册 L221][t221]、[天赋册 L223][t223]、[天赋册 L260][t260] |
| T07 | 一级 | 一张卡默认单触发；只有独立的离散触发点才开附加触发行（暂限 1 行），附加行不取「永久生效」。 | 天赋、装备特效 | D-045 |
| T08 | 二级 | `effect` 没有另行声明时，全部效果跟随主事件结算；不因一句效果有多个结果就拆附加触发。 | 天赋、装备特效 | 沿用：[天赋册 L266][t266] |
| T09 | 一级 | 攻击链时机：「命中时」「暴击时」在判定成立时触发，不读伤害结果；「造成伤害时」按每段实际伤害触发，0 伤不触发；「击杀时」在击杀结算后触发；新卡不选「命中后」。 | 天赋、装备特效 | D-046、D-005、设计库 R1.4 |
| T10 | 一级 | 不用条件段绕过事件选择；枚举覆盖不了的时机按 G08 提请用户扩枚举。 | 天赋、装备特效 | 沿用：[天赋册 L232][t232] |
| T11 | 二级 | 事件就窄不就宽：能挂「暴击时」就不挂「命中时」；带对象槽位的事件尽量填对象。 | 天赋、装备特效 | 沿用：[天赋册 L231][t231]、[天赋册 L233][t233] |
| T12 | 二级 | 阈值条件即时判定、不做快照；需要快照时在 `rules` 写明。 | 天赋、装备特效 | 沿用：[天赋册 L254][t254] |
| T13 | 一级 | 战斗结算中不插入玩家选择；需要玩家选目标、形态、代价或开关的，在动作开始前完成。 | 天赋、技能 | 沿用：[天赋册 L252][t252] |
| T14 | 一级 | `unlock_trigger` 只写本卡出现需要什么，格式「前置:X(池名)」；不写本卡是谁的前置。 | 天赋 | 沿用：[天赋册 L270][t270] |
| T15 | 一级 | 职业强化类天赋不填 `upgrade_skill_id`、不另建替换技能；它与回忆不共用字段蓝本。 | 天赋 | 沿用：[天赋册 L163][t163]、[天赋册 L288][t288] |
| T16 | 二级 | 普通天赋在职业、技能、回忆与回忆节点成立之后再设计。 | 普通天赋 | D-067 |
| T17 | 一级 | 设计一张普通天赋先说明它在棋盘上改变了什么决策（站位、行动顺序、目标选择、技能取舍），不只加一个数。 | 普通天赋 | D-068 |
| T18 | 一级 | 不用依赖通用追击、自动反击或先手后手的机制；反击只来自回忆或技能给出的反击。 | 天赋 | D-069、D-070 |
| T19 | 一级 | 每张普通天赋标注所属流派（输出方向与技能重心两维）；每个流派在各稀有度都要有可选的卡。 | 普通天赋 | D-070 |
| T20 | 一级 | 资源加速类卡写明服务哪个兑现方向（技能威力或特效伤害）；只加速、无兑现的卡不通过。 | 天赋 | D-071 |
| T21 | 二级 | 剑气获取类卡在同一职业线的天赋池里只留少数几张（不超过 3 张，推断）；每张核对它把基础循环（〔斩击〕攒剑气、〔居合〕花剑气）改成几回合、对〔心眼〕有什么影响，结论写在 `notes` 或评审记录里，不写进卡面。 | 剑士线天赋 | D-039、D-003 |
| T22 | 二级 | 优先设计随属性或属性差变化的效果，少用小百分比增伤；剑圣的移动类机制绑定速度或〔一闪〕，再移动类留给骑士一类职业。 | 天赋 | D-037 |
| T23 | 二级 | 效果落在本职业未饱和的维度；设计前查职业 `stat_tiers` 与相关判定链。 | 天赋 | 沿用：[天赋册 L97][t97]、[天赋册 L100][t100] |

## S 技能

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| S01 | 一级 | 每个技能填 `skill_type`（做什么）与 `resource_type`（耗哪种行动资源），两者正交；自身指向的姿态类归「增益」。 | 技能 | 沿用：[技能册 L22][s22]、[技能册 L27][s27] |
| S02 | 一级 | 技能没有 trigger 字段，时机由 `resource_type` 与引擎侧时机约束表达；不按天赋的字段面设计技能，反之亦然。 | 技能 | 沿用：[技能册 L12][s12]、[技能册 L20][s20] |
| S03 | 一级 | 技能的伤害参数（威力、系数、命中、暴击、基数属性、段数）只记在伤害条目 `damage_entries`，`effect` 不重复。 | 技能 | D-021 |
| S04 | 二级 | `is_projectile` 默认为否；要可被拦截必须显式声明。 | 技能 | D-022 |
| S05 | 一级 | `target_mode` 独立记录，不由作用范围形状反推。 | 技能 | D-023 |
| S06 | 一级 | 射程（以施法者为原点）与作用范围（以目标格为原点）分别用各自字段记录；位移类技能的作用范围记为「单体＋0」，受伤格按位移沿途计算、由射程上限封顶。 | 技能 | 沿用：[技能册 L39][s39]、[技能册 L44][s44] |
| S07 | 一级 | 游戏没有普通攻击；无冷却的基础攻击技能仍按完整技能设计。 | 技能 | 沿用：[技能册 L31][s31] |
| S08 | 一级 | 技能设计写明它占用哪种行动资源，以及同槽技能在默认容量与扩容后的取舍。 | 技能 | 设计库 R3.2 |
| S09 | 一级 | 下位职业的技能不含上位职业专属机制（例如剑圣的印记）；转职后追加的内容做成上位职业的独立条目，不改写下位版本。 | 职业技能 | 设计库 R2.4 |
| S10 | 二级 | 转职时同名技能可以增加效果，也可以替换原有效果；上位职业有自己的同名条目时使用上位版，不与继承来的下位版并存。 | 职业技能 | D-027 |
| S11 | 一级 | 同一职业线的下位与上位职业可以有同名技能，靠 `class_id` 区分；设计、点名、手算与实装都按「职业＋技能」确定是哪个版本。 | 技能 | D-026、D-028 |
| S12 | 一级 | 「奥义」tag 只标一条职业线的终极技能，按身份不按强度，天赋不挂；被攻击或被触发的反应类技能挂「反应」tag。 | 技能 | D-025 |
| S13 | 一级 | 先攻优先级等时点资源按技能释放时的一次性效果设计，不写成条件维持型被动。 | 技能、天赋 | 沿用：[通则 L117][g117] |
| S14 | 一级 | 技能交互顺着回合规则：先移动再攻击，移动机会只有一次。 | 技能、回忆节点 | D-056 |
| S15 | 二级 | 剑士线的标准动作技能以剑气与印记为使用条件，迅捷、移动技能以冷却为使用条件；冷却一般给功能性技能（〔太阴剑〕冷却 0 是特例）；近战受击不改变剑气。 | 剑士线技能 | D-075、D-076、D-074 |
| S16 | 二级 | 额外标准行动做成每关卡限定次数；〔阴阳剑〕阴阳圆满的额外回合不加此上限。 | 技能、回忆 | D-077、D-078 |
| S17 | 一级 | 其他技能、天赋或装备中写明「命中时」的效果，在整次〔连斩〕中最多发动一次；明确写明逐刀发动的除外。这一例外写在〔连斩〕卡面，设计库 R1.10 不变。 | 仅〔连斩〕 | D-004 |
| S18 | 一级 | 同一槽位的升级、临时替换与恢复形态都要有可辨认的图标，并在实际技能栏尺寸下同屏验收辨识度。 | 技能图标 | D-029 |
| S19 | 一级 | 快捷键按当前可主动使用的技能顺序排布，被动技能不永久排除；冷却和资源不足不改变编号；技能角标与实际按键用同一顺序来源。 | 技能栏 | D-030 |

## M 回忆升级

「回忆」是把一个基础技能永久升级成新技能的天赋；「升级技能」是升级后的那个技能。

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| M01 | 一级 | 回忆只把一个上位职业的基础技能永久升级为同职业的新技能；回忆、基础技能与升级技能的 `class_id` 相同；回忆没有等级维度，不做 lv1→lvN。 | 回忆 | 沿用：[天赋册 L286][t286]、[天赋册 L295][t295]、[天赋册 L300][t300] |
| M02 | 一级 | 回忆不以下位职业技能或已升级的技能为目标；升级技能的 `upgrade_of` 指向基础技能，禁止链式升级。 | 回忆 | 沿用：[天赋册 L296][t296]、[天赋册 L297][t297] |
| M03 | 一级 | 同一技能的升级回忆互斥：一局内一个技能只能被回忆升级一次。 | 回忆 | D-007 |
| M04 | 一级 | 升级技能独立给出完整字段；升级技能没写的效果就是没有，包括基础技能自带的被动加成。 | 升级技能 | D-048 |
| M05 | 一级 | 作用于基础技能的外部效果按设计库 R2.5 作用于升级版本，且只能修改升级形态实际存在的内容。 | 回忆、天赋 | 设计库 R2.5 |
| M06 | 二级 | 回忆的天赋名与升级技能名可以不同。 | 回忆 | 沿用：[天赋册 L301][t301] |
| M07 | 一级 | 合格的回忆升级至少改变目标、空间、结算结构、资源节奏或行动风险中的一项，并同时给出玩家得到的优势和承担的限制或风险；删去新机制后基础技能照样运行、只少一段收益的方案不是回忆升级。 | 回忆 | 沿用：[天赋册 L330][t330]、[天赋册 L385][t385] |
| M08 | 一级 | 每个基础技能提交兼容矩阵，覆盖固定工作集里全部当前有效对象，写明每项按一次使用、逐目标还是逐段生效；没有对象也写检索范围和「无」；设计兼容性与运行时可实现性分别下结论。 | 回忆 | 沿用：[天赋册 L349][t349]、[天赋册 L354][t354]、[天赋册 L359][t359] |
| M09 | 一级 | 多目标、多段与自动续击不得把外部效果的触发次数静默放大。 | 回忆 | 设计库 R1.10 |
| M10 | 一级 | 一个回忆对应多个条件形态时，按真实关系分别记录，不压成一套统一字段。 | 回忆 | 沿用：[技能册 L91][s91] |
| M11 | 一级 | 回忆不能洗点，加点后本局固定。 | 回忆 | D-050 |
| M12 | 一级 | 回忆点在击败传奇敌人时获得（最终 Boss 除外），玩家自由分配到回忆本体与专属节点；每个回忆最多 3 个专属节点；三选一固定给普通天赋。 | 回忆、天赋获取 | D-051 |
| M13 | 二级 | 回忆本体持平或略亏，专属节点给更高的额外收益。 | 回忆 | D-052 |
| M14 | 一级 | 回忆本体保持自身特色，特色不移到节点。 | 回忆 | D-053 |
| M15 | 二级 | 一个回忆的几个节点覆盖不同方向（功能、数值补足、移动、单体破甲、属性堆叠、技能交互），不落在同一方向。 | 回忆节点 | D-055 |
| M16 | 二级 | 节点要有存在感；代理自己设计的节点在评估中失效时重做，不硬调数值。 | 回忆节点 | D-057 |
| M17 | 二级 | 节点不提供跨战斗的永久增益，本场战斗内持续的增益可以。 | 回忆节点 | D-058 |
| M18 | 二级 | 招架组牺牲一定主动性换较为持续的减伤或反击；〔浮生若梦〕确定抵抗少量攻击、靠冷却决定释放时机，节点不把它扩成长期覆盖多次攻击的防御；〔见切〕是输出端补强，冷却更短，防御收益更低且是概率性的。 | 剑圣招架组回忆 | D-065、D-066 |

## E 装备

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| E01 | 一级 | 不设计流派改变型装备效果；装备与遗物的协同只做风味放大，不承载核心构筑。 | 装备 | D-080 |
| E02 | 一级 | 武器特效写进装备自身的 `effect`、trigger 五段与 `rules`；不另立词缀实体，不往 `notes` 里塞特效。 | 装备 | D-031 |
| E03 | 一级 | 「装备加属性」目前没有结构化字段，这类效果继续占位，不塞进 `effect`。 | 装备 | 沿用：[装备册 L20][e20] |
| E04 | 一级 | 尚未接入结算的特效，在 `rules` 写明不生效。 | 装备 | 沿用：[装备册 L44][e44] |
| E05 | 一级 | 需要新判定机制的效果（例如对某类单位额外伤害）按 G08 作为规则新增处理，不由装备批次先行实装。 | 装备 | 沿用：[装备册 L45][e45] |
| E06 | 二级 | 装备稀有度主轴是有无特效，第二轴是数值强度；普通制式武器不需要特效；不照搬外部作品的军阶分档。 | 装备 | 沿用：[装备册 L34–36][e34-36] |
| E07 | 一级 | 装备用稀有度加品阶（品阶只给额外数值），遗物只用稀有度。 | 装备、遗物 | D-032 |
| E08 | 一级 | 移植外部作品的武器数值须联网核实并逐件记录来源 URL；同一武器只取一个版本；促销码专属或与既有条目完全重复的项跳过；SoT 没有对应机制的维度不移植；敌方专属改编为玩家可得时在 `notes` 注明。 | 装备取材 | 沿用：[装备册 L50–53][e50-53] |

## L 遗物

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| L01 | 一级 | 遗物是 L5 构筑定义层，分经济类（加速职业既有的成长曲线，不改成长模型）与流派类（改变职业形态或天赋节点行为）。 | 遗物 | D-080 |
| L02 | 一级 | 正典名是「遗物 Relic」，新内容不用 Rune。 | 遗物 | D-081 |
| L03 | 一级 | 单件遗物定标计入占用六个遗物槽之一的机会成本。 | 遗物 | D-080 |
| L04 | 一级 | 流派类遗物的 `effect` 写明它改动的机制锚点（节点、术语或机制名），不泛写「强化所有 X」。 | 遗物 | 沿用：[遗物册 L31][r31] |
| L05 | 一级 | 遗物不设「唯一」或「可叠加」的去重机制。 | 遗物 | D-033 |
| L06 | 二级 | 遗物掉落先按稀有度分桶抽取。 | 遗物 | D-034 |

## N 数值与稀有度

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| N01 | 二级 | 数值模式（固定值、百分比、属性挂钩）按这件内容的定位选择，可单用或混合，没有唯一最优。 | 带数值的实体 | 沿用：[通则 L31][g31] |
| N02 | 一级 | 可反复触发的概率效果必须设递减或上限（限流与递减至少用一种）。 | 带数值的实体 | 沿用：[通则 L31][g31]、[天赋册 L262][t262] |
| N03 | 一级 | 写增伤先定它落在设计库 R1.1 的哪一层（技能威力、技能系数、普通天赋提升、总增与总降），再定数值。 | 天赋、技能 | D-036、设计库 R1.1 |
| N04 | 一级 | 多张卡可以共用同一乘区，不因乘区热门就判定卡错了；数学不同的修正通道各自保留，不为整齐统一措辞。 | 带数值的实体 | D-015、D-014 |
| N05 | 二级 | 定标先问数值落进哪条乘区再问给多少：拥挤的乘区要给得更多才等价。 | 带数值的实体 | D-013 |
| N06 | 一级 | 估算属性挂钩数值的预期时，基准取成长到 25 级的属性值 × 2；测试用的极端值不当证据；提请用户的数值区间按此基准。 | 带数值的实体 | D-016 |
| N07 | 一级 | 剑气的获得、消耗与阈值取 5 的倍数。 | 剑士线 | D-024 |
| N08 | 一级 | 剑气以固定 50 点分高低两区；卡面与汇报写固定点数条件（高于 50 点、不高于 50 点），不得换写成上限百分比，不得自造简称指代两个区间。 | 剑士线 | D-038、沿用：[天赋册 L107][t107] |
| N09 | 二级 | 基础配置下剑气花费大于收入；投入后在有利场景里主导是投入的回报。 | 剑士线 | D-073 |
| N10 | 一级 | 条件必须在结算时点真实可变；前置机制已保证成立的条件按无条件效果定标。 | 带条件的效果 | 沿用：[通则 L119][g119] |
| N11 | 一级 | 天赋稀有度按用户量化定档：传奇接近回忆、一定程度改变玩法；史诗是较强数值、新奇小机制或机制联动，不只是单一增伤；稀有与普通以数值为主，偶尔有改善操作的极小机制。 | 天赋 | D-010、D-011 |
| N12 | 一级 | 回忆与独特是特殊档，不进普通稀有度池，不影响其他档的出现概率。 | 天赋 | 沿用：[天赋册 L181][t181] |
| N13 | 二级 | 同一效果轴相邻稀有度的数值步进参考 ×1.3～1.5，不超过 ×1.5；仅在数值可比时适用。 | 天赋 | 沿用：[天赋册 L185][t185] |
| N14 | 二级 | 定标先做同池同档横向比较，再手算经济验证（逐回合产耗剑气、到达阈值的回合数、与〔心眼〕的联动、组合外溢）。 | 天赋 | 沿用：[天赋册 L188–189][t188-189] |
| N15 | 一级 | 减冷却是强度设计，不当作普通档的小数值；幅度一般取 −1，或改为加长现有位移技能的冷却。 | 天赋、回忆节点 | D-047 |
| N16 | 一级 | 评估输出组合时分别计算攻击动作次数、直接伤害段数、目标数、每段附伤数、每个目标的追加攻击数，不只比较最终百分比；组合样本充分之前只锁定结算关系，不提前压低数值。 | 评估 | 沿用：[天赋册 L73][t73]、[天赋册 L77][t77] |
| N17 | 二级 | 额外回合、额外行动类回忆单资源时低于对位、多资源时相对更高；评估按玩家标准与迅捷动作各最多 2 次、敌人每回合单次行动，看各方案的相对差异，不追究理论强度上升。 | 评估 | D-054、D-079 |
| N18 | 二级 | 敌人攻击模型可以大胆，不按属性推算。 | 敌人 | D-064 |
| N19 | 二级 | 剑圣的防御身份是闪避且整局有效；不新增百分比减伤；护盾可以有但量受控；新增或重做的节点不提高防御减伤。 | 剑圣 | D-061、D-062、D-063 |
| N20 | 二级 | 按剑气高低设计的卡默认共用 50 点阈值；用其他阈值时把差异作为明确设计内容定标，不能由剑气上限变化间接产生。 | 剑士线 | D-038、沿用：[天赋册 L113][t113] |
| N21 | 二级 | 减冷却效果的稀有度按它改变的行动经济定档，不因数字小而降档（推断）。 | 天赋、回忆节点 | D-047 |

## P 设计工作流程

| 编号 | 级别 | 规则 | 适用 | 来源 |
|---|---|---|---|---|
| P01 | 一级 | 动手前按 [设计规则面索引](design-rules-index.md) 读本表相关节、对应实体的指引和设计库现行记录；派发子代理时在提示里写明要读的节与指引。 | 全部设计工作 | D-001 |
| P02 | 一级 | 设计前读取同池当前实体、目标职业（`tier`、`promotes_from`、`stat_tiers`、`weapon_types`）和相关注册表，核对名称与机制，防止撞名撞机制。 | 全部设计工作 | 沿用：[通则 L14][g14]、[通则 L15][g15] |
| P03 | 一级 | 设计结论指到依据：本表编号、决策登记编号、设计库规则编号或用户裁决原话；没有依据的数值标「[占位]」或「推断」。 | 全部设计结论 | D-001、D-008 |
| P04 | 一级 | 结论与本表冲突时写明冲突的编号，交用户裁决，不静默违反。 | 全部设计结论 | D-001 |
| P05 | 一级 | 用户的新设计裁决：改本表对应行（没有就新增），在决策登记登记来源，删除被推翻的行；没有 KB 写入授权时，在汇报里列出待登记的裁决原话、日期和对应编号。 | 全部设计工作 | D-001 |
| P06 | 一级 | 修改基座机制、术语或规则时，同批检查在库实体对它的引用。 | 规则与机制变更 | 沿用：[通则 L17][g17] |
| P07 | 一级 | 查询、过滤或写入枚举前读取 live API 或当前 schema 的真实值。 | 设计库操作 | 沿用：[通则 L82][g82] |
| P08 | 一级 | 新内容落库 `status=待审阅`；新实体类型必须接入设计库的导入落库层。 | 设计库写入 | 沿用：[通则 L79][g79]、[通则 L80][g80] |
| P09 | 一级 | 写入生产设计库按 `sot-designlib` 流程：dry-run、独立审查、逐条写入回读。 | 设计库写入 | D-009 |
| P10 | 一级 | 设计库能存而 Ship 不消费的内容不写成已可实装；需要新枚举或共享形状合同时先作为用户审核项，不在内容任务中自行扩建。 | 设计与实装 | 沿用：[天赋册 L371][t371] |
| P11 | 一级 | 存量卡 trigger 回填先出逐条措辞映射清单交用户过目，代理不自行改在库卡的 trigger。 | 天赋、装备 | 沿用：[天赋册 L224][t224] |
| P12 | 一级 | 批量设计时检查命名长度、trigger 形状、效果类型、防滥用护栏、条件轴和节点形态的分布；同一解决方式在一批内反复出现时改换设计轴。 | 批量设计 | 沿用：[通则 L118][g118] |
| P13 | 一级 | 回忆升级先冻结固定工作集（记录 live API 版本、来源提交与集合摘要并与仓库快照对照，按 G02 筛材料，冻结全部相关对象）；兼容对象同时按结构化指向、玩家文案和通用结算语义检索，文本命中只用于发现候选。 | 回忆设计 | 沿用：[天赋册 L313][t313]、[天赋册 L315][t315] |
| P14 | 一级 | 回忆升级的收敛条件：方案字段完整、兼容矩阵无漏项、独立反方审查意见已处理，最终只提交一套推荐成果包；来源出现无法解释的漂移、冻结对象缺失、所需权威事实无法取得或写入将超出授权时停止。 | 回忆设计 | 沿用：[天赋册 L372][t372]、[天赋册 L405][t405] |

<!-- 行级出处：改写前固定提交 8b517dd 中的原句 -->
[e20]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L20
[e34-36]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L34-L36
[e44]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L44
[e45]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L45
[e50-53]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/equipment-design-principles.md#L50-L53
[g100]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L100
[g102]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L102
[g104-111]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L104-L111
[g115]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L115
[g117]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L117
[g118]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L118
[g119]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L119
[g13]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L13
[g14]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L14
[g15]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L15
[g17]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L17
[g31]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L31
[g57]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L57
[g61]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L61
[g63]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L63
[g67]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L67
[g79]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L79
[g80]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L80
[g82]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L82
[g97]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/content-design-general.md#L97
[p30]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/.agents/skills/sot-design-present/SKILL.md#L30
[p31]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/.agents/skills/sot-design-present/SKILL.md#L31
[p32]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/.agents/skills/sot-design-present/SKILL.md#L32
[p33]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/.agents/skills/sot-design-present/SKILL.md#L33
[p34]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/.agents/skills/sot-design-present/SKILL.md#L34
[r31]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/relic-design-principles.md#L31
[s12]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L12
[s20]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L20
[s22]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L22
[s27]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L27
[s31]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L31
[s39]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L39
[s44]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L44
[s91]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/skill-design-principles.md#L91
[t100]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L100
[t107]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L107
[t113]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L113
[t163]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L163
[t181]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L181
[t185]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L185
[t188-189]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L188-L189
[t209]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L209
[t221]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L221
[t223]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L223
[t224]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L224
[t231]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L231
[t232]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L232
[t233]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L233
[t251]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L251
[t252]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L252
[t254]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L254
[t260]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L260
[t262]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L262
[t266]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L266
[t270]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L270
[t286]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L286
[t288]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L288
[t295]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L295
[t296]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L296
[t297]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L297
[t300]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L300
[t301]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L301
[t313]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L313
[t315]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L315
[t330]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L330
[t349]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L349
[t354]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L354
[t359]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L359
[t370]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L370
[t371]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L371
[t372]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L372
[t385]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L385
[t405]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L405
[t73]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L73
[t77]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L77
[t81]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L81
[t83]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L83
[t87]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L87
[t90]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L90
[t91]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L91
[t97]: https://github.com/392fyc/Ship_of_Theseus/blob/8b517dd0c841396be21c98eb38f7d7daea508c32/docs/00-rules/talent-design-principles.md#L97
