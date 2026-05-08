# Benchmarks Game Java-equivalent smoke report

- Timestamp: 2026-05-08T22:46:41+00:00
- ish binary: /workspace/projects/ish-arm64/build-arm64-linux/ish
- rootfs: /workspace/projects/ish-arm64/alpine-arm64-fakefs
- timeout: 900s
- Java mode: mixed
- guest workdir: /tmp/benchmarksgame-java-equivalent-smoke
- Source status: current Benchmarks Game pages do not advertise a Java language row; this runner uses local Java equivalents.
- Java startup: PASS
- Build result: PASS
- Result: 10 / 10 passing

## Results

| Benchmark | Status | Bytes | Lines | CRC:Size | Time (s) |
|---|---:|---:|---:|---|---:|
| binarytrees | PASS | 144 | 4 | 3398443640:144 | 3.78 |
| fannkuchredux | PASS | 24 | 2 | 3876461884:24 | 2.45 |
| fasta | PASS | 1024 | 18 | 1840911314:1024 | 1.55 |
| knucleotide | PASS | 100 | 13 | 463387513:100 | 12.69 |
| mandelbrot | PASS | 1311 | 2 | 640347331:1311 | 3.44 |
| nbody | PASS | 26 | 2 | 980964627:26 | 4.09 |
| pidigits | PASS | 151 | 10 | 3273113594:151 | 3.89 |
| regexredux | PASS | 263 | 13 | 3404323976:263 | 7.74 |
| revcomp | PASS | 10174 | 168 | 2332509513:10174 | 3.58 |
| spectralnorm | PASS | 12 | 1 | 2938823901:12 | 5.57 |

## Raw guest log tail

```text
__JAVA_MODE:mixed
__JAVA_VERSION_BEGIN
openjdk version "21.0.10" 2026-01-20
OpenJDK Runtime Environment (build 21.0.10+7-alpine-r0)
OpenJDK 64-Bit Server VM (build 21.0.10+7-alpine-r0, mixed mode, sharing)
__JAVA_VERSION_END
__JAVA_VERSION_OK
__JAVA_BUILD:PASS
__BG_BEGIN:binarytrees
__BG_TIME:binarytrees:3.78
__BG_RESULT:binarytrees:PASS:144:4:3398443640:144
__BG_BEGIN:fannkuchredux
__BG_TIME:fannkuchredux:2.45
__BG_RESULT:fannkuchredux:PASS:24:2:3876461884:24
__BG_BEGIN:fasta
__BG_TIME:fasta:1.55
__BG_RESULT:fasta:PASS:1024:18:1840911314:1024
__BG_BEGIN:knucleotide
__BG_TIME:knucleotide:12.69
__BG_RESULT:knucleotide:PASS:100:13:463387513:100
__BG_BEGIN:mandelbrot
__BG_TIME:mandelbrot:3.44
__BG_RESULT:mandelbrot:PASS:1311:2:640347331:1311
__BG_BEGIN:nbody
__BG_TIME:nbody:4.09
__BG_RESULT:nbody:PASS:26:2:980964627:26
__BG_BEGIN:pidigits
__BG_TIME:pidigits:3.89
__BG_RESULT:pidigits:PASS:151:10:3273113594:151
__BG_BEGIN:regexredux
__BG_TIME:regexredux:7.74
__BG_RESULT:regexredux:PASS:263:13:3404323976:263
__BG_BEGIN:revcomp
__BG_TIME:revcomp:3.58
__BG_RESULT:revcomp:PASS:10174:168:2332509513:10174
__BG_BEGIN:spectralnorm
__BG_TIME:spectralnorm:5.57
__BG_RESULT:spectralnorm:PASS:12:1:2938823901:12
__BG_ALL_DONE

```

## Notes

- This runner now defaults to HotSpot mixed mode for `javac` and benchmark execution (`JAVA_SMOKE_MODE=mixed`). Use `JAVA_SMOKE_MODE=interpreter` for the conservative `-Xint -Xshare:off` fallback lane; that mode was also revalidated on 2026-05-08.
- ARM64 iSH reports a 64-byte DC ZVA block and implements `dc zva`; this fixed the previous `assembler_aarch64.hpp:245` startup abort.
- The signal frame uses the Linux/musl aarch64 ucontext layout (`uc_mcontext` at offset 176, FPSIMD extension area 16-byte aligned), and low/null read faults are delivered to guest SIGSEGV handlers instead of being synthesized as zero loads. This is required for HotSpot implicit null checks.
- The previous default mixed-mode `javac`/C2 crash while compiling `java.util.concurrent.ConcurrentHashMap::tabAt` was fixed by implementing ARM64 `LDPSW` pair-load sign extension and rejecting unallocated GPR pair encodings.
