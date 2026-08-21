import Foundation
import llama

public enum LlamaBackend {
    // MARK: - Process-global backend lifetime

    // llama_backend_init()/llama_backend_free() operate on process-global state.
    // Tearing the backend down while another Llama instance still holds a model
    // or context handle is undefined behavior, so the backend lifetime is
    // ref-counted: init on first retain, free only when the last retain drops.
    private static let lifetimeLock = NSLock()
    // Access is serialized by `lifetimeLock`; `nonisolated(unsafe)` only silences
    // the global-actor check for this lock-guarded counter.
    nonisolated(unsafe) private static var lifetimeRetainCount = 0

    /// Retain the process-global llama + ggml backend.
    /// Initializes it on the first retain; subsequent retains are no-ops.
    public static func retain() {
        lifetimeLock.lock()
        defer { lifetimeLock.unlock() }
        if lifetimeRetainCount == 0 {
            llama_backend_init()
        }
        lifetimeRetainCount += 1
    }

    /// Release one backend retain acquired via `retain()`.
    /// Frees the backend only when the last retain is released.
    public static func release() {
        lifetimeLock.lock()
        defer { lifetimeLock.unlock() }
        guard lifetimeRetainCount > 0 else { return }
        lifetimeRetainCount -= 1
        if lifetimeRetainCount == 0 {
            llama_backend_free()
        }
    }

    /// Initialize the llama + ggml backend. Ref-counted; safe to call multiple times.
    public static func initialize() { retain() }
    /// Release one backend reference. The backend is freed when the last reference drops.
    public static func shutdown() { release() }
    /// Whether mmap/mlock/gpu offload/rpc are supported by the compiled library.
    public static var supportsMmap: Bool { llama_supports_mmap() }
    public static var supportsMlock: Bool { llama_supports_mlock() }
    public static var supportsGpuOffload: Bool { llama_supports_gpu_offload() }
    public static var supportsRpc: Bool { llama_supports_rpc() }
    /// Maximum devices and parallel sequences
    public static var maxDevices: Int { Int(llama_max_devices()) }
    public static var maxParallelSequences: Int { Int(llama_max_parallel_sequences()) }

    /// Initialize NUMA with a given strategy.
    public static func numaInit(_ strategy: ggml_numa_strategy) { llama_numa_init(strategy) }

    /// Microsecond timer from llama.cpp
    public static func timeMicros() -> Int64 { llama_time_us() }

    /// Return system info string provided by llama.cpp
    public static func systemInfo() -> String {
        guard let systemInfoCString = llama_print_system_info() else { return "" }
        return String(cString: systemInfoCString)
    }

    /// Attach the library-managed auto threadpool to a context.
    public static func attachAutoThreadpool(to context: LlamaContext) {
        llama_attach_threadpool(context.contextPointer, nil, nil)
    }

    /// Detach any threadpools from the context.
    public static func detachThreadpool(from context: LlamaContext) {
        llama_detach_threadpool(context.contextPointer)
    }
}

