# 天天健康（HealthDaily）

一个极简的减脂反馈控制器：根据身体信息和活动基准生成热量预算，再结合饮食与体重记录逐步校准每日预估消耗。

## MVP 功能

- 四步初始化：身体信息、活动基准、目标、计划预览
- 每日饮食与个人食材库
- 当日运动记录，运动消耗按 1:1 增加当天和本周可用额度
- 体重记录与从第一天可见、按实际体重范围动态缩放的趋势展示
- 周热量预算汇总，并可进入过去或今天的明细补录、编辑饮食和运动
- 静息消耗、步数活动基准和动态 TDEE 校准
- kcal/kJ 双向换算和桌面快捷记录入口
- 所有数据仅保存在本机，不接入 Apple Health、账号或云同步

## 开发环境

- Xcode 26.6
- Swift 6.3.3 编译器（工程保持 Swift 5 language mode）
- iOS 17.0+
- SwiftUI + SwiftData + Charts

## 运行

1. 打开 `TiantianHealth.xcodeproj`。
2. 选择 `TiantianHealth` Scheme。
3. 选择 iOS 17 或更高版本模拟器运行。
4. 真机运行时，在 Signing & Capabilities 中选择自己的开发团队，并确保 Bundle ID 唯一。

真机覆盖安装必须保留现有数据，并分别核对主 App 与 Widget 的签名。完整流程见 [真机签名与无损安装手册](docs/DEVICE_INSTALLATION.md)。

## 测试

```bash
xcodebuild \
  -project TiantianHealth.xcodeproj \
  -scheme TiantianHealth \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

项目包含 16 个单元测试和 1 个 MVP 端到端 UI 测试，并覆盖历史补录、记录编辑和旧版 SwiftData 数据的原位升级验证。

## 隐私

当前版本不联网、不包含第三方 SDK，身体、饮食和体重数据仅保存在用户设备内。上架前需将正式隐私政策发布为公开 HTTPS 页面。
