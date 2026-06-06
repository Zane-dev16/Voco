# MODEL_RUNTIME_GUIDE

> **Purpose:** Comprehensive reference for how each of Voco's 11 translation models runs on the custom llama.cpp backend.
>
> **Date:** 2026-06-05

**Source files (6):**
- `Voco/Voco/Models/ModelConfiguration.swift` — 9 presets
- `Voco/Voco/Models/TranslationModel.swift` — 11-model catalog
- `Voco/Voco/Services/LlamaService.swift` — Voco's translation service
- `Packages/swift-llama-cpp/Sources/SwiftLlama/LlamaService.swift` — SwiftLlama layer
- `Packages/swift-llama-cpp/Sources/SwiftLlama/Llama.swift` — Core engine
- `Packages/swift-llama-cpp/Sources/SwiftLlama/LlamaModel.swift` — Model layer

---

## Architecture Overview

**Prompt flow through the stack:**

```
TranslationModel
    |
    +-- ModelConfiguration (promptStrategy, addBos, stopStrings, ...)
    |
    v
LlamaService.translate() / translateStream()
    |
    +-- routes to one of three paths:
    |     raw           -> streamCompletionRaw(text, addBos:)
    |     chatWithSystem -> streamCompletion(messages)
    |     chatUserOnly   -> streamCompletion(messages)
    |
    v
SwiftLlama.LlamaService.streamCompletionRaw() / streamCompletion()
    |
    v
Llama.initializeCompletion(text:addBos:) / initializeCompletion(messages:)
    |
    v
LlamaModel.tokenize() / applyChatTemplate()
    |
    v
llama.cpp C API -> token generation loop
```

### Three Prompt Strategies

| Strategy | Bypasses Chat Template? | Calls | Used By |
|---|---|---|---|
| `raw` | Yes | `streamCompletionRaw()` | Hunyuan, Gemma 4 |
| `chatWithSystem` | No (system + user) | `streamCompletion()` | Llama 3.2, Qwen3.5 |
| `chatUserOnly` | No (user only) | `streamCompletion()` | TranslateGemma |

**Strategy routing** (LlamaService.swift:74-103):
```swift
switch model.config.promptStrategy {
case .raw:
    // Build prompt from userPromptTemplate, replace {target}/{text}
    // Call streamCompletionRaw(text, addBos: config.addBos)
    // Optionally strip via rawPromptMarker
case .chatUserOnly, .chatWithSystem:
    // Build LlamaChatMessage array (+ system for chatWithSystem)
    // Call respond(to: messages) -> applyChatTemplate()
    // Strip <think>...</think> blocks
}
```

---

## addBos Parameter Chain (CRITICAL)

This is the most important piece of Voco's model runtime. Getting it wrong
causes models to silently fail (echo prompt instead of translating).

**Full parameter chain:**

```
ModelConfiguration.addBos: Bool?
    |
    v
LlamaService.translate()
    service.streamCompletionRaw(addBos: model.config.addBos)
    |
    v
SwiftLlama.LlamaService.streamCompletionRaw(of:samplingConfig:addBos:)
    |
    v
Llama.initializeCompletion(text:addBos:)
    let effectiveAddBos = addBos ?? model.shouldAddBos()  // LINE 108
    model.tokenize(text: text, addBos: effectiveAddBos, special: true)
```

**shouldAddBos() logic** (LlamaModel.swift:101-107):

```swift
public func shouldAddBos() -> Bool {
    let addBos = llama_vocab_get_add_bos(vocabPointer)
    if addBos {
        return llama_vocab_type(vocabPointer) == LLAMA_VOCAB_TYPE_SPM
    }
    return addBos
}
```

**Critical insight:** `shouldAddBos()` checks TWO conditions:
1. `llama_vocab_get_add_bos()` — does the GGUF metadata say add_bos=true?
2. `llama_vocab_type() == LLAMA_VOCAB_TYPE_SPM` — is the tokenizer SentencePiece?

**BPE tokenizer models (Gemma 4) return FALSE** even if GGUF says add_bos=true,
because they're not SPM. This is the root cause of the Gemma 4 E2B bug:
no BOS token -> model echoes prompt -> no translation.

**Fix:** `addBos: true` in config forces BOS, overriding `shouldAddBos()`.

| addBos value | Behavior |
|---|---|
| `nil` (default) | Defer to `shouldAddBos()` — most models |
| `true` | Force BOS regardless — Gemma 4 rescue |
| `false` | Force NO BOS regardless — not currently used |

---

## Chat Template Fallback

**applyChatTemplate()** (LlamaModel.swift:161-218):

