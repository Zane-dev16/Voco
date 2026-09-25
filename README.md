# Voco

Voco is an iOS app that runs translation models entirely on device. Translation works offline after the first model download. The build targets Apple Silicon with ARM NEON, and supports 10 downloadable models listed in the registry.

## Setup

Requirements: iOS 17.0 or later, an iPhone, and 500 MB to 5 GB of free storage depending on the model. The internet is needed only for the first model download.

```bash
git clone https://github.com/Zane-dev16/Voco.git
cd Voco
xcodebuild -scheme Voco -destination 'platform=iOS Simulator,name=iPhone' build
```

Replace `iPhone` with any installed simulator. List them with `xcrun simctl list devices available`.

The bundled `llama.xcframework` contains arm64 slices only (device and simulator). If you build with the generic destination (`generic/platform=iOS Simulator`), pass `ARCHS=arm64` or the x86_64 slice fails to link.

The project uses a local Swift package at `Packages/swift-llama-cpp/` wrapping a custom `llama.cpp` build. No additional dependencies.

See MODEL_REGISTRY.md, MODEL_RUNTIME_GUIDE.md, and MEMORY_LIFECYCLE_AUDIT.md for the model catalog, runtime notes, and memory audit.

## Privacy

Translation runs on device, and no text, audio, or analytics data leaves the phone. Model weights download directly from HuggingFace on first use and are cached locally. No account is required.

## License

Voco is MIT licensed. See LICENSE. Model weights keep their own provider licenses, listed in the app under Settings and Models and Licenses.
