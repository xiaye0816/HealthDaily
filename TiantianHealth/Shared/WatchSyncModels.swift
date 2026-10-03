import Foundation

enum WatchSyncConstants {
    static let schemaVersion = 1
    static let dashboardKey = "watch.dashboard"
    static let credentialStateKey = "watch.credential-state"
}

struct WatchFoodPresetSnapshot: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let baseQuantity: Double
    let unit: String
    let calories: Double
    let activityAt: Date
    let recommendationScores: [String: Double]?

    init(
        id: UUID,
        name: String,
        baseQuantity: Double,
        unit: String,
        calories: Double,
        activityAt: Date,
        recommendationScores: [String: Double]? = nil
    ) {
        self.id = id
        self.name = name
        self.baseQuantity = baseQuantity
        self.unit = unit
        self.calories = calories
        self.activityAt = activityAt
        self.recommendationScores = recommendationScores
    }
}

struct WatchCredentialState: Codable, Hashable {
    let revision: Int
    let isConfigured: Bool
}

struct WatchDashboardSnapshot: Codable, Hashable {
    let schemaVersion: Int
    let generatedAt: Date
    let calorieSnapshot: WidgetCalorieSnapshot
    let presets: [WatchFoodPresetSnapshot]
    let processedOperationIDs: [UUID]
    let credentialState: WatchCredentialState

    init(
        generatedAt: Date = .now,
        calorieSnapshot: WidgetCalorieSnapshot,
        presets: [WatchFoodPresetSnapshot],
        processedOperationIDs: [UUID],
        credentialState: WatchCredentialState
    ) {
        schemaVersion = WatchSyncConstants.schemaVersion
        self.generatedAt = generatedAt
        self.calorieSnapshot = calorieSnapshot
        self.presets = presets
        self.processedOperationIDs = processedOperationIDs
        self.credentialState = credentialState
    }

    var targetDeviationBeforeToday: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return calorieSnapshot.days.reduce(0) { result, day in
            guard calendar.startOfDay(for: day.date) < today,
                  let achieved = day.currentDeficit,
                  let target = day.targetDeficit else { return result }
            return result + achieved - target
        }
    }
}

enum WatchFoodRecordSource: String, Codable, Hashable {
    case library
    case voice
}

struct WatchFoodRecordItem: Codable, Hashable, Identifiable {
    let id: UUID
    let presetID: UUID?
    let name: String
    let quantity: Double
    let unit: String
    let calories: Double
    let servings: Double

    init(
        id: UUID = UUID(),
        presetID: UUID?,
        name: String,
        quantity: Double,
        unit: String,
        calories: Double,
        servings: Double = 1
    ) {
        self.id = id
        self.presetID = presetID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.calories = calories
        self.servings = servings
    }
}

struct WatchFoodRecordCommand: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    let mealRaw: String
    let source: WatchFoodRecordSource
    let items: [WatchFoodRecordItem]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        mealRaw: String,
        source: WatchFoodRecordSource,
        items: [WatchFoodRecordItem]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mealRaw = mealRaw
        self.source = source
        self.items = items
    }
}

struct WatchFoodRecordReceipt: Codable, Hashable {
    let operationID: UUID
    let succeeded: Bool
    let message: String?
}

struct WatchVoiceAnalysisItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let estimatedAmount: Double
    let unit: String
    let calories: Double
}

struct WatchVoiceAnalysisResult: Codable, Hashable {
    let transcript: String
    let overallName: String
    let totalCalories: Double
    let items: [WatchVoiceAnalysisItem]
    let assumptions: [String]

    init(
        transcript: String,
        overallName: String,
        totalCalories: Double,
        items: [WatchVoiceAnalysisItem],
        assumptions: [String]
    ) {
        self.transcript = transcript
        self.overallName = overallName
        self.totalCalories = totalCalories
        self.items = items
        self.assumptions = assumptions
    }

    private enum CodingKeys: String, CodingKey {
        case transcript, overallName, totalCalories, items, assumptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcript = try container.decode(String.self, forKey: .transcript)
        overallName = try container.decodeIfPresent(String.self, forKey: .overallName) ?? transcript
        totalCalories = try container.decode(Double.self, forKey: .totalCalories)
        items = try container.decode([WatchVoiceAnalysisItem].self, forKey: .items)
        assumptions = try container.decode([String].self, forKey: .assumptions)
    }
}

enum WatchVoiceRecordGrouping: String, CaseIterable, Codable, Hashable, Identifiable {
    case whole = "整份记录"
    case separate = "分项记录"

    var id: String { rawValue }
}