1. Try GGUF metadata: `llama_model_chat_template(modelPointer, nil)`
2. If template is `nil` (GGUF lacks `tokenizer.chat_template`):
   - Check `general.architecture` metadata
   - If architecture starts with `"gemma"` -> pass `"<start_of_turn>user\n"` (triggers Gemma format)
   - If architecture starts with `"llama"` -> pass `"<|start_header_id|>user<|end_header_id|>\n"` (triggers Llama 3 format — requires BOTH tokens per llama-chat.cpp:175)
   - `llama_chat_apply_template` detects `<start_of_turn>` and applies Gemma format
   - Other architectures -> C API falls back to chatml

```swift
if cTemplatePointer == nil {
    var archBuffer = [CChar](repeating: 0, count: 64)
    let archLen = llama_model_meta_val_str(modelPointer, "general.architecture", &archBuffer, 64)
    if archLen > 0 {
        let arch = String(cString: archBuffer)
        if arch.hasPrefix("gemma") {
            cTemplatePointer = UnsafePointer(strdup("<start_of_turn>user\n"))
        }
    }
}
```

---

## Per-Config Sections

### Config: `hunyuanMT` (2 models)

**Models:**
- `hy-mt2-1.8b-stq` — Hy-MT2 1.8B, 441 MB, STQ1_0 (1.25-bit) — next-gen 33-language
- `hy-mt1.5-1.8b-q4km` — Hy-MT1.5 1.8B, 1.08 GB, Q4_K_M — previous gen HQ

| Property | Value |
|---|---|
| Strategy | `raw` |
| Tokenizer | SPM (SentencePiece) |
| addBos | `nil` (shouldAddBos() -> true for SPM) |
| GPU | Disabled (CPU/NEON only) |
| Temperature | 0.0 (greedy) |
| Stop strings | none (empty) |
| rawPromptMarker | nil |
| batchSize | 512 |
| maxTokenCount | 512 |
| threadCount | 2 / 2 (batch) |

**Prompt template:**

```
<|hy_begin|of|sentence|><|hy_place|holder|no|3>
<|hy_begin|of|sentence|>
<|hy_User|>Translate the following segment into {target}, without additional explanation.

{text}
<|hy_Assistant|>
```

> Note: The actual special tokens use Unicode \u2581 (▁) instead of `|`; simplified above for readability. See `ModelConfiguration.swift:53` for exact template.

**Gotchas:**
- CPU-only due to STQ1_0 NEON kernel bug — generic C kernel at ~4.5 tok/s vs broken NEON at ~50 tok/s
- Special SentencePiece prompt format with Hunyuan-specific tokens
- Both models share the same config preset

---

### Config: `llamaInstruct` (2 models)

**Models:**
- `llama-3.2-1b-q8` — Llama 3.2 1B, 1.32 GB, Q8_0
- `llama-3.2-3b-iq3m` — Llama 3.2 3B, 1.53 GB, IQ3_M

| Property | Value |
|---|---|
| Strategy | `chatWithSystem` |
| Tokenizer | SPM (SentencePiece) |
| addBos | `nil` (default) |
| GPU | Enabled |
| Temperature | 0.0 (greedy) |
| Stop strings | `["<|eot_id|>"]` |
| rawPromptMarker | nil |
| batchSize | 256 |
| maxTokenCount | 512 |

**System prompt:**
```
You are a professional translator. Translate the user's text accurately
and naturally into {target}. Output ONLY the translation, with no extra
commentary, notes, or explanations.
```

**User prompt:** `{text}`

**Gotchas:**
- Stop string `</think>` strips any thinking/reasoning blocks from output
- Attribution required: "Built with Meta Llama 3.2"
- `requiresBuiltWithLlamaAttribution: true` in TranslationModel

---

### Config: `qwenInstruct` (3 models)

**Models:**
- `qwen3.5-0.8b-q8` — Qwen3.5 0.8B, 795 MB, Q8_0
- `qwen3.5-2b-q4km` — Qwen3.5 2B, 1.25 GB, Q4_K_M — sweet spot
- `qwen3.5-4b-q4km` — Qwen3.5 4B, 2.60 GB, Q4_K_M — exceeds 1.5 GB soft limit

| Property | Value |
|---|---|
| Strategy | `chatWithSystem` |
| Tokenizer | BPE (but chat template handles BOS via addBos: nil) |
| addBos | `nil` (default — chat template adds BOS, not tokenizer) |
| GPU | Enabled |
| Temperature | 0.0 (greedy) |
| Stop strings | `["<|im_end|>"]` |
| rawPromptMarker | nil |
| batchSize | 256 |
| maxTokenCount | 256 |

**System prompt:** `You are a translator. Output the translation and nothing else.`

**User prompt:** `Translate to {target}: {text}`

