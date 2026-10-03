import Foundation

enum WatchVoiceError: LocalizedError {
    case missingKey
    case invalidKey
    case insufficientBalance
    case rateLimited
    case invalidResponse
    case responseIncomplete(String?)
    case responseFailed(String?)
    case modelUnavailable
    case timedOut
    case credentialStorage
    case server(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "请先在 iPhone 上把 DeepSeek API Key 同步到手表。"
        case .invalidKey: "API Key 已失效，请在 iPhone 上重新同步。"
        case .insufficientBalance: "DeepSeek 账户余额不足。"
        case .rateLimited: "请求较多，请稍后再试。"
        case .invalidResponse: "没有识别到可记录的食物，请换一种说法。"
        case let .responseIncomplete(reason):
            reason == "max_output_tokens"
                ? "模型输出被截断，请重新识别。"
                : "模型没有完成识别，请重新识别。"
        case let .responseFailed(message):
            message.map { "模型识别失败：\($0)" } ?? "模型识别失败，请重试。"
        case .modelUnavailable: "当前识别模型暂时不可用。"
        case .timedOut: "识别等待时间过长，请重试。"
        case .credentialStorage: "手表未能安全保存 API Key。"
        case let .server(code): "DeepSeek 服务暂时不可用（\(code)）。"
        case let .network(message): "网络请求失败：\(message)"
        }
    }
}

struct WatchDeepSeekService {
    static let model = "deepseek-v4-flash"
    private let endpoint = URL(string: "https://api.deepseek.com/responses")!

