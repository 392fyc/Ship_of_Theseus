# 核心战斗循环实证结果 — 剑圣资源打法对照

TRIALS=120  ROUNDS=14  居合剑气费=6  拔刀剑气费=2  剑气上限=10
WALL=单·不灭木桩(HP999 DEF2 永不死)  WAVE=单·复活木桩(HP30 DEF1 每回合复活)  PACK=三·复活木桩簇

## 汇总表

| 场景 | 策略 | 总伤害 | ±std | 每回合 | 动作熵 | 均剑气 | 满气% | 浪费气/局 | 浪费印/局 | 倾泻/局 | 击杀/局 | 居合杀/局 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| WALL | BASE | 242.5 | 12.2 | 17.3 | 0.00 | 6.1 | 29% | 4.00 | 11.00 | 0.00 | 0.00 | 0.00 |
| WALL | IAI | 347.5 | 10.5 | 24.8 | 0.59 | 3.0 | 0% | 0.00 | 9.00 | 2.00 | 0.00 | 0.00 |
| WALL | IAI_CD | 504.6 | 8.1 | 36.0 | 0.94 | 0.9 | 0% | 0.00 | 7.00 | 5.00 | 0.00 | 0.00 |
| WALL | BADAO | 270.3 | 32.2 | 19.3 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 0.00 | 0.00 |
| WALL | GREEDY | 270.3 | 32.2 | 19.3 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 0.00 | 0.00 |
| WAVE | BASE | 259.0 | 13.5 | 18.5 | 0.00 | 6.1 | 29% | 4.00 | 11.00 | 0.00 | 0.00 | 0.00 |
| WAVE | IAI | 278.0 | 11.9 | 19.9 | 0.59 | 3.6 | 0% | 0.00 | 9.00 | 2.00 | 2.00 | 2.00 |
| WAVE | IAI_CD | 338.9 | 9.8 | 24.2 | 1.00 | 3.2 | 0% | 0.00 | 6.00 | 7.00 | 7.00 | 7.00 |
| WAVE | BADAO | 268.7 | 11.1 | 19.2 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 0.40 | 0.00 |
| WAVE | GREEDY | 268.7 | 11.1 | 19.2 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 0.40 | 0.00 |
| PACK | BASE | 259.0 | 13.5 | 18.5 | 0.00 | 6.1 | 29% | 4.00 | 11.00 | 0.00 | 0.00 | 0.00 |
| PACK | IAI | 278.0 | 11.9 | 19.9 | 0.59 | 3.6 | 0% | 0.00 | 9.00 | 2.00 | 2.00 | 2.00 |
| PACK | IAI_CD | 338.9 | 9.8 | 24.2 | 1.00 | 3.2 | 0% | 0.00 | 6.00 | 7.00 | 7.00 | 7.00 |
| PACK | BADAO | 366.4 | 17.3 | 26.2 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 1.34 | 0.00 |
| PACK | GREEDY | 366.4 | 17.3 | 26.2 | 0.75 | 2.6 | 0% | 0.00 | 0.00 | 3.00 | 1.34 | 0.00 |

## 技能使用分布（次数合计 / 伤害占比）

| 场景 | 策略 | 斩击 | 居合 | 拔刀 | 居合伤% | 拔刀伤% | 斩击伤% |
|---|---|---:|---:|---:|---:|---:|---:|
| WALL | BASE | 1680 | 0 | 0 | 0% | 0% | 100% |
| WALL | IAI | 1440 | 240 | 0 | 41% | 0% | 59% |
| WALL | IAI_CD | 1080 | 600 | 0 | 70% | 0% | 30% |
| WALL | BADAO | 1320 | 0 | 360 | 0% | 36% | 64% |
| WALL | GREEDY | 1320 | 0 | 360 | 0% | 36% | 64% |
| WAVE | BASE | 1680 | 0 | 0 | 0% | 0% | 100% |
| WAVE | IAI | 1440 | 240 | 0 | 22% | 0% | 78% |
| WAVE | IAI_CD | 840 | 840 | 0 | 62% | 0% | 38% |
| WAVE | BADAO | 1320 | 0 | 360 | 0% | 31% | 69% |
| WAVE | GREEDY | 1320 | 0 | 360 | 0% | 31% | 69% |
| PACK | BASE | 1680 | 0 | 0 | 0% | 0% | 100% |
| PACK | IAI | 1440 | 240 | 0 | 22% | 0% | 78% |
| PACK | IAI_CD | 840 | 840 | 0 | 62% | 0% | 38% |
| PACK | BADAO | 1320 | 0 | 360 | 0% | 49% | 51% |
| PACK | GREEDY | 1320 | 0 | 360 | 0% | 49% | 51% |

