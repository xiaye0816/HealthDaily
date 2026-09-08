import XCTest

final class TiantianHealthUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testCoreMVPFlow() throws {
        let onboardingTitle = app.staticTexts["先认识一下你"]
        let brandSplash = app.otherElements["brand-splash"]
        XCTAssertTrue(onboardingTitle.waitForExistence(timeout: 8))
        XCTAssertFalse(brandSplash.exists)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(onboardingTitle.waitForExistence(timeout: 3))
        XCTAssertFalse(brandSplash.exists)

        capture("01-onboarding")
        app.buttons["birth-month-row"].tap()
        XCTAssertTrue(app.staticTexts["出生年月"].waitForExistence(timeout: 3))
        app.buttons["关闭"].tap()
        app.buttons["height-row"].tap()
        XCTAssertTrue(app.staticTexts["选择身高"].waitForExistence(timeout: 3))
        app.buttons["关闭"].tap()
        app.buttons["current-weight-row"].tap()
        XCTAssertTrue(app.staticTexts["选择当前体重"].waitForExistence(timeout: 3))
        capture("02-weight-wheel")
        app.buttons["关闭"].tap()
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["设置日常活动基准"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["固定运动"].exists)
        capture("03-daily-activity")
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["你想以什么节奏前进？"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["阶段目标"].exists)
        app.buttons["target-weight-row"].tap()
        XCTAssertTrue(app.staticTexts["设置阶段目标"].waitForExistence(timeout: 3))
        app.buttons["关闭"].tap()
        app.buttons["继续"].tap()
        XCTAssertTrue(app.staticTexts["你的起步计划"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["计划热量缺口"].exists)
        XCTAssertTrue(app.staticTexts["理论脂肪量"].exists)
        capture("04-plan-preview")
        app.buttons["开始使用"].tap()

        XCTAssertTrue(app.navigationBars["今天"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["记录饮食"].exists)
        XCTAssertFalse(app.staticTexts["体重"].exists)

        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.staticTexts["记录运动"].waitForExistence(timeout: 4))
        app.textFields["exercise-type"].tap()
        app.textFields["exercise-type"].typeText("游泳")
        app.textFields["exercise-calories"].tap()
        app.textFields["exercise-calories"].typeText("250")
        app.buttons["save-exercise"].tap()
        XCTAssertTrue(app.staticTexts["+250 kcal"].waitForExistence(timeout: 4))
        capture("05-today-exercise")

        app.buttons["记录饮食"].tap()
        XCTAssertTrue(app.buttons["新建食物"].waitForExistence(timeout: 4))
        app.buttons["新建食物"].tap()
        XCTAssertTrue(app.staticTexts["新建食物"].waitForExistence(timeout: 4))
        capture("06-food-editor")

        let nameField = app.textFields["名称，例如：煎鸡胸"]
        nameField.tap()
        nameField.typeText("煎鸡胸")
        let caloriesField = app.textFields["food-calories"]
        caloriesField.tap()
        caloriesField.typeText("250")
        app.buttons["保存并选中"].tap()

        let addToMeal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "加入")).firstMatch
        XCTAssertTrue(addToMeal.waitForExistence(timeout: 4))
        addToMeal.tap()
        XCTAssertTrue(app.staticTexts["煎鸡胸"].waitForExistence(timeout: 5))

        app.tabBars.buttons["预算"].tap()
        XCTAssertTrue(app.navigationBars["本周预算"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["每天的热量情况"].exists)
        XCTAssertTrue(app.staticTexts["点按查看明细"].exists)
        XCTAssertTrue(["周一", "周二", "周三", "周四", "周五", "周六", "周日"].contains { app.staticTexts[$0].exists })
        XCTAssertFalse(app.navigationBars["调整预算"].exists)
        capture("07-read-only-budget")

        let todayBudgetDay = app.buttons["budget-day-today"]
        XCTAssertTrue(todayBudgetDay.waitForExistence(timeout: 3))
        todayBudgetDay.tap()
        XCTAssertTrue(app.staticTexts["饮食与运动明细"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["煎鸡胸"].exists)

        app.buttons["edit-food-煎鸡胸"].tap()
        XCTAssertTrue(app.staticTexts["编辑饮食记录"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["food-log-name"].exists)
        XCTAssertTrue(app.textFields["food-log-quantity"].exists)
        XCTAssertTrue(app.textFields["food-log-calories"].exists)
        app.buttons["save-food-log"].tap()
        XCTAssertTrue(app.staticTexts["饮食与运动明细"].waitForExistence(timeout: 4))

        app.buttons["edit-exercise-游泳"].tap()
        XCTAssertTrue(app.staticTexts["修改运动"].waitForExistence(timeout: 4))
        app.buttons["save-exercise"].tap()
        XCTAssertTrue(app.staticTexts["饮食与运动明细"].waitForExistence(timeout: 4))
        capture("08-today-detail")
        app.navigationBars.buttons["本周预算"].tap()
        XCTAssertTrue(app.navigationBars["本周预算"].waitForExistence(timeout: 4))

        let pastBudgetDay = app.buttons["budget-day-past"]
        XCTAssertTrue(pastBudgetDay.waitForExistence(timeout: 3))
        pastBudgetDay.tap()
        XCTAssertTrue(app.staticTexts["饮食与运动明细"].waitForExistence(timeout: 4))
        app.buttons["daily-add-运动"].tap()
        app.textFields["exercise-type"].tap()
        app.textFields["exercise-type"].typeText("散步")
        app.textFields["exercise-calories"].tap()
        app.textFields["exercise-calories"].typeText("120")
        app.buttons["save-exercise"].tap()
        XCTAssertTrue(app.staticTexts["+120 kcal"].waitForExistence(timeout: 4))

        app.buttons["daily-add-早餐"].tap()
        XCTAssertTrue(app.buttons["选择 煎鸡胸"].waitForExistence(timeout: 4))
        app.buttons["选择 煎鸡胸"].tap()
        app.buttons["加入早餐"].tap()
        XCTAssertTrue(app.staticTexts["煎鸡胸"].waitForExistence(timeout: 4))
        capture("09-past-day-backfill")
        app.navigationBars.buttons["本周预算"].tap()
        XCTAssertTrue(app.navigationBars["本周预算"].waitForExistence(timeout: 4))

        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.navigationBars["趋势"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["体重方向"].exists)
        app.navigationBars["趋势"].buttons["记录"].tap()
        XCTAssertTrue(app.staticTexts["记录体重"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["保存体重"].isHittable)
        capture("10-weight-sheet")
        app.buttons["增加体重"].tap()
        app.buttons["保存体重"].tap()
        XCTAssertTrue(app.navigationBars["趋势"].waitForExistence(timeout: 4))

        let weightChart = app.otherElements["weight-chart"]
        XCTAssertTrue(weightChart.waitForExistence(timeout: 3))
        let chartStart = weightChart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        let chartEnd = weightChart.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        chartStart.press(forDuration: 0.2, thenDragTo: chartEnd)
        XCTAssertTrue(app.staticTexts["65.1 kg"].waitForExistence(timeout: 3))

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["我的食材库"].exists)

        let converter = app.buttons["calorie-converter"]
        for _ in 0..<2 where !converter.isHittable { app.swipeUp() }
        XCTAssertTrue(converter.waitForExistence(timeout: 3))
        converter.tap()
        XCTAssertTrue(app.navigationBars["热量换算"].waitForExistence(timeout: 4))
        app.textFields["calorie-converter-input"].tap()
        app.textFields["calorie-converter-input"].typeText("100")
        XCTAssertTrue(app.staticTexts["418.4"].waitForExistence(timeout: 3))
        app.navigationBars["热量换算"].buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 3))

        let resetButton = app.buttons["reset-all-data"]
        for _ in 0..<3 where !resetButton.isHittable { app.swipeUp() }
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3))
        resetButton.tap()
        XCTAssertTrue(app.staticTexts["确认重置数据"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["体重、热量、饮食和运动记录"].exists)
        app.buttons["confirm-reset-all-data"].tap()
        XCTAssertTrue(app.staticTexts["先认识一下你"].waitForExistence(timeout: 6))
        XCTAssertFalse(brandSplash.exists)
    }

    func testWeightChartTracksRecordsAndSupportsScrubbing() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-weight-chart"]
        app.launch()

        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.navigationBars["趋势"].waitForExistence(timeout: 5))

        let weightChart = app.otherElements["weight-chart"]
        XCTAssertTrue(weightChart.waitForExistence(timeout: 3))
        let chartStart = weightChart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        let chartEnd = weightChart.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.55))
        chartStart.press(forDuration: 0.2, thenDragTo: chartEnd)
        let selectionExpectation = expectation(
            for: NSPredicate(format: "value CONTAINS %@", "80.5 kg"),
            evaluatedWith: weightChart
        )
        wait(for: [selectionExpectation], timeout: 3)
        capture("11-weight-chart-scrubbing")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
