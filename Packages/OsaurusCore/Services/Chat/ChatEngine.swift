//
//  ChatEngine.swift
//  osaurus
//
//  Actor encapsulating model routing and generation streaming.
//

import Foundation

actor ChatEngine: Sendable, ChatEngineProtocol {
    private let services: [ModelService]
    private let installedModelsProvider: @Sendable () -> [String]

    /// Source of the inference (for logging purposes)
    private var inferenceSource: InferenceSource = .httpAPI

    init(
        services: [ModelService] = [FoundationModelService(), VMLXServiceBridge(), MLXService()],
        installedModelsProvider: @escaping @Sendable () -> [String] = {
            // Merge VMLX models (JANG quants from well-known dirs) with MLX models (ModelManager)
            let vmlxModels = VMLXServiceBridge.getAvailableModels()
            let mlxModels = MLXService.getAvailableModels()
            // De-duplicate: VMLX models take priority, then MLX models not already listed
            let vmlxSet = Set(vmlxModels)
            return vmlxModels + mlxModels.filter { !vmlxSet.contains($0) }
        },
        source: InferenceSource = .httpAPI
    ) {
        self.services = services
        self.installedModelsProvider = installedModelsProvider
        self.inferenceSource = source
    }
    struct EngineError: Error {}

    private func enrichMessagesWithSystemPrompt(_ messages: [ChatMessage]) async -> [ChatMessage] {
        debugLog("[ChatEngine] enrichMessages: start count=\(messages.count)")
        if messages.contains(where: { $0.role == "system" }) {
            debugLog("[ChatEngine] enrichMessages: already has system, returning early")
            return messages
        }

        let systemPrompt = await MainActor.run {
            ChatConfigurationStore.load().systemPrompt
        }
        debugLog("[ChatEngine] enrichMessages: got systemPrompt, injecting")

        let effective = SystemPromptBuilder.effectiveBasePrompt(systemPrompt)
        var enriched = messages
        SystemPromptBuilder.injectSystemContent(effective, into: &enriched)
        return enriched
    }

    /// Estimate input tokens from messages (rough heuristic: ~4 chars per token)
    private func estimateInputTokens(_ messages: [ChatMessage]) -> Int {
        let totalChars = messages.reduce(0) { sum, msg in
            sum + (msg.content?.count ?? 0)
        }
        return max(1, totalChars / 4)
    }

    func streamChat(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<String, Error> {
        debugLog("[ChatEngine] streamChat: start model=\(request.model)")
        let messages = await enrichMessagesWithSystemPrompt(request.messages)
        debugLog("[ChatEngine] streamChat: enriched messages count=\(messages.count), fetching remote services")
        let temperature = request.temperature
        let maxTokens = request.max_tokens ?? 16384
        let repPenalty: Float? = {
            // Map OpenAI penalties (presence/frequency) to a simple repetition penalty if provided
            if let fp = request.frequency_penalty, fp > 0 { return 1.0 + fp }
            if let pp = request.presence_penalty, pp > 0 { return 1.0 + pp }
            return nil
        }()
        let params = GenerationParameters(
            temperature: temperature,
            maxTokens: maxTokens,
            topPOverride: request.top_p,
            repetitionPenalty: repPenalty,
            modelOptions: request.modelOptions ?? [:],
            sessionId: request.session_id,
            cacheHint: request.cache_hint
        )

        // Candidate services and installed models (injected for testability)
        let services = self.services

        // Fetch current remote services from MainActor at request time so routing always
        // reflects the latest connected Bonjour/remote agents without requiring a new engine.
        let remoteServices: [ModelService] = await MainActor.run {
            RemoteProviderManager.shared.connectedServices()
        }
        debugLog("[ChatEngine] streamChat: remoteServices=\(remoteServices.count), routing model=\(request.model ?? "nil")")

        // Use the same routing logic as completeChat: remote providers first for
        // explicit model requests (e.g. "openai/gpt-4"), then local services.
        // This ensures streaming and non-streaming endpoints behave identically.
        let route = ModelServiceRouter.resolve(
            requestedModel: request.model,
            services: services,
            remoteServices: remoteServices
        )

        // Build an ordered list of services to try: routed service first, then all
        // remaining services as fallback (e.g. VMLX can't load a model → MLXService).
        var candidateServices: [ModelService] = []
        if case .service(let primary, _) = route {
            candidateServices.append(primary)
        }
        for svc in services where !candidateServices.contains(where: { $0.id == svc.id }) {
            candidateServices.append(svc)
        }
        for svc in remoteServices where !candidateServices.contains(where: { $0.id == svc.id }) {
            candidateServices.append(svc)
        }

        var lastError: Error?
        for service in candidateServices {
            guard service.isAvailable(), service.handles(requestedModel: request.model) else { continue }

            do {
                let innerStream: AsyncThrowingStream<String, Error>

                if let tools = request.tools, !tools.isEmpty, let toolSvc = service as? ToolCapableService {
                    let stopSequences = request.stop ?? []
                    debugLog("[ChatEngine] streamChat: trying \(service.id) with tools=\(tools.count)")
                    innerStream = try await toolSvc.streamWithTools(
                        messages: messages,
                        parameters: params,
                        stopSequences: stopSequences,
                        tools: tools,
                        toolChoice: request.tool_choice,
                        requestedModel: request.model
                    )
                } else {
                    debugLog("[ChatEngine] streamChat: trying \(service.id) streamDeltas")
                    innerStream = try await service.streamDeltas(
                        messages: messages,
                        parameters: params,
                        requestedModel: request.model,
                        stopSequences: request.stop ?? []
                    )
                }

                let source = self.inferenceSource
                let inputTokens = estimateInputTokens(messages)
                let model = request.model ?? "default"

                return wrapStreamWithLogging(
                    innerStream,
                    source: source,
                    model: model,
                    inputTokens: inputTokens,
                    temperature: temperature,
                    maxTokens: maxTokens
                )
            } catch {
                debugLog("[ChatEngine] streamChat: \(service.id) failed: \(error.localizedDescription), trying next service")
                lastError = error
                continue
            }
        }

        if let err = lastError { throw err }
        throw EngineError()
    }

    /// Wraps an async stream to count output tokens and log on completion.
    /// Uses Task.detached to avoid actor isolation deadlocks when consumed from MainActor.
    /// Properly handles cancellation via onTermination handler to prevent orphaned tasks.
    private func wrapStreamWithLogging(
        _ inner: AsyncThrowingStream<String, Error>,
        source: InferenceSource,
        model: String,
        inputTokens: Int,
        temperature: Float?,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        // Create the producer task and store reference for cancellation
        // IMPORTANT: Use Task.detached to run on cooperative thread pool instead of
        // ChatEngine actor's executor. This prevents deadlocks when the MainActor
        // consumes this stream while waiting for actor-isolated yields.
        let producerTask = Task.detached(priority: .userInitiated) {
            let startTime = Date()
            var outputTokenCount = 0
            var deltaCount = 0
            var finishReason: InferenceLog.FinishReason = .stop
            var errorMsg: String? = nil
            var toolInvocation: (name: String, args: String)? = nil
            var lastDeltaTime = startTime

            print("[Osaurus][Stream] Starting stream wrapper for model: \(model)")

            do {
                for try await delta in inner {
                    // Check for task cancellation to allow early termination
                    if Task.isCancelled {
                        print("[Osaurus][Stream] Task cancelled after \(deltaCount) deltas")
                        continuation.finish()
                        return
                    }

                    // Pass through tool-hint sentinels without counting as tokens
                    if StreamingToolHint.isSentinel(delta) {
                        continuation.yield(delta)
                        continue
                    }

                    deltaCount += 1
                    let now = Date()
                    let timeSinceStart = now.timeIntervalSince(startTime)
                    let timeSinceLastDelta = now.timeIntervalSince(lastDeltaTime)
                    lastDeltaTime = now

                    // Log every 50th delta or if there's a long gap (potential freeze indicator)
                    if deltaCount % 50 == 1 || timeSinceLastDelta > 2.0 {
                        print(
                            "[Osaurus][Stream] Delta #\(deltaCount): +\(String(format: "%.2f", timeSinceStart))s total, gap=\(String(format: "%.3f", timeSinceLastDelta))s, len=\(delta.count)"
                        )
                    }

                    // Estimate tokens: each delta chunk is roughly proportional to tokens
                    // More accurate: count whitespace-separated words, or use tokenizer
                    outputTokenCount += max(1, delta.count / 4)
                    continuation.yield(delta)
                }

                // Finish the stream FIRST so the UI can stop the typing indicator
                // immediately. Logging runs after — never block stream termination.
                continuation.finish()

                let totalTime = Date().timeIntervalSince(startTime)
                print(
                    "[Osaurus][Stream] Stream completed: \(deltaCount) deltas in \(String(format: "%.2f", totalTime))s"
                )
            } catch let inv as ServiceToolInvocation {
                print("[Osaurus][Stream] Tool invocation: \(inv.toolName)")
                toolInvocation = (inv.toolName, inv.jsonArguments)
                finishReason = .toolCalls
                continuation.finish(throwing: inv)
            } catch {
                // Check if this is a CancellationError (expected when consumer stops)
                if Task.isCancelled || error is CancellationError {
                    print("[Osaurus][Stream] Stream cancelled after \(deltaCount) deltas")
                    continuation.finish()
                    return
                }
                print("[Osaurus][Stream] Stream error after \(deltaCount) deltas: \(error.localizedDescription)")
                finishReason = .error
                errorMsg = error.localizedDescription
                continuation.finish(throwing: error)
            }

            // Log the completed inference (only for Chat UI - HTTP requests are logged by HTTPHandler)
            if source == .chatUI {
                let durationMs = Date().timeIntervalSince(startTime) * 1000
                var toolCalls: [ToolCallLog]? = nil
                if let (name, args) = toolInvocation {
                    toolCalls = [ToolCallLog(name: name, arguments: args)]
                }

                InsightsService.logInference(
                    source: source,
                    model: model,
                    inputTokens: inputTokens,
                    outputTokens: outputTokenCount,
                    durationMs: durationMs,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    toolCalls: toolCalls,
                    finishReason: finishReason,
                    errorMessage: errorMsg
                )
            }
        }

        // Set up termination handler to cancel the producer task when consumer stops consuming
        // This ensures proper cleanup when the UI task is cancelled or completes early
        continuation.onTermination = { @Sendable termination in
            switch termination {
            case .cancelled:
                print("[Osaurus][Stream] Consumer cancelled - stopping producer task")
                producerTask.cancel()
            case .finished:
                // Normal completion, producer should already be done
                break
            @unknown default:
                producerTask.cancel()
            }
        }

        return stream
    }

    func completeChat(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let startTime = Date()
        let messages = await enrichMessagesWithSystemPrompt(request.messages)
        let inputTokens = estimateInputTokens(messages)
        let temperature = request.temperature
        let maxTokens = request.max_tokens ?? 16384
        let repPenalty2: Float? = {
            if let fp = request.frequency_penalty, fp > 0 { return 1.0 + fp }
            if let pp = request.presence_penalty, pp > 0 { return 1.0 + pp }
            return nil
        }()
        let params = GenerationParameters(
            temperature: temperature,
            maxTokens: maxTokens,
            topPOverride: request.top_p,
            repetitionPenalty: repPenalty2,
            modelOptions: request.modelOptions ?? [:],
            sessionId: request.session_id,
            cacheHint: request.cache_hint
        )

        let services = self.services

        // Fetch current remote services from MainActor at request time.
        let remoteServices = await MainActor.run { RemoteProviderManager.shared.connectedServices() }

        let route = ModelServiceRouter.resolve(
            requestedModel: request.model,
            services: services,
            remoteServices: remoteServices
        )

        let created = Int(Date().timeIntervalSince1970)
        let responseId =
            "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"

        switch route {
        case .service(let service, let effectiveModel):
            // If tools were provided and the service supports them, use the message-based API
            if let tools = request.tools, !tools.isEmpty, let toolSvc = service as? ToolCapableService {
                let stopSequences = request.stop ?? []
                do {
                    let text = try await toolSvc.respondWithTools(
                        messages: messages,
                        parameters: params,
                        stopSequences: stopSequences,
                        tools: tools,
                        toolChoice: request.tool_choice,
                        requestedModel: request.model
                    )
                    let outputTokens = max(1, text.count / 4)
                    let choice = ChatChoice(
                        index: 0,
                        message: ChatMessage(
                            role: "assistant",
                            content: text,
                            tool_calls: nil,
                            tool_call_id: nil
                        ),
                        finish_reason: "stop"
                    )
                    let usage = Usage(
                        prompt_tokens: inputTokens,
                        completion_tokens: outputTokens,
                        total_tokens: inputTokens + outputTokens
                    )

                    // Log the inference (only for Chat UI - HTTP requests are logged by HTTPHandler)
                    if inferenceSource == .chatUI {
                        let durationMs = Date().timeIntervalSince(startTime) * 1000
                        InsightsService.logInference(
                            source: inferenceSource,
                            model: effectiveModel,
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            durationMs: durationMs,
                            temperature: temperature,
                            maxTokens: maxTokens,
                            finishReason: .stop
                        )
                    }

                    return ChatCompletionResponse(
                        id: responseId,
                        created: created,
                        model: effectiveModel,
                        choices: [choice],
                        usage: usage,
                        system_fingerprint: nil
                    )
                } catch let inv as ServiceToolInvocation {
                    // Convert tool invocation to OpenAI-style non-stream response
                    let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    let callId = "call_" + String(raw.prefix(24))
                    let toolCall = ToolCall(
                        id: callId,
                        type: "function",
                        function: ToolCallFunction(name: inv.toolName, arguments: inv.jsonArguments),
                        geminiThoughtSignature: inv.geminiThoughtSignature
                    )
                    let assistant = ChatMessage(
                        role: "assistant",
                        content: nil,
                        tool_calls: [toolCall],
                        tool_call_id: nil
                    )
                    let choice = ChatChoice(index: 0, message: assistant, finish_reason: "tool_calls")
                    let usage = Usage(prompt_tokens: inputTokens, completion_tokens: 0, total_tokens: inputTokens)

                    // Log the inference (only for Chat UI - HTTP requests are logged by HTTPHandler)
                    if inferenceSource == .chatUI {
                        let durationMs = Date().timeIntervalSince(startTime) * 1000
                        InsightsService.logInference(
                            source: inferenceSource,
                            model: effectiveModel,
                            inputTokens: inputTokens,
                            outputTokens: 0,
                            durationMs: durationMs,
                            temperature: temperature,
                            maxTokens: maxTokens,
                            toolCalls: [ToolCallLog(name: inv.toolName, arguments: inv.jsonArguments)],
                            finishReason: .toolCalls
                        )
                    }

                    return ChatCompletionResponse(
                        id: responseId,
                        created: created,
                        model: effectiveModel,
                        choices: [choice],
                        usage: usage,
                        system_fingerprint: nil
                    )
                }
            }

            // Use streaming internally to capture engine stats from sentinels.
            let stream = try await service.streamDeltas(
                messages: messages,
                parameters: params,
                requestedModel: request.model,
                stopSequences: request.stop ?? []
            )
            var text = ""
            var engineStats: GenerationStats? = nil
            for try await delta in stream {
                if let stats = StreamingToolHint.decodeStats(delta) {
                    engineStats = stats
                } else if !StreamingToolHint.isSentinel(delta) {
                    text += delta
                }
            }
            let outputTokens = engineStats?.completionTokens ?? max(1, text.count / 4)
            let promptToks = engineStats?.promptTokens ?? inputTokens
            let choice = ChatChoice(
                index: 0,
                message: ChatMessage(role: "assistant", content: text, tool_calls: nil, tool_call_id: nil),
                finish_reason: "stop"
            )
            let usage = Usage(
                prompt_tokens: promptToks,
                completion_tokens: outputTokens,
                total_tokens: promptToks + outputTokens,
                cached_tokens: engineStats.map { $0.cachedTokens > 0 ? $0.cachedTokens : nil } ?? nil
            )

            // Build engine stats for API response
            let xEngine: EngineStats? = engineStats.map {
                EngineStats(
                    ttft: $0.ttft,
                    prompt_tokens_per_sec: $0.prefillTokensPerSecond,
                    generation_tokens_per_sec: $0.decodeTokensPerSecond,
                    cache_detail: $0.cacheDetail,
                    cache_bytes: Int($0.cacheBytes)
                )
            }

            // Log the inference (only for Chat UI - HTTP requests are logged by HTTPHandler)
            if inferenceSource == .chatUI {
                let durationMs = Date().timeIntervalSince(startTime) * 1000
                InsightsService.logInference(
                    source: inferenceSource,
                    model: effectiveModel,
                    inputTokens: promptToks,
                    outputTokens: outputTokens,
                    durationMs: durationMs,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    finishReason: .stop
                )
            }

            return ChatCompletionResponse(
                id: responseId,
                created: created,
                model: effectiveModel,
                choices: [choice],
                usage: usage,
                system_fingerprint: nil,
                x_engine: xEngine
            )
        case .none:
            throw EngineError()
        }
    }

    // MARK: - Remote Provider Services

}
