---
name: sot-designlib
description: "Operate the SoT design library (SoT 设计库) end to end: read/write its data, run scripts inside its container, and ship code changes. Use whenever a task touches 设计库 / SoT-fyc-space / the talent-skill-rule database, its NAS deployment, or its web UI. Encodes the QNAP Container Station quirks and the verification rules that previous sessions got wrong."
---

# SoT 设计库操作

设计库 = 天赋 / 技能 / 规则 / 装备 / 遗物的**单一事实源**，FastAPI + SQLite + Jinja2 + HTMX + Alpine，跑在 NAS 的 Docker 容器里。

| 项 | 值 |
|---|---|
| 代码仓 | `D:\ShipOfTheseus\SoT-fyc-space`（master，有私有远端） |
| NAS 部署目录 | `/share/homes/392fyc/sot-codex`（**拷贝部署，非 git**；旁边一堆 `app.backup-*`） |
| 容器 | `sot-codex-app-1`（应用）、`sot-codex-tunnel-1`（Cloudflare 隧道） |
| 宿主访问 | `http://localhost:8400` |
| **容器内**访问 | `http://localhost:8000` ← 端口不同，别搞混 |
| 公网 | `https://sot.fyc-space.uk`（Cloudflare Access 挡，脚本别走公网） |
| API token | NAS 的 `/share/homes/392fyc/sot-codex/.env` 里 `API_TOKEN=` |

SSH 凭据与 sudo 密码见 `~/.claude/commands/nas-ssh.md`（是 **command 不是 skill**，按 skill 找会找不到）。

---

## 一、读数据：从 NAS 内部 curl

公网被 Access 挡，宿主直连即可。**设计库是活数据**，Mercury 会直接改生产库——仓库 HEAD 不动不代表数据没变，凡计数必须当场数，别信文档或快照。

```bash
ssh -i C:/Users/392fy/.ssh/id_ed25519 392fyc@192.168.0.254 \
  "cd /share/homes/392fyc/sot-codex && T=\$(grep -E '^API_TOKEN=' .env | head -1 | cut -d= -f2- | tr -d '\"' | tr -d '\r'); \
   curl -s -H \"X-API-Token: \$T\" 'http://localhost:8400/api/talents?include_shelved=true'"
```

- **列表端点必须加 `include_shelved=true`**，否则数不到已归档与待删除的。
- 端点：`/api/{talents,skills,equipment,relics,rules,tags,classes,resources,states,judgments}`。
- 拿回来的 JSON 用**本地** python 解析——NAS 宿主没有 python3 也没有 jq。

## 二、写数据：PATCH + 回读核对

批量写生产数据前先 dry-run。参考 `scripts/backfill_trigger.py` 的做法：默认不写、写入后**立即回读比对**，不一致就停。别做「发完 200 就算成功」。

跑脚本要进容器（宿主无 python3）：

```bash
# 文件传到 NAS（scp 不可用！QNAP 没开 sftp subsystem，用 ssh 管道）
cat plan.json | ssh -i <key> 392fyc@192.168.0.254 "cat > /tmp/plan.json"

# 再送进容器执行，注意 SOT_API_BASE 用容器内端口 8000
ssh -i <key> 392fyc@192.168.0.254 'cd /share/homes/392fyc/sot-codex
T=$(grep -E "^API_TOKEN=" .env | head -1 | cut -d= -f2- | tr -d "\"" | tr -d "\r")
CSD="/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker -H unix:///var/run/system-docker.sock"
$CSD cp /tmp/plan.json sot-codex-app-1:/tmp/
$CSD exec -e SOT_API_TOKEN="$T" -e SOT_API_BASE="http://localhost:8000" \
  sot-codex-app-1 python /tmp/script.py --plan /tmp/plan.json'
```

## 三、改代码 → 上线：只走 deploy.sh

**只提交不部署等于没做。** 曾因此让三批改动（equipment 四字段、trigger 分级选择器、标签悬浮换行）在线上消失了整整一周，用户以为「什么都没做」。

```bash
cd /d/ShipOfTheseus/SoT-fyc-space
bash scripts/deploy.sh            # 同步 → 构建 → 重建容器 → 健康检查 → 版本核对
bash scripts/deploy.sh --check    # 只读自检
bash scripts/deploy.sh --no-build # 只同步（不算上线）
```

sudo 密码放 `scripts/deploy.local`（gitignored，从 nas-ssh.md 取），否则脚本会因为没有 tty 而中止。

