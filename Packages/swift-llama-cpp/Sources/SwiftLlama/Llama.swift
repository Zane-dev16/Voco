import Foundation
import llama
import os

enum NextToken {
    case token(String)
    case endOfString
}

/// Shared os.Logger for the SwiftLlama module.
/// Replaces raw print()/NSLog so release builds stay quiet (debug-level
/// messages are filtered out unless debug logging is explicitly enabled).
enum SwiftLlamaLog {
    static let logger = Logger(subsystem: "dev.voco.SwiftLlama", category: "inference")

    /// Privacy-safe preview of user text: truncated to a short prefix.
    /// Call sites mark the result `.private` so prompt contents never land in
    /// default logs; the truncation also keeps long prompts from bloating entries.
    static func promptPreview(_ text: String, limit: Int = 48) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

/// Thrown when token generation is attempted before a sampling configuration
/// has been applied via `updateSamplingConfig(_:)`.
public struct LlamaSamplerNotConfiguredError: Error, LocalizedError {
    public init() {}
    public var errorDescription: String? {
        "Token generation was requested before a sampling configuration was applied."
    }
}

final actor Llama {
    private let model: LlamaModel
    let context: LlamaContext
    private var batch: LlamaBatch
    /// Optional (not implicitly unwrapped): generating before
    /// `updateSamplingConfig(_:)` throws instead of crashing.
    private var sampler: LlamaSampler?

    // Configuration

    private let config: LlamaConfig
    let maxTokenCount: UInt32
    /// Tracks the current position in the token sequence during decoding.
    var currentTokenPosition: Int32 = 0
    var processedTokens: [llama_token] = []

    init(modelPath: String, config: LlamaConfig) throws {
        self.config = config
        // Ref-counted process-global backend; freed when the last Llama deinits.
        LlamaBackend.retain()
        var modelParameters = llama_model_default_params()

        if !config.useGPU {
            modelParameters.n_gpu_layers = 0
        }

        #if targetEnvironment(simulator)
                modelParameters.n_gpu_layers = 0
                SwiftLlamaLog.logger.debug("Running on simulator, force use n_gpu_layers = 0")
        #endif

        let model = LlamaModel(path: modelPath, parameters: modelParameters)
        guard let model else {
            SwiftLlamaLog.logger.error("Could not load model at \(modelPath, privacy: .public)")
            throw LlamaError.couldNotInitializeContext
        }

        let threadCount = max(config.nThreads, 1)
        let threadCountBatch = max(config.nThreadsBatch, 1)
        SwiftLlamaLog.logger.info("[Llama] Using threadCount=\(threadCount) threadCountBatch=\(threadCountBatch)")

        var contextParam = llama_context_default_params()
        contextParam.n_ctx = config.maxTokenCount
        contextParam.n_threads       = Int32(threadCount)
        contextParam.n_threads_batch = Int32(threadCountBatch)
        contextParam.n_batch = config.batchSize
        contextParam.n_ubatch = config.batchSize
        contextParam.offload_kqv = true

        let context = LlamaContext(model: model, parameters: contextParam)
        guard let context else {
            SwiftLlamaLog.logger.error("Could not load context!")
            throw LlamaError.couldNotInitializeContext
        }


        self.maxTokenCount = min(UInt32(model.trainedContextSize()), config.maxTokenCount)
        self.model = context.model
        self.context = context
        self.batch = .init(initialSize: Int32(config.batchSize))
    }

    deinit {
        // Release our backend retain; the backend itself is only freed once the
        // last live Llama instance releases its reference.
        LlamaBackend.release()
    }

    // Expose some backend/system utilities for convenience
    /// Return system info string from the backend.
    static func printSystemInfo() -> String {
        guard let systemInfoCString = llama_print_system_info() else { return "" }
        return String(cString: systemInfoCString)
    }

    /// Expose the underlying context to trusted callers (tests / advanced users).
    /// Access is actor-isolated; callers must `await`.
    func contextHandle() -> LlamaContext { context }

    // MARK: - Testing & Introspection helpers (actor-safe)

    func getLastLogits() -> [Float]? { context.lastLogits() }
    func getEmbeddings() -> [Float]? { context.embeddings(at: -1) }
    func enableEmbeddingsOutput(_ enabled: Bool) { context.setEmbeddingsOutput(enabled) }
    func saveStateData() -> Data { context.saveState() }
    func loadStateData(_ data: Data) -> Bool { context.loadState(data) }
    func setThreads(nThreads: Int32, nThreadsBatch: Int32) { context.setThreads(nThreads: nThreads, nThreadsBatch: nThreadsBatch) }
    func getThreads() -> (Int32, Int32) { (context.nThreads(), context.nThreadsBatch()) }
    func kvMinPosition() -> Int32 { context.memory.minPosition(for: 0) }
    func kvMaxPosition() -> Int32 { context.memory.maxPosition(for: 0) }
    func clearKV() { context.clearKVCache() }

    /// Return the full processed token id sequence (prompt + generated).
    func getProcessedTokenIds() -> [llama_token] { processedTokens }

    func initializeCompletion(messages: [LlamaChatMessage], addAssistant: Bool? = nil) throws {
        let formattedPrompt = model.applyChatTemplate(to: messages, addAssistant: addAssistant)
        try initializeCompletion(text: formattedPrompt)
    }

    func initializeCompletion(text: String, addBos: Bool? = nil) throws {
        // Log only a truncated, privacy-redacted preview — never the full prompt.
        let preview = SwiftLlamaLog.promptPreview(text)
        SwiftLlamaLog.logger.debug("attempting to complete \"\(preview, privacy: .private)\" (\(text.utf8.count) bytes)")

        let effectiveAddBos = addBos ?? model.shouldAddBos()
        let tokenList = model.tokenize(text: text, addBos: effectiveAddBos, special: true)
        guard tokenList.count < maxTokenCount - 4 else {
            throw LlamaError.contextSizeLimitExceeded
        }

        if tokenList.starts(with: processedTokens) {
            SwiftLlamaLog.logger.debug("Using cached processing")
            try processPrompt(tokens: Array(tokenList[processedTokens.count...]), startIndex: processedTokens.count)
        } else {
            // Check if we can optimize by only clearing from the divergence point
            let divergenceIndex = findDivergenceIndex(newTokenList: tokenList, processedTokens: processedTokens)
            
            if divergenceIndex > 0 && shouldUsePartialOptimization(divergenceIndex: divergenceIndex, totalProcessed: processedTokens.count) {
                SwiftLlamaLog.logger.debug("Using partial optimization from position \(divergenceIndex)")
                do {
                    try optimizedReprocessing(newTokenList: tokenList, divergenceIndex: divergenceIndex)
                } catch {
                    SwiftLlamaLog.logger.error("Partial optimization failed, falling back to full reprocessing")
                    clear()
                    try processPrompt(tokens: tokenList, startIndex: 0)
                }
            } else {
                SwiftLlamaLog.logger.debug("Full reprocessing required")
                clear()
                try processPrompt(tokens: tokenList, startIndex: 0)
            }
        }
    }

    /// Find the index where the two token lists diverge
    private func findDivergenceIndex(newTokenList: [llama_token], processedTokens: [llama_token]) -> Int {
        let minLength = min(newTokenList.count, processedTokens.count)
        for index in 0..<minLength {
            if newTokenList[index] != processedTokens[index] {
                return index
            }
        }
        return minLength
    }
    
    /// Decide whether to use partial optimization based on the divergence point
    private func shouldUsePartialOptimization(divergenceIndex: Int, totalProcessed: Int) -> Bool {
        // Only use partial optimization if:
        // 1. We have a significant amount of processed tokens (at least 10)
        // 2. The divergence is not too early (at least 50% of tokens match)
        // 3. The divergence is not at the very beginning
        
        guard divergenceIndex > 0 && totalProcessed >= 10 else { return false }
        
        let matchPercentage = Double(divergenceIndex) / Double(totalProcessed)
        return matchPercentage >= 0.5 // At least 50% of tokens match
    }
    
    /// Optimized reprocessing that only clears cache from the divergence point
    private func optimizedReprocessing(newTokenList: [llama_token], divergenceIndex: Int) throws {
        // Clear KV cache from the divergence point onward
        context.clearKVCacheFromPosition(Int32(divergenceIndex))
        
        // Update our internal state
        processedTokens = Array(processedTokens[0..<divergenceIndex])
        currentTokenPosition = Int32(divergenceIndex)
        
        // Process only the tokens from the divergence point onward
        let tokensToProcess = Array(newTokenList[divergenceIndex...])
        try processPrompt(tokens: tokensToProcess, startIndex: divergenceIndex)
    }

    func generateNextToken() throws -> NextToken {
        // Stop before sampling if we've reached the context limit to avoid mutating sampler state
        if currentTokenPosition >= Int32(maxTokenCount) {
            return .endOfString
        }
        guard let sampler else {
            throw LlamaSamplerNotConfiguredError()
        }
        let newTokenId = sampler.sample(context: context)

        if model.isEogToken(newTokenId) || currentTokenPosition >= Int32(maxTokenCount) {
            return .endOfString
        }

        batch.reset()
        batch.addToken(newTokenId, at: currentTokenPosition, logits: true)
        processedTokens.append(newTokenId)

        currentTokenPosition += 1
        try context.decode(batch: batch)

        return .token(model.piece(from: newTokenId))
    }

    func updateSamplingConfig(_ config: LlamaSamplingConfig) {
        self.sampler = .init(config: config, model: model)
    }

    private func clear() {
        context.clearKVCache()
        processedTokens = []
        batch = .init(initialSize: Int32(config.batchSize))
    }

    private func processBatch() throws {
        do {
            try context.decode(batch: batch)
        } catch {
            SwiftLlamaLog.logger.error("llama_decode() failed")
            throw LlamaError.decodingError
        }
    }

    private func processPrompt(tokens: [llama_token], startIndex: Int) throws {
        guard !tokens.isEmpty else { return }
        batch.reset()

        for tokenIndex in 0..<tokens.count {
            let tokenPosition = startIndex + tokenIndex
            let tokenId = tokens[tokenIndex]
            batch.addToken(tokenId, at: Int32(tokenPosition), logits: false)
            processedTokens.append(tokenId)
            if batch.size == config.batchSize {
                try processBatch()
                batch.reset()
            }
        }

        batch.setLastTokenLogits(true)
        try processBatch()

        currentTokenPosition = Int32(processedTokens.count)

    }
}
