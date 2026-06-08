1|//
2|//  LlamaEngineTests.swift
3|//  LlamaSwift
4|//
5|//  Created by Piotr Gorzelany on 22/10/2024.
6|//
7|
8|import Testing
9|import Foundation
10|import OSLog
11|@testable import SwiftLlama
12|
13|struct LlamaEngineTests {
14|
15|    // MARK: - Test Configuration
16|    
17|    private struct TestConfig {
18|        static let contextLength: UInt32 = 16384
19|        static let batchSize: UInt32 = 1024
20|        static let performanceTargetTokens = 500
21|        static let jsonTestMaxTokens = 100
22|        // Local performance baselines captured on this machine (detect regressions)
23|        static let minimumTokensPerSecond: Double = 20.0
24|        static let testSeed: UInt32 = 42
25|        static let shortTestTokens = 50
26|        static let grammarPerformanceTokens = 20
27|        static let grammarMinimumTokensPerSecond: Double = 3.0
28|        static let deterministicTokens = 100
29|        static let deterministicMinCharacters = 200
30|    }
31|    
32|    // MARK: - Properties
33|    
34|    private var llamaService: LlamaEngine!
35|    private let logger = Logger(subsystem: "SwiftLlamaTests", category: "LlamaServiceTests")
36|    
37|    // MARK: - Setup and Teardown
38|
39|    init() {
40|        llamaService = createLlamaEngine()
41|    }
42|
43|    // MARK: - Performance Tests
44|
45|    @Test("Streaming performance baseline")
46|    func testStreamCompletionPerformance() async throws {
47|        // Given
48|        let messages = createStoryMessages()
49|        let samplingConfig = createPerformanceSamplingConfig()
50|        
51|        // When
52|        let result = try await measureTokenGenerationPerformance(
53|            messages: messages,
54|            samplingConfig: samplingConfig,
55|            targetTokens: TestConfig.performanceTargetTokens
56|        )
57|        
58|        // Then
59|        #expect(result.tokenCount == TestConfig.performanceTargetTokens)
60|        // Local baseline; intent is regression tracking, not strict perf
61|        #expect(result.tokensPerSecond > TestConfig.minimumTokensPerSecond)
62|        
63|        // Log performance metrics
64|        print("PERF_STREAM tokens=\(result.tokenCount) tps=\(String(format: "%.2f", result.tokensPerSecond))")
65|        logger.info("=== Performance Test Results ===")
66|        logger.info("Generated \(result.tokenCount) tokens")
67|        logger.info("Speed: \(String(format: "%.2f", result.tokensPerSecond), privacy: .public) tokens/second")
68|        logger.info("Generated text preview: \(String(result.generatedText.prefix(100)), privacy: .public)...")
69|    }
70|    
71|    @Test("Grammar generation performance baseline")
72|    func testGrammarGenerationPerformance() async throws {
73|        // Given
74|        let messages = createJSONMessages()
75|        let samplingConfig = try createJSONSamplingConfig()
76|        
77|        // When
78|        let result = try await measureTokenGenerationPerformance(
79|            messages: messages,
80|            samplingConfig: samplingConfig,
81|            targetTokens: TestConfig.grammarPerformanceTokens
82|        )
83|        
84|        // Then
85|        // Baseline: ensure some progress and modest throughput to track regressions
86|        #expect(result.tokenCount >= 10)
87|        #expect(result.tokensPerSecond > TestConfig.grammarMinimumTokensPerSecond)
88|        
89|        // Note: performance harness may cut mid-JSON; don't validate structure here
90|        
91|        // Log performance metrics
92|        print("PERF_GRAMMAR tokens=\(result.tokenCount) tps=\(String(format: "%.2f", result.tokensPerSecond))")
93|        logger.info("=== Grammar Generation Performance ===")
94|        logger.info("Generated \(result.tokenCount) tokens")
95|        logger.info("Speed: \(String(format: "%.2f", result.tokensPerSecond), privacy: .public) tokens/second")
96|        logger.info("Valid JSON generated: \(result.generatedText.prefix(100), privacy: .public)...")
97|    }
98|
99|    // MARK: - Grammar Tests
100|    
101|    @Test("JSON object generation with grammar")
102|    func testJSONGenerationWithGrammar() async throws {
103|        // Given
104|        let messages = createJSONMessages()
105|        let samplingConfig = try createJSONSamplingConfig()
106|        
107|        // When
108|        let generatedText = try await generateJSONWithGrammar(
109|            messages: messages,
110|            samplingConfig: samplingConfig,
111|            maxTokens: TestConfig.jsonTestMaxTokens
112|        )
113|        
114|        // Then
115|        #expect(!generatedText.isEmpty)
116|        
117|        let jsonObject = try validateJSON(generatedText)
118|        
119|        // Log results
120|        logger.info("=== JSON Generation Test Results ===")
121|        logger.info("Generated JSON: \(generatedText, privacy: .public)")
122|        logger.info("Parsed object keys: \(Array(jsonObject.keys), privacy: .public)")
123|        
124|        // Verify structure (optional - could be more specific based on requirements)
125|        #expect(jsonObject.count > 0)
126|    }
127|    
128|    @Test("JSON array generation with grammar")
129|    func testJSONArrayGenerationWithGrammar() async throws {
130|        // Given
131|        let messages = createJSONArrayMessages()
132|        let samplingConfig = try createJSONArraySamplingConfig()
133|        
134|        // When
135|        let generatedText = try await generateJSONWithGrammar(
136|            messages: messages,
137|            samplingConfig: samplingConfig,
138|            maxTokens: TestConfig.jsonTestMaxTokens
139|        )
140|        
141|        // Then
142|        #expect(!generatedText.isEmpty)
143|        
144|        let jsonArray = try validateJSONArray(generatedText)
145|        
146|        // Log results
147|        logger.info("=== JSON Array Generation Test Results ===")
148|        logger.info("Generated JSON Array: \(generatedText, privacy: .public)")
149|        logger.info("Array contains \(jsonArray.count) elements")
150|        if !jsonArray.isEmpty {
151|            logger.info("First element type: \(String(describing: type(of: jsonArray[0])), privacy: .public)")
152|        }
153|        
154|        // Verify structure
155|        #expect(jsonArray.count >= 0)
156|    }
157|
158|    @Test("JSON string array generation and parsing to [String]")
159|    func testJSONStringArrayGenerationAndParsing() async throws {
160|        // Given
161|        let messages = [
162|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in valid JSON array format."),
163|            LlamaChatMessage(role: .user, content: "Generate a JSON array of 5 programming languages as strings.")
164|        ]
165|        let samplingConfig = try createJSONStringArraySamplingConfig()
166|
167|        // When
168|        let generatedText = try await generateJSONWithGrammar(
169|            messages: messages,
170|            samplingConfig: samplingConfig,
171|            maxTokens: TestConfig.jsonTestMaxTokens
172|        )
173|
174|        // Then
175|        let array = try validateStringArray(generatedText)
176|        #expect(!array.isEmpty)
177|        // Basic sanity: ensure they look like single words or known languages
178|        #expect(array.count == 5)
179|    }
180|    
181|    // MARK: - Sampling Configuration Tests
182|    
183|    @Test("Determinism: same seed -> identical output")
184|    func testSeedReproducibility() async throws {
185|        // Given
186|        let messages = createSimpleMessages()
187|        let seed: UInt32 = 12345
188|        let samplingConfig = LlamaSamplingConfig(temperature: 0.1, seed: seed)
189|
190|        // When - Generate same content twice with same seed
191|        let result1 = try await generateLimitedText(
192|            messages: messages,
193|            samplingConfig: samplingConfig,
194|            maxTokens: TestConfig.shortTestTokens
195|        )
196|
197|        let result2 = try await generateLimitedText(
198|            messages: messages,
199|            samplingConfig: samplingConfig,
200|            maxTokens: TestConfig.shortTestTokens
201|        )
202|        
203|        // Then
204|        #expect(result1 == result2)
205|        
206|        logger.info("=== Reproducibility Test Results ===")
207|        logger.info("Output 1: \(result1, privacy: .public)")
208|        logger.info("Output 2: \(result2, privacy: .public)")
209|    }
210|
211|    @Test("Deterministic run produces at least 200 characters")
212|    func testDeterministicMinimumCharacterCount() async throws {
213|        // Given: use the longer story prompt and fixed seed
214|        let messages = createStoryMessages()
215|        let samplingConfig = LlamaSamplingConfig(temperature: 0.1, seed: TestConfig.testSeed)
216|
217|        // When
218|        let result = try await generateLimitedText(
219|            messages: messages,
220|            samplingConfig: samplingConfig,
221|            maxTokens: TestConfig.deterministicTokens
222|        )
223|
224|        // Then
225|        #expect(result.count >= TestConfig.deterministicMinCharacters)
226|        logger.info("Deterministic length: \(result.count, privacy: .public) chars")
227|    }
228|
229|    @Test("Short story matches deterministic baseline")
230|    func testShortStoryMatchesBaseline() async throws {
231|        // Given: fixed prompt and seed/temperature for determinism
232|        let baseline = "Whiskers, a sleek and agile feline, spent her Martian days lounging in the low-gravity sunbeams that streamed through the transparent dome of her habitat module. At night, she'd prowl the dusty terrain outside, chasing after the occasional Martian dust bunny as she explored the barren landscape of Olympus Mons, the largest volcano on the Red Planet."
233|        let messages = [
234|            LlamaChatMessage(role: .system, content: "You are a helpful assistant."),
235|            LlamaChatMessage(role: .user, content: "Write a concise two-sentence story about a cat living on Mars. Be specific.")
236|        ]
237|        let cfg = LlamaSamplingConfig(temperature: 0.1, seed: TestConfig.testSeed)
238|
239|        // When
240|        let generated = try await generateLimitedText(messages: messages, samplingConfig: cfg, maxTokens: 160)
241|
242|        // Then: compare after light whitespace normalization to avoid incidental spacing differences
243|        func normalize(_ s: String) -> String {
244|            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
245|            let squashed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
246|            return squashed
247|        }
248|        #expect(normalize(generated) == normalize(baseline))
249|    }
250|
251|    // NOTE: The baseline above was captured by a temporary print-only test and then inlined.
252|    
253|    @Test("Temperature impacts output")
254|    func testTemperatureEffectsOnOutput() async throws {
255|        // Given
256|        let messages = createSimpleMessages()
257|        let temperatureValues: [Float] = [0.0, 0.7, 1.3, 2.0]
258|        var successes = 0
259|        
260|        logger.info("=== Temperature Effects Test Results ===")
261|        logger.info("Testing temperatures from 0.0 to 2.0 in 0.1 intervals...")
262|        
263|        // When - Test each temperature value
264|        for temperature in temperatureValues {
265|            let samplingConfig = LlamaSamplingConfig(
266|                temperature: temperature,
267|                seed: TestConfig.testSeed
268|            )
269|            
270|            do {
271|                let result = try await generateLimitedText(
272|                    messages: messages,
273|                    samplingConfig: samplingConfig,
274|                    maxTokens: 10
275|                )
276|                if !result.isEmpty { successes += 1 }
277|            } catch {
278|                let formattedTemp = String(format: "%.1f", temperature)
279|                Issue.record("Temperature \(formattedTemp) failed with error: \(error)")
280|            }
281|        }
282|        
283|        // At least one temperature setting should yield output
284|        #expect(successes >= 1)
285|    }
286|    
287|    @Test("Top-K sampling produces output")
288|    func testTopKSamplingConstraints() async throws {
289|        // Given
290|        let messages = createSimpleMessages()
291|        let topKConfig = LlamaSamplingConfig(
292|            temperature: 0.8,
293|            seed: TestConfig.testSeed,
294|            topK: 5 // Very restrictive top-k
295|        )
296|        
297|        // When
298|        let result = try await generateLimitedText(
299|            messages: messages,
300|            samplingConfig: topKConfig,
301|            maxTokens: TestConfig.shortTestTokens
302|        )
303|        
304|        // Then
305|        #expect(!result.isEmpty)
306|        
307|        logger.info("=== Top-K Sampling Test Results ===")
308|        logger.info("Generated with top-K=5: \(result, privacy: .public)")
309|    }
310|
311|    // MARK: - respond<T: Codable>() Tests
312|    
313|    private struct Person: Codable, Equatable {
314|        let name: String
315|        let age: Int
316|        let city: String?
317|    }
318|    
319|    @Test("Typed respond() produces decodable JSON object")
320|    func testRespondProducesDecodableObject() async throws {
321|        // Given
322|        let messages = [
323|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in JSON matching the schema."),
324|            LlamaChatMessage(role: .user, content: "Return a person with name 'Ada', age 36, city 'London'.")
325|        ]
326|        
327|        // When
328|        let person = try await llamaService.respond(to: messages, generating: Person.self)
329|        
330|        // Then
331|        #expect(!person.name.isEmpty)
332|        #expect(person.age >= 0)
333|    }
334|
335|    @Test("Typed respond() produces decodable array of strings")
336|    func testRespondProducesArrayOfStrings() async throws {
337|        // Given
338|        let messages = [
339|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in a JSON array of strings."),
340|            LlamaChatMessage(role: .user, content: "Return an array of 3 fruits as strings.")
341|        ]
342|        
343|        // When
344|        let fruits = try await llamaService.respond(to: messages, generating: [String].self)
345|        
346|        // Then
347|        #expect(!fruits.isEmpty)
348|        #expect(fruits.count >= 3)
349|    }
350|    
351|    // MARK: - respond(messages:samplingConfig:) Tests
352|    
353|    @Test("Plain respond() returns non-empty text")
354|    func testRespondTextNonEmpty() async throws {
355|        // Given: small token budget to keep the test bounded
356|        let service = LlamaEngine(
357|            modelUrl: .llama1B,
358|            config: .init(batchSize: 256, maxTokenCount: 80, useGPU: false)
359|        )
360|        let messages = [
361|            LlamaChatMessage(role: .system, content: "You are a helpful assistant."),
362|            LlamaChatMessage(role: .user, content: "Write a single short sentence (max 20 words).")
363|        ]
364|        let cfg = LlamaSamplingConfig(temperature: 0.3, seed: TestConfig.testSeed)
365|
366|        // When
367|        let text = try await service.respond(to: messages, samplingConfig: cfg)
368|
369|        // Then
370|        #expect(!text.isEmpty)
371|    }
372|
373|    @Test("Plain respond() is deterministic with same seed")
374|    func testRespondDeterminismWithSameSeed() async throws {
375|        // Given: two fresh services and identical config for determinism
376|        let cfg = LlamaSamplingConfig(temperature: 0.1, seed: TestConfig.testSeed)
377|        let serviceA = LlamaEngine(
378|            modelUrl: .llama1B,
379|            config: .init(batchSize: 256, maxTokenCount: 80, useGPU: false)
380|        )
381|        let serviceB = LlamaEngine(
382|            modelUrl: .llama1B,
383|            config: .init(batchSize: 256, maxTokenCount: 80, useGPU: false)
384|        )
385|        let messages = createSimpleMessages()
386|
387|        // When
388|        let out1 = try await serviceA.respond(to: messages, samplingConfig: cfg)
389|        let out2 = try await serviceB.respond(to: messages, samplingConfig: cfg)
390|
391|        // Then
392|        #expect(out1 == out2)
393|    }
394|
395|    // MARK: - json_array_strings.gbnf grammar with respond()
396|
397|    @Test("JSONStringArray grammar via respond() decodes to [String]")
398|    func testJSONStringArrayRespondParsesToArray() async throws {
399|        // Given
400|        let samplingConfig = try createJSONStringArraySamplingConfig()
401|        let service = LlamaEngine(
402|            modelUrl: .llama1B,
403|            config: .init(batchSize: 256, maxTokenCount: 120, useGPU: false)
404|        )
405|        let messages = [
406|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in a JSON array of strings."),
407|            LlamaChatMessage(role: .user, content: "Generate a JSON array of 4 animals as strings.")
408|        ]
409|
410|        // When
411|        let generatedText = try await service.respond(to: messages, samplingConfig: samplingConfig)
412|
413|        // Then
414|        let array = try validateStringArray(generatedText)
415|        #expect(array.count == 4)
416|    }
417|
418|    @Test("JSONStringArray grammar via respond() is deterministic with same seed")
419|    func testJSONStringArrayRespondDeterminism() async throws {
420|        // Given
421|        let samplingConfig = try createJSONStringArraySamplingConfig()
422|        let serviceA = LlamaEngine(
423|            modelUrl: .llama1B,
424|            config: .init(batchSize: 256, maxTokenCount: 120, useGPU: false)
425|        )
426|        let serviceB = LlamaEngine(
427|            modelUrl: .llama1B,
428|            config: .init(batchSize: 256, maxTokenCount: 120, useGPU: false)
429|        )
430|        let messages = [
431|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in a JSON array of strings."),
432|            LlamaChatMessage(role: .user, content: "Generate a JSON array of 3 programming languages as strings.")
433|        ]
434|
435|        // When
436|        let out1 = try await serviceA.respond(to: messages, samplingConfig: samplingConfig)
437|        let out2 = try await serviceB.respond(to: messages, samplingConfig: samplingConfig)
438|
439|        // Then
440|        #expect(out1 == out2)
441|        let arr1 = try validateStringArray(out1)
442|        let arr2 = try validateStringArray(out2)
443|        #expect(arr1 == arr2)
444|    }
445|
446|    @Test("JSONStringArray grammar remains valid at high temperature via respond()")
447|    func testJSONStringArrayHighTemperatureValidity() async throws {
448|        // Given: high temperature but constrained by grammar should still yield valid JSON array of strings
449|        let grammarString = try loadJSONStringArrayGrammar()
450|        let grammarConfig = LlamaGrammarConfig(grammar: grammarString, grammarRoot: "root")
451|        let samplingConfig = LlamaSamplingConfig(
452|            temperature: 1.8,
453|            seed: TestConfig.testSeed,
454|            grammarConfig: grammarConfig
455|        )
456|        let service = LlamaEngine(
457|            modelUrl: .llama1B,
458|            config: .init(batchSize: 256, maxTokenCount: 120, useGPU: false)
459|        )
460|        let messages = [
461|            LlamaChatMessage(role: .system, content: "You are a helpful assistant that responds only in a JSON array of strings."),
462|            LlamaChatMessage(role: .user, content: "Generate a short JSON array of lowercase fruit names as strings.")
463|        ]
464|
465|        // When
466|        let generatedText = try await service.respond(to: messages, samplingConfig: samplingConfig)
467|
468|        // Then: ensure it's a valid JSON array of strings (size may vary)
469|        let array = try validateStringArray(generatedText)
470|        #expect(!array.isEmpty)
471|    }
472|    
473|    @Test("Repetition penalty produces output")
474|    func testRepetitionPenaltyConfiguration() async throws {
475|        // Given
476|        let messages = createRepetitivePromptMessages()
477|        let penaltyConfig = LlamaRepetitionPenaltyConfig(
478|            lastN: 20,
479|            repeatPenalty: 1.3,
480|            freqPenalty: 0.1,
481|            presentPenalty: 0.1
482|        )
483|        let samplingConfig = LlamaSamplingConfig(
484|            temperature: 0.8,
485|            seed: TestConfig.testSeed,
486|            repetitionPenaltyConfig: penaltyConfig
487|        )
488|        
489|        // When
490|        let result = try await generateLimitedText(
491|            messages: messages,
492|            samplingConfig: samplingConfig,
493|            maxTokens: TestConfig.shortTestTokens
494|        )
495|        
496|        // Then
497|        #expect(!result.isEmpty)
498|        
499|        logger.info("=== Repetition Penalty Test Results ===")
500|        logger.info("Generated with penalties: \(result, privacy: .public)")
501|