import Foundation
import XCTest
import SwiftData
@testable import TiantianHealth

final class HealthCalculatorTests: XCTestCase {
    func testFoodPhotoAnalysisDecodesStructuredResponse() throws {
        let json = """
        {
          "sceneType": "plated_meal",
          "overallName": "牛肉米饭套餐",
          "totalCalories": 520,
          "calorieRange": {"minimum": 450, "maximum": 620},
          "confidence": 0.78,
          "items": [
            {"id": "rice", "name": "米饭", "category": "主食", "estimatedAmount": 200, "unit": "g", "calories": 232, "basis": "约一碗", "confidence": 0.82},
            {"id": "beef", "name": "牛肉", "category": "肉类", "estimatedAmount": 120, "unit": "g", "calories": 288, "basis": "可见份量", "confidence": 0.74}
          ],
          "assumptions": ["未计餐盘"],
          "requiresUserConfirmation": true
        }
        """
        let result = try JSONDecoder().decode(FoodPhotoAnalysis.self, from: Data(json.utf8))
        XCTAssertEqual(result.totalCalories, 520, accuracy: 0.001)
        XCTAssertEqual(result.overallName, "牛肉米饭套餐")
        XCTAssertEqual(result.items.reduce(0) { $0 + $1.calories }, 520, accuracy: 0.001)
        XCTAssertTrue(result.requiresUserConfirmation)
        XCTAssertNil(result.userNote)
    }

    func testDeepSeekResponseFindsNestedOutputText() throws {
        let payload: [String: Any] = [
            "output": [["content": [["type": "output_text", "text": "{\"ok\":true}"]]]]
        ]
        XCTAssertEqual(DeepSeekVisionService.firstOutputText(in: payload), "{\"ok\":true}")
    }

