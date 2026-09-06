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
        XCTAssertTrue(app.staticTexts["先认识一下你"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.staticTexts["设置活动消耗基准"].waitForExistence(timeout: 3))
        app.buttons["添加"].tap()
        XCTAssertTrue(app.staticTexts["固定运动"].waitForExistence(timeout: 3))
        capture("03-workout-sheet")
        app.buttons["关闭"].tap()
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

        app.buttons["修改"].tap()
        XCTAssertTrue(app.navigationBars["记录体重"].waitForExistence(timeout: 4))
        app.buttons["增加体重"].tap()
        app.buttons["保存体重"].tap()
        XCTAssertTrue(app.navigationBars["今天"].waitForExistence(timeout: 4))

        app.buttons["记录饮食"].tap()
        XCTAssertTrue(app.buttons["新建食物"].waitForExistence(timeout: 4))
        app.buttons["新建食物"].tap()
        XCTAssertTrue(app.staticTexts["新建食物"].waitForExistence(timeout: 4))
        capture("05-food-editor")

        let nameField = app.textFields["名称，例如：煎鸡胸"]
        nameField.tap()
        nameField.typeText("煎鸡胸")
        let caloriesField = app.textFields["这份食物的热量"]
        caloriesField.tap()
        caloriesField.typeText("250")
        app.buttons["保存并选中"].tap()

        let addToMeal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "加入")).firstMatch
        XCTAssertTrue(addToMeal.waitForExistence(timeout: 4))
        addToMeal.tap()
        XCTAssertTrue(app.staticTexts["煎鸡胸"].waitForExistence(timeout: 5))

        app.tabBars.buttons["预算"].tap()
        XCTAssertTrue(app.navigationBars["本周预算"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["每天怎么分"].exists)
        app.buttons["today-budget-row"].tap()
        XCTAssertTrue(app.navigationBars["调整预算"].waitForExistence(timeout: 4))
        app.buttons["增加 50"].tap()
        app.buttons["保存并自动平衡本周"].tap()
        XCTAssertTrue(app.navigationBars["本周预算"].waitForExistence(timeout: 4))

        app.tabBars.buttons["进展"].tap()
        XCTAssertTrue(app.navigationBars["进展"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["体重方向"].exists)

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["我的食材库"].exists)

        let resetButton = app.buttons["reset-all-data"]
        for _ in 0..<3 where !resetButton.isHittable { app.swipeUp() }
        XCTAssertTrue(resetButton.waitForExistence(timeout: 3))
        resetButton.tap()
        XCTAssertTrue(app.staticTexts["确认重置数据"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["体重、热量和饮食记录"].exists)
        app.buttons["confirm-reset-all-data"].tap()
        XCTAssertTrue(app.staticTexts["先认识一下你"].waitForExistence(timeout: 6))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
