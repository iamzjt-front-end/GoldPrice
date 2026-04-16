# GoldPrice iPhone 版接入说明

当前仓库现在已经带上了一个可生成的 iOS 工程方案，可以继续往真正的 `ipa` 走。

当前仓库可以做成你自己用的 iPhone App，而且复用率比较高：

- `Sources/Models`、`Sources/Services`、`Sources/Shared` 基本都能直接复用
- 真正绑死在 macOS 的主要是 `AppKit` 状态栏、`NSMenu` 和悬浮面板
- 这次已经补了一个 iOS 三 tab 骨架：`行情`、`持仓`、`设置`

## 当前移动端范围

- `行情`
  - 展示 4 个金价源
  - 显示当前价、涨跌、高低点、日内小图
  - 支持手动刷新
- `持仓`
  - 录入多笔持仓
  - 支持手续费
  - 自动计算浮盈浮亏
- `设置`
  - 默认数据源
  - 自动刷新间隔

本轮没有把这些一起搬过去：

- 金友圈
- 价格提醒 / 涨跌幅提醒 / 收益提醒 / 新高新低提醒
- macOS 状态栏展示相关设置

## 怎么在 Xcode 里做成 iPhone App

因为 Swift Package 目前仍是 macOS 可执行项目，这里最稳妥的做法是新建一个 iOS App target，然后复用现有源码。

1. 用 Xcode 新建一个 `App` 项目，比如命名为 `GoldPriceMobile`
2. Deployment Target 建议选 `iOS 16.0+`
3. 删除 Xcode 自动生成的 `GoldPriceMobileApp.swift` 和 `ContentView.swift`
4. 把下面这些目录里的文件加进 iOS target

```text
Sources/Models
Sources/Services/GoldPriceService.swift
Sources/Services/OfficialIntradayChartService.swift
Sources/Services/PriceHistoryManager.swift
Sources/Shared
Sources/Mobile/GoldPriceMobileViewModel.swift
Sources/Mobile/GoldPriceMobileApp.swift
Sources/Views/MenuItems/MiniChartView.swift
```

5. 在 iOS target 里添加系统框架

```text
Charts
SwiftUI
Combine
```

6. 不要把这些 macOS 专属文件加入 iOS target

```text
Sources/App
Sources/Controllers
Sources/Views/StatusBarPopupView.swift
Sources/Views/MenuItems/PriceMenuItemView.swift
Sources/Views/MenuItems/PositionMenuItemView.swift
Sources/Views/MenuItems/ChartMenuItemView.swift
Sources/Views/MenuItems/GoldCircleDetailView.swift
Sources/Services/GoldCircleService.swift
```

## 装到你自己的手机

如果只是你自己用，最省事的是：

1. iPhone 用数据线连 Mac
2. Xcode 里选择你的手机作为运行目标
3. 用你自己的 Apple ID 做签名
4. 直接 Run 安装到手机

免费 Apple ID 也能装到自己手机，只是签名有效期会比较短，需要偶尔重新安装。

## 现在仓库里的状态

仓库里已经有这些 iOS 侧文件：

- `Sources/Mobile/GoldPriceMobileApp.swift`
- `Sources/Mobile/GoldPriceMobileViewModel.swift`
- `Sources/Shared/AppTheme.swift`
- `Sources/Shared/PriceChartPanel.swift`
- `scripts/generate_ios_project.rb`
- `scripts/build_ios_ipa.sh`
- `ios/GoldPriceiOS.xcodeproj`

也就是说，代码层面已经为 iPhone 三 tab 版本补了工程骨架；接下来主要卡在：

- Xcode 首次启动后的 license / components
- Xcode 账号里的 `Personal Team` 或开发者团队
- 真机签名与导出