**Effective ChatML prompt (after template application):**
```
<|im_start|>system
You are a translator. Output the translation and nothing else.<|im_end|>
<|im_start|>user
Translate to Spanish: Hello, how are you?<|im_end|>
<|im_start|>assistant
```

**Gotchas:**
- ChatML format — `<|im_end|>` is critical for clean output
- Qwen3.5 4B at 2.60 GB risks memory pressure on devices with <4 GB free
- BPE tokenizer but addBos: nil works because chat template adds BOS token in the formatted prompt

---

### Config: `gemma4Raw` (2 models)

**Models:**
- `gemma-4-e2b-q4km` — Gemma 4 E2B, 3.27 GB, Q4_K_M
- `gemma-4-e4b-q4km` — Gemma 4 E4B, 5.09 GB, Q4_K_M

| Property | Value |
|---|---|
| Strategy | `raw` (bypasses chat template) |
| Tokenizer | **BPE** — shouldAddBos() returns FALSE |
| **addBos** | **`true` (FORCED — CRITICAL)** |
| GPU | Disabled (CPU/NEON only) |
| Temperature | 0.0 (greedy) |
| Stop strings | **none** (empty — see gotchas) |
| rawPromptMarker | nil |
| batchSize | 256 |
| maxTokenCount | 512 |

**Prompt template:**
```
Translate to {target}: {text}
{target}:
```

**Example prompt:**
```
Translate to Spanish: Hello, how are you?
Spanish:
```

**Gotchas:**
- **MUST have `addBos: true`** — BPE tokenizer silently drops BOS otherwise,
  causing model to echo prompt instead of translating
- **Do NOT add stop strings** like `"\n<"` or `"\n\n"` — these fire on
  the prompt's own content (e.g., the newline before `{target}:`)
- The `addBos` parameter was on unmerged branch `be9f13c`, re-added 2026-06-05
- E4B is 5+ GB — risks jetsam (iOS memory kill) on 6 GB devices
- Both models were previously broken — this config is the fix

---

### Config: `gemmaInstruct` (1 model)

**Models:**
- `translategemma-4b-q2k` — TranslateGemma 4B, 1.65 GB, Q2_K

| Property | Value |
|---|---|
| Strategy | `chatUserOnly` (user role only, no system) |
| Tokenizer | SPM (SentencePiece) |
| addBos | `nil` (default) |
| GPU | Disabled (CPU/NEON only) |
| Temperature | 0.0 (greedy) |
| Stop strings | `["\n\n"]` |
| rawPromptMarker | nil |
| batchSize | 256 |
| **maxTokenCount** | **32** (very tight — translation specialist) |

**User prompt:** `Translate to {target}: {text}`

**Gotchas:**
- No system role — system messages confuse Gemma-family models
- Tight token limit (32) — this is a dedicated translation model,
  not a general-purpose LLM, so outputs are short by design
- Translation-specialist Gemma variant with properly embedded chat template
- This model worked from day one while Gemma 4 E2B/E4B were broken

---

## Technical Deep-Dives

### Stop String Processing

**Non-streaming path** (LlamaService.swift:322-334):
```swift
private func truncateAtStopStrings(_ text: String, config: ModelConfiguration) -> String {
    guard !config.stopStrings.isEmpty else { return text }
    var earliestRange: Range<String.Index>?
    for stop in config.stopStrings {
        if let range = text.range(of: stop) {
            if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                earliestRange = range
            }
        }
    }
    guard let range = earliestRange else { return text }
    return String(text[..<range.lowerBound])
}
```

**Streaming path** (LlamaService.swift:162-176):
- Checks buffer against stop strings after each token
- When found: yields content before the stop string, sets `stopped = true`
- Stops yielding immediately — no further tokens processed

**Critical warning:** Stop strings that appear in prompt content will fire prematurely.
This was part of the Gemma 4 bug — the stop string `"\n<"` matched the prompt's
own newline characters. For raw prompt models, keep stop strings empty unless you're
certain they won't appear in the prompt template.

### rawPromptMarker

Field on `ModelConfiguration` — when set, strips everything before (and including)
the marker from the raw completion output. Designed to handle models that echo
their prompt in raw mode.

**Non-streaming** (LlamaService.swift:94-98):
```swift
if let marker = model.config.rawPromptMarker, let range = output.range(of: marker) {
    rawOutput = String(output[range.upperBound...])
} else {
    rawOutput = output
}
```

**Streaming** (LlamaService.swift:146-159):
- Accumulates tokens until marker found in buffer
- Trims buffer to last 200 chars if >500 chars to avoid unbounded growth
- Only yields tokens after marker is found

