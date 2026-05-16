# Voco Model Registry

The model registry is a single source of truth for all downloadable translation models. Adding a model requires editing **only one file**: `Voco/Models/TranslationModel.swift`.

## Quick Start: Adding a Model

1. Find a GGUF model on HuggingFace (e.g. `unsloth/Qwen3-0.6B-GGUF`).
2. Pick a quantization that fits your target device:
   - `Q2_K` / `Q3_K_M` — ~300-500 MB, works on simulator
   - `Q4_K_M` — ~400-600 MB, balanced
   - `Q5_K_M` / `Q6_K` — ~700 MB+, physical device only
3. Copy the direct download URL:
   ```
   https://huggingface.co/<repo>/resolve/main/<filename>.gguf
   ```
4. Append a new `TranslationModel(...)` entry to the `availableModels` array in `TranslationModel.swift`.
5. Choose a `config` preset:
   - `.compact`  — batchSize 512, for models ≤400 MB
   - `.standard` — batchSize 256, for models ~600-800 MB
   - `.quality`  — batchSize 2048, for physical devices with ample RAM
6. Verify the URL with a HEAD request before committing:
   ```bash
   curl -I -L "<url>"
   ```
   Must return HTTP 200. If it returns 401/404, the model is gated or deleted — pick a different one.

## Example Entry

```swift
TranslationModel(
    id: "my-model-id",               // unique kebab-case ID
    displayName: "My Model 1B",      // human-readable name shown in UI
    description: "Short description",// shown in the model picker
    provider: "MyOrg",               // company/organization name
    sourceURL: URL(string: "https://huggingface.co/...")!,
    fileSizeBytes: 400_000_000,      // accurate byte count from HF
    supportedLanguages: [.english, .spanish, .french],
    hfRepo: "org/repo-GGUF",         // HuggingFace repo path
    quantization: "Q4_K_M",          // quantization label shown in UI
    config: .compact,                // or .standard / .quality
    capability: .simulatorAndDevice  // or .deviceRecommended
)
```

## Architecture

| File | Responsibility |
|------|----------------|
| `TranslationModel.swift` | Registry array + `TranslationModel` struct |
| `ModelConfiguration.swift` | Reusable config presets (batch, tokens, prompts) |
| `LlamaService.swift` | Reads `model.config` at runtime — zero hardcoded values |

`LlamaService` builds chat messages using `config.systemPrompt` and `config.userPromptTemplate`, and sampling using `config.temperature` / `config.topP` / `config.topK`. No service code changes are needed when adding a model.

## Current Models

| Model | Provider | Size | Quant | Config | Capability |
|-------|----------|------|-------|--------|------------|
| Qwen3 0.6B | Alibaba | ~397 MB | Q4_K_M | `.compact` | Simulator + Device |
| Hunyuan 0.5B | Tencent | ~308 MB | Q3_K_M | `.compact` | Simulator + Device |
| Gemma 3 1B | Google | ~690 MB | Q2_K | `.standard` | Device recommended |

## Notes

- **Never bundle GGUF files in Git.** They are downloaded at runtime into the app sandbox.
- If a model URL breaks (404/401), replace the entry rather than adding a duplicate. URLs for un-gated models are generally stable; gated models (e.g. `google/gemma-*` direct) may return 401 — use unsloth or bartowski mirrors instead.