跑测试**必须用仓内虚拟环境**：`.venv/Scripts/python.exe -m pytest -q`。用系统 Python 会报 32 个 collection error（`No module named 'sqlalchemy'`），看着像代码坏了、其实只是环境不对。

## 四、QNAP Container Station 的坑（全部实测过）

1. **docker 不在 PATH**，在 `/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker`。直接敲 `docker` 得到的是 `command not found`——若把 stderr 丢了（`2>/dev/null`）就会看成「零输出 = 没有容器」，从而误判。
2. **必须显式 `-H unix:///var/run/system-docker.sock`**。`/var/run/docker.sock` **不存在**。
3. **非 root 下 `build` 与 `compose` 两个子命令不可见**——不报错，只打印通用帮助。`ps` / `exec` / `cp` / `restart` 可用。所以构建必须 sudo。
4. **`392fyc` 在 administrators 组，但 sudo 仍要密码**；交互式 `sudo` 需要 tty，agent 环境没有 → 用 `sudo -S` 从 stdin 喂密码。
5. **busybox 工具集很窄**：没有 `comm`、没有 `python3`、没有 `jq`；`find` 不支持 `-empty`，也不支持某些 `-o` 组合。写要在 NAS 上跑的 shell 前先探测，别照 GNU 习惯写。
6. **scp 不可用**（连接直接关闭），用 `cat file | ssh host "cat > /tmp/file"`。

## 五、验证纪律（这几条都是踩过才写下来的）

**★ 用与被验对象相同的解析规则，否则结论必然是错的。**

1. **验「线上是不是新代码」要看运行时行为，不能比对文件。** 文件送到了 ≠ 进程加载了。deploy.sh 的做法是拉线上的设计书导航、数条目数，与本地 `NAV_STRUCTURE` 比。曾经文件明明是新的、容器跑的还是旧逻辑。
2. **验 HTML 属性要用 `html.parser`，不能用正则。** 曾用宽松正则跨引号取 `x-data`，把浏览器眼里已经破碎的 HTML 又拼回成完整 JSON，于是判定「服务端数据完全正常」，白白去猜 CDN 和 Rocket Loader。真凶是 `x-data="...{{ x|tojson }}..."` 用了双引号——**Jinja 的 tojson 只转义 `< > & '`，不转义 `"`**，属性在 JSON 第一个双引号处就被截断。同类写法必须用单引号包裹。
3. **Alpine 渲染的东西不能在服务端 HTML 里 grep。** 下拉选项与 `selected` 状态是浏览器端由 `x-for` / `x-model` 生成的，服务端根本不输出。要验当前值，去解析传给组件的初始参数（`x-data="triggerPicker({...}, {...})"` 的第一个实参）。
4. **任何「零命中 / 零输出」先自证有权限、有工具、命令真的执行了。** 三次误判都源于此：非 root 跑 `crontab -l` 被 QNAP 拒绝、`docker` 不在 PATH 而 stderr 被丢、远端没有 `comm` 导致差集恒为空却照样打印「无过期文件」。
5. **改测试断言时，要断言新的正确行为并补反向断言**，不要放宽成「怎么都能过」。

## 六、数据结构要点

- **稀有度**：普通 / 稀有 / 史诗 / 传奇 / 独特（`app/models.py` `Rarity`）。
- **基数来源** `damage_type`：无 / 物理 / 魔法 / 混合（2026-08-04 起改名并去掉「纯粹」——「纯粹」属于应用侧，不是基数取哪个属性）。引擎侧 Godot 仓的 `damage_type` 是**独立 taxonomy**（physical/magical/pure），两者不要互相套用。
- **生效时机五段**：`trigger_event`（23 个枚举，9 族）/ `trigger_object`（仅 8 个事件带此槽，值必须是注册表 id）/ `trigger_source`（仅 6 个事件带此槽）/ `trigger_condition`（自由文本）/ `trigger_frequency` + `_n`。槽位约束服务端会 400。
- **架状态** `shelf_state`：在用 / 已归档 / 待删除，只有「在用」进池。
- 天赋回填现状与遗留缺口见 `docs/trigger-backfill-2026-08-04.md`。

## 七、别做的事

- 别从公网 curl 写数据（Cloudflare Access 会挡）。
- 别手编 `engine_json`（引擎数值只读镜像，Mercury 有回填管线，手改会被覆盖）。
- 别把条数写进文档当真源——活数据，当场数。
- 别在归档 / 待删除的卡上做批量回填，那些措辞是草稿速记，硬映射产生的是看着有结构、实则不可信的数据。
