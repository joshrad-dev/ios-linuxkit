#!/usr/bin/env bash
# perf-bench.sh — pinned multi-run performance benchmark for the ARM64 gadget executor.
#
# Runs every workload N times on a pinned CPU core and reports p5/p50/p95 timings
# in a Markdown table. No performance claim is valid without a row from this script.
#
# Usage:
#   ISH_BIN=./build-arm64-linux/ish ROOTFS=./alpine-arm64-fakefs ./tests/arm64/perf-bench.sh
#
# Knobs:
#   ISH_BIN          path to ish binary (default: build-arm64-linux/ish relative to project root)
#   ROOTFS           path to Alpine ARM64 fakefs (default: alpine-arm64-fakefs)
#   PERF_RUNS        iterations per workload (default: 21)
#   PERF_CPU         CPU core to pin to (default: 11 — highest big A720 on OPi6+)
#   REPORT_DIR       where to write the Markdown report (default: /workspace/tmp)
#   TIMEOUT_S        per-run timeout in seconds (default: 60)
#   HEAVY_TIMEOUT_S  per-run timeout for heavy workloads like go build (default: 120)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ISH_BIN="${ISH_BIN:-$PROJECT_DIR/build-arm64-linux/ish}"
ROOTFS="${ROOTFS:-$PROJECT_DIR/alpine-arm64-fakefs}"
PERF_RUNS="${PERF_RUNS:-21}"
PERF_CPU="${PERF_CPU:-11}"
REPORT_DIR="${REPORT_DIR:-/workspace/tmp}"
TIMEOUT_S="${TIMEOUT_S:-60}"
HEAVY_TIMEOUT_S="${HEAVY_TIMEOUT_S:-120}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/ish-arm64-perf-bench-$STAMP.md"

[ -x "$ISH_BIN" ] || { echo "missing ish binary: $ISH_BIN" >&2; exit 1; }
[ -d "$ROOTFS" ]   || { echo "missing rootfs: $ROOTFS" >&2; exit 1; }
mkdir -p "$REPORT_DIR"

ISH_CMD="taskset -c $PERF_CPU $ISH_BIN -f $ROOTFS"

# ── helpers ──────────────────────────────────────────────────────────────────

log() { printf '>>> %s\n' "$*"; }

# Run a guest command and return wall-clock milliseconds.
# Writes ms to stdout; non-zero exit or crash keyword → prints FAIL.
time_run() {
    local tmo="$1"; shift
    local cmd="$*"
    local tmp; tmp="$(mktemp)"
    local t0 t1 rc=0
    t0=$( date +%s%N )
    timeout "$tmo" $ISH_CMD /bin/sh -c \
        "export HOME=/root PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin NO_COLOR=1 CI=1 TERM=dumb; { $cmd; }; printf '\n__ISH_STATUS:%s\n' \$?" \
        >"$tmp" 2>&1 || rc=$?
    t1=$( date +%s%N )
    local ms=$(( (t1 - t0) / 1000000 ))
    if [ "$rc" -ne 0 ] || ! grep -q '^__ISH_STATUS:0$' "$tmp" ||
       grep -Eq 'SAFETY-VALVE|Segmentation fault|Bun has crashed|illegal instruction|HOST CRASH|page fault on|Assertion failed' "$tmp"; then
        rm -f "$tmp"
        echo "FAIL"
        return
    fi
    rm -f "$tmp"
    echo "$ms"
}

# Run PERF_RUNS times and compute p5/p50/p95.
# Prints: "p5=X p50=Y p95=Z" (all in ms), or FAIL if any run failed.
bench() {
    local label="$1"; local tmo="$2"; shift 2; local cmd="$*"
    local samples=()
    local fail=0
    log "  $label ($PERF_RUNS runs on cpu$PERF_CPU)"
    for i in $(seq 1 "$PERF_RUNS"); do
        local ms
        ms="$(time_run "$tmo" "$cmd")"
        if [ "$ms" = "FAIL" ]; then
            fail=$((fail + 1))
            printf ' FAIL'
        else
            samples+=("$ms")
            printf ' %s' "$ms"
        fi
    done
    printf '\n'
    if [ "${#samples[@]}" -lt 3 ]; then
        echo "FAIL"
        return
    fi
    # Sort and compute percentiles in python3 (always available on host)
    python3 - "${samples[@]}" <<'PY'
import sys, statistics
vals = sorted(int(x) for x in sys.argv[1:])
n = len(vals)
def pct(p): return vals[int(round(p/100*(n-1)))]
print(f"p5={pct(5)} p50={pct(50)} p95={pct(95)} min={vals[0]} max={vals[-1]} n={n}")
PY
}

# ── setup guest workload files once ──────────────────────────────────────────

log "Setting up guest workload files..."

# Write Python fib(30) script into the fakefs /tmp via a single ish run.
$ISH_CMD /bin/sh -c \
    'export HOME=/root; printf "def fib(n):\n  if n<=1: return n\n  return fib(n-1)+fib(n-2)\nprint(fib(30))\n" > /tmp/bench_fib.py' \
    >/dev/null 2>&1 || true

# Write Go fib source.
$ISH_CMD /bin/sh -c \
    'export HOME=/root; printf "package main\nimport \"fmt\"\nfunc fib(n int) int { if n<=1 { return n }; return fib(n-1)+fib(n-2) }\nfunc main() { fmt.Println(fib(30)) }\n" > /tmp/bench_fib.go' \
    >/dev/null 2>&1 || true

