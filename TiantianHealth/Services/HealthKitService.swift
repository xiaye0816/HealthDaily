import Foundation
import HealthKit

struct HealthEnergySnapshot: Equatable {
    let resting: Double?
    let active: Double?
    let updatedAt: Date

    var total: Double? {
        guard resting != nil || active != nil else { return nil }
        return (resting ?? 0) + (active ?? 0)
    }
}

struct HealthDailyEnergy: Equatable {
    let date: Date
    let resting: Double?
    let active: Double?
}

struct HealthWeightSample: Identifiable, Equatable {
    let id: UUID
    let measuredAt: Date
    let weightKG: Double
    let sourceName: String
    let syncIdentifier: String?
}

@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "healthKitEnabled")
    @Published private(set) var todayEnergy: HealthEnergySnapshot?
    @Published private(set) var dailyEnergy: [HealthDailyEnergy] = []
    @Published private(set) var healthWeights: [HealthWeightSample] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var activeType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var restingType: HKQuantityType { HKQuantityType(.basalEnergyBurned) }

    func connect() async -> Bool {
        guard isAvailable else {
            lastErrorMessage = "此设备不支持 Apple 健康"
            return false
        }
        do {
            try await store.requestAuthorization(
                toShare: [bodyMassType],
                read: [bodyMassType, activeType, restingType]
            )
            isEnabled = true
            UserDefaults.standard.set(true, forKey: "healthKitEnabled")
            startForegroundObservers()
            await refreshAll()
            return true
        } catch {
            lastErrorMessage = readableMessage(for: error)
            return false
        }
    }

    func disconnect() {
        observers.forEach(store.stop)
        observers.removeAll()
        isEnabled = false
        todayEnergy = nil
        dailyEnergy = []
        healthWeights = []
        UserDefaults.standard.set(false, forKey: "healthKitEnabled")
    }

    func restoreConnectionIfNeeded() {
        guard !isEnabled, isAvailable else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: "healthKitEnabled")
        startForegroundObservers()
    }

    func refreshAll() async {
        guard isEnabled, isAvailable, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let today = loadTodayEnergy()
            async let history = loadDailyEnergy(days: 28)
            async let weights = loadWeights()
            let values = try await (today, history, weights)
            todayEnergy = values.0
            dailyEnergy = values.1
            healthWeights = values.2
            lastErrorMessage = nil
            startForegroundObservers()
        } catch {
            lastErrorMessage = readableMessage(for: error)
        }
    }

    func refreshToday() async {
        guard isEnabled else { return }
        do {
            todayEnergy = try await loadTodayEnergy()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = readableMessage(for: error)
        }
    }

    func saveWeight(_ kilograms: Double, at date: Date, syncIdentifier: String, version: Int) async throws -> UUID {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: syncIdentifier,
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyWasUserEntered: true
            ]
        )
        try await save(sample)
        await refreshAll()
        return sample.uuid
    }

    func deleteWeight(syncIdentifier: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [syncIdentifier]
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: bodyMassType, predicate: predicate) { success, _, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
            }
        }
        await refreshAll()
    }

    private func loadTodayEnergy() async throws -> HealthEnergySnapshot {
        let start = Calendar.current.startOfDay(for: .now)
        async let resting = sum(type: restingType, start: start, end: .now)
        async let active = sum(type: activeType, start: start, end: .now)
        return try await HealthEnergySnapshot(resting: resting, active: active, updatedAt: .now)
    }

    private func loadDailyEnergy(days: Int) async throws -> [HealthDailyEnergy] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return try await withThrowingTaskGroup(of: HealthDailyEnergy.self) { group in
            for offset in 1...days {
                guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                group.addTask { [store, restingType, activeType] in
                    async let resting = Self.sum(store: store, type: restingType, start: start, end: end)
                    async let active = Self.sum(store: store, type: activeType, start: start, end: end)
                    return try await HealthDailyEnergy(date: start, resting: resting, active: active)
                }
            }
            var result: [HealthDailyEnergy] = []
            for try await day in group { result.append(day) }
            return result.sorted { $0.date < $1.date }
        }
    }

    private func loadWeights() async throws -> [HealthWeightSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    HealthWeightSample(
                        id: $0.uuid,
                        measuredAt: $0.startDate,
                        weightKG: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                        sourceName: $0.sourceRevision.source.name,
                        syncIdentifier: $0.metadata?[HKMetadataKeySyncIdentifier] as? String
                    )
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func sum(type: HKQuantityType, start: Date, end: Date) async throws -> Double? {
        try await Self.sum(store: store, type: type, start: start, end: end)
    }

    nonisolated private static func sum(store: HKHealthStore, type: HKQuantityType, start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()))
            }
            store.execute(query)
        }
    }

    nonisolated private static func isNoDataError(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == HKErrorDomain && value.code == HKError.Code.errorNoData.rawValue
    }

    private func readableMessage(for error: Error) -> String {
        if Self.isNoDataError(error) {
            return "Apple 健康中暂时没有这段时间的数据"
        }
        return error.localizedDescription
    }

    private func save(_ sample: HKSample) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
            }
        }
    }

    private func startForegroundObservers() {
        guard observers.isEmpty, isEnabled else { return }
        for type in [activeType, restingType, bodyMassType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    await self?.refreshAll()
                    completion()
                }
            }
            observers.append(query)
            store.execute(query)
        }
    }
}