## DATA
DATA|scn=WALL|pol=BASE|dmg=242.49|std=12.23|dpr=17.32|ent=0.000|qi=6.07|capped=0.286|wqi=4.00|wmk=11.00|dump=0.00|kill=0.00|jkill=0.00
DATA|scn=WALL|pol=IAI|dmg=347.49|std=10.49|dpr=24.82|ent=0.592|qi=3.00|capped=0.000|wqi=0.00|wmk=9.00|dump=2.00|kill=0.00|jkill=0.00
DATA|scn=WALL|pol=IAI_CD|dmg=504.58|std=8.05|dpr=36.04|ent=0.940|qi=0.86|capped=0.000|wqi=0.00|wmk=7.00|dump=5.00|kill=0.00|jkill=0.00
DATA|scn=WALL|pol=BADAO|dmg=270.27|std=32.16|dpr=19.31|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=0.00|jkill=0.00
DATA|scn=WALL|pol=GREEDY|dmg=270.27|std=32.16|dpr=19.31|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=0.00|jkill=0.00
DATA|scn=WAVE|pol=BASE|dmg=259.00|std=13.52|dpr=18.50|ent=0.000|qi=6.07|capped=0.286|wqi=4.00|wmk=11.00|dump=0.00|kill=0.00|jkill=0.00
DATA|scn=WAVE|pol=IAI|dmg=278.02|std=11.91|dpr=19.86|ent=0.592|qi=3.64|capped=0.000|wqi=0.00|wmk=9.00|dump=2.00|kill=2.00|jkill=2.00
DATA|scn=WAVE|pol=IAI_CD|dmg=338.86|std=9.75|dpr=24.20|ent=1.000|qi=3.21|capped=0.000|wqi=0.00|wmk=6.00|dump=7.00|kill=7.00|jkill=7.00
DATA|scn=WAVE|pol=BADAO|dmg=268.73|std=11.11|dpr=19.19|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=0.40|jkill=0.00
DATA|scn=WAVE|pol=GREEDY|dmg=268.73|std=11.11|dpr=19.19|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=0.40|jkill=0.00
DATA|scn=PACK|pol=BASE|dmg=259.00|std=13.52|dpr=18.50|ent=0.000|qi=6.07|capped=0.286|wqi=4.00|wmk=11.00|dump=0.00|kill=0.00|jkill=0.00
DATA|scn=PACK|pol=IAI|dmg=278.02|std=11.91|dpr=19.86|ent=0.592|qi=3.64|capped=0.000|wqi=0.00|wmk=9.00|dump=2.00|kill=2.00|jkill=2.00
DATA|scn=PACK|pol=IAI_CD|dmg=338.86|std=9.75|dpr=24.20|ent=1.000|qi=3.21|capped=0.000|wqi=0.00|wmk=6.00|dump=7.00|kill=7.00|jkill=7.00
DATA|scn=PACK|pol=BADAO|dmg=366.44|std=17.33|dpr=26.17|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=1.34|jkill=0.00
DATA|scn=PACK|pol=GREEDY|dmg=366.44|std=17.33|dpr=26.17|ent=0.750|qi=2.64|capped=0.000|wqi=0.00|wmk=0.00|dump=3.00|kill=1.34|jkill=0.00
