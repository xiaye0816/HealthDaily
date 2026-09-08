# 天天健康项目约定

## 真机签名与无损安装

- 本项目路径、Bundle ID、描述文件、证书、构建目录、设备容器和备份均按 App 独立管理，不得借用或修改其他项目的签名资产。
- 主 App Bundle ID 固定为 `com.shaoguoqing.tiantianhealth`，Widget Bundle ID 固定为 `com.shaoguoqing.tiantianhealth.widget`，Team ID 固定为 `4TL62DTQQM`，App Group 固定为 `group.com.shaoguoqing.tiantianhealth`。
- 真机安装前必须确认 Xcode 已登录 Apple 账号。浏览器登录 developer.apple.com 不等于 Xcode 已登录；Xcode 刚登录后，应先从 Xcode 对当前 App 执行一次 Run，完成账号、设备和签名握手。
- 安装前必须记录设备 UDID/CoreDevice ID、当前 App 版本、数据容器 UUID、签名证书、主 App 与 Widget 的描述文件 UUID，并备份完整 App Data Container 到 `/Users/shaoguoqing/Documents/TiantianHealthBackups/` 的时间戳目录。
- 始终保持 Bundle ID 和 Team 不变并覆盖安装。不得卸载 App、删除容器、重置数据或改变 Bundle ID；这些操作只有在用户明确要求清空数据时才允许。
- 带 Widget 的真机包必须同时使用两个与目标精确匹配的离线描述文件：主 App 和 Widget 都要包含当前设备及 `group.com.shaoguoqing.tiantianhealth`。不得用不含 App Group 的通配符描述文件签 Widget。
- 不得把带 `PPQCheck = true` 的在线 Managed Development 描述文件作为默认真机交付方案。若设备无法完成 PPQ 验证，它会导致“无法验证 App”或“Developer App Certificate is not trusted”，且设备设置中可能没有可操作的信任选项。
- 默认优先使用不依赖 PPQ 的离线 Ad Hoc 签名；若只能使用开发签名，必须先确认描述文件、设备、证书、entitlements 和 PPQ 状态，并在覆盖安装前准备好可回退的离线包。
- “VPN 与设备管理”中没有 Developer App 条目不等于安装异常。Ad Hoc 包通常不会显示该条目；遇到错误时先判断签名类型，不得反复让用户寻找不存在的入口。
- 安装前用 `security cms -D`、`codesign -d --entitlements :-` 和 `codesign --verify --deep --strict` 检查主 App 与所有扩展。主 App 和 Widget 的 Team、App Group、Bundle ID 前缀必须一致，嵌入描述文件必须未过期并包含当前设备。
- 安装后不能以安装命令成功作为完成标准。必须启动 App、确认进程运行，并再次导出数据容器，检查 SQLite/SwiftData 完整性，对比安装前后的记录数量、ID 和关键值。
- 如果新包启动失败，立即使用相同 Bundle ID 的已验证离线包覆盖回退，并再次核对数据；不得卸载重装。
- 所有临时归档、DerivedData 和测试模拟器都必须是本任务专属。完成后只清理本任务产生的内容，不得触碰其他 App 或任务的构建、模拟器和签名资产。

详细流程见 [docs/DEVICE_INSTALLATION.md](docs/DEVICE_INSTALLATION.md)。
