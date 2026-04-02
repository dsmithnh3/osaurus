# Known Issues — Beta Build

Last updated: 2026-04-02

---

## Active Issues

### P0 — Must Fix Before Wider Beta

| Issue | Status | Notes |
|-------|--------|-------|
| mlx-swift package identity conflict | Warning (builds OK) | Two sources for mlx-swift — will become a SwiftPM error in future. Need to remove mlx-swift-lm dep long-term |
| Metal custom kernels disabled | Workaround active | GatedDelta and SSM Metal kernels cause EXC_BAD_ACCESS during prewarm. Ops-based fallback works but may be slower |

### P1 — Known Limitations

| Issue | Status | Notes |
|-------|--------|-------|
| NemotronH inference not fully validated | Implemented | Code landed, Python-reference-verified, but needs broader real-model testing |
| Mistral Small 4 inference not fully validated | Implemented | Same — config decoding fixed, needs more testing |
| SSMReDeriver not the main recovery path | Partial | Exists but paged/memory cache are the primary paths; re-derivation is backup only |
| TurboQuant cross-turn story incomplete | Partial | TQ compresses in-flight, exports float. Full TQ-compressed disk persistence not done |
| Continuous batching not active | Partial | Scheduler primitives exist but actor runs one generation at a time |
| Vision encoder inference | Pending | VisionProcessor + cache exist but encoder forward pass not wired |
| MiniMax M2.5 tokenizer | Pending | Tokenizer compatibility not resolved |

### P2 — Cosmetic / Low Priority

| Issue | Status | Notes |
|-------|--------|-------|
| `default.profraw` tracked in git | Cleanup needed | Code coverage artifact, should be gitignored |
| `crash.ips` untracked | Cleanup needed | Crash report from debugging, should not be committed |

---

## Recently Fixed (Last 5 Commits)

| Fix | Commit | Impact |
|-----|--------|--------|
| TQ cache export emitting lossy compressed data → garbled second turn | uncommitted | **Critical** — float export prevents quality degradation on restore |
| Paged cache COW violation (shared block mutation) | uncommitted | Data corruption in multi-session scenarios |
| Paged cache nil layer reconstruction | uncommitted | Cache fetch failures for hybrid models with sparse SSM layers |
| GPU task sync (concurrent MLX ops → EXC_BAD_ACCESS) | uncommitted | Crash on rapid regeneration |
| DiskCache stale file_size on re-store | uncommitted | Incorrect eviction decisions after TQ re-compression |
| Mixed-precision weight loading (JANG 3/4/5/8 bit) | uncommitted | gather_qmm crash for mixed-quant models |
| Streaming UI freeze on long responses | uncommitted | Markdown re-parse throttled for >3KB during streaming |

---

## Workarounds in Place

1. **Metal kernels disabled** — `vmlxPrewarmCustomKernels()` commented out, SSM Metal kernel bypassed. Ops-based fallback handles all computation. Performance impact unclear but correctness is preserved.

2. **GPU sync wait** — New generation waits up to 3 seconds for previous generation's GPU work to complete before starting. Prevents concurrent MLX operations that corrupt the kernel cache.

3. **mlx-swift-lm still included** — Acts as fallback for model families VMLXRuntime doesn't handle natively. Will be removed when coverage is complete.