    func testDeepSeekValidationCallsTheTargetVisionModelDirectly() throws {
        let request = try DeepSeekVisionService().validationRequest(apiKey: "test-key")
        XCTAssertEqual(request.url?.path, "/responses")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, DeepSeekVisionService.model)
        XCTAssertEqual(object["input"] as? String, "只回答 OK")
        XCTAssertNil(object["thinking"])
        XCTAssertEqual((object["reasoning"] as? [String: String])?["effort"], "none")
    }

    func testDeepSeekBalanceRequestUsesAuthenticatedGETWithoutBody() {
        let request = DeepSeekAccountService().balanceRequest(apiKey: "balance-key")

        XCTAssertEqual(request.url?.path, "/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer balance-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testDeepSeekBalanceDecodesMultipleCurrencies() throws {
        let data = Data("""
        {
          "is_available": true,
          "balance_infos": [
            {"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"},
            {"currency":"USD","total_balance":"2.50","granted_balance":"0.50","topped_up_balance":"2.00"}
          ]
        }
        """.utf8)

        let result = try JSONDecoder().decode(DeepSeekAccountBalance.self, from: data)

        XCTAssertTrue(result.isAvailable)
        XCTAssertEqual(result.balanceInfos.count, 2)
        XCTAssertEqual(result.balanceInfos[0].currency, "CNY")
        XCTAssertEqual(result.balanceInfos[0].totalBalance, "110.00")
        XCTAssertEqual(result.balanceInfos[1].currency, "USD")
        XCTAssertEqual(result.balanceInfos[1].grantedBalance, "0.50")
    }

    func testDeepSeekBalanceRetriesServerFailureOnce() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DeepSeekMockURLProtocol.reset()
        DeepSeekMockURLProtocol.responses = [
            (503, Data("{\"error\":{\"message\":\"busy\"}}".utf8)),
            (200, Data("{\"is_available\":true,\"balance_infos\":[{\"currency\":\"CNY\",\"total_balance\":\"9.90\",\"granted_balance\":\"0.00\",\"topped_up_balance\":\"9.90\"}]}".utf8))
        ]
        let service = DeepSeekAccountService(session: session, sleep: { _ in })

        let result = try await service.fetchBalance(apiKey: "test-key")

        XCTAssertEqual(DeepSeekMockURLProtocol.requestCount, 2)
        XCTAssertEqual(result.balanceInfos.first?.totalBalance, "9.90")
    }

    func testDeepSeekAnalysisRequestIncludesOptionalUserNote() throws {
        let request = try DeepSeekVisionService().analysisRequest(
            imageData: Data([0x01, 0x02]),
            apiKey: "test-key",
            userNote: "  请重点识别包装内容  "
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let prompt = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertTrue(prompt.contains("用户补充说明：请重点识别包装内容"))
        XCTAssertFalse(prompt.contains("  请重点"))
    }

    func testDeepSeekAnalysisUsesLargeOutputBudgetAndCompactSchema() throws {
        let request = try DeepSeekVisionService().analysisRequest(
            imageData: Data([0x01]),
            apiKey: "test-key",
            userNote: nil
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["max_output_tokens"] as? Int, 10_000)
        XCTAssertNil(object["thinking"])
        XCTAssertEqual((object["reasoning"] as? [String: String])?["effort"], "none")

        let text = try XCTUnwrap(object["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNil(properties["totalCalories"])
        XCTAssertNil(properties["confidence"])
        let items = try XCTUnwrap(properties["items"] as? [String: Any])
        let itemSchema = try XCTUnwrap(items["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(itemSchema["properties"] as? [String: Any])
        XCTAssertNil(itemProperties["id"])
        XCTAssertNil(itemProperties["confidence"])
        XCTAssertNotNil(itemProperties["basis"])
    }

    func testDeepSeekAnalysisRequestOmitsEmptyUserNote() throws {
        let request = try DeepSeekVisionService().analysisRequest(
            imageData: Data([0x01]),
            apiKey: "test-key",
            userNote: "   "
        )
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        let prompt = try XCTUnwrap(content.first?["text"] as? String)

        XCTAssertFalse(prompt.contains("用户补充说明："))
    }

    func testDeepSeekLogRequestHidesImageBase64ButKeepsRequestShape() throws {
        let image = Data([0x01, 0x02, 0x03])
        let request = try DeepSeekVisionService().analysisRequest(
            imageData: image,
            apiKey: "secret-key-must-not-appear",
            userNote: "识别整份热量"
        )
        let output = DeepSeekVisionService.sanitizedRequestJSON(request.httpBody, imageData: image)

        XCTAssertTrue(output.contains("图片 Base64 已隐藏"))
        XCTAssertTrue(output.contains("识别整份热量"))
        XCTAssertTrue(output.contains(DeepSeekVisionService.model))
        XCTAssertFalse(output.contains(image.base64EncodedString()))
        XCTAssertFalse(output.contains("secret-key-must-not-appear"))
    }

    func testDeepSeekAPILogStoreKeepsOnlyRecentSevenDays() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeepSeekAPILogStore(rootDirectory: root)
        let now = Date.now
        let recent = DeepSeekAPILogRecord(
            id: UUID(), operationID: UUID(), createdAt: now, kind: .photoAnalysis, attempt: 1,
            model: DeepSeekVisionService.model, inputTokens: 120, outputTokens: 80, httpStatus: 200,
            duration: 2.5, requestBytes: 100, responseBytes: 200, requestID: "recent",
            requestJSON: "{}", responseJSON: "{}", errorMessage: nil, imageThumbnailFilename: nil
        )
        let expired = DeepSeekAPILogRecord(
            id: UUID(), operationID: UUID(), createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            kind: .keyValidation, attempt: 1, model: DeepSeekVisionService.model,
            inputTokens: nil, outputTokens: nil, httpStatus: 500, duration: 1,
            requestBytes: 10, responseBytes: 10, requestID: "expired",
            requestJSON: "{}", responseJSON: "{}", errorMessage: "失败", imageThumbnailFilename: nil
        )

        await store.append(expired, thumbnailData: nil)
        await store.append(recent, thumbnailData: nil)
        let records = await store.records(now: now)

        XCTAssertEqual(records.map(\.requestID), ["recent"])
    }

    func testDeepSeekAPILogStoreDeduplicatesTransferredWatchLogs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeepSeekAPILogStore(rootDirectory: root)
        let id = UUID()
        let original = DeepSeekAPILogRecord(
            id: id, operationID: UUID(), createdAt: .now, kind: .watchVoiceAnalysis, attempt: 1,
            model: "deepseek-v4-flash", inputTokens: 10, outputTokens: 5, httpStatus: 500,
            duration: 1, requestBytes: 20, responseBytes: 30, requestID: nil,
            requestJSON: "{}", responseJSON: "{}", errorMessage: "失败", imageThumbnailFilename: nil
        )
        let deliveredAgain = DeepSeekAPILogRecord(
            id: id, operationID: original.operationID, createdAt: original.createdAt,
            kind: .watchVoiceAnalysis, attempt: 1, model: original.model,
            inputTokens: 10, outputTokens: 5, httpStatus: 500, duration: 1,
            requestBytes: 20, responseBytes: 30, requestID: "watch-request",
            requestJSON: "{}", responseJSON: "{}", errorMessage: "失败", imageThumbnailFilename: nil
        )

        await store.append(original, thumbnailData: nil)
        await store.append(deliveredAgain, thumbnailData: nil)
        let records = await store.records()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.requestID, "watch-request")
    }

    func testWatchVoiceAnalysisBuildsWholeAndSeparateRecords() throws {
        let result = WatchVoiceAnalysisResult(
            transcript: "鸭腿饭",
            overallName: "卤鸭腿饭",
            totalCalories: 615,
            items: [
                WatchVoiceAnalysisItem(id: "duck", name: "卤鸭腿", estimatedAmount: 1, unit: "只", calories: 320),
                WatchVoiceAnalysisItem(id: "rice", name: "米饭", estimatedAmount: 1, unit: "碗", calories: 230),
                WatchVoiceAnalysisItem(id: "sauce", name: "卤汁", estimatedAmount: 30, unit: "克", calories: 65),
                WatchVoiceAnalysisItem(id: "water", name: "水", estimatedAmount: 1, unit: "杯", calories: 0)
            ],
            assumptions: []
        )
        let selected: Set<String> = ["duck", "rice", "sauce"]

        let whole = result.recordItems(selectedIDs: selected, grouping: .whole)
        let separate = result.recordItems(selectedIDs: selected, grouping: .separate)

        XCTAssertEqual(whole.count, 1)
        XCTAssertEqual(whole.first?.name, "卤鸭腿饭")
        XCTAssertEqual(whole.first?.calories, 615)
        XCTAssertEqual(separate.map(\.name), ["卤鸭腿", "米饭", "卤汁"])
        XCTAssertEqual(separate.reduce(0) { $0 + $1.calories }, 615)
    }

    func testWatchVoiceAnalysisDecodesLegacyResultWithoutOverallName() throws {
        let data = Data("""
        {"transcript":"鸭腿饭","totalCalories":320,"items":[{"id":"1","name":"鸭腿","estimatedAmount":1,"unit":"只","calories":320}],"assumptions":[]}
        """.utf8)

        let result = try JSONDecoder().decode(WatchVoiceAnalysisResult.self, from: data)

        XCTAssertEqual(result.overallName, "鸭腿饭")
    }

    func testDeepSeekRetriesServerErrorOnceAndLogsBothAttempts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeepSeekAPILogStore(rootDirectory: root)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DeepSeekMockURLProtocol.reset()
        DeepSeekMockURLProtocol.responses = [
            (500, Data("{\"error\":{\"message\":\"temporary\"}}".utf8)),
            (200, Self.validDeepSeekAnalysisResponse)
        ]
        let service = DeepSeekVisionService(session: session, logStore: store, sleep: { _ in })

        let result = try await service.analyze(imageData: Data([0x01]), apiKey: "test-key", userNote: nil)
        let records = await store.records()

        XCTAssertEqual(result.totalCalories, 120)
        XCTAssertEqual(DeepSeekMockURLProtocol.requestCount, 2)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.compactMap(\.httpStatus)), Set([200, 500]))
        XCTAssertEqual(records.first(where: { $0.httpStatus == 200 })?.inputTokens, 42)
        XCTAssertEqual(records.first(where: { $0.httpStatus == 200 })?.outputTokens, 21)
    }

    func testDeepSeekDoesNotRetryIncompleteHTTP200AndLogsReason() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeepSeekAPILogStore(rootDirectory: root)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        DeepSeekMockURLProtocol.reset()
        DeepSeekMockURLProtocol.responses = [
            (200, Data("{\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"usage\":{\"input_tokens\":323,\"output_tokens\":1200}}".utf8))
        ]
        let service = DeepSeekVisionService(session: session, logStore: store, sleep: { _ in })

        do {
            _ = try await service.analyze(imageData: Data([0x01]), apiKey: "test-key", userNote: nil)
            XCTFail("Expected an incomplete response error")
        } catch {
            XCTAssertEqual(error as? DeepSeekAnalysisError, .responseIncomplete("max_output_tokens"))
        }

        let records = await store.records()
        XCTAssertEqual(DeepSeekMockURLProtocol.requestCount, 1)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.httpStatus, 200)
        XCTAssertEqual(records.first?.responseStatus, "incomplete")
        XCTAssertEqual(records.first?.incompleteReason, "max_output_tokens")
        XCTAssertFalse(records.first?.succeeded ?? true)
    }

    private static var validDeepSeekAnalysisResponse: Data {
        let analysis = """
        {"sceneType":"packaged_food","overallName":"饼干","totalCalories":120,"calorieRange":{"minimum":110,"maximum":130},"confidence":0.9,"items":[{"id":"1","name":"饼干","category":"零食","estimatedAmount":1,"unit":"份","calories":120,"basis":"营养表","confidence":0.9}],"assumptions":[],"requiresUserConfirmation":false}
        """
        let response: [String: Any] = [
            "status": "completed",
            "usage": ["input_tokens": 42, "output_tokens": 21],
            "output": [["content": [["type": "output_text", "text": analysis]]]]
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }

    func testEditableFoodAnalysisSelectionTotal() {
        let source = FoodPhotoAnalysis.Item(
            id: "drink", name: "饮料", category: "饮品", estimatedAmount: 1,
            unit: "瓶", calories: 180, basis: "营养表", confidence: 0.95
        )
        var item = EditableFoodAnalysisItem(source)
        XCTAssertEqual(item.isSelected ? item.calories : 0, 180, accuracy: 0.001)
        item.isSelected = false
        XCTAssertEqual(item.isSelected ? item.calories : 0, 0, accuracy: 0.001)
    }

    func testZeroCaloriePhotoAnalysisItemStartsUnselected() {
        let source = FoodPhotoAnalysis.Item(
            id: "ice", name: "冰块", category: "其他", estimatedAmount: 150,
            unit: "ml", calories: 0, basis: "水本身无热量", confidence: 0.99
        )
        XCTAssertFalse(EditableFoodAnalysisItem(source).isSelected)
    }

    func testPhotoAnalysisHistoryRoundTripsStructuredResult() throws {
        let analysis = FoodPhotoAnalysis(
            sceneType: "plated_meal",
            overallName: "鸡腿套餐",
            totalCalories: 520,
            calorieRange: .init(minimum: 470, maximum: 580),
            confidence: 0.8,
            items: [
                .init(id: "chicken", name: "鸡腿", category: "肉类", estimatedAmount: 1, unit: "个", calories: 320, basis: "可见份量", confidence: 0.8),
                .init(id: "rice", name: "米饭", category: "主食", estimatedAmount: 1, unit: "碗", calories: 200, basis: "约一碗", confidence: 0.8)
            ],
            assumptions: [],
            requiresUserConfirmation: false,
            userNote: "包装显示净含量 200 g"
        )
        let record = try FoodPhotoAnalysisRecord(imageFilename: "fixture.image", overallName: analysis.overallName, analysis: analysis)
        XCTAssertEqual(record.analysis, analysis)
        XCTAssertEqual(record.totalCalories, 520, accuracy: 0.001)
        XCTAssertEqual(record.analysis?.userNote, "包装显示净含量 200 g")
    }

    @MainActor
    func testAddingPhotoHistoryModelPreservesExistingStoreData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TiantianHealthPhotoHistoryMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("health.store")

        let presetID: UUID
        let logID: UUID
        let weightID: UUID
        do {
            let oldSchema = Schema([
                UserProfile.self,
                WorkoutBaseline.self,
                WeightEntry.self,
                FoodPreset.self,
                FoodLogEntry.self,
                ExerciseLogEntry.self,
                DailyBudget.self,
                HealthIntegrationState.self
            ])
            let oldConfiguration = ModelConfiguration(schema: oldSchema, url: storeURL)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])

            let preset = FoodPreset(name: "迁移测试食物", baseQuantity: 2, unit: .item, calories: 345)
            let log = FoodLogEntry(
                date: .now,
                meal: .lunch,
                presetID: preset.id,
                name: preset.name,
                quantity: 2,
                unit: preset.unit.rawValue,
                calories: 690
            )
            let weight = WeightEntry(date: .now, weightKG: 79.4)
            presetID = preset.id
            logID = log.id
            weightID = weight.id
            oldContainer.mainContext.insert(preset)
            oldContainer.mainContext.insert(log)
            oldContainer.mainContext.insert(weight)
            try oldContainer.mainContext.save()
        }

        let upgradedSchema = Schema([
            UserProfile.self,
            WorkoutBaseline.self,
            WeightEntry.self,
            FoodPreset.self,
            FoodLogEntry.self,
            FoodPhotoAnalysisRecord.self,
            ExerciseLogEntry.self,
            DailyBudget.self,
            HealthIntegrationState.self
        ])
        let upgradedConfiguration = ModelConfiguration(schema: upgradedSchema, url: storeURL)
        let upgradedContainer = try ModelContainer(for: upgradedSchema, configurations: [upgradedConfiguration])
        let presets = try upgradedContainer.mainContext.fetch(FetchDescriptor<FoodPreset>())
        let logs = try upgradedContainer.mainContext.fetch(FetchDescriptor<FoodLogEntry>())
        let weights = try upgradedContainer.mainContext.fetch(FetchDescriptor<WeightEntry>())
        let histories = try upgradedContainer.mainContext.fetch(FetchDescriptor<FoodPhotoAnalysisRecord>())

        XCTAssertEqual(presets.map(\.id), [presetID])
        XCTAssertEqual(presets.first?.baseQuantity, 2)
        XCTAssertEqual(presets.first?.calories, 345)
        XCTAssertEqual(logs.map(\.id), [logID])
        XCTAssertEqual(logs.first?.calories, 690)
        XCTAssertEqual(weights.map(\.id), [weightID])
        XCTAssertEqual(weights.first?.weightKG, 79.4)
        XCTAssertTrue(histories.isEmpty)
    }

    func testDeepSeekKeyMaskKeepsOnlyPrefixAndLastFourCharacters() {
        XCTAssertEqual(
            DeepSeekCredentialStore.mask("sk-1234567890abcdef"),
            "sk-••••••••cdef"
        )
        XCTAssertFalse(DeepSeekCredentialStore.mask("sk-1234567890abcdef").contains("123456"))
    }

    func testPhotoAnalysisDuplicateMatchingNormalizesNameAndRoundsCalories() {
        XCTAssertTrue(FoodAnalysisLibraryPlanner.isDuplicate(
            analyzedName: "  SuperModel 零蔗糖酸奶 ",
            analyzedCalories: 18.2,
            presetName: "supermodel 零蔗糖酸奶",
            presetCalories: 18.4
        ))
        XCTAssertFalse(FoodAnalysisLibraryPlanner.isDuplicate(
            analyzedName: "SuperModel 零蔗糖酸奶",
            analyzedCalories: 19.6,
            presetName: "SuperModel 零蔗糖酸奶",
            presetCalories: 18.4
        ))
    }

    func testMifflinRestingEnergyForMale() {
        let result = HealthCalculator.restingEnergy(sex: .male, age: 30, heightCM: 180, weightKG: 80)
        XCTAssertEqual(result, 1_780, accuracy: 0.01)
    }

    func testMifflinRestingEnergyForFemale() {
        let result = HealthCalculator.restingEnergy(sex: .female, age: 30, heightCM: 165, weightKG: 65)
        XCTAssertEqual(result, 1_370.25, accuracy: 0.01)
    }

    func testStepFactorInterpolates() {
        XCTAssertEqual(HealthCalculator.stepFactor(for: 5_000), 0.20, accuracy: 0.0001)
        XCTAssertEqual(HealthCalculator.stepFactor(for: 6_250), 0.235, accuracy: 0.0001)
        XCTAssertEqual(HealthCalculator.stepFactor(for: 50_000), 0.55, accuracy: 0.0001)
    }

    func testWorkoutIncludedInStepsIsNotDoubleCounted() {
        let included = WorkoutDraft(type: "快走", durationMinutes: 60, sessionsPerWeek: 7, met: 4, includedInSteps: true)
        let separate = WorkoutDraft(type: "游泳", durationMinutes: 60, sessionsPerWeek: 7, met: 6, includedInSteps: false)
        XCTAssertEqual(HealthCalculator.dailyWorkoutEnergy(weightKG: 70, workouts: [included]), 0, accuracy: 0.01)
        XCTAssertEqual(HealthCalculator.dailyWorkoutEnergy(weightKG: 70, workouts: [separate]), 350, accuracy: 0.01)
        XCTAssertEqual(HealthCalculator.weeklyWorkoutEnergy(weightKG: 70, workouts: [separate]), 2_450, accuracy: 0.01)
    }

    func testJinRoundTrip() {
        let display = WeightUnit.jin.displayValue(fromKilograms: 72.4)
        XCTAssertEqual(display, 144.8, accuracy: 0.001)
        XCTAssertEqual(WeightUnit.jin.kilograms(fromDisplayValue: display), 72.4, accuracy: 0.001)
    }

    func testTrendStartsImmediately() {
        let only = WeightEntry(date: .now, weightKG: 80)
        let points = HealthCalculator.trendPoints(from: [only])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].trendKG, 80, accuracy: 0.001)
    }

    func testWeightChartDomainGivesSinglePointOneKilogramContext() {
        let point = WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        let domain = HealthCalculator.weightChartDomain(points: [point])
        XCTAssertEqual(domain?.lowerBound ?? 0, 80.5, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 81.5, accuracy: 0.001)
    }

    func testWeightChartDomainAmplifiesSmallChanges() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 80.8, trendKG: 80.8),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points)
        XCTAssertEqual(domain?.lowerBound ?? 0, 80.4, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 81.4, accuracy: 0.001)
    }

    func testWeightChartDomainAddsPaddingForLargerRange() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 75, trendKG: 75),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 81)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points)
        XCTAssertEqual(domain?.lowerBound ?? 0, 73.8, accuracy: 0.001)
        XCTAssertEqual(domain?.upperBound ?? 0, 82.2, accuracy: 0.001)
    }

    func testWeightChartDomainIncludesTargetReferenceLine() {
        let points = [
            WeightPoint(id: UUID(), date: .now, rawKG: 80.5, trendKG: 80.5),
            WeightPoint(id: UUID(), date: .now, rawKG: 81, trendKG: 80.875)
        ]
        let domain = HealthCalculator.weightChartDomain(points: points, referenceValues: [75])

        XCTAssertLessThan(domain?.lowerBound ?? .infinity, 75)
        XCTAssertGreaterThan(domain?.upperBound ?? 0, 81)
    }

    func testWeightChartAxisUsesActualRecordDates() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let points = (0..<7).map { index in
            WeightPoint(
                id: UUID(),
                date: start.addingTimeInterval(Double(index) * 86_400),
                rawKG: 81 - Double(index) * 0.1,
                trendKG: 81
            )
        }
        let dates = HealthCalculator.weightChartAxisDates(points: points)
        XCTAssertEqual(dates, [points[0].date, points[2].date, points[4].date, points[6].date])
    }

    func testWeightChartAxisShowsOneLabelForMultipleRecordsOnSameDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let first = WeightPoint(id: UUID(), date: day.addingTimeInterval(3_600), rawKG: 81, trendKG: 81)
        let second = WeightPoint(id: UUID(), date: day.addingTimeInterval(43_200), rawKG: 80.5, trendKG: 80.875)

        XCTAssertEqual(HealthCalculator.weightChartAxisDates(points: [first, second]), [first.date])
    }

    func testNearestWeightPointSupportsChartScrubbing() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = WeightPoint(id: UUID(), date: start, rawKG: 81, trendKG: 81)
        let second = WeightPoint(id: UUID(), date: start.addingTimeInterval(86_400), rawKG: 80.5, trendKG: 80.875)
        let touchedDate = start.addingTimeInterval(70_000)
        XCTAssertEqual(HealthCalculator.nearestWeightPoint(to: touchedDate, in: [first, second])?.id, second.id)
    }

    func testOnlyPastAndTodayLogsAreEditable() {
        let reference = DateTools.day(.now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: reference)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: reference)!
        XCTAssertTrue(DateTools.canEditLogs(on: yesterday, referenceDate: reference))
        XCTAssertTrue(DateTools.canEditLogs(on: reference, referenceDate: reference))
        XCTAssertFalse(DateTools.canEditLogs(on: tomorrow, referenceDate: reference))
    }

    func testCalorieTargetRoundsToFifty() {
        let result = HealthCalculator.dailyCalorieTarget(tdee: 2_280, weightKG: 80, pace: .gentle, sex: .male)
        XCTAssertEqual(result.truncatingRemainder(dividingBy: 50), 0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result, 1_500)
    }

    func testProfileResolvesPresetAndCustomDeficitToNumericTarget() throws {
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: .now))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 178,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .standard,
            averageSteps: 5_000,
            baselineTDEE: 2_200
        )

        XCTAssertEqual(
            profile.dailyDeficitTarget(weightKG: 80),
            HealthCalculator.presetDailyDeficit(weightKG: 80, pace: .standard),
            accuracy: 0.001
        )

        profile.setCustomDailyDeficitTarget(537)
        XCTAssertTrue(profile.usesCustomDailyDeficitTarget)
        XCTAssertEqual(profile.customDailyDeficitTarget ?? 0, 525, accuracy: 0.001)
        XCTAssertEqual(profile.dailyDeficitTarget(weightKG: 70), 525, accuracy: 0.001)

        profile.pace = .fast
        XCTAssertFalse(profile.usesCustomDailyDeficitTarget)
        XCTAssertEqual(
            profile.dailyDeficitTarget(weightKG: 70),
            HealthCalculator.presetDailyDeficit(weightKG: 70, pace: .fast),
            accuracy: 0.001
        )
    }

    func testDailyIntakePlanUsesHigherOfEstimatedAndActualExpenditure() {
        let plan = HealthCalculator.dailyIntakePlan(
            planningExpenditure: 2_200,
            actualExpenditure: 2_450,
            goalDeficit: 425,
            minimumCalories: 1_500
        )

        XCTAssertEqual(plan.expenditureBasis, 2_450, accuracy: 0.001)
        XCTAssertEqual(plan.targetDeficit, 425, accuracy: 0.001)
        XCTAssertEqual(plan.targetIntake, 2_025, accuracy: 0.001)

        let protectedPlan = HealthCalculator.dailyIntakePlan(
            planningExpenditure: 1_200,
            actualExpenditure: 900,
            goalDeficit: 425,
            minimumCalories: 1_500
        )
        XCTAssertEqual(protectedPlan.targetDeficit, 0, accuracy: 0.001)
        XCTAssertEqual(protectedPlan.targetIntake, 1_500, accuracy: 0.001)
    }

    func testIntakeProgressSegmentsReserveDeficitAndExposeOverflow() {
        let normal = HealthCalculator.intakeProgressSegments(
            consumed: 1_530,
            planningExpenditure: 2_356,
            actualExpenditure: 2_156,
            targetDeficit: 425
        )
        XCTAssertEqual(normal.scale, 2_356, accuracy: 0.001)
        XCTAssertEqual(normal.intakeLimit, 1_931, accuracy: 0.001)
        XCTAssertEqual(normal.safeConsumed, 1_530, accuracy: 0.001)
        XCTAssertEqual(normal.exceededIntakeLimit, 0, accuracy: 0.001)
        XCTAssertEqual(normal.unconsumedReservedDeficit, 425, accuracy: 0.001)
        XCTAssertEqual(normal.reservedDeficitStart, 1_931, accuracy: 0.001)

        let withinReserve = HealthCalculator.intakeProgressSegments(
            consumed: 2_100,
            planningExpenditure: 2_356,
            actualExpenditure: nil,
            targetDeficit: 425
        )
        XCTAssertEqual(withinReserve.safeConsumed, 1_931, accuracy: 0.001)
        XCTAssertEqual(withinReserve.exceededIntakeLimit, 169, accuracy: 0.001)
        XCTAssertEqual(withinReserve.unconsumedReservedDeficit, 256, accuracy: 0.001)
        XCTAssertEqual(withinReserve.reservedDeficitStart, 2_100, accuracy: 0.001)

        let beyondExpenditure = HealthCalculator.intakeProgressSegments(
            consumed: 2_600,
            planningExpenditure: 2_356,
            actualExpenditure: 2_450,
            targetDeficit: 425
        )
        XCTAssertEqual(beyondExpenditure.scale, 2_600, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.intakeLimit, 2_025, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.exceededIntakeLimit, 575, accuracy: 0.001)
        XCTAssertEqual(beyondExpenditure.unconsumedReservedDeficit, 0, accuracy: 0.001)
    }

    func testWeeklySummaryUsesOnlyCompletedPastDaysForTargetDeviation() {
        let start = DateTools.day(.now)
        func day(
            offset: Int,
            phase: HealthCalculator.CalorieDayPhase,
            expenditure: Double?,
            consumed: Double,
            targetIntake: Double,
            hasIntake: Bool
        ) -> HealthCalculator.CalorieDeficitDay {
            HealthCalculator.CalorieDeficitDay(
                date: Calendar.current.date(byAdding: .day, value: offset, to: start)!,
                phase: phase,
                source: expenditure == nil ? .healthEstimated : .healthActual,
                recordedExpenditure: expenditure,
                planningExpenditure: targetIntake + 400,
                actualRestingExpenditure: expenditure.map { $0 * 0.8 },
                actualActiveExpenditure: expenditure.map { $0 * 0.2 },
                targetDeficit: 400,
                consumed: consumed,
                targetIntake: targetIntake,
                hasIntakeData: hasIntake
            )
        }

        let days = [
            day(offset: -3, phase: .past, expenditure: 2_500, consumed: 1_500, targetIntake: 2_100, hasIntake: true),
            day(offset: -2, phase: .past, expenditure: 2_000, consumed: 1_800, targetIntake: 1_600, hasIntake: true),
            day(offset: -1, phase: .past, expenditure: 2_200, consumed: 0, targetIntake: 1_800, hasIntake: false),
            day(offset: 0, phase: .today, expenditure: 900, consumed: 1_000, targetIntake: 1_900, hasIntake: true),
            day(offset: 1, phase: .future, expenditure: nil, consumed: 0, targetIntake: 1_800, hasIntake: false)
        ]

        let summary = HealthCalculator.calorieDeficitSummary(days: days)
        XCTAssertEqual(summary.currentDeficit, 1_100, accuracy: 0.001)
        XCTAssertEqual(summary.pastTargetDeviation, 400, accuracy: 0.001)
        XCTAssertEqual(summary.weeklyRemainingIntake, 3_100, accuracy: 0.001)
        XCTAssertEqual(summary.completedPastDayCount, 2)
    }

    func testWeeklySummaryExcludesTodayFromTargetDeviationAndAllowsOverTargetState() {
        let today = DateTools.day(.now)
        let day = HealthCalculator.CalorieDeficitDay(
            date: today,
            phase: .today,
            source: .healthProjected,
            recordedExpenditure: 1_000,
            planningExpenditure: 2_300,
            actualRestingExpenditure: 800,
            actualActiveExpenditure: 200,
            targetDeficit: 400,
            consumed: 3_000,
            targetIntake: 1_900,
            hasIntakeData: true
        )

        let summary = HealthCalculator.calorieDeficitSummary(days: [day])
        XCTAssertEqual(summary.pastTargetDeviation, 0, accuracy: 0.001)
        XCTAssertEqual(summary.weeklyRemainingIntake, -1_100, accuracy: 0.001)
        XCTAssertEqual(summary.completedPastDayCount, 0)
    }

    func testRealizedDeficitUsesOnlyActualExpenditureAndIgnoresTarget() {
        let today = DateTools.day(.now)
        func day(
            phase: HealthCalculator.CalorieDayPhase,
            recordedExpenditure: Double?,
            consumed: Double,
            targetDeficit: Double = 400,
            hasIntakeData: Bool = true
        ) -> HealthCalculator.CalorieDeficitDay {
            HealthCalculator.CalorieDeficitDay(
                date: today,
                phase: phase,
                source: recordedExpenditure == nil ? .healthEstimated : .healthActual,
                recordedExpenditure: recordedExpenditure,
                planningExpenditure: 2_400,
                actualRestingExpenditure: recordedExpenditure.map { $0 * 0.8 },
                actualActiveExpenditure: recordedExpenditure.map { $0 * 0.2 },
                targetDeficit: targetDeficit,
                consumed: consumed,
                targetIntake: 2_000,
                hasIntakeData: hasIntakeData
            )
        }

        XCTAssertEqual(day(phase: .today, recordedExpenditure: 1_500, consumed: 1_100).realizedDeficit, 400, accuracy: 0.001)
        XCTAssertEqual(day(phase: .today, recordedExpenditure: 1_500, consumed: 1_800).realizedDeficit, -300, accuracy: 0.001)
        XCTAssertEqual(day(phase: .today, recordedExpenditure: 1_500, consumed: 1_100, targetDeficit: 800).realizedDeficit, 400, accuracy: 0.001)
        XCTAssertEqual(day(phase: .future, recordedExpenditure: 2_400, consumed: 500).realizedDeficit, 0, accuracy: 0.001)
        XCTAssertEqual(day(phase: .past, recordedExpenditure: 2_400, consumed: 0, hasIntakeData: false).realizedDeficit, 2_400, accuracy: 0.001)
        XCTAssertEqual(day(phase: .past, recordedExpenditure: nil, consumed: 1_600).realizedDeficit, 0, accuracy: 0.001)
    }

    func testStageGoalDefaultsToFivePercentAndLimitsRange() {
        XCTAssertEqual(HealthCalculator.healthyStageTarget(weightKG: 80), 76, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.healthyStageRange(weightKG: 80).lowerBound, 72, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.healthyStageRange(weightKG: 80).upperBound, 79.5, accuracy: 0.001)
    }

    func testDeficitFatEquivalent() {
        XCTAssertEqual(HealthCalculator.plannedDeficit(tdee: 2_300, calorieTarget: 2_000), 300, accuracy: 0.001)
        XCTAssertEqual(HealthCalculator.theoreticalFatEquivalentKG(calorieDeficit: 2_310), 0.3, accuracy: 0.001)
    }

    func testMondayWeightProgressComparesWithPreviousDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 23)))
        func measurement(day: Int, hour: Int, weight: Double, source: WeightMeasurement.Source = .local) -> WeightMeasurement {
            let measuredAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
            return WeightMeasurement(
                id: UUID(),
                date: calendar.startOfDay(for: measuredAt),
                measuredAt: measuredAt,
                weightKG: weight,
                source: source,
                localEntryID: source == .local ? UUID() : nil
            )
        }
        let measurements = [
            measurement(day: 20, hour: 8, weight: 79.4, source: .appleHealth),
            measurement(day: 20, hour: 20, weight: 79.25),
            measurement(day: 21, hour: 8, weight: 78.7)
        ]

        let result = HealthCalculator.weeklyWeightProgress(
            measurements: measurements,
            weekStart: weekStart,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result?.context, .previousDay)
        XCTAssertEqual(result?.baselineWeightKG ?? 0, 79.25, accuracy: 0.001)
        XCTAssertEqual(result?.latestWeightKG ?? 0, 78.7, accuracy: 0.001)
        XCTAssertEqual(result?.changeKG ?? 0, -0.55, accuracy: 0.001)
    }

    func testMondayWithoutPreviousDayUsesWeekStartingWeight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 23)))
        func measurement(day: Int, hour: Int, weight: Double) -> WeightMeasurement {
            let measuredAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
            return WeightMeasurement(
                id: UUID(),
                date: calendar.startOfDay(for: measuredAt),
                measuredAt: measuredAt,
                weightKG: weight,
                source: .local,
                localEntryID: UUID()
            )
        }

        let result = HealthCalculator.weeklyWeightProgress(
            measurements: [measurement(day: 21, hour: 8, weight: 78.7)],
            weekStart: weekStart,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result?.context, .weekStart)
        XCTAssertEqual(result?.baselineWeightKG ?? 0, 78.7, accuracy: 0.001)
    }

    func testTuesdayWeightProgressUsesFirstMeasurementThisWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 23)))
        func measurement(day: Int, weight: Double) -> WeightMeasurement {
            let measuredAt = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 8))!
            return WeightMeasurement(
                id: UUID(), date: calendar.startOfDay(for: measuredAt), measuredAt: measuredAt,
                weightKG: weight, source: .local, localEntryID: UUID()
            )
        }

        let result = HealthCalculator.weeklyWeightProgress(
            measurements: [
                measurement(day: 20, weight: 79.25),
                measurement(day: 21, weight: 78.7),
                measurement(day: 22, weight: 78.6)
            ],
            weekStart: weekStart,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result?.context, .currentWeek)
        XCTAssertEqual(result?.baselineWeightKG ?? 0, 78.7, accuracy: 0.001)
        XCTAssertEqual(result?.latestWeightKG ?? 0, 78.6, accuracy: 0.001)
        XCTAssertEqual(result?.changeKG ?? 0, -0.1, accuracy: 0.001)
    }

    func testFirstMeasurementMidweekUsesWeekStartingWeightUntilAnotherDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23)))
        let measuredAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 8)))
        let measurement = WeightMeasurement(
            id: UUID(), date: calendar.startOfDay(for: measuredAt), measuredAt: measuredAt,
            weightKG: 78.5, source: .local, localEntryID: UUID()
        )

        let result = HealthCalculator.weeklyWeightProgress(
            measurements: [measurement],
            weekStart: weekStart,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result?.context, .weekStart)
        XCTAssertEqual(result?.baselineWeightKG ?? 0, 78.5, accuracy: 0.001)
    }

    func testGoalArrivalEstimateRoundsUpAndReturnsDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)))

        let result = HealthCalculator.goalArrivalEstimate(
            currentWeightKG: 78.8,
            targetWeightKG: 77.5,
            dailyDeficit: 425,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(result?.remainingWeightKG ?? 0, 1.3, accuracy: 0.001)
        XCTAssertEqual(result?.remainingDays, 24)
        XCTAssertEqual(result?.estimatedDate, calendar.date(byAdding: .day, value: 24, to: referenceDate))
    }

    func testGoalArrivalEstimateRequiresRemainingWeightAndEffectiveDeficit() {
        XCTAssertNil(HealthCalculator.goalArrivalEstimate(currentWeightKG: 77.5, targetWeightKG: 77.5, dailyDeficit: 425))
        XCTAssertNil(HealthCalculator.goalArrivalEstimate(currentWeightKG: 78.8, targetWeightKG: 77.5, dailyDeficit: 0))
    }

    func testAppleHealthBaselineBlendsUntilSevenCompleteDays() {
        let start = DateTools.day(.now)
        let days = (1...3).map { offset in
            HealthDailyEnergy(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: start)!,
                resting: 1_700,
                active: 500
            )
        }

        let result = HealthCalculator.appleHealthBaseline(days: days, fallbackTDEE: 2_000)

        XCTAssertEqual(result?.validDayCount, 3)
        XCTAssertEqual(result?.confidence ?? 0, 3.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(result?.total ?? 0, 2_000 * 4.0 / 7.0 + 2_200 * 3.0 / 7.0, accuracy: 0.001)
    }

    func testAppleHealthBaselineUsesRecentMedianAndSkipsIncompleteDays() {
        let start = DateTools.day(.now)
        var days = (1...7).map { offset in
            HealthDailyEnergy(
                date: Calendar.current.date(byAdding: .day, value: -offset, to: start)!,
                resting: offset == 1 ? 3_000 : 1_700,
                active: offset == 2 ? 1_500 : 500
            )
        }
        days.append(HealthDailyEnergy(date: start, resting: nil, active: 300))
        days.append(HealthDailyEnergy(date: start.addingTimeInterval(1), resting: 1_800, active: nil))

        let result = HealthCalculator.appleHealthBaseline(days: days, fallbackTDEE: 1_900)

        XCTAssertEqual(result?.resting ?? 0, 1_700, accuracy: 0.001)
        XCTAssertEqual(result?.active ?? 0, 500, accuracy: 0.001)
        XCTAssertEqual(result?.total ?? 0, 2_200, accuracy: 0.001)
        XCTAssertEqual(result?.validDayCount, 7)
    }

    func testLatestWeightMeasurementPerDayUsesLatestTimeAndPrefersLocalForTies() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
        let healthID = UUID()
        let localID = UUID()
        let nextDayID = UUID()
        let health = WeightMeasurement(
            id: healthID,
            date: day,
            measuredAt: day.addingTimeInterval(7_200),
            weightKG: 81,
            source: .appleHealth,
            localEntryID: nil
        )
        let laterLocal = WeightMeasurement(
            id: localID,
            date: day,
            measuredAt: day.addingTimeInterval(10_800),
            weightKG: 80.7,
            source: .local,
            localEntryID: localID
        )
        let nextDay = WeightMeasurement(
            id: nextDayID,
            date: day.addingTimeInterval(86_400),
            measuredAt: day.addingTimeInterval(90_000),
            weightKG: 80.5,
            source: .appleHealth,
            localEntryID: nil
        )

        let latest = HealthCalculator.latestWeightMeasurementsPerDay([health, nextDay, laterLocal], calendar: calendar)
        XCTAssertEqual(latest.map(\.id), [localID, nextDayID])

        let tiedLocal = WeightMeasurement(
            id: localID,
            date: day,
            measuredAt: health.measuredAt,
            weightKG: 80.9,
            source: .local,
            localEntryID: localID
        )
        XCTAssertEqual(
            HealthCalculator.latestWeightMeasurementsPerDay([health, tiedLocal], calendar: calendar).first?.id,
            localID
        )
    }

    func testExerciseAddsToAvailableCalories() {
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: 320), 2_170, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.availableCalories(base: 1_850, exercise: -50), 1_850, accuracy: 0.001)
    }

    func testProjectedFullDayExpenditureUsesCurrentAndTypicalRemainder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 10,
            hour: 12
        )))

        let result = try XCTUnwrap(HealthCalculator.projectedFullDayExpenditure(
            currentResting: 900,
            currentActive: 200,
            typicalResting: 1_800,
            typicalActive: 400,
            at: noon,
            calendar: calendar
        ))

        XCTAssertEqual(result, 2_200, accuracy: 0.001)
    }

    func testProjectedFullDayExpenditureRequiresCurrentHealthValue() {
        XCTAssertNil(HealthCalculator.projectedFullDayExpenditure(
            currentResting: nil,
            currentActive: nil,
            typicalResting: 1_800,
            typicalActive: 400
        ))
    }

    func testHealthDrivenDaysCombinePastActualTodayLiveAndFutureEstimate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12)))
        let today = calendar.startOfDay(for: reference)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1990, month: 1, day: 1)))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 180,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_200
        )
        profile.setCustomDailyDeficitTarget(525)
        let state = HealthIntegrationState()
        state.isEnabled = true
        state.typicalRestingEnergy = 1_800
        state.typicalActiveEnergy = 400
        let yesterdayLog = FoodLogEntry(
            date: yesterday,
            meal: .dinner,
            presetID: nil,
            name: "昨天",
            quantity: 1,
            unit: "份",
            calories: 1_900
        )
        let todayLog = FoodLogEntry(
            date: today,
            meal: .lunch,
            presetID: nil,
            name: "今天",
            quantity: 1,
            unit: "份",
            calories: 1_600
        )
        // FoodLogEntry normalizes with Calendar.current. Pin these fixtures to the
        // GMT day used by this test so local timezone does not move them a day.
        yesterdayLog.date = yesterday
        todayLog.date = today
        let logs = [yesterdayLog, todayLog]

        let days = HealthCalculator.healthDrivenCalorieDays(
            dates: [yesterday, today, tomorrow],
            profile: profile,
            latestWeightKG: 80,
            todayEnergy: HealthEnergySnapshot(resting: 900, active: 200, updatedAt: reference),
            historicalEnergy: [HealthDailyEnergy(date: yesterday, resting: 1_800, active: 500)],
            foodLogs: logs,
            exerciseLogs: [],
            state: state,
            healthEnabled: true,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0].phase, .past)
        XCTAssertEqual(days[0].targetDeficit, 525, accuracy: 0.001)
        XCTAssertEqual(days[0].recordedExpenditure ?? 0, 2_300, accuracy: 0.001)
        XCTAssertEqual(days[0].currentDeficit ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(days[1].phase, .today)
        XCTAssertEqual(days[1].targetDeficit, 525, accuracy: 0.001)
        XCTAssertEqual(days[1].recordedExpenditure ?? 0, 1_100, accuracy: 0.001)
        XCTAssertEqual(days[1].actualRestingExpenditure ?? 0, 900, accuracy: 0.001)
        XCTAssertEqual(days[1].actualActiveExpenditure ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(days[1].actualExpenditure ?? 0, 1_100, accuracy: 0.001)
        XCTAssertEqual(days[1].planningExpenditure, 2_250, accuracy: 0.001)
        XCTAssertEqual(days[1].currentDeficit ?? 0, -500, accuracy: 0.001)
        XCTAssertEqual(days[1].forecastDeficit ?? 0, days[1].targetDeficit, accuracy: 0.001)
        XCTAssertEqual(days[2].phase, .future)
        XCTAssertEqual(days[2].targetDeficit, 525, accuracy: 0.001)
        XCTAssertNil(days[2].recordedExpenditure)
        XCTAssertEqual(days[2].source, .healthEstimated)

        let summary = HealthCalculator.calorieDeficitSummary(days: days)
        XCTAssertEqual(summary.currentDeficit, -100, accuracy: 0.001)
        XCTAssertEqual(summary.forecastDeficit, 400 + days[1].targetDeficit + days[2].targetDeficit, accuracy: 0.001)
    }

    func testMissingOrPartialHealthEnergyNeverPretendsToBeActualDeficit() throws {
        let calendar = Calendar.current
        let reference = Date.now
        let today = calendar.startOfDay(for: reference)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let birthDate = try XCTUnwrap(calendar.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .female,
            birthDate: birthDate,
            heightCM: 165,
            weightUnit: .kg,
            initialWeightKG: 65,
            targetWeightKG: 62,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_000
        )
        let state = HealthIntegrationState()
        state.isEnabled = true
        state.typicalRestingEnergy = 1_500
        state.typicalActiveEnergy = 500

        let days = HealthCalculator.healthDrivenCalorieDays(
            dates: [yesterday, today],
            profile: profile,
            latestWeightKG: 65,
            todayEnergy: HealthEnergySnapshot(resting: 900, active: nil, updatedAt: reference),
            historicalEnergy: [HealthDailyEnergy(date: yesterday, resting: 1_500, active: 500)],
            foodLogs: [],
            exerciseLogs: [],
            state: state,
            healthEnabled: true,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertNil(days[0].currentDeficit)
        XCTAssertEqual(days[0].source, .healthActual)
        XCTAssertEqual(days[0].recordedExpenditure ?? 0, 2_000, accuracy: 0.001)
        XCTAssertNil(days[0].forecastDeficit)
        XCTAssertNil(days[1].currentDeficit)
        XCTAssertEqual(days[1].source, .healthProjected)
    }

    func testYesterdayTodayEnergyIsIgnoredAfterMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let reference = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: today))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let staleUpdate = try XCTUnwrap(calendar.date(byAdding: .hour, value: 23, to: yesterday))
        let birthDate = try XCTUnwrap(calendar.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 178,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_100
        )
        let state = HealthIntegrationState()
        state.isEnabled = true
        state.typicalRestingEnergy = 1_700
        state.typicalActiveEnergy = 400

        let day = try XCTUnwrap(HealthCalculator.healthDrivenCalorieDays(
            dates: [today],
            profile: profile,
            latestWeightKG: 80,
            todayEnergy: HealthEnergySnapshot(resting: 1_700, active: 400, updatedAt: staleUpdate),
            historicalEnergy: [],
            foodLogs: [],
            exerciseLogs: [],
            state: state,
            healthEnabled: true,
            referenceDate: reference,
            calendar: calendar
        ).first)

        XCTAssertEqual(day.phase, .today)
        XCTAssertEqual(day.source, .healthEstimated)
        XCTAssertNil(day.actualRestingExpenditure)
        XCTAssertNil(day.actualActiveExpenditure)
        XCTAssertNil(day.actualExpenditure)
        XCTAssertNil(day.recordedExpenditure)
        XCTAssertEqual(day.planningExpenditure, 2_100, accuracy: 0.001)
    }

    func testBodyFallbackIsForecastOnly() throws {
        let reference = Date.now
        let today = DateTools.day(reference)
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .male,
            birthDate: birthDate,
            heightCM: 178,
            weightUnit: .kg,
            initialWeightKG: 80,
            targetWeightKG: 76,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_100
        )

        let day = try XCTUnwrap(HealthCalculator.healthDrivenCalorieDays(
            dates: [today],
            profile: profile,
            latestWeightKG: 80,
            todayEnergy: nil,
            historicalEnergy: [],
            foodLogs: [],
            exerciseLogs: [],
            state: nil,
            healthEnabled: false,
            referenceDate: reference
        ).first)

        XCTAssertNil(day.currentDeficit)
        XCTAssertEqual(day.source, .bodyEstimated)
        XCTAssertEqual(day.forecastDeficit ?? 0, day.targetDeficit, accuracy: 0.001)
    }

    func testHealthSupplementIsAddedWithoutDoubleCountingOtherManualExercise() throws {
        let reference = Date.now
        let today = DateTools.day(reference)
        let birthDate = try XCTUnwrap(Calendar.current.date(byAdding: .year, value: -30, to: today))
        let profile = UserProfile(
            sex: .female,
            birthDate: birthDate,
            heightCM: 165,
            weightUnit: .kg,
            initialWeightKG: 65,
            targetWeightKG: 61.8,
            pace: .gentle,
            averageSteps: 5_000,
            baselineTDEE: 2_000
        )
        let state = HealthIntegrationState()
        state.typicalRestingEnergy = 1_500
        state.typicalActiveEnergy = 500
        let ordinary = ExerciseLogEntry(date: today, type: "健康已记录", calories: 300, isHealthSupplement: false)
        let supplement = ExerciseLogEntry(date: today, type: "补录", calories: 100, isHealthSupplement: true)
        let baseEnergy = HealthEnergySnapshot(resting: 1_000, active: 300, updatedAt: reference)

        let day = try XCTUnwrap(HealthCalculator.healthDrivenCalorieDays(
            dates: [today],
            profile: profile,
            latestWeightKG: 65,
            todayEnergy: baseEnergy,
            historicalEnergy: [],
            foodLogs: [],
            exerciseLogs: [ordinary, supplement],
            state: state,
            healthEnabled: true,
            referenceDate: reference
        ).first)

        XCTAssertEqual(day.recordedExpenditure ?? 0, 1_400, accuracy: 0.001)
        XCTAssertEqual(day.actualRestingExpenditure ?? 0, 1_000, accuracy: 0.001)
        XCTAssertEqual(day.actualActiveExpenditure ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(day.actualExpenditure ?? 0, 1_400, accuracy: 0.001)
    }

    func testKilocalorieKilojouleRoundTrip() {
        let kilojoules = CalorieMath.kilojoules(fromKilocalories: 250)
        XCTAssertEqual(kilojoules, 1_046, accuracy: 0.001)
        XCTAssertEqual(CalorieMath.kilocalories(fromKilojoules: kilojoules), 250, accuracy: 0.001)
    }

    func testNutritionLabelPackageKilocalories() {
        let calories = CalorieMath.packageKilocalories(
            kilojoulesPer100Grams: 1_680,
            netWeightGrams: 50
        )

        XCTAssertEqual(calories, 840 / 4.184, accuracy: 0.001)
        XCTAssertEqual(calories.rounded(), 201)
        XCTAssertEqual(
            CalorieMath.packageKilocalories(kilojoulesPer100Grams: 0, netWeightGrams: 50),
            0
        )
        XCTAssertEqual(
            CalorieMath.packageKilocalories(kilojoulesPer100Grams: 1_680, netWeightGrams: -1),
            0
        )
    }

    func testFoodPresetsSortByMostRecentCreationOrUse() {
        let now = Date.now
        let olderUsed = FoodPreset(name: "鸡蛋", baseQuantity: 1, unit: .item, calories: 75)
        olderUsed.createdAt = now.addingTimeInterval(-500)
        olderUsed.lastUsedAt = now.addingTimeInterval(-100)
        let newestUsed = FoodPreset(name: "酸奶", baseQuantity: 1, unit: .serving, calories: 120)
        newestUsed.createdAt = now.addingTimeInterval(-800)
        newestUsed.lastUsedAt = now
        let olderUnused = FoodPreset(name: "米饭", baseQuantity: 1, unit: .bowl, calories: 230)
        olderUnused.createdAt = now.addingTimeInterval(-300)
        let newestUnused = FoodPreset(name: "苹果", baseQuantity: 1, unit: .item, calories: 90)
        newestUnused.createdAt = now.addingTimeInterval(-10)

        let result = FoodPresetOrdering.sortedByRecentUse([olderUnused, olderUsed, newestUnused, newestUsed])
        XCTAssertEqual(result.map(\.id), [newestUsed.id, newestUnused.id, olderUsed.id, olderUnused.id])
    }

    func testFoodPresetsSortByCreationForLibrary() {
        let now = Date.now
        let older = FoodPreset(name: "鸡蛋", baseQuantity: 1, unit: .item, calories: 75)
        older.createdAt = now.addingTimeInterval(-100)
        older.lastUsedAt = now
        let newer = FoodPreset(name: "酸奶", baseQuantity: 1, unit: .serving, calories: 120)
        newer.createdAt = now

        let result = FoodPresetOrdering.sortedByCreation([older, newer])
        XCTAssertEqual(result.map(\.id), [newer.id, older.id])
    }

    func testFoodRecommendationsPreferMatchingMealWhenUsageIsOtherwiseEqual() {
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let breakfastFood = FoodPreset(name: "苏打饼干", baseQuantity: 1, unit: .serving, calories: 120)
        let lunchFood = FoodPreset(name: "饭团", baseQuantity: 1, unit: .serving, calories: 200)
        for preset in [breakfastFood, lunchFood] {
            preset.createdAt = reference.addingTimeInterval(-30 * 86_400)
            preset.lastUsedAt = reference
        }

        let breakfastLog = FoodLogEntry(
            date: reference,
            meal: .breakfast,
            presetID: breakfastFood.id,
            name: breakfastFood.name,
            quantity: 1,
            unit: breakfastFood.unit.rawValue,
            calories: breakfastFood.calories
        )
        breakfastLog.createdAt = reference
        let lunchLog = FoodLogEntry(
            date: reference,
            meal: .lunch,
            presetID: lunchFood.id,
            name: lunchFood.name,
            quantity: 1,
            unit: lunchFood.unit.rawValue,
            calories: lunchFood.calories
        )
        lunchLog.createdAt = reference

        let result = FoodPresetOrdering.sortedForMeal(
            [lunchFood, breakfastFood],
            foodLogs: [breakfastLog, lunchLog],
            meal: .breakfast,
            referenceDate: reference
        )

        XCTAssertEqual(result.map(\.id), [breakfastFood.id, lunchFood.id])
    }

    func testFoodRecommendationsAllowStrongGlobalUsageToBeatWeakMealMatch() {
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let weakMealMatch = FoodPreset(name: "早餐牛奶", baseQuantity: 1, unit: .serving, calories: 120)
        let strongGlobal = FoodPreset(name: "苏打饼干", baseQuantity: 1, unit: .serving, calories: 120)
        for preset in [weakMealMatch, strongGlobal] {
            preset.createdAt = reference.addingTimeInterval(-30 * 86_400)
            preset.lastUsedAt = reference
        }

        let breakfastLog = FoodLogEntry(
            date: reference,
            meal: .breakfast,
            presetID: weakMealMatch.id,
            name: weakMealMatch.name,
            quantity: 1,
            unit: weakMealMatch.unit.rawValue,
            calories: weakMealMatch.calories
        )
        breakfastLog.createdAt = reference
        let globalLogs = (0..<4).map { index in
            let log = FoodLogEntry(
                date: reference,
                meal: .snack,
                presetID: strongGlobal.id,
                name: strongGlobal.name,
                quantity: 1,
                unit: strongGlobal.unit.rawValue,
                calories: strongGlobal.calories
            )
            log.createdAt = reference.addingTimeInterval(-Double(index) * 60)
            return log
        }

        let result = FoodPresetOrdering.sortedForMeal(
            [weakMealMatch, strongGlobal],
            foodLogs: [breakfastLog] + globalLogs,
            meal: .breakfast,
            referenceDate: reference
        )

        XCTAssertEqual(result.first?.id, strongGlobal.id)
    }

    func testFoodRecommendationsDecayOlderMealHistory() {
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let recent = FoodPreset(name: "近期加餐", baseQuantity: 1, unit: .serving, calories: 100)
        let old = FoodPreset(name: "很久前的加餐", baseQuantity: 1, unit: .serving, calories: 100)
        for preset in [recent, old] {
            preset.createdAt = reference.addingTimeInterval(-180 * 86_400)
            preset.lastUsedAt = reference.addingTimeInterval(-180 * 86_400)
        }
        recent.lastUsedAt = reference

        let recentLog = FoodLogEntry(
            date: reference,
            meal: .snack,
            presetID: recent.id,
            name: recent.name,
            quantity: 1,
            unit: recent.unit.rawValue,
            calories: recent.calories
        )
        recentLog.createdAt = reference
        let oldLog = FoodLogEntry(
            date: reference.addingTimeInterval(-180 * 86_400),
            meal: .snack,
            presetID: old.id,
            name: old.name,
            quantity: 1,
            unit: old.unit.rawValue,
            calories: old.calories
        )
        oldLog.createdAt = reference.addingTimeInterval(-180 * 86_400)

        let result = FoodPresetOrdering.sortedForMeal(
            [old, recent],
            foodLogs: [oldLog, recentLog],
            meal: .snack,
            referenceDate: reference
        )

        XCTAssertEqual(result.first?.id, recent.id)
    }

    func testWatchFoodPresetSnapshotDecodesLegacyPayloadWithoutRecommendationScores() throws {
        struct LegacySnapshot: Codable {
            let id: UUID
            let name: String
            let baseQuantity: Double
            let unit: String
            let calories: Double
            let activityAt: Date
        }

        let legacy = LegacySnapshot(
            id: UUID(),
            name: "苏打饼干",
            baseQuantity: 1,
            unit: "份",
            calories: 120,
            activityAt: .now
        )
        let decoded = try JSONDecoder().decode(
            WatchFoodPresetSnapshot.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertNil(decoded.recommendationScores)
    }

    func testWidgetMetricsExposeTodayAndWeekDeficits() {
        let calendar = Calendar.current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 10))!
        let monday = DateTools.startOfWeek(containing: reference)
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: reference,
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: (0..<7).map { index in
                let date = calendar.date(byAdding: .day, value: index, to: monday)!
                return WidgetCalorieDay(
                    date: date,
                    baseBudget: 1_800,
                    exercise: 0,
                    consumed: index == 0 ? 1_600 : (index == 1 ? 1_400 : 0),
                    targetDeficit: 400,
                    currentDeficit: index == 0 ? 500 : (index == 1 ? 250 : nil),
                    forecastDeficit: index == 0 ? 500 : 400
                )
            }
        )

        let metrics = snapshot.metrics(on: reference, calendar: calendar)
        XCTAssertTrue(metrics.todayHasCurrentDeficit)
        XCTAssertEqual(metrics.todayCurrentDeficit, 250, accuracy: 0.001)
        XCTAssertEqual(metrics.todayTargetDeficit, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.todayRemainingIntake, 400, accuracy: 0.001)
        XCTAssertEqual(metrics.weekConsumed, 3_000, accuracy: 0.001)
        XCTAssertEqual(metrics.weekTargetDeficit, 2_800, accuracy: 0.001)
        XCTAssertEqual(metrics.weekCurrentDeficit, 750, accuracy: 0.001)
        XCTAssertEqual(metrics.weekForecastDeficit, 2_900, accuracy: 0.001)
        XCTAssertEqual(metrics.weekRemainingIntake, 9_600, accuracy: 0.001)
    }

    func testWidgetMetricsExposeOverTargetIntakeWithoutChangingStoredValues() {
        let now = Date.now
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_700,
            days: [WidgetCalorieDay(
                date: now,
                baseBudget: 1_700,
                exercise: 0,
                consumed: 2_000,
                targetDeficit: 400,
                currentDeficit: -200,
                forecastDeficit: -200
            )]
        )

        let metrics = snapshot.metrics(on: now)
        XCTAssertEqual(metrics.todayRemainingIntake, -300, accuracy: 0.001)
        XCTAssertEqual(metrics.todayCurrentDeficit, -200, accuracy: 0.001)
        XCTAssertEqual(metrics.todayForecastDeficit, -200, accuracy: 0.001)
    }

    func testWidgetMetricsExposeTodayEnergyBarsAndReservedDeficit() {
        let now = Date.now
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_925,
            days: [WidgetCalorieDay(
                date: now,
                baseBudget: 1_925,
                exercise: 0,
                consumed: 1_530,
                targetDeficit: 425,
                currentDeficit: 626,
                forecastDeficit: 809,
                actualRestingExpenditure: 1_785,
                actualActiveExpenditure: 371,
                estimatedExpenditure: 2_356
            )]
        )

        let metrics = snapshot.metrics(on: now)
        XCTAssertEqual(metrics.todayActualExpenditure ?? 0, 2_156, accuracy: 0.001)
        XCTAssertEqual(metrics.todayEstimatedExpenditure, 2_356, accuracy: 0.001)
        XCTAssertEqual(metrics.todayIntakeLimit, 1_931, accuracy: 0.001)
        XCTAssertEqual(metrics.todayEstimatedRemainingIntake, 401, accuracy: 0.001)
        XCTAssertEqual(metrics.todaySafeConsumed, 1_530, accuracy: 0.001)
        XCTAssertEqual(metrics.todayExceededIntakeLimit, 0, accuracy: 0.001)
        XCTAssertEqual(metrics.todayUnconsumedReservedDeficit, 425, accuracy: 0.001)

        let overTarget = WidgetCalorieSnapshot(
            generatedAt: now,
            isOnboarded: true,
            fallbackDailyBudget: 1_925,
            days: [WidgetCalorieDay(
                date: now,
                baseBudget: 1_925,
                exercise: 0,
                consumed: 2_100,
                targetDeficit: 425,
                actualRestingExpenditure: 1_785,
                actualActiveExpenditure: 371,
                estimatedExpenditure: 2_356
            )]
        ).metrics(on: now)

        XCTAssertEqual(overTarget.todaySafeConsumed, 1_931, accuracy: 0.001)
        XCTAssertEqual(overTarget.todayExceededIntakeLimit, 169, accuracy: 0.001)
        XCTAssertEqual(overTarget.todayUnconsumedReservedDeficit, 256, accuracy: 0.001)
    }

    func testWidgetSnapshotDecodesPayloadFromPreviousVersion() throws {
        let now = Date.now
        let dateValue = Int(now.timeIntervalSince1970 * 1_000)
        let oldPayload: [String: Any] = [
            "generatedAt": dateValue,
            "isOnboarded": true,
            "fallbackDailyBudget": 1_800,
            "days": [[
                "date": dateValue,
                "baseBudget": 1_800,
                "exercise": 0,
                "consumed": 1_200,
                "targetDeficit": 400,
                "forecastDeficit": 400
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: oldPayload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(WidgetCalorieSnapshot.self, from: data)

        XCTAssertNil(decoded.days.first?.actualRestingExpenditure)
        XCTAssertNil(decoded.days.first?.actualActiveExpenditure)
        XCTAssertNil(decoded.days.first?.estimatedExpenditure)
        XCTAssertEqual(decoded.metrics(on: now).todayEstimatedExpenditure, 2_200, accuracy: 0.001)
    }

    func testWidgetSnapshotStoreDoesNotRewriteUnchangedContentAndCanClear() {
        let suiteName = "WidgetSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let first = WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: []
        )
        let sameContent = WidgetCalorieSnapshot(
            generatedAt: .now.addingTimeInterval(30),
            isOnboarded: true,
            fallbackDailyBudget: 1_800,
            days: []
        )

        XCTAssertTrue(store.save(first))
        XCTAssertFalse(store.save(sameContent))
        XCTAssertEqual(store.load()?.fallbackDailyBudget, 1_800)
        XCTAssertTrue(store.clear())
        XCTAssertNil(store.load())
        XCTAssertFalse(store.clear())
    }

    func testWatchDashboardRoundTripsAndExcludesTodayFromTargetDeviation() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let snapshot = WidgetCalorieSnapshot(
            generatedAt: .now,
            isOnboarded: true,
            fallbackDailyBudget: 1_900,
            days: [
                WidgetCalorieDay(
                    date: yesterday,
                    baseBudget: 1_900,
                    exercise: 0,
                    consumed: 1_600,
                    targetDeficit: 400,
                    currentDeficit: 550
                ),
                WidgetCalorieDay(
                    date: today,
                    baseBudget: 1_900,
                    exercise: 0,
                    consumed: 500,
                    targetDeficit: 400,
                    currentDeficit: 1_000
                )
            ]
        )
        let presetID = UUID()
        let dashboard = WatchDashboardSnapshot(
            calorieSnapshot: snapshot,
            presets: [
                WatchFoodPresetSnapshot(
                    id: presetID,
                    name: "米饭",
                    baseQuantity: 1,
                    unit: "碗",
                    calories: 200,
                    activityAt: .now
                )
            ],
            processedOperationIDs: [UUID()],
            credentialState: WatchCredentialState(revision: 3, isConfigured: true)
        )

        let decoded = try JSONDecoder().decode(
            WatchDashboardSnapshot.self,
            from: JSONEncoder().encode(dashboard)
        )

        XCTAssertEqual(decoded, dashboard)
        XCTAssertEqual(decoded.presets.first?.id, presetID)
        XCTAssertEqual(decoded.targetDeviationBeforeToday, 150, accuracy: 0.001)
    }

    func testWatchFoodRecordCommandRoundTripsWithoutLosingOperationID() throws {
        let operationID = UUID()
        let presetID = UUID()
        let command = WatchFoodRecordCommand(
            id: operationID,
            createdAt: .now,
            mealRaw: MealType.lunch.rawValue,
            source: .library,
            items: [
                WatchFoodRecordItem(
                    presetID: presetID,
                    name: "米饭",
                    quantity: 2,
                    unit: "碗",
                    calories: 400,
                    servings: 2
                )
            ]
        )

        let envelope = try WatchWireEnvelope(kind: .recordCommand, payload: command)
        let decoded = try envelope.decode(WatchFoodRecordCommand.self)

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.id, operationID)
        XCTAssertEqual(decoded.items.first?.presetID, presetID)
    }

    @MainActor
    func testHomeScreenQuickActionRoutes() {
        let router = AppRouter.shared
        router.clearPendingShortcut()

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.weight"))
        XCTAssertEqual(router.selectedTab, .trend)
        XCTAssertEqual(router.pendingQuickAction?.destination, .weight)

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.breakfast"))
        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.breakfast))

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.lunch"))
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.lunch))

        XCTAssertTrue(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.dinner"))
        XCTAssertEqual(router.pendingQuickAction?.destination, .meal(.dinner))

        XCTAssertFalse(router.enqueueShortcut(type: "com.shaoguoqing.tiantianhealth.unknown"))
        router.clearPendingShortcut()
    }

    @MainActor
    func testWidgetDeepLinksSelectTheExpectedTab() {
        let router = AppRouter.shared
        XCTAssertTrue(router.open(url: URL(string: "tiantianhealth://today")!))
        XCTAssertEqual(router.selectedTab, .today)
        router.clearPendingShortcut()
        XCTAssertTrue(router.open(url: URL(string: "tiantianhealth://food")!))
        XCTAssertEqual(router.selectedTab, .today)
        if case .meal = router.pendingQuickAction?.destination {
            // The suggested meal is intentionally time-dependent.
        } else {
            XCTFail("Food widget deep link should enqueue a meal entry route")
        }
        XCTAssertTrue(router.open(url: URL(string: "tiantianhealth://budget")!))
        XCTAssertEqual(router.selectedTab, .budget)
        XCTAssertFalse(router.open(url: URL(string: "https://example.com/budget")!))
        XCTAssertFalse(router.open(url: URL(string: "tiantianhealth://unknown")!))
    }
}

private final class DeepSeekMockURLProtocol: URLProtocol {
    static var responses: [(Int, Data)] = []
    private(set) static var requestCount = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        responses = []
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let index = Self.requestCount
        Self.requestCount += 1
        let response = Self.responses[min(index, Self.responses.count - 1)]
        Self.lock.unlock()

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.0,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-request-id": "test-\(index + 1)"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
