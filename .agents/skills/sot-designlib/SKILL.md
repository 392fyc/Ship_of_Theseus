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

SSH 凭据与 `sudo` 密码必须来自用户明确提供或受保护运行时环境，不在文档里明示明文，也不写入到脚本输出。

---

## 一、读数据：从 NAS 内部 curl

公网被 Access 挡，宿主直连即可。**设计库是活数据**，Mercury 会直接改生产库——仓库 HEAD 不动不代表数据没变，凡计数必须当场数，别信文档或快照。

```bash
ssh -i C:/Users/392fy/.ssh/id_ed25519 392fyc@192.168.0.254 \
  "cd /share/homes/392fyc/sot-codex && T=\$(grep -E '^API_TOKEN=' .env | head -1 | cut -d= -f2- | tr -d '\"' | tr -d '\r'); \
   curl -s -H \"X-API-Token: \$T\" 'http://localhost:8400/api/talents?include_shelved=true'"
```

- **数全量必须带对参数**：talents / relics / equipment 加 `include_shelved=true`（否则漏掉已归档与待删除），skills 加 `include_upgrades=true`（否则漏掉回忆天赋产出的升级版技能）。其余端点没有这两个参数，传了会被静默忽略。
- 端点：`/api/{talents,skills,equipment,relics,rules,tags,classes,resources,states,judgments}`。
- 拿回来的 JSON 用**本地** python 解析——NAS 宿主没有 python3 也没有 jq。

## 二、写数据：PATCH + 回读核对

批量写生产数据前先 dry-run。参考 `scripts/backfill_trigger.py` 的做法：默认不写、写入后**立即回读比对**，不一致就停。别做「发完就算成功」。

实体 id 可改（2026-08-05 起）：`POST /api/{talents,skills,equipment,relics,states,resources,judgments}/{id}/rename-id`，body `{"new_id": "..."}`——全库引用单事务级联（对象槽按事件类型过滤防跨注册表误改），返回各引用点更新行数。id 是建卡时的拼音助记，改名后用它纠正 id、别放着旧拼音骗人。

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

**只提交不部署等于没做。** 曾因此让三批改动在线上消失了整整一周，用户以为「什么都没做」。

```bash
cd /d/ShipOfTheseus/SoT-fyc-space
bash scripts/deploy.sh            # 同步 → 构建 → 重建容器 → 健康检查 → 版本核对
bash scripts/deploy.sh --check    # 只读自检
bash scripts/deploy.sh --no-build # 只同步（不算上线）
```

sudo 密码放 `scripts/deploy.local`（gitignored，从 nas-ssh.md 取），缺失时脚本在无 tty 环境会直接中止并给出补救路径。

## 四、写测试：照抄既有脚手架，别自己发明

曾有一轮独立写验证脚手架连撞 14 次失败，全是下面这些约定没对上，没有一次是实装错。**先照抄参考测试，再写新断言。**

1. **必须用仓内虚拟环境**：`.venv/Scripts/python.exe -m pytest -q`。系统 Python 会在 collection 阶段成片报 `No module named 'sqlalchemy'`，看着像代码坏了、其实只是环境不对。
2. **鉴权**：`API_TOKEN` 是 `app/deps.py` 在 import 期读入的模块常量，`monkeypatch.setenv` 已经太晚 → `monkeypatch.setattr(deps, "API_TOKEN", "t")`（照 `tests/test_class_tier_api.py`）。例外：review 系端点的 `require_review_token` 故意从 `config` 动态读属性，要 patch `config`（照 `tests/test_review_async.py`）。
3. **夹具标准写法**：内存 engine + `tests/fixtures/design_library_fixture.json` + `app.seed.import_payload` + `app.dependency_overrides[get_session]`（照 `tests/test_classes_page.py`）。
4. **状态码**：POST 建资源返回 **201**，PATCH 才是 200。
5. **`SkillIn.skill_type` 无默认值**（2026-07-08 裁决：强制显式声明），构造技能 payload 漏传直接 422。
6. **L1 校验的真实入口**是 `run_l1_deterministic(candidate, ctx)` + `L1Context`（`app/validation/l1.py`），不是想当然的 `run_l1` / `ValidationContext`。
7. **改断言要断言新的正确行为并补反向断言**，不要放宽成「怎么都能过」。

## 五、QNAP Container Station 的坑（全部实测过）

