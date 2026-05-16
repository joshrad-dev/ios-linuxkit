# ios-linuxkit documentation

This directory contains the supporting documentation for `ios-linuxkit`. The top-level README is intentionally concise; detailed architecture, validation, workload, and legacy upstream notes live here.

## Runtime and validation

- [Runtime validation](RUNTIME_VALIDATION.md) — current staged coverage gate, commands, status table, AI CLI lane, failure rules, and major fixes covered by tests.
- [ARM64 workload smoke tests](ARM64_WORKLOAD_SMOKE_TESTS.md) — real workloads used to harden the runtime beyond tiny reproducers.
- [Smoke issues and syscall coverage](ARM64_SMOKE_ISSUES_AND_SYSCALL_COVERAGE.md) — issue disposition and syscall/runtime coverage appraisal.
- [Production baseline](ARM64_PRODUCTION_BASELINE.md) and [production deployment](ARM64_PRODUCTION_DEPLOYMENT.md) — known-good package/rootfs/code baseline and deployment notes.

## Architecture and platform notes

- [ARM64 backend notes](ARM64_BACKEND.md) — detailed architecture and implementation notes from the `ish-arm64` bring-up.
- [ARM64 backend notes, Chinese](ARM64_BACKEND_ZH.md) — Chinese version of the ARM64 backend notes.
- [Executor optimization roadmap](ARM64_GADGET_FUSION_PLAN.md) — gadget fusion, block chaining, eager prechain experiments, and dispatch-cache work.
- [Linux build and host ABI](LINUX_BUILD_AND_HOST_ABI.md) — Linux-host build flow and platform abstraction notes.

## Workload reports

- [Benchmarks Game matrix](BENCHMARKSGAME_MATRIX.md) — cross-language benchmark matrix and feasibility notes.
- Per-language Benchmarks Game reports: [GCC](BENCHMARKSGAME_GCC_SMOKE.md), [G++](BENCHMARKSGAME_GPP_SMOKE.md), [Go](BENCHMARKSGAME_GO_SMOKE.md), [Java-equivalent](BENCHMARKSGAME_JAVA_EQUIVALENT_SMOKE.md), [Lua](BENCHMARKSGAME_LUA_SMOKE.md), [Node](BENCHMARKSGAME_NODE_SMOKE.md), [Perl](BENCHMARKSGAME_PERL_SMOKE.md), [PHP](BENCHMARKSGAME_PHP_SMOKE.md), [Python](BENCHMARKSGAME_PYTHON_SMOKE.md), and [Ruby](BENCHMARKSGAME_RUBY_SMOKE.md).
- [go-gte progress](GO_GTE_PROGRESS.md) — model conversion and Go runtime workload notes.

## Upstream and legacy material

- [Original iSH README](ORIGINAL_ISH_README.md) — preserved upstream/fork README material.
- [Legacy localized upstream READMEs](legacy/) — preserved Chinese, Japanese, and Korean README variants from upstream iSH.
