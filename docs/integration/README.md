# VMLXRuntime Integration — Beta Build

**Branch:** `feature/vmlx`
**Status:** Team-internal beta (not public release)
**Last updated:** 2026-04-02

---

## What This Is

Osaurus is replacing `mlx-swift-lm` (Apple's reference MLX LLM library) with **VMLXRuntime** — a custom native inference engine built on raw `mlx-swift`. This gives us:

- Native hybrid SSM/transformer support (Qwen 3.5, NemotronH, Mistral 4)
- TurboQuant KV cache compression for longer context in limited VRAM
- Paged + prefix + disk cache hierarchy with SSM-aware safety rules
- JANG mixed-precision quantization format support
- Full streaming tool-call and reasoning parsers

The beta build ships both engines: VMLXRuntime is tried first, with `mlx-swift-lm` as automatic fallback for any model VMLXRuntime doesn't handle yet.

---

## Branch Stats

| Metric | Value |
|--------|-------|
| Commits ahead of main | 77 |
| Files changed | 125 |
| Lines added | ~14,100 |
| Lines removed | ~3,100 |
| New files | ~25 |
| Deleted files | 3 |
| Build status | Release builds clean |

---

## Quick Links

| Doc | Purpose |
|-----|---------|
| [BETA-TESTING.md](BETA-TESTING.md) | What to test and how to report issues |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How VMLXRuntime fits into Osaurus |
| [KNOWN-ISSUES.md](KNOWN-ISSUES.md) | Current limitations and workarounds |
| [CHANGELOG.md](CHANGELOG.md) | What changed, organized by area |
