#!/usr/bin/env bash
# 逐个运行 tests/test_*.gd（extends SceneTree 的 headless 回归脚本，约定退出码 0 = 全过）。
# 用法：GODOT=<godot 可执行文件> tools/ci/run_godot_tests.sh [测试名匹配串 ...]
# 本地与 CI 共用；capture_* / exp_* 需要渲染或属于实验，不在这里跑；
# 需要图形渲染的 test_* 登记在 godot_render_only_tests.txt 中跳过。
set -u

GODOT="${GODOT:?请用 GODOT 环境变量指定 Godot 可执行文件}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PER_TEST_TIMEOUT="${PER_TEST_TIMEOUT:-300}"
LOG_DIR="${LOG_DIR:-$ROOT/.ci-logs}"
mkdir -p "$LOG_DIR"

# 首次检出没有 .godot/ 导入缓存：先导入一次，否则 preload 的资源找不到。
echo "::group::导入项目资源"
timeout 600 "$GODOT" --headless --path "$ROOT" --import >"$LOG_DIR/_import.log" 2>&1
import_code=$?
echo "导入结束，退出码 $import_code（导入阶段的警告不判失败）"
echo "::endgroup::"
if [ "$import_code" -ne 0 ]; then
  echo "项目导入失败，后续测试没有意义："; tail -n 40 "$LOG_DIR/_import.log"; exit 1
fi
# 导入会编译全部脚本：借此做一次廉价的 GDScript 解析检查。
if grep -aE "SCRIPT ERROR|Parse Error" "$LOG_DIR/_import.log"; then
  echo "导入时出现脚本解析错误（见上）"; exit 1
fi

mapfile -t tests < <(cd "$ROOT" && ls tests/test_*.gd | sort)
if [ "$#" -gt 0 ]; then
  filtered=()
  for t in "${tests[@]}"; do
    for pat in "$@"; do [[ "$t" == *"$pat"* ]] && filtered+=("$t") && break; done
  done
  tests=("${filtered[@]}")
fi
if [ "${#tests[@]}" -eq 0 ]; then
  echo "没有匹配的测试文件，按失败处理，避免误报通过"; exit 1
fi

# 只能在有显示环境时运行的测试（清单见 godot_render_only_tests.txt）。
declare -A render_only=()
while read -r entry _; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  [ -f "$ROOT/tests/$entry.gd" ] || { echo "跳过清单里的 $entry 已不存在，请同步清单"; exit 1; }
  render_only["$entry"]=1
done < "$ROOT/tools/ci/godot_render_only_tests.txt"

pass=0; skipped=0; failed=()
for t in "${tests[@]}"; do
  name="$(basename "$t" .gd)"
  if [ -n "${render_only[$name]:-}" ]; then
    skipped=$((skipped + 1)); echo "SKIP  $name（需要图形渲染）"; continue
  fi
  log="$LOG_DIR/$name.log"
  start=$(date +%s)
  timeout "$PER_TEST_TIMEOUT" "$GODOT" --headless --path "$ROOT" --script "res://$t" >"$log" 2>&1
  code=$?
  secs=$(( $(date +%s) - start ))
  if [ "$code" -eq 0 ]; then
    pass=$((pass + 1)); echo "PASS  $name (${secs}s)"
  else
    failed+=("$name"); echo "FAIL  $name (退出码 $code, ${secs}s)"
    echo "::group::$name 日志末尾"; tail -n 40 "$log"; echo "::endgroup::"
  fi
done

echo "通过 $pass，跳过 $skipped，共 ${#tests[@]}"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '失败：%s\n' "${failed[@]}"
  exit 1
fi