1. **docker 的唯一正确调用**：`/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker -H unix:///var/run/system-docker.sock`。它不在 PATH（直接敲 `docker` 是 command not found，stderr 一丢就会误判成「没有容器」），且 `/var/run/docker.sock` **不存在**，socket 必须显式指定。
2. **非 root 下 `build` 与 `compose` 两个子命令不可见**——不报错，只打印通用帮助。`ps` / `exec` / `cp` / `restart` 可用。所以构建必须 sudo。
3. **sudo 要密码，交互式 sudo 要 tty**，agent 环境没有 → 用 `sudo -S` 从 stdin 喂密码。
4. **busybox 工具集很窄**：没有 `comm`、`python3`、`jq`；`find` 不支持 `-empty`，也不支持某些 `-o` 组合。写要在 NAS 上跑的 shell 前先探测，别照 GNU 习惯写。
5. **scp 不可用**（连接直接关闭），用 `cat file | ssh host "cat > /tmp/file"`。

## 六、验证纪律（这几条都是踩过才写下来的）

**★ 用与被验对象相同的解析规则，否则结论必然是错的。**

1. **验「线上是不是新代码」要看运行时行为，不能比对文件。** 文件送到了 ≠ 进程加载了。deploy.sh 的做法是拉线上的设计书导航、数条目数，与本地 `NAV_STRUCTURE` 比。曾经文件明明是新的、容器跑的还是旧逻辑。
2. **验 HTML 属性要用 `html.parser`，不能用正则。** 曾用宽松正则把浏览器眼里已经破碎的属性拼回「完整 JSON」，判成「服务端完全正常」，白白去猜 CDN。根因：**Jinja 的 `tojson` 只转义 `< > & '`，不转义 `"`**，`x-data="...{{ x|tojson }}..."` 在 JSON 第一个双引号处就截断——这类属性必须用单引号包裹。
3. **Alpine 渲染的东西不能在服务端 HTML 里 grep。** 下拉选项与 `selected` 状态是浏览器端由 `x-for` / `x-model` 生成的，服务端根本不输出。要验当前值，去解析传给组件的初始参数（`x-data="triggerPicker({...}, {...})"` 的第一个实参）。
4. **任何「零命中 / 零输出」先自证有权限、有工具、命令真的执行了。** 三次误判都源于此：非 root 跑 `crontab -l` 被 QNAP 拒绝、`docker` 不在 PATH 而 stderr 被丢、远端没有 `comm` 导致差集恒为空却照样打印「无过期文件」。

## 七、数据结构要点

- **稀有度**（`app/models.py` `Rarity`）：普通 / 稀有 / 史诗 / 传奇 / 独特 / **回忆**。末两档是特殊档，不进普通稀有度池。回忆 = 技能升级专用：`Talent.upgrade_skill_id` 指向升级后技能，`Skill.upgrade_of` 标记它是谁的升级版；升级版技能默认不出现在列表端点。
- **基数来源** `damage_type`：无 / 物理 / 魔法 / 混合（2026-08-04 起改名并去掉「纯粹」——「纯粹」属于应用侧，不是基数取哪个属性）。引擎侧 Godot 仓的 `damage_type` 是**独立 taxonomy**（physical/magical/pure），两者不要互相套用。
- **生效时机五段**：`trigger_event`（24 个枚举，9 族，2026-08-05 起含「命中后」）/ `trigger_object`（仅 8 个事件带此槽，值必须是注册表 id）/ `trigger_source`（仅 7 个事件带此槽）/ `trigger_condition`（自由文本）/ `trigger_frequency` + `_n`。槽位约束服务端会 400（枚举与槽位表都定义在 `app/models.py`，`validation/trigger.py` 只是引用）。天赋另有**附加触发行**子表（`talent_trigger_extra`，每卡 ≤1 行；API 字段 `extra_triggers`：缺省=不动、`[]`=清空、给列表=整组替换）。
- **上架状态** `shelf_state`：在用 / 已归档 / 待删除，只有「在用」进池。
- 天赋回填现状与遗留缺口见 `docs/trigger-backfill-2026-08-04.md`。

## 八、别做的事

- 别从公网 curl 写数据（Cloudflare Access 会挡）。
- 别手编 `engine_json`（引擎数值只读镜像，Mercury 有回填管线，手改会被覆盖）。
- 别把条数写进文档当真源——活数据，当场数。
- 别在归档 / 待删除的卡上做批量回填，那些措辞是草稿速记，硬映射产生的是看着有结构、实则不可信的数据。
