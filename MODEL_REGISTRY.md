# Voco Model Registry

The model registry is the single source of truth for all downloadable translation
models. Adding a model requires editing **only one file**: `Voco/Models/TranslationModel.swift`.

## Current Models (10 entries, 4 providers)

| # | ID | Provider | Model | Quantization | Size | Capability |
|---|-----|----------|-------|-------------|------|------------|
| 1 | `hy-mt2-1.8b-stq` | Tencent | Hy-MT2 1.8B | 1.25-bit STQ1_0 | 441 MB | Simulator + Device |
| 2 | `hy-mt1.5-1.8b-q4km` | Tencent | Hy-MT1.5 1.8B HQ | Q4_K_M | 1.06 GB | Simulator + Device |
| 3 | `llama-3.2-1b-q8` | Meta | Llama 3.2 1B | Q8_0 | 1.32 GB | Device Recommended |
| 4 | `llama-3.2-3b-iq3m` | Meta | Llama 3.2 3B | IQ3_M | 1.53 GB | Device Recommended |
| 5 | `qwen3.5-0.8b-q8` | Qwen | Qwen3.5 0.8B | Q8_0 | 795 MB | Simulator + Device |
| 6 | `qwen3.5-2b-q4km` | Qwen | Qwen3.5 2B | Q4_K_M | 1.22 GB | Device Recommended |
| 7 | `qwen3.5-4b-q4km` | Qwen | Qwen3.5 4B | Q4_K_M | 2.60 GB | Device Recommended |
| 8 | `gemma-4-e2b-q4km` | Google | Gemma 4 E2B | Q4_K_M | 3.19 GB | Device Recommended |
| 9 | `gemma-4-e4b-q4km` | Google | Gemma 4 E4B | Q4_K_M | 5.02 GB | Device Recommended |
| 10 | `translategemma-4b-q2k` | Google | TranslateGemma 4B | Q2_K | 1.65 GB | Device Recommended |

## Adding a Model

1. Find a GGUF model on HuggingFace.
2. Pick a quantization that fits your target device.
3. Append a new `TranslationModel(...)` entry to the `availableModels` array
   in `TranslationModel.swift`.
4. Choose a `config` preset: `.hunyuanMT`, `.llamaInstruct`, `.qwenInstruct`,
   `.gemma4Raw`, `.gemmaInstruct`, `.compact`, `.standard`, `.quality`, or `.nllbTranslate`.
5. Verify the URL with a HEAD request before committing.

## Architecture

| File | Responsibility |
|------|----------------|
| `TranslationModel.swift` | Registry array + `TranslationModel` struct |
| `ModelConfiguration.swift` | Reusable config presets (batch, tokens, prompts) |
| `LlamaService.swift` | Reads `model.config` at runtime — zero hardcoded values |

## Notes

- **Never bundle GGUF files in Git.** They are downloaded at runtime.
- If a model URL breaks, replace the entry rather than adding a duplicate.
- Gated models (Meta Llama) require HF token authentication.
