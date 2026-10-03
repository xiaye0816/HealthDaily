import Foundation
import SwiftData
import WatchConnectivity

struct PhoneWatchSyncSource: Hashable {
    let calorieSource: WidgetSnapshotSource
    let presets: [WatchFoodPresetSnapshot]

    init(
        calorieSource: WidgetSnapshotSource,
        presets: [FoodPreset],
        foodLogs: [FoodLogEntry],
        referenceDate: Date = .now
    ) {
        self.calorieSource = calorieSource
        let scores = FoodPresetOrdering.recommendationScores(
            presets: presets,
            foodLogs: foodLogs,
            referenceDate: referenceDate
        )
        self.presets = FoodPresetOrdering.sortedByRecentUse(presets).map { preset in
            WatchFoodPresetSnapshot(
                id: preset.id,
                name: preset.name,
                baseQuantity: preset.baseQuantity,
                unit: preset.unit.rawValue,
                calories: preset.calories,
                activityAt: max(preset.createdAt, preset.lastUsedAt ?? .distantPast),
                recommendationScores: Dictionary(uniqueKeysWithValues: MealType.allCases.map { meal in
                    (meal.rawValue, scores[preset.id]?[meal] ?? 0)
                })
            )
        }
    }
}

@MainActor
final class PhoneWatchConnectivityCoordinator: NSObject, ObservableObject {
    static let shared = PhoneWatchConnectivityCoordinator()

    private struct ProcessedOperation: Codable {
        let id: UUID
        let processedAt: Date
    }

    private static let processedOperationsKey = "watch.processed-food-operations.v1"
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var modelContext: ModelContext?
    private var lastCalorieSnapshot: WidgetCalorieSnapshot?
    private var lastPresets: [WatchFoodPresetSnapshot] = []
    private var pendingCommands: [WatchFoodRecordCommand] = []
    private var hasPendingCredentialChange = false

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        NotificationCenter.default.addObserver(
            forName: .deepSeekCredentialDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hasPendingCredentialChange = true
                self?.publishLatestContext()
                self?.pushCredentialChangeIfNeeded()
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        let queued = pendingCommands
        pendingCommands.removeAll()
        for command in queued {
            _ = process(command)
        }
    }

    func publish(_ source: PhoneWatchSyncSource) {
        lastCalorieSnapshot = source.calorieSource.snapshot
        lastPresets = source.presets
        publishLatestContext()
    }

    private func publishLatestContext() {
        guard let session, session.activationState == .activated else { return }
        let credential = WatchCredentialState(
            revision: DeepSeekCredentialStore.revision,
            isConfigured: DeepSeekCredentialStore.hasKey
        )
        var context: [String: Any] = [:]
        if let credentialData = try? JSONEncoder().encode(credential) {
            context[WatchSyncConstants.credentialStateKey] = credentialData
        }
        if let dashboard = latestDashboard(credential: credential),
           let dashboardData = try? JSONEncoder().encode(dashboard) {
            context[WatchSyncConstants.dashboardKey] = dashboardData
            sendDashboardImmediately(dashboard, through: session)
        }
        try? session.updateApplicationContext(context)
    }

    private func pushCredentialChangeIfNeeded() {
        guard hasPendingCredentialChange,
              let session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }

