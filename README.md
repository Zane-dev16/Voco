# Voco — Offline Privacy-First AI Translation

**An iOS app that runs translation models entirely on-device, with no data
leaving your iPhone.**

## Supported Models

Voco ships with 11 downloadable translation models from 4 providers:

| Provider | Models | Quantizations |
|----------|--------|---------------|
| Tencent | Hy-MT1.5 1.8B, Hy-MT2 1.8B | STQ1_0 1.25-bit, Q4_K_M |
| Meta | Llama 3.2 1B, Llama 3.2 3B | Q8_0, IQ3_M |
| Qwen | Qwen3.5 0.8B, 2B, 4B | Q8_0, Q4_K_M |
| Google | Gemma 4 E2B, Gemma 4 E4B, TranslateGemma 4B | Q4_K_M, Q2_K |

See [MODEL_REGISTRY.md](MODEL_REGISTRY.md) for the full catalog.

## Requirements

- iOS 17.0 or later
- iPhone (optimized for Apple Silicon / ARM NEON)
- ~500 MB free storage for the smallest model; ~5 GB for the largest
- Internet connection for initial model download only — all translation is offline

## Build

```bash
git clone https://github.com/Zane-dev16/Voco.git
cd Voco
xcodebuild -scheme Voco -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The project uses a local Swift package at `Packages/swift-llama-cpp/` wrapping
a custom `llama.cpp` build (PR #22836, STQ1_0 kernel). No additional dependencies.

## Privacy

All translation runs on-device. No text, audio, or analytics data leaves your
iPhone. Model weights are downloaded directly from HuggingFace on first use and
cached locally. No account required.

## License

Voco is MIT licensed. See [LICENSE](LICENSE).

Individual model weights are distributed under their respective provider licenses
(Tencent Hunyuan, Llama 3.2 Community, Apache 2.0, Gemma). License details are
available in-app under Settings → Models & Licenses.