# Compile the Go binary once so the go-build bench only measures linking/codegen, not parse.
log "Pre-building go binary for go-run bench..."
timeout "$HEAVY_TIMEOUT_S" $ISH_CMD /bin/sh -c \
    'export HOME=/root PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; go build -o /tmp/bench_fib_bin /tmp/bench_fib.go' \
    >/dev/null 2>&1 || log "  (go build warmup failed — go-build bench may FAIL)"

# ── run benchmarks ────────────────────────────────────────────────────────────

log "Running benchmarks (cpu=$PERF_CPU, runs=$PERF_RUNS)..."

BENCH_ROWS=()

run_bench() {
    local name="$1"; local tmo="$2"; local cmd="$3"
    log "Workload: $name"
    local result
    result="$(bench "$name" "$tmo" "$cmd")"
    BENCH_ROWS+=("$name|$result")
    log "  → $result"
}

# 1. Shell startup — time to launch /bin/sh and print a token (exit 0 prevents status print).
run_bench "shell startup" "$TIMEOUT_S" \
    'true'

# 2. Shell loop 500 — classic micro-benchmark from IR speed log (comparability).
run_bench "shell loop 500" "$TIMEOUT_S" \
    'i=0; while [ $i -lt 500 ]; do i=$((i+1)); done'

# 3. Shell loop 2000 — longer variant to reduce startup dominance.
run_bench "shell loop 2000" "$TIMEOUT_S" \
    'i=0; while [ $i -lt 2000 ]; do i=$((i+1)); done'

# 4. Python fib(30) — interpreter-heavy, tests ALU/branch throughput.
run_bench "python fib(30)" "$TIMEOUT_S" \
    'python3 /tmp/bench_fib.py'

# 5. Bun JSON — JS runtime throughput, JSC, mmap behaviour.
run_bench "bun json 12000" "$TIMEOUT_S" \
    'bun -e "let s=0;for(let i=0;i<12000;i++){s+=JSON.parse(JSON.stringify({a:i,b:i*2,c:[i,i+1,i+2]})).a}console.log(s)"'

# 6. Bun eval startup — measures Bun/JSC cold start only.
run_bench "bun startup" "$TIMEOUT_S" \
    'bun --version'

# 7. Node eval startup.
run_bench "node startup" "$TIMEOUT_S" \
    'node --version'

# 8. Go run fib(30) — Go runtime startup + execution.
run_bench "go run fib(30)" "$TIMEOUT_S" \
    'go run /tmp/bench_fib.go'

# 9. Go build — linker/codegen heavy, exercises mmap and large-VA paths.
run_bench "go build fib" "$HEAVY_TIMEOUT_S" \
    'go build -o /tmp/bench_fib_out /tmp/bench_fib.go'

# ── write report ──────────────────────────────────────────────────────────────

log "Writing report: $REPORT"

ISH_VERSION="$(cd "$PROJECT_DIR" && git log -1 --format='%h %s')"

{
cat <<EOF
# iSH ARM64 performance benchmark

- Timestamp: $(date -Is)
- Binary: $ISH_BIN
- Rootfs: $ROOTFS
- Runs: $PERF_RUNS
- Pinned CPU: $PERF_CPU ($(cat /sys/devices/system/cpu/cpu${PERF_CPU}/cpufreq/cpuinfo_max_freq 2>/dev/null || echo '?') Hz max)
- Host: $(uname -n) / $(uname -r)
- Load at start: $(uptime | awk -F'load average:' '{print $2}' | xargs)
- Commit: $ISH_VERSION

## Results

| Workload | p5 ms | p50 ms | p95 ms | min ms | max ms | n |
|---|---:|---:|---:|---:|---:|---:|
EOF

for row in "${BENCH_ROWS[@]}"; do
    name="${row%%|*}"
    stats="${row#*|}"
    if [ "$stats" = "FAIL" ]; then
        printf '| %s | FAIL | FAIL | FAIL | FAIL | FAIL | 0 |\n' "$name"
    else
        p5=$(echo "$stats"   | grep -o 'p5=[0-9]*'   | cut -d= -f2)
        p50=$(echo "$stats"  | grep -o 'p50=[0-9]*'  | cut -d= -f2)
        p95=$(echo "$stats"  | grep -o 'p95=[0-9]*'  | cut -d= -f2)
        min=$(echo "$stats"  | grep -o 'min=[0-9]*'  | cut -d= -f2)
        max=$(echo "$stats"  | grep -o 'max=[0-9]*'  | cut -d= -f2)
        n=$(echo "$stats"    | grep -o 'n=[0-9]*'    | cut -d= -f2)
        printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
            "$name" "$p5" "$p50" "$p95" "$min" "$max" "$n"
    fi
done

cat <<'EOF'

## Notes

- All timings are wall-clock milliseconds measured on the host (includes guest startup).
- p5/p50/p95 computed over PERF_RUNS runs on a pinned CPU core.
- A workload row is not a valid baseline if host load was >2.0 during the run.
- Shell loop rows are directly comparable to the historic IR speed-log rows (same workload).
EOF
} >"$REPORT"

log "Report: $REPORT"
echo "report: $REPORT"
exit 0