    func analyze(transcript: String) async throws -> WatchVoiceAnalysisResult {
        guard let apiKey = WatchCredentialStore.read(), !apiKey.isEmpty else {
            throw WatchVoiceError.missingKey
        }
        let body = try requestBody(transcript: transcript)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = body

        let operationID = UUID()
        for attempt in 1...2 {
            let startedAt = Date.now
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let duration = Date.now.timeIntervalSince(startedAt)
                guard let http = response as? HTTPURLResponse else {
                    let error = WatchVoiceError.invalidResponse
                    sendLog(operationID: operationID, attempt: attempt, request: request, data: data, response: nil, duration: duration, error: error)
                    throw error
                }
                guard (200..<300).contains(http.statusCode) else {
                    let error = Self.error(for: http.statusCode)
                    sendLog(operationID: operationID, attempt: attempt, request: request, data: data, response: http, duration: duration, error: error)
                    if attempt == 1, Self.shouldRetry(http.statusCode) {
                        try await Task.sleep(for: .seconds(1.5))
                        continue
                    }
                    throw error
                }

                if let error = Self.responseError(from: data) {
                    sendLog(operationID: operationID, attempt: attempt, request: request, data: data, response: http, duration: duration, error: error)
                    throw error
                }

                do {
                    let result = try Self.parse(data: data, transcript: transcript)
                    sendLog(operationID: operationID, attempt: attempt, request: request, data: data, response: http, duration: duration, error: nil)
                    return result
                } catch {
                    let mapped = error as? WatchVoiceError ?? .invalidResponse
                    sendLog(operationID: operationID, attempt: attempt, request: request, data: data, response: http, duration: duration, error: mapped)
                    throw mapped
                }
            } catch let error as WatchVoiceError {
                throw error
            } catch {
                let duration = Date.now.timeIntervalSince(startedAt)
                let mapped: WatchVoiceError = (error as? URLError)?.code == .timedOut
                    ? .timedOut
                    : .network(error.localizedDescription)
                sendLog(operationID: operationID, attempt: attempt, request: request, data: nil, response: nil, duration: duration, error: mapped)
                if attempt == 1, Self.isRetryable(error) {
                    try await Task.sleep(for: .seconds(1.5))
                    continue
                }
                throw mapped
            }
        }
        throw WatchVoiceError.invalidResponse
    }

    private func requestBody(transcript: String) throws -> Data {
        let prompt = """
        你是饮食热量记录助手。根据用户口述，独立识别其中的食物和饮品，不要匹配任何已有食材库。
        给整份饮食生成一个简短明确的 overallName，并为每个可食用项目估算实际数量、单位和千卡。调味料只有在明显影响热量时才单列；水、冰块等零热量项目可以返回但热量必须为 0。
        输出必须符合给定 JSON schema。用户口述：\(transcript)
        """
        let body: [String: Any] = [
            "model": Self.model,
            "reasoning": ["effort": "none"],
            "max_output_tokens": 10_000,
            "input": prompt,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "watch_food_voice_analysis",
                    "schema": Self.schema
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["overallName", "items", "assumptions"],
        "properties": [
            "overallName": ["type": "string"],
            "items": [
                "type": "array",
                "minItems": 1,
                "maxItems": 20,
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "estimatedAmount", "unit", "calories"],
                    "properties": [
                        "name": ["type": "string"],
                        "estimatedAmount": ["type": "number", "exclusiveMinimum": 0],
                        "unit": ["type": "string"],
                        "calories": ["type": "number", "minimum": 0]
                    ]
                ]
            ],
            "assumptions": [
                "type": "array",
                "maxItems": 5,
                "items": ["type": "string"]
            ]
        ]
    ]

    private struct ResponseBody: Decodable {
        struct Item: Decodable {
            let name: String
            let estimatedAmount: Double
            let unit: String
            let calories: Double
        }

        let overallName: String
        let items: [Item]
        let assumptions: [String]
    }

    private static func parse(data: Data, transcript: String) throws -> WatchVoiceAnalysisResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let output = firstOutputText(in: object),
              let json = output.data(using: .utf8),
              let body = try? JSONDecoder().decode(ResponseBody.self, from: json) else {
            throw WatchVoiceError.invalidResponse
        }
        let items = body.items.compactMap { item -> WatchVoiceAnalysisItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  item.estimatedAmount.isFinite,
                  item.estimatedAmount > 0,
                  item.calories.isFinite,
                  item.calories >= 0 else { return nil }
            return WatchVoiceAnalysisItem(
                id: UUID().uuidString,
                name: name,
                estimatedAmount: item.estimatedAmount,
                unit: item.unit,
                calories: item.calories
            )
        }
        guard !items.isEmpty else { throw WatchVoiceError.invalidResponse }
        return WatchVoiceAnalysisResult(
            transcript: transcript,
            overallName: body.overallName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? transcript : body.overallName,
            totalCalories: items.reduce(0) { $0 + $1.calories },
            items: items,
            assumptions: body.assumptions
        )
    }

    private static func firstOutputText(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "output_text",
               let text = dictionary["text"] as? String { return text }
            for child in dictionary.values {
                if let found = firstOutputText(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstOutputText(in: child) { return found }
            }
        }
        return nil
    }

    private static func responseError(from data: Data) -> WatchVoiceError? {
        let metadata = DeepSeekResponseMetadata.read(from: data)
        switch metadata.status {
        case "incomplete": return .responseIncomplete(metadata.incompleteReason)
        case "failed": return .responseFailed(metadata.errorMessage)
        default: return nil
        }
    }

    private func sendLog(
        operationID: UUID,
        attempt: Int,
        request: URLRequest,
        data: Data?,
        response: HTTPURLResponse?,
        duration: TimeInterval,
        error: WatchVoiceError?
    ) {
        let usage = Self.usage(from: data)
        let metadata = DeepSeekResponseMetadata.read(from: data)
        let requestID = response?.value(forHTTPHeaderField: "x-request-id")
            ?? response?.value(forHTTPHeaderField: "request-id")
            ?? response?.value(forHTTPHeaderField: "x-ds-request-id")
        let payload = WatchAPILogPayload(
            id: UUID(),
            operationID: operationID,
            createdAt: .now,
            model: Self.model,
            inputTokens: usage.input,
            outputTokens: usage.output,
            httpStatus: response?.statusCode,
            duration: duration,
            requestBytes: request.httpBody?.count ?? 0,
            responseBytes: data?.count ?? 0,
            requestJSON: request.httpBody.map(Self.prettyJSON) ?? "{}",
            responseJSON: data.map(Self.prettyJSON),
            errorMessage: error?.localizedDescription,
            attempt: attempt,
            requestID: requestID,
            responseStatus: metadata.status,
            incompleteReason: metadata.incompleteReason
        )
        Task { @MainActor in WatchSessionManager.shared.sendAPILog(payload) }
    }

    private static func usage(from data: Data?) -> (input: Int?, output: Int?) {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["usage"] as? [String: Any] else { return (nil, nil) }
        return (usage["input_tokens"] as? Int, usage["output_tokens"] as? Int)
    }

    private static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let output = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return String(decoding: data, as: UTF8.self)
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func error(for status: Int) -> WatchVoiceError {
        switch status {
        case 401: .invalidKey
        case 402: .insufficientBalance
        case 404: .modelUnavailable
        case 429: .rateLimited
        default: .server(status)
        }
    }

    private static func shouldRetry(_ status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let value = error as? URLError else { return false }
        return [.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet].contains(value.code)
    }
}
