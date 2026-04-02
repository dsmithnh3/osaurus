# Beta Testing Guide — Team Only

**Build:** Release configuration (Debug is 2.8x slower — always test Release)
**Branch:** `feature/vmlx`

---

## How to Build

```bash
git checkout feature/vmlx
# Open osaurus.xcworkspace in Xcode
# Scheme: osaurus, Configuration: Release, Destination: My Mac
# Build & Run (Cmd+R)
```

Or from CLI:
```bash
xcodebuild -workspace osaurus.xcworkspace -scheme osaurus -configuration Release -destination 'platform=macOS' build
```

---

## What to Test

### Priority 1 — Core Inference (Must Work)

1. **Standard transformer models** (Llama, Qwen2.5, Gemma)
   - Load a model from HuggingFace
   - Send a simple prompt, verify coherent response
   - Check generation speed in the stats overlay (tok/s)
   - Try a multi-turn conversation (cache reuse should kick in)

2. **Qwen 3.5 hybrid models** (if you have one downloaded)
   - Same as above — this exercises the SSM + attention hybrid path
   - Watch for garbled output on second turn (cache restore regression)

3. **Streaming quality**
   - Long responses (1000+ tokens) should not freeze the UI
   - Thinking blocks should stream smoothly, not re-render the whole block each token
   - Markdown rendering should stay responsive during streaming

### Priority 2 — Cache System

4. **Cache hit on re-prompt**
   - Send a long system prompt + user message
   - Send another message in the same conversation
   - The second response should start faster (prefix cache hit)
   - Check stats: `cached_tokens` should be > 0

5. **Model switching**
   - Switch models mid-conversation
   - Old model should unload cleanly (no crash)
   - New model loads and generates

### Priority 3 — Edge Cases

6. **Rapid regeneration**
   - Hit regenerate multiple times quickly
   - Should not crash (GPU sync fix)
   - Previous generation cancels cleanly

7. **Tool calling** (if model supports it)
   - Models with tool-call parsers should format tool calls correctly
   - Check Qwen, Llama, Mistral tool-call patterns

8. **Thinking/reasoning models**
   - Models that output `<think>` blocks should show the reasoning UI
   - Toggling thinking on/off should work

---

## What NOT to Test Yet

- NemotronH and Mistral Small 4 models — implemented but still under correctness validation
- Vision/multimodal — encoder inference not complete
- MiniMax M2.5 — tokenizer compatibility pending
- Continuous batching (multiple simultaneous generations) — not wired yet

---

## How to Report Issues

For the beta, just message the team channel with:

1. **Model name** (exact HuggingFace ID)
2. **What you did** (prompt, action)
3. **What happened** (crash, garbled output, hang, wrong stats)
4. **Console output** if there's a crash (Xcode console or Console.app → osaurus)

The app logs key events:
- `[VMLX]` prefix for runtime events
- `[CacheCoordinator]` for cache hits/misses
- `[ModelLoader]` for model loading steps

---

## Performance Expectations

On Apple Silicon:

| Model Size | Expected tok/s (M1 Max) | Expected tok/s (M4 Pro) |
|------------|-------------------------|-------------------------|
| 1-3B | 40-80 | 60-100+ |
| 7-9B | 15-30 | 25-45 |
| 14B | 8-15 | 12-25 |
| 30B+ | 3-8 | 5-12 |

These are rough — actual numbers depend on quantization, context length, and VRAM pressure. The stats overlay shows real numbers per generation.