        let revision = DeepSeekCredentialStore.revision
        guard let data = try? credentialEnvelopeData() else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let response = try? JSONDecoder().decode(WatchWireEnvelope.self, from: reply),
                          let receipt = try? response.decode(WatchFoodRecordReceipt.self),
                          receipt.succeeded else {
                        self?.queueCredentialTransfer(data, revision: revision)
                        return
                    }
                    self?.hasPendingCredentialChange = false
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.queueCredentialTransfer(data, revision: revision) }
            })
        } else {
            queueCredentialTransfer(data, revision: revision)
        }
    }

    private func queueCredentialTransfer(_ data: Data, revision: Int) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued),
                  envelope.kind == .credential,
                  let payload = try? envelope.decode(WatchCredentialPayload.self) else { return false }
            return payload.revision == revision
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
        hasPendingCredentialChange = false
    }

    private func credentialEnvelopeData() throws -> Data {
        let payload = WatchCredentialPayload(
            apiKey: try DeepSeekCredentialStore.read(),
            revision: DeepSeekCredentialStore.revision
        )
        let envelope = try WatchWireEnvelope(kind: .credential, payload: payload)
        return try JSONEncoder().encode(envelope)
    }

    private func latestDashboard(credential: WatchCredentialState? = nil) -> WatchDashboardSnapshot? {
        guard let lastCalorieSnapshot else { return nil }
        return WatchDashboardSnapshot(
            calorieSnapshot: lastCalorieSnapshot,
            presets: lastPresets,
            processedOperationIDs: processedOperationIDs(),
            credentialState: credential ?? WatchCredentialState(
                revision: DeepSeekCredentialStore.revision,
                isConfigured: DeepSeekCredentialStore.hasKey
            )
        )
    }

    private func sendDashboardImmediately(_ dashboard: WatchDashboardSnapshot, through session: WCSession) {
        guard session.isReachable,
              let envelope = try? WatchWireEnvelope(kind: .dashboard, payload: dashboard),
              let data = try? JSONEncoder().encode(envelope) else { return }
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    private func receive(_ data: Data, replyHandler: ((Data) -> Void)?) {
        do {
            let envelope = try JSONDecoder().decode(WatchWireEnvelope.self, from: data)
            switch envelope.kind {
            case .dashboardRequest:
                _ = try envelope.decode(WatchDashboardRequest.self)
                if let dashboard = latestDashboard() {
                    if let replyHandler {
                        let response = try WatchWireEnvelope(kind: .dashboard, payload: dashboard)
                        replyHandler(try JSONEncoder().encode(response))
                    } else {
                        publishLatestContext()
                    }
                } else if let replyHandler {
                    let response = try WatchWireEnvelope(
                        kind: .recordReceipt,
                        payload: WatchFoodRecordReceipt(
                            operationID: UUID(),
                            succeeded: false,
                            message: "iPhone 数据尚未准备好"
                        )
                    )
                    replyHandler(try JSONEncoder().encode(response))
                }
            case .dashboard:
                break
            case .credentialRequest:
                _ = try envelope.decode(WatchCredentialRequest.self)
                if let replyHandler {
                    replyHandler(try credentialEnvelopeData())
                } else {
                    hasPendingCredentialChange = true
                    pushCredentialChangeIfNeeded()
                }
            case .recordCommand:
                let command = try envelope.decode(WatchFoodRecordCommand.self)
                let receipt = process(command)
                if let replyHandler {
                    let response = try WatchWireEnvelope(kind: .recordReceipt, payload: receipt)
                    replyHandler(try JSONEncoder().encode(response))
                }
            case .apiLog:
                let payload = try envelope.decode(WatchAPILogPayload.self)
                Task { [weak self] in
                    await DeepSeekAPILogStore.shared.append(
                        DeepSeekAPILogRecord(
                            id: payload.id,
                            operationID: payload.operationID,
                            createdAt: payload.createdAt,
                            kind: .watchVoiceAnalysis,
                            attempt: payload.attempt,
                            model: payload.model,
                            inputTokens: payload.inputTokens,
                            outputTokens: payload.outputTokens,
                            httpStatus: payload.httpStatus,
                            duration: payload.duration,
                            requestBytes: payload.requestBytes,
                            responseBytes: payload.responseBytes,
                            requestID: payload.requestID,
                            requestJSON: payload.requestJSON,
                            responseJSON: payload.responseJSON,
                            errorMessage: payload.errorMessage,
                            imageThumbnailFilename: nil,
                            responseStatus: payload.responseStatus,
                            incompleteReason: payload.incompleteReason
                        ),
                        thumbnailData: nil
                    )
                    guard let receiptData = try? Self.apiLogReceiptData(logID: payload.id) else { return }
                    if let replyHandler {
                        replyHandler(receiptData)
                    } else {
                        await MainActor.run { self?.queueAPILogReceipt(receiptData, logID: payload.id) }
                    }
                }
            case .recordReceipt, .credential, .apiLogReceipt:
                break
            }
        } catch {
            if let replyHandler,
               let response = try? WatchWireEnvelope(
                kind: .recordReceipt,
                payload: WatchFoodRecordReceipt(operationID: UUID(), succeeded: false, message: error.localizedDescription)
               ),
               let encoded = try? JSONEncoder().encode(response) {
                replyHandler(encoded)
            }
        }
    }

    private static func apiLogReceiptData(logID: UUID) throws -> Data {
        let envelope = try WatchWireEnvelope(kind: .apiLogReceipt, payload: WatchAPILogReceipt(logID: logID))
        return try JSONEncoder().encode(envelope)
    }

    private func queueAPILogReceipt(_ data: Data, logID: UUID) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued),
                  envelope.kind == .apiLogReceipt,
                  let receipt = try? envelope.decode(WatchAPILogReceipt.self) else { return false }
            return receipt.logID == logID
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
    }

    private func process(_ command: WatchFoodRecordCommand) -> WatchFoodRecordReceipt {
        if processedOperationIDs().contains(command.id) {
            return WatchFoodRecordReceipt(operationID: command.id, succeeded: true, message: nil)
        }
        guard let modelContext else {
            pendingCommands.append(command)
            return WatchFoodRecordReceipt(operationID: command.id, succeeded: false, message: "iPhone App 尚未准备好，请稍后重试")
        }
        guard let meal = MealType(rawValue: command.mealRaw), !command.items.isEmpty, command.items.count <= 30 else {
            return WatchFoodRecordReceipt(operationID: command.id, succeeded: false, message: "饮食记录内容无效")
        }

        do {
            let allPresets = try modelContext.fetch(FetchDescriptor<FoodPreset>())
            let presetByID = Dictionary(uniqueKeysWithValues: allPresets.map { ($0.id, $0) })
            let usedAt = Date.now
            var inserted = 0
            var insertedCalories = 0.0

            for item in command.items {
                switch command.source {
                case .library:
                    guard let presetID = item.presetID,
                          let preset = presetByID[presetID],
                          item.servings.isFinite,
                          item.servings >= 0.25,
                          item.servings <= 50 else { continue }
                    modelContext.insert(FoodLogEntry(
                        date: command.createdAt,
                        meal: meal,
                        presetID: preset.id,
                        name: preset.name,
                        quantity: preset.baseQuantity * item.servings,
                        unit: preset.unit.rawValue,
                        calories: max(0, preset.calories * item.servings)
                    ))
                    insertedCalories += max(0, preset.calories * item.servings)
                    preset.lastUsedAt = usedAt
                    inserted += 1
                case .voice:
                    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty,
                          item.quantity.isFinite,
                          item.quantity > 0,
                          item.calories.isFinite,
                          item.calories >= 0,
                          item.calories <= 20_000 else { continue }
                    modelContext.insert(FoodLogEntry(
                        date: command.createdAt,
                        meal: meal,
                        presetID: nil,
                        name: name,
                        quantity: item.quantity,
                        unit: item.unit,
                        calories: item.calories
                    ))
                    insertedCalories += item.calories
                    inserted += 1
                }
            }

            guard inserted > 0 else {
                modelContext.rollback()
                return WatchFoodRecordReceipt(operationID: command.id, succeeded: false, message: "没有可记录的食物")
            }
            try modelContext.save()
            rememberProcessed(command.id)
            applyCommittedFoodCalories(insertedCalories, at: command.createdAt)
            publishLatestContext()
            return WatchFoodRecordReceipt(operationID: command.id, succeeded: true, message: nil)
        } catch {
            modelContext.rollback()
            return WatchFoodRecordReceipt(operationID: command.id, succeeded: false, message: "iPhone 保存失败，请稍后重试")
        }
    }

    private func applyCommittedFoodCalories(_ calories: Double, at date: Date) {
        guard calories > 0, let snapshot = lastCalorieSnapshot else { return }
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        var applied = false
        let updatedDays = snapshot.days.map { day in
            guard !applied, calendar.isDate(day.date, inSameDayAs: targetDay) else { return day }
            applied = true
            return WidgetCalorieDay(
                date: day.date,
                baseBudget: day.baseBudget,
                exercise: day.exercise,
                consumed: day.consumed + calories,
                targetDeficit: day.targetDeficit,
                currentDeficit: day.currentDeficit.map { $0 - calories },
                forecastDeficit: day.forecastDeficit.map { $0 - calories },
                actualRestingExpenditure: day.actualRestingExpenditure,
                actualActiveExpenditure: day.actualActiveExpenditure,
                estimatedExpenditure: day.estimatedExpenditure
            )
        }
        guard applied else { return }
        lastCalorieSnapshot = WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: snapshot.isOnboarded,
            fallbackDailyBudget: snapshot.fallbackDailyBudget,
            days: updatedDays
        )
    }

    private func processedOperationIDs(now: Date = .now) -> [UUID] {
        processedOperations(now: now).map(\.id)
    }

    private func processedOperations(now: Date = .now) -> [ProcessedOperation] {
        guard let data = UserDefaults.standard.data(forKey: Self.processedOperationsKey),
              let values = try? JSONDecoder().decode([ProcessedOperation].self, from: data) else { return [] }
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        return Array(values.filter { $0.processedAt >= cutoff }.suffix(500))
    }

    private func rememberProcessed(_ id: UUID) {
        var values = processedOperations().filter { $0.id != id }
        values.append(ProcessedOperation(id: id, processedAt: .now))
        if let data = try? JSONEncoder().encode(Array(values.suffix(500))) {
            UserDefaults.standard.set(data, forKey: Self.processedOperationsKey)
        }
    }
}

extension PhoneWatchConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.publishLatestContext()
            self.pushCredentialChangeIfNeeded()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.publishLatestContext()
            self.pushCredentialChangeIfNeeded()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            self.publishLatestContext()
            self.pushCredentialChangeIfNeeded()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.receive(messageData, replyHandler: nil) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        Task { @MainActor in self.receive(messageData, replyHandler: replyHandler) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["envelope"] as? Data else { return }
        Task { @MainActor in self.receive(data, replyHandler: nil) }
    }
}
