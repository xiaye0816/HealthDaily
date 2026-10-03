import Foundation
import Security
import WatchConnectivity
import WidgetKit

enum WatchCredentialStore {
    private static let service = "com.shaoguoqing.tiantianhealth.watch.deepseek"
    private static let account = "api-key"
    private static let revisionKey = "watch.deepseek.credential-revision"

    static var revision: Int { UserDefaults.standard.integer(forKey: revisionKey) }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, revision: Int) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let update = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if update != errSecSuccess {
            guard update == errSecItemNotFound,
                  SecItemAdd(lookup.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw WatchVoiceError.credentialStorage
            }
        }
        UserDefaults.standard.set(revision, forKey: revisionKey)
    }

    static func delete(revision: Int? = nil) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        if let revision {
            UserDefaults.standard.set(revision, forKey: revisionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: revisionKey)
        }
    }
}

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published private(set) var dashboard: WatchDashboardSnapshot?
    @Published private(set) var credentialState: WatchCredentialState?
    @Published private(set) var pendingCommands: [WatchFoodRecordCommand] = []
    @Published private(set) var pendingAPILogs: [WatchAPILogPayload] = []
    @Published private(set) var statusMessage: String?

    private static let dashboardCacheKey = "watch.dashboard-cache.v1"
    private static let pendingCommandsKey = "watch.pending-food-commands.v1"
    private static let pendingAPILogsKey = "watch.pending-api-logs.v1"
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var lastDashboardRequestAt: Date = .distantPast
    private var lastCredentialRequestAt: Date = .distantPast

    var credentialReady: Bool {
        WatchCredentialStore.read() != nil
    }

    private override init() {
        super.init()
        dashboard = Self.load(WatchDashboardSnapshot.self, key: Self.dashboardCacheKey)
        credentialState = dashboard?.credentialState
        pendingCommands = Self.load([WatchFoodRecordCommand].self, key: Self.pendingCommandsKey) ?? []
        pendingAPILogs = Self.load([WatchAPILogPayload].self, key: Self.pendingAPILogsKey) ?? []
        if let dashboard {
            updateComplications(using: dashboard)
        }
        session?.delegate = self
        session?.activate()
        reconcilePending()
    }

    @discardableResult
    func submit(_ command: WatchFoodRecordCommand) -> Bool {
        guard !pendingCommands.contains(where: { $0.id == command.id }) else { return false }
        pendingCommands.append(command)
        persistPending()
        statusMessage = "正在同步到 iPhone…"
        send(command)
        return true
    }

    func retryPending() {
        for command in pendingCommands { send(command) }
        for payload in pendingAPILogs { sendAPILogPayload(payload) }
    }

    func requestLatestDashboard(force: Bool = false) {
        guard let session, session.activationState == .activated else {
            self.session?.activate()
            return
        }

        apply(session.receivedApplicationContext)
        let now = Date.now
        guard force || now.timeIntervalSince(lastDashboardRequestAt) >= 2 else { return }
        lastDashboardRequestAt = now

        guard let envelope = try? WatchWireEnvelope(
            kind: .dashboardRequest,
            payload: WatchDashboardRequest(requestedAt: now)
        ), let data = try? JSONEncoder().encode(envelope) else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: { [weak self] reply in
                Task { @MainActor in self?.receiveDashboard(reply) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.queueDashboardRequest(data) }
            })
        } else {
            queueDashboardRequest(data)
        }
    }

    func requestCredentialIfNeeded(force: Bool = false) {
        guard credentialState?.isConfigured != false else { return }
        let hasLocalKey = WatchCredentialStore.read() != nil
        let revisionMismatch = credentialState.map { $0.revision != WatchCredentialStore.revision } ?? false
        guard force || !hasLocalKey || revisionMismatch else { return }
        guard let session, session.activationState == .activated else {
            self.session?.activate()
            return
        }

        let now = Date.now
        guard force || now.timeIntervalSince(lastCredentialRequestAt) >= 5 else { return }
        lastCredentialRequestAt = now

        let request = WatchCredentialRequest(
            requestedAt: now,
            localRevision: WatchCredentialStore.revision,
            hasLocalKey: hasLocalKey
        )
        guard let envelope = try? WatchWireEnvelope(kind: .credentialRequest, payload: request),
              let data = try? JSONEncoder().encode(envelope) else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: { [weak self] reply in
                Task { @MainActor in self?.receiveCredentialReply(reply) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.queueCredentialRequest(data) }
            })
        } else {
            queueCredentialRequest(data)
        }
    }

    func sendAPILog(_ payload: WatchAPILogPayload) {
        guard !pendingAPILogs.contains(where: { $0.id == payload.id }) else { return }
        pendingAPILogs.append(payload)
        persistPendingAPILogs()
        sendAPILogPayload(payload)
    }

    private func sendAPILogPayload(_ payload: WatchAPILogPayload) {
        guard let envelope = try? WatchWireEnvelope(kind: .apiLog, payload: payload),
              let data = try? JSONEncoder().encode(envelope) else { return }
        guard let session, session.activationState == .activated else {
            self.session?.activate()
            return
        }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: { [weak self] reply in
                Task { @MainActor in self?.receiveAPILogReceipt(reply) }
            }) { [weak self] _ in
                Task { @MainActor in self?.queueAPILogTransfer(data, logID: payload.id) }
            }
        } else {
            queueAPILogTransfer(data, logID: payload.id)
        }
    }

    private func send(_ command: WatchFoodRecordCommand) {
        guard let session,
              let envelope = try? WatchWireEnvelope(kind: .recordCommand, payload: command),
              let data = try? JSONEncoder().encode(envelope) else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: { [weak self] data in
                Task { @MainActor in self?.receiveReceipt(data) }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in self?.queueTransfer(data, operationID: command.id) }
            })
        } else {
            queueTransfer(data, operationID: command.id)
        }
    }

    private func queueTransfer(_ data: Data, operationID: UUID) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued),
                  envelope.kind == .recordCommand,
                  let command = try? envelope.decode(WatchFoodRecordCommand.self) else { return false }
            return command.id == operationID
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
        statusMessage = "已保存在手表，连接 iPhone 后自动同步"
    }

    private func queueDashboardRequest(_ data: Data) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued) else { return false }
            return envelope.kind == .dashboardRequest
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
    }

    private func queueCredentialRequest(_ data: Data) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued) else { return false }
            return envelope.kind == .credentialRequest
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
    }

    private func queueAPILogTransfer(_ data: Data, logID: UUID) {
        guard let session else { return }
        let alreadyQueued = session.outstandingUserInfoTransfers.contains { transfer in
            guard let queued = transfer.userInfo["envelope"] as? Data,
                  let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: queued),
                  envelope.kind == .apiLog,
                  let payload = try? envelope.decode(WatchAPILogPayload.self) else { return false }
            return payload.id == logID
        }
        if !alreadyQueued { session.transferUserInfo(["envelope": data]) }
    }

    private func receiveDashboard(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: data),
              envelope.kind == .dashboard,
              let value = try? envelope.decode(WatchDashboardSnapshot.self) else { return }
        applyDashboard(value)
    }

    private func receiveCredentialReply(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: data),
              envelope.kind == .credential else { return }
        _ = receiveCredential(envelope)
    }

    private func receiveReceipt(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: data),
              envelope.kind == .recordReceipt,
              let receipt = try? envelope.decode(WatchFoodRecordReceipt.self) else { return }
        if receipt.succeeded {
            complete(receipt.operationID)
        } else {
            statusMessage = receipt.message ?? "同步失败，请稍后重试"
        }
    }

    private func receiveAPILogReceipt(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: data),
              envelope.kind == .apiLogReceipt,
              let receipt = try? envelope.decode(WatchAPILogReceipt.self) else { return }
        pendingAPILogs.removeAll { $0.id == receipt.logID }
        persistPendingAPILogs()
    }

    private func complete(_ operationID: UUID) {
        pendingCommands.removeAll { $0.id == operationID }
        persistPending()
        statusMessage = "已记录"
    }

    private func apply(_ context: [String: Any]) {
        if let stateData = context[WatchSyncConstants.credentialStateKey] as? Data,
           let state = try? JSONDecoder().decode(WatchCredentialState.self, from: stateData) {
            credentialState = state
        }
        if let data = context[WatchSyncConstants.dashboardKey] as? Data,
           let value = try? JSONDecoder().decode(WatchDashboardSnapshot.self, from: data),
           value.schemaVersion == WatchSyncConstants.schemaVersion {
            applyDashboard(value)
        }
        requestCredentialIfNeeded()
    }

    private func applyDashboard(_ value: WatchDashboardSnapshot) {
        guard value.schemaVersion == WatchSyncConstants.schemaVersion,
              value.generatedAt >= (dashboard?.generatedAt ?? .distantPast) else { return }
        dashboard = value
        credentialState = value.credentialState
        Self.save(value, key: Self.dashboardCacheKey)
        updateComplications(using: value)
        reconcilePending()
    }

    private func updateComplications(using dashboard: WatchDashboardSnapshot) {
        guard WatchComplicationStore.save(WatchComplicationSnapshot(dashboard: dashboard)) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
    }

    private func reconcilePending() {
        guard let processed = dashboard?.processedOperationIDs else { return }
        let before = pendingCommands.count
        pendingCommands.removeAll { processed.contains($0.id) }
        if pendingCommands.count != before {
            persistPending()
            statusMessage = "已记录"
        }
    }

    private func receiveCredential(_ envelope: WatchWireEnvelope) -> Data? {
        let receipt: WatchFoodRecordReceipt
        do {
            let payload = try envelope.decode(WatchCredentialPayload.self)
            if payload.revision >= WatchCredentialStore.revision {
                if let apiKey = payload.apiKey, !apiKey.isEmpty {
                    try WatchCredentialStore.save(apiKey, revision: payload.revision)
                    credentialState = WatchCredentialState(revision: payload.revision, isConfigured: true)
                } else {
                    WatchCredentialStore.delete(revision: payload.revision)
                    credentialState = WatchCredentialState(revision: payload.revision, isConfigured: false)
                }
            }
            receipt = WatchFoodRecordReceipt(operationID: UUID(), succeeded: true, message: nil)
        } catch {
            receipt = WatchFoodRecordReceipt(operationID: UUID(), succeeded: false, message: error.localizedDescription)
        }
        guard let response = try? WatchWireEnvelope(kind: .recordReceipt, payload: receipt) else { return nil }
        return try? JSONEncoder().encode(response)
    }

    private func persistPending() {
        Self.save(pendingCommands, key: Self.pendingCommandsKey)
    }

    private func persistPendingAPILogs() {
        Self.save(pendingAPILogs, key: Self.pendingAPILogsKey)
    }

    private static func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.apply(session.receivedApplicationContext)
            self.retryPending()
            self.requestLatestDashboard(force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            self.apply(session.receivedApplicationContext)
            self.retryPending()
            self.requestLatestDashboard(force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["envelope"] as? Data,
              let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: data) else { return }
        Task { @MainActor in
            switch envelope.kind {
            case .credential:
                _ = self.receiveCredential(envelope)
            case .dashboard:
                self.receiveDashboard(data)
            case .apiLogReceipt:
                self.receiveAPILogReceipt(data)
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: messageData) else { return }
        Task { @MainActor in
            switch envelope.kind {
            case .dashboard:
                self.receiveDashboard(messageData)
            case .credential:
                _ = self.receiveCredential(envelope)
            case .apiLogReceipt:
                self.receiveAPILogReceipt(messageData)
            default:
                break
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        guard let envelope = try? JSONDecoder().decode(WatchWireEnvelope.self, from: messageData) else { return }
        Task { @MainActor in
            switch envelope.kind {
            case .credential:
                if let reply = self.receiveCredential(envelope) { replyHandler(reply) }
            case .dashboard:
                self.receiveDashboard(messageData)
            case .apiLogReceipt:
                self.receiveAPILogReceipt(messageData)
            default:
                break
            }
        }
    }
}