**Current status:** `nil` for all configs. The Gemma 4 fix was `addBos: true`,
not marker stripping. This field exists for future use if a model needs prompt
echo stripped but can't use addBos for some reason.

### Think-Tag Stripping

**`stripThinkingTags()`** (LlamaService.swift:310-317):

```swift
static func stripThinkingTags(from text: String) -> String {
    var result = text
    while let start = result.range(of: "<think>"),
          let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
        result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- Applied to `chatWithSystem` and `chatUserOnly` paths only (not raw)
- Streaming path handles think blocks inline (LlamaService.swift:238-264)
- Streaming: sets `inThinkBlock = true` when `<think>` seen, discards until `</think>`
- Non-streaming: strips all `<think>...</think>` blocks post-hoc

### Tokenizer Comparison

| Model Family | Tokenizer Type | BOS Behavior | Config |
|---|---|---|---|
| Tencent Hunyuan | SPM | Auto-added | hunyuanMT |
| Meta Llama 3.2 | SPM | Auto-added | llamaInstruct |
| Qwen3.5 | BPE | Added by chat template | qwenInstruct |
| Gemma 4 | BPE | **MUST be forced** (addBos: true) | gemma4Raw |
| TranslateGemma | SPM | Auto-added | gemmaInstruct |

Key rule: BPE tokenizers need special attention for BOS. Chat-template models
get their BOS from the template itself. Raw-prompt BPE models need the forced override.

---

## Quick Reference Table

| # | Model ID | Config | Strategy | addBos | GPU | Stop Strings | Size |
|---|---|---|---|---|---|---|---|
| 1 | hy-mt2-1.8b-stq | hunyuanMT | raw | nil | OFF | none | 441 MB |
| 2 | hy-mt1.5-1.8b-q4km | hunyuanMT | raw | nil | OFF | none | 1.08 GB |
| 3 | llama-3.2-1b-q8 | llamaInstruct | chat+sys | nil | ON | `<|eot_id|>` | 1.32 GB |
| 4 | llama-3.2-3b-iq3m | llamaInstruct | chat+sys | nil | ON | `<|eot_id|>` | 1.53 GB |
| 5 | qwen3.5-0.8b-q8 | qwenInstruct | chat+sys | nil | ON | `<|im_end|>` | 795 MB |
| 6 | qwen3.5-2b-q4km | qwenInstruct | chat+sys | nil | ON | `<|im_end|>` | 1.25 GB |
| 7 | qwen3.5-4b-q4km | qwenInstruct | chat+sys | nil | ON | `<|im_end|>` | 2.60 GB |
| 8 | gemma-4-e2b-q4km | gemma4Raw | raw | **true** | OFF | none | 3.27 GB |
| 9 | gemma-4-e4b-q4km | gemma4Raw | raw | **true** | OFF | none | 5.09 GB |
| 10 | translategemma-4b-q2k | gemmaInstruct | chat/user | nil | OFF | `\n\n` | 1.65 GB |

> Note: Model #10 appears as #11 in the TranslationModel catalog because Hy-MT1.5 STQ (#1 in catalog) is also included there. The table above covers the 10 models using the 5 active configs covered in this guide. Models using `compact`, `standard`, `quality`, or `nllbTranslate` configs exist in `ModelConfiguration.swift` but are not currently mapped to any `TranslationModel`.

---

## Key Code Paths Reference

### To fix a model that echoes/doesn't translate:

1. Check `ModelConfiguration.addBos` — if BPE tokenizer, must be `true` or the chat template must handle it
2. Check `ModelConfiguration.stopStrings` — any that appear in the prompt will fire prematurely
3. Check `ModelConfiguration.promptStrategy` — `raw` vs `chatUserOnly` vs `chatWithSystem`
4. For raw models: check `rawPromptMarker` if prompt echo is still an issue after addBos fix
5. For chat models: check `applyChatTemplate()` fallback path for missing GGUF templates

### Source locations for key functions:

| Function | File | Lines |
|---|---|---|
| `shouldAddBos()` | LlamaModel.swift | 101-107 |
| `initializeCompletion(text:addBos:)` | Llama.swift | 105-109 |
| `streamCompletionRaw(addBos:)` | LlamaService.swift (SwiftLlama) | 159-184 |
| `translate()` | LlamaService.swift (Voco) | 57-107 |
| `translateStream()` | LlamaService.swift (Voco) | 110-278 |
| `applyChatTemplate()` | LlamaModel.swift | 161-218 |
| `truncateAtStopStrings()` | LlamaService.swift (Voco) | 322-334 |
| `stripThinkingTags()` | LlamaService.swift (Voco) | 310-317 |

---

*Generated from source code analysis, 2026-06-05. Source files are authoritative;
this guide reflects the code as understood at the time of writing.*
