# GoldPrice - 黄金价格 macOS 状态栏应用

## 项目简介

GoldPrice 是一个 macOS 状态栏应用，用于实时显示黄金价格。
支持国内金价（京东浙商、京东民生）和国际金价（伦敦金、纽约金），并提供今日涨跌、24 小时走势图、持仓收益计算等功能。

## 效果展示

- 浅色模式
![Light](./Assets/Light.png?v=2)

- 深色模式
![Dark](./Assets/Dark.png?v=2)

## 功能特点

- 🏅 **实时金价** - 状态栏实时显示黄金价格，支持自定义图标（emoji 选择器）
- 📊 **多数据源** - 京东浙商、京东民生（元/克）、伦敦金、纽约金（$/oz）
- 📈 **今日涨跌** - 显示涨跌幅度与方向箭头
- 📉 **24h 走势图** - 悬浮价格行即可查看当日走势、最高价、最低价
- 💰 **持仓收益** - 设置持仓克数和买入均价，实时计算收益金额与收益率
- ⚙️ **偏好设置** - 自定义状态栏图标、状态栏收益显示模式（金额/收益率/都显示/不显示）
- 🔄 **自动刷新** - 定时自动刷新价格数据，支持手动立即刷新

## 安装

### 直接下载

前往 [Releases](https://github.com/iamzjt-front-end/GoldPrice/releases) 下载最新的 `GoldPrice.dmg`，打开后将 GoldPrice.app 拖入 Applications 文件夹即可。

> **提示**：如果打开时提示 **"app已损坏，无法打开"**，请在终端运行以下命令：
>
> ```bash
> xattr -cr /Applications/GoldPrice.app
> ```
>
> 该命令会清除 macOS 为从网络下载的文件添加的隔离属性（`com.apple.quarantine`）。由于应用未经过 Apple 签名公证，Gatekeeper 会阻止其运行，执行此命令后即可正常打开。

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/iamzjt-front-end/GoldPrice.git
cd GoldPrice

# 调试运行
swift build && .build/debug/GoldPrice

# 一键打包 DMG
bash build.sh
```

## 系统要求

- macOS 12.0 或更高版本
- Swift 5.5 或更高版本

## 项目结构

| 文件 | 说明 |
|------|------|
| `GoldPriceApp.swift` | 应用入口 |
| `StatusBarController.swift` | 状态栏控制器，管理菜单与交互 |
| `GoldPriceService.swift` | 数据获取服务，负责从各数据源获取金价 |
| `PriceModels.swift` | 数据模型（数据源、价格信息、持仓、设置） |
| `PriceHistoryManager.swift` | 历史数据与持仓/设置的持久化管理 |
| `PriceMenuItemView.swift` | 主菜单价格行自定义视图 |
| `ChartMenuItemView.swift` | 走势图子菜单视图 |
| `MiniChartView.swift` | 24h 走势图绘制 |
| `PositionMenuItemView.swift` | 持仓显示/编辑、偏好设置视图 |
| `build.sh` | 一键编译打包 DMG 脚本 |

## 数据存储

应用数据存储在 `~/Library/Application Support/GoldPrice/` 目录下：

- `priceHistory.json` - 当日价格历史（每日零点自动清理）
- `position.json` - 持仓信息
- `settings.json` - 偏好设置

## 技术特性

- **原生菜单** - 基于 NSMenu + NSHostingView，嵌入 SwiftUI 自定义视图
- **响应式设计** - 支持 macOS 深色/浅色模式自动适配
- **Combine 框架** - 响应式数据绑定与自动 UI 更新
- **文件持久化** - 数据存储在 Application Support 目录，debug/release 一致
- **网络适配** - 智能处理不同 API 的数据格式和编码（JSON / GB18030）

## iPhone 版可行性

当前仓库可以扩展成你自己用的 iPhone App。现有业务层和数据层复用率很高，主要需要替换的是 macOS 状态栏与菜单交互。

仓库里已经补了一个 iOS 三 tab 骨架：

- `行情`
- `持仓`
- `设置`

接入方式和文件清单见 [docs/IOS_APP_SETUP.md](./docs/IOS_APP_SETUP.md)。

## 许可证

MIT License
