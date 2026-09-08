# 天天健康真机签名与无损安装手册

## 这次问题的根因

本次带小组件的构建需要主 App 和 Widget 同时拥有 App Group。Xcode 自动生成的两个 Managed Development 描述文件虽然 entitlement 正确，但包含 `PPQCheck = true`。这台 iPhone 当时无法完成在线开发包验证，因此安装成功后仍提示“无法验证 App”或开发证书不受信任。

设备的“VPN 与设备管理”没有可选条目并不是用户漏操作。它既不能解决 PPQ 验证失败，也不是 Ad Hoc 包必须出现的入口。

临时恢复方案是：保留相同 Bundle ID 和数据容器，用已验证的离线开发描述文件重新签名主 App，并暂时不嵌入需要 App Group 的 Widget。该包可以启动，用户数据也保持完整；但它不是最终的小组件交付包。

## 后续固定签名路线

带小组件的真机版本只采用以下方案之一：

1. 首选：为主 App 与 Widget 分别创建精确 App ID 的离线 Ad Hoc 描述文件，两者都包含当前设备和 `group.com.shaoguoqing.tiantianhealth`，使用本机有效的 Apple Distribution 证书签名。
2. 备选：使用两个离线 Development 描述文件，要求同样包含设备和 App Group，并确认不依赖 `PPQCheck`；安装前先完成 Xcode 账号与设备握手。
3. 不再直接交付 Xcode 自动生成且带 `PPQCheck = true` 的在线 Managed Development 包。

主 App 与 Widget 必须成套更新。不能让主 App 使用精确 App Group 描述文件、Widget 使用通配符描述文件，也不能为了让主 App 启动而永久删除 Widget 后声称小组件已经交付。

## 每次安装前检查

- Xcode 的 Apple Accounts 中已登录 `861256127@qq.com`，团队为 `4TL62DTQQM`。
- 目标设备连接、解锁、开启 Developer Mode，且描述文件明确包含该设备 UDID。
- 记录当前安装版本和数据容器 UUID。
- 备份整个 Data Container，而不只是 SwiftData 的 `.store` 文件。
- 导出并核对主 App 与 Widget 的嵌入描述文件：UUID、类型、有效期、设备列表、Team、App ID、App Group 和 `PPQCheck`。
- 核对主 App 与 Widget 的最终签名 entitlements，并执行严格签名验证。
- 先保留一个已验证可启动的同 Bundle ID 离线回退包。

## 覆盖安装与验收

1. 只做同 Bundle ID 覆盖安装，不卸载旧 App。
2. 安装后立即通过设备接口冷启动 App，不能只看 Xcode 的 “Build Succeeded” 或安装命令退出码。
3. 确认 App 进程持续运行，而不是启动后崩溃或被系统拒绝。
4. 再次导出完整 Data Container。
5. 对 SwiftData/SQLite 执行完整性检查，并比较身体资料、食物库、餐食、运动、体重和预算的数量、ID 与关键字段。
6. 验证小组件可以添加、显示和深链接跳转。
7. 只有以上全部通过，才报告真机安装完成。

## 失败处理

- “无法验证 App”：先查嵌入描述文件是否为在线 Development、是否有 `PPQCheck`，再查网络验证和账号握手；不要重复生成相同类型的在线描述文件。
- “Developer App Certificate is not trusted”：先确认 Xcode 已登录并从 Xcode Run 一次。若设置中没有信任入口，不继续要求用户寻找，改用离线签名路线。
- 安装后打不开：不卸载，立即用保留的离线回退包覆盖恢复，然后验证数据。
- 数据校验不一致：停止继续安装，保留现场与备份，不执行自动迁移、清库或重新初始化。

## 已验证的项目常量

- 主 App：`com.shaoguoqing.tiantianhealth`
- Widget：`com.shaoguoqing.tiantianhealth.widget`
- Team：`4TL62DTQQM`
- App Group：`group.com.shaoguoqing.tiantianhealth`
- 备份目录：`/Users/shaoguoqing/Documents/TiantianHealthBackups/`

设备标识、证书和描述文件 UUID 会随设备或续期变化，因此每次安装都必须重新读取，不能把旧值当作永久配置。
