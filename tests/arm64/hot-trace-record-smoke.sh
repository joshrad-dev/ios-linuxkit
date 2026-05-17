#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ISH_BIN="${ISH_BIN:-$PROJECT_DIR/build-arm64-linux/ish}"
ROOTFS="${ROOTFS:-$PROJECT_DIR/alpine-arm64-fakefs}"
ROOTFS_LANES="${ROOTFS_LANES:-alpine=$ROOTFS}"
TIMEOUT_S="${TIMEOUT_S:-120}"
REPORT_DIR="${REPORT_DIR:-/workspace/tmp}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/ish-arm64-hot-trace-record-smoke-$STAMP.md"
HOST_TMP="$(mktemp -d)"
LANE_NAME=default
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0
REPORT_ROWS=""

cleanup() {
    rm -rf "$HOST_TMP"
}
trap cleanup EXIT

mkdir -p "$REPORT_DIR"

append_row() {
    local stage="$1"
    local name="$2"
    local status="$3"
    local detail="$4"
    REPORT_ROWS+="| $LANE_NAME | $stage | $name | $status | ${detail//$'\n'/<br>} |"$'\n'
}

record_result() {
    local stage="$1"
    local name="$2"
    local status="$3"
    local detail="$4"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    printf '[%s/%s] %s ... %s\n' "$LANE_NAME" "$stage" "$name" "$status"
    if [ "$status" = PASS ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    append_row "$stage" "$name" "$status" "$(printf '%s' "$detail" | sed 's/|/\\|/g')"
}

guest_capture() {
    local out="$1"
    local env_prefix="$2"
    local cmd="$3"
    set +e
    timeout "$TIMEOUT_S" env $env_prefix "$ISH_BIN" -f "$ROOTFS" /bin/sh -lc "export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=/root NO_COLOR=1 CI=1 TERM=dumb; { $cmd; }; rc=\$?; printf '\n__ISH_STATUS:%s\n' \"\$rc\"" >"$out" 2>&1
    local rc=$?
    set -e
    return "$rc"
}

has_clean_status() {
    local out="$1"
    grep -q '^__ISH_STATUS:0$' "$out" && ! grep -Eq 'SAFETY-VALVE|HOST CRASH|Segmentation fault|Assertion failed|Bun has crashed|Illegal instruction' "$out"
}

stat_field() {
    local out="$1"
    local key="$2"
    grep 'ARM64_BLOCK_HOT_STATS' "$out" | tail -1 | tr ' ' '\n' | awk -F= -v key="$key" '$1 == key { print $2; found=1; exit } END { if (!found) exit 1 }'
}

assert_no_arm64_stats() {
    local out="$1"
    ! grep -Eq 'ARM64_.*STATS' "$out"
}

run_host_audits() {
    LANE_NAME=host
    local matches
    matches="$(grep -R --line-number --exclude-dir=.git --exclude-dir=build-arm64-linux --exclude-dir=build-arm64-linux-debug 'ISH_ARM64_HOT_TRACE' "$PROJECT_DIR/app" "$PROJECT_DIR/iSH.xcodeproj" 2>/dev/null || true)"
    if [ -z "$matches" ]; then
        record_result audit ios-default-off PASS "no app/iSH.xcodeproj references to ISH_ARM64_HOT_TRACE"
    else
        record_result audit ios-default-off FAIL "$(printf '%s\n' "$matches" | sed -n '1,12p')"
    fi
}

run_lane() {
    LANE_NAME="$1"
    ROOTFS="$2"
    [ -d "$ROOTFS" ] || { echo "missing rootfs for lane $LANE_NAME: $ROOTFS" >&2; return 1; }

    local out value created retired attempts live retire_page retire_source retire_target guard_checks guard_passes dispatch_probes dispatch_hits dispatch_guard_passes dispatch_guard_fails dispatch_fallbacks

    out="$HOST_TMP/${LANE_NAME}-default.out"
    if guest_capture "$out" "" "node -e 'console.log(2+2)'" && has_clean_status "$out" && assert_no_arm64_stats "$out"; then
        record_result silence default PASS "no ARM64 stats output"
    else
        record_result silence default FAIL "$(grep -v '^__ISH_STATUS:' "$out" | sed -n '1,12p')"
    fi

    out="$HOST_TMP/${LANE_NAME}-hotonly.out"
    if guest_capture "$out" "ISH_ARM64_HOT_TRACE=1" "node -e 'console.log(2+2)'" && has_clean_status "$out" && assert_no_arm64_stats "$out"; then
        record_result silence hot-trace-only PASS "no ARM64 stats output"
    else
        record_result silence hot-trace-only FAIL "$(grep -v '^__ISH_STATUS:' "$out" | sed -n '1,12p')"
    fi

    out="$HOST_TMP/${LANE_NAME}-stats.out"
    if guest_capture "$out" "ISH_ARM64_BLOCK_STATS=1" "node -e 'console.log(2+2)'" && has_clean_status "$out"; then
        value="$(stat_field "$out" hot_trace_enabled || true)"
        attempts="$(stat_field "$out" hot_trace_record_create_attempts || true)"
        created="$(stat_field "$out" hot_trace_record_created || true)"
        guard_checks="$(stat_field "$out" hot_trace_record_guard_checks || true)"
        dispatch_probes="$(stat_field "$out" hot_trace_record_dispatch_probes || true)"
        if [ "$value" = 0 ] && [ "$attempts" = 0 ] && [ "$created" = 0 ] && [ "$guard_checks" = 0 ] && [ "$dispatch_probes" = 0 ]; then
            record_result counters stats-only-zero PASS "hot_trace_enabled=$value hot_trace_record_create_attempts=$attempts hot_trace_record_created=$created hot_trace_record_guard_checks=$guard_checks hot_trace_record_dispatch_probes=$dispatch_probes"
        else
            record_result counters stats-only-zero FAIL "hot_trace_enabled=${value:-missing} hot_trace_record_create_attempts=${attempts:-missing} hot_trace_record_created=${created:-missing} hot_trace_record_guard_checks=${guard_checks:-missing} hot_trace_record_dispatch_probes=${dispatch_probes:-missing}"
        fi
    else
        record_result counters stats-only-zero FAIL "$(grep -v '^__ISH_STATUS:' "$out" | sed -n '1,16p')"
    fi

    out="$HOST_TMP/${LANE_NAME}-enabled.out"
    if guest_capture "$out" "ISH_ARM64_BLOCK_STATS=1 ISH_ARM64_HOT_TRACE=1" "node -e 'let s=0; for (let i=0;i<2000;i++) s+=i; console.log(s)'" && has_clean_status "$out"; then
        value="$(stat_field "$out" hot_trace_enabled || true)"
        attempts="$(stat_field "$out" hot_trace_record_create_attempts || true)"
        created="$(stat_field "$out" hot_trace_record_created || true)"
        retired="$(stat_field "$out" hot_trace_record_retired || true)"
        live="$(stat_field "$out" hot_trace_record_live || true)"
        retire_page="$(stat_field "$out" hot_trace_record_retire_page || true)"
        retire_source="$(stat_field "$out" hot_trace_record_retire_source || true)"
        retire_target="$(stat_field "$out" hot_trace_record_retire_target || true)"
        guard_checks="$(stat_field "$out" hot_trace_record_guard_checks || true)"
        guard_passes="$(stat_field "$out" hot_trace_record_guard_passes || true)"
        dispatch_probes="$(stat_field "$out" hot_trace_record_dispatch_probes || true)"
        dispatch_hits="$(stat_field "$out" hot_trace_record_dispatch_hits || true)"
        dispatch_guard_passes="$(stat_field "$out" hot_trace_record_dispatch_guard_passes || true)"
        dispatch_guard_fails="$(stat_field "$out" hot_trace_record_dispatch_guard_fails || true)"
        dispatch_fallbacks="$(stat_field "$out" hot_trace_record_dispatch_fallbacks || true)"
        if [ "$value" = 1 ] && [ "${attempts:-0}" -gt 0 ] && [ "${created:-0}" -gt 0 ] && [ "${created:-0}" -le 8192 ] && [ "${retired:-0}" -gt 0 ]; then
            record_result counters stats-hot-trace-records PASS "hot_trace_record_create_attempts=$attempts hot_trace_record_created=$created hot_trace_record_live=$live hot_trace_record_retired=$retired"
        else
            record_result counters stats-hot-trace-records FAIL "hot_trace_enabled=${value:-missing} hot_trace_record_create_attempts=${attempts:-missing} hot_trace_record_created=${created:-missing} hot_trace_record_live=${live:-missing} hot_trace_record_retired=${retired:-missing}"
        fi
        if [ "${guard_checks:-0}" -gt 0 ] && [ "${guard_passes:-0}" -ge "${created:-0}" ] && [ "${guard_checks:-0}" -ge "${guard_passes:-0}" ]; then
            record_result counters stats-hot-trace-guard-checks PASS "hot_trace_record_guard_checks=$guard_checks hot_trace_record_guard_passes=$guard_passes hot_trace_record_created=$created"
        else
            record_result counters stats-hot-trace-guard-checks FAIL "hot_trace_record_guard_checks=${guard_checks:-missing} hot_trace_record_guard_passes=${guard_passes:-missing} hot_trace_record_created=${created:-missing}"
        fi
        if [ "${dispatch_probes:-0}" -gt 0 ] && [ "${dispatch_hits:-0}" -gt 0 ] && [ "$dispatch_hits" = "$dispatch_fallbacks" ] && [ "$dispatch_hits" = "$(( ${dispatch_guard_passes:-0} + ${dispatch_guard_fails:-0} ))" ]; then
            record_result counters stats-hot-trace-dispatch-dry-run PASS "hot_trace_record_dispatch_probes=$dispatch_probes hot_trace_record_dispatch_hits=$dispatch_hits hot_trace_record_dispatch_fallbacks=$dispatch_fallbacks"
        else
            record_result counters stats-hot-trace-dispatch-dry-run FAIL "hot_trace_record_dispatch_probes=${dispatch_probes:-missing} hot_trace_record_dispatch_hits=${dispatch_hits:-missing} hot_trace_record_dispatch_guard_passes=${dispatch_guard_passes:-missing} hot_trace_record_dispatch_guard_fails=${dispatch_guard_fails:-missing} hot_trace_record_dispatch_fallbacks=${dispatch_fallbacks:-missing}"
        fi
        if [ "${retire_page:-0}" -gt 0 ] && [ $(( ${retire_source:-0} + ${retire_target:-0} )) -gt 0 ]; then
            record_result counters stats-hot-trace-retirement-paths PASS "hot_trace_record_retire_page=$retire_page hot_trace_record_retire_source=$retire_source hot_trace_record_retire_target=$retire_target"
        else
            record_result counters stats-hot-trace-retirement-paths FAIL "hot_trace_record_retire_page=${retire_page:-missing} hot_trace_record_retire_source=${retire_source:-missing} hot_trace_record_retire_target=${retire_target:-missing}"
        fi
    else
        record_result counters stats-hot-trace-records FAIL "$(grep -v '^__ISH_STATUS:' "$out" | sed -n '1,16p')"
    fi
}

run_host_audits

for lane in $ROOTFS_LANES; do
    run_lane "${lane%%=*}" "${lane#*=}"
done

{
    echo '# ARM64 hot trace record smoke report'
    echo
    echo "- Generated: $(date -Iseconds)"
    echo "- Binary: $ISH_BIN"
    echo "- Rootfs lanes: $ROOTFS_LANES"
    echo "- Timeout: ${TIMEOUT_S}s"
    echo "- Total: $TOTAL_COUNT"
    echo "- Passed: $PASS_COUNT"
    echo "- Failed: $FAIL_COUNT"
    echo
    echo '| Lane | Stage | Test | Status | Detail |'
    echo '|---|---|---|---|---|'
    printf '%s' "$REPORT_ROWS"
} >"$REPORT"

echo
echo "$REPORT"

if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi
