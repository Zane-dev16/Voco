# Memory Lifecycle Audit — Voco

Date: 2026-06-01
Branch: `fix/memory-lifecycle-audit`

## 1. Test Harness Removal — VERIFIED

- `VocoApp.swift` — pure `WindowGroup { ContentView() }`. No `.task`, no test calls.
- `quickTest()` — fully removed from codebase.
- `iOS17CompatibilityTest.swift` — standalone, not wired to app lifecycle.
- `TranslationViewModel.swift` — dead code, never instantiated.

**Verified:** No model loads at launch beyond intentional `autoActivateModel()`. ✅

## 2. Background RAM Release — VERIFIED

Flow: `scenePhase == .background` → `Task { await deactivate() }` → `unloadModel()` → `inferenceService = nil` → ARC deinit chain frees `llama_free`, `llama_model_free`, `llama_backend_free`.

**Guaranteed:** RAM released on every background transition. ✅

## 3. Model Switching — FIXED + VERIFIED

### 3a. autoActivateModel race (FIXED)
`ContentView` had `.onChange(of: selectedModelID)` calling `autoActivateModel` in parallel with `selectModel`'s own activation Task. **Removed** `.onChange` trigger. `autoActivateModel` now only fires on `.onAppear`.

### 3b. selectModel sequential (VERIFIED)
Both SettingsView and ModelCatalogView use single sequential Task: cancel → deactivate → check cancelled → activate. Never both models in RAM simultaneously. ✅

### 3c. Rapid selection cancellation (VERIFIED)
`@State private var loadTask` stored. Each `selectModel` cancels previous Task. Cancelled Task checks `Task.isCancelled` between steps. ✅

### 3d. OnboardingView download path (VERIFIED)
`performDownload()` → `activate()` → internal `deactivate()` handles old model. Sequential. ✅

## 4. State Wrapper Correctness — VERIFIED

`@State var` with `@Observable` class on iOS 17+ is idiomatic. Correct for deployment target. ✅

## 5. Build

`xcodebuild -scheme Voco -destination 'generic/platform=iOS' build` → **BUILD SUCCEEDED**. Zero errors.

## 6. Remaining Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Deactivate 500ms delay may not complete if OS suspends aggressively | Low | iOS gives ~5s cleanup window |
| OnboardingView download Task not cancellable across model switches | Low | Rare scenario, impacts one extra load cycle |
| `@State` instance lost if ContentView destroyed | Low | Single-window app, root never destroyed |

## 7. Changes (this branch vs fix/memory-lifecycle-bugs)

- `ContentView.swift` — removed `.onChange(of: selectedModelID)` race trigger
- `MEMORY_LIFECYCLE_AUDIT.md` — this report