extension WatchVoiceAnalysisResult {
    func recordItems(selectedIDs: Set<String>, grouping: WatchVoiceRecordGrouping) -> [WatchFoodRecordItem] {
        let selected = items.filter { selectedIDs.contains($0.id) }
        switch grouping {
        case .whole:
            let fallback = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferred = overallName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return [] }
            return [WatchFoodRecordItem(
                presetID: nil,
                name: preferred.isEmpty ? fallback : preferred,
                quantity: 1,
                unit: "份",
                calories: selected.reduce(0) { $0 + $1.calories }
            )]
        case .separate:
            return selected.map {
                WatchFoodRecordItem(
                    presetID: nil,
                    name: $0.name,
                    quantity: $0.estimatedAmount,
                    unit: $0.unit,
                    calories: $0.calories
                )
            }
        }
    }
}

enum WatchWireKind: String, Codable {
    case dashboardRequest
    case dashboard
    case credentialRequest
    case recordCommand
    case recordReceipt
    case credential
    case apiLog
    case apiLogReceipt
}

struct WatchCredentialRequest: Codable {
    let requestedAt: Date
    let localRevision: Int
    let hasLocalKey: Bool

    init(
        requestedAt: Date = .now,
        localRevision: Int,
        hasLocalKey: Bool
    ) {
        self.requestedAt = requestedAt
        self.localRevision = localRevision
        self.hasLocalKey = hasLocalKey
    }
}

struct WatchDashboardRequest: Codable {
    let requestedAt: Date

    init(requestedAt: Date = .now) {
        self.requestedAt = requestedAt
    }
}

struct WatchWireEnvelope: Codable {
    let kind: WatchWireKind
    let payload: Data

    init<Payload: Encodable>(kind: WatchWireKind, payload: Payload) throws {
        self.kind = kind
        self.payload = try JSONEncoder().encode(payload)
    }

    func decode<Payload: Decodable>(_ type: Payload.Type) throws -> Payload {
        try JSONDecoder().decode(type, from: payload)
    }
}

struct WatchCredentialPayload: Codable {
    let apiKey: String?
    let revision: Int
}

struct WatchAPILogPayload: Codable {
    let id: UUID
    let operationID: UUID
    let createdAt: Date
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
    let httpStatus: Int?
    let duration: TimeInterval
    let requestBytes: Int
    let responseBytes: Int
    let requestJSON: String
    let responseJSON: String?
    let errorMessage: String?
    let attempt: Int
    let requestID: String?
    let responseStatus: String?
    let incompleteReason: String?

    init(
        id: UUID,
        operationID: UUID,
        createdAt: Date,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        httpStatus: Int?,
        duration: TimeInterval,
        requestBytes: Int,
        responseBytes: Int,
        requestJSON: String,
        responseJSON: String?,
        errorMessage: String?,
        attempt: Int,
        requestID: String?,
        responseStatus: String? = nil,
        incompleteReason: String? = nil
    ) {
        self.id = id
        self.operationID = operationID
        self.createdAt = createdAt
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.httpStatus = httpStatus
        self.duration = duration
        self.requestBytes = requestBytes
        self.responseBytes = responseBytes
        self.requestJSON = requestJSON
        self.responseJSON = responseJSON
        self.errorMessage = errorMessage
        self.attempt = attempt
        self.requestID = requestID
        self.responseStatus = responseStatus
        self.incompleteReason = incompleteReason
    }

    private enum CodingKeys: String, CodingKey {
        case id, operationID, createdAt, model, inputTokens, outputTokens, httpStatus
        case duration, requestBytes, responseBytes, requestJSON, responseJSON, errorMessage
        case attempt, requestID, responseStatus, incompleteReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        operationID = try container.decode(UUID.self, forKey: .operationID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        model = try container.decode(String.self, forKey: .model)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        httpStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        requestBytes = try container.decode(Int.self, forKey: .requestBytes)
        responseBytes = try container.decode(Int.self, forKey: .responseBytes)
        requestJSON = try container.decode(String.self, forKey: .requestJSON)
        responseJSON = try container.decodeIfPresent(String.self, forKey: .responseJSON)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        attempt = try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 1
        requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
        responseStatus = try container.decodeIfPresent(String.self, forKey: .responseStatus)
        incompleteReason = try container.decodeIfPresent(String.self, forKey: .incompleteReason)
    }
}

struct DeepSeekResponseMetadata: Equatable {
    let status: String?
    let incompleteReason: String?
    let errorMessage: String?

    static func read(from data: Data?) -> DeepSeekResponseMetadata {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DeepSeekResponseMetadata(status: nil, incompleteReason: nil, errorMessage: nil)
        }
        let incomplete = object["incomplete_details"] as? [String: Any]
        let error = object["error"] as? [String: Any]
        return DeepSeekResponseMetadata(
            status: object["status"] as? String,
            incompleteReason: incomplete?["reason"] as? String,
            errorMessage: error?["message"] as? String
        )
    }
}

struct WatchAPILogReceipt: Codable {
    let logID: UUID
}
