# Mio ShadowFlow

[English](README.md)

**面向 macOS SwiftUI 与 AppKit 的可见性驱动阴影渲染架构。**

Mio ShadowFlow 是一个小型参考核心，用于协调卡片阴影与裁切、滚动和页面转场。它提供可配置的可见性数学、snapshot/live 阴影所有权选择、扩展阴影宿主的坐标映射，以及 renderer protocol。

> **当前定位：**这是参考实现，尚不是可直接使用的 UI 组件。它不包含完整的 `CALayer` renderer、完整 SwiftUI visual component 或分页器。集成方需要将几何计算接入自己的视图与渲染生命周期。

## 项目简介

在复杂 SwiftUI 层级中，即使卡片的位置正确，它的阴影也可能被祖先裁切。分页器在 snapshot 到 live 内容交接时可能发生阴影跳变；即将完全离屏的卡片可能仍保留完整阴影；扩大内容裁切区以露出阴影，又可能让邻页卡片背景、图标或文字泄漏出来。

ShadowFlow 将卡片实体与阴影像素视为不同的渲染职责。卡片实体继续留在产品的逻辑内容视口中；renderer 可以通过独立宿主绘制阴影。纯几何计算则让每个阴影与当前页面和卡片可见度保持同步。

这个 Package 提炼的是可复用数学和少量协调类型，不包含来源产品的分页器或业务 UI。

## 为什么需要 ShadowFlow？

当视图层级没有严格裁切时，SwiftUI 的 `.shadow()` 很方便。但在 `ScrollView`、嵌套分页器或裁切过的转场容器中，阴影仍然属于视图渲染结果的一部分，可能一起被父层裁掉。扩大整个内容视口可以露出阴影，却可能把相邻页的卡片表面、图片或文字也显示出来。

转场期间，snapshot 和 live destination 可能同时存在。如果两者都绘制相同阴影，阴影会叠深；如果两者都没有 owner，阴影会短暂消失。仅使用页面级透明度也不足以处理单张卡片只露出一小部分的情况。

ShadowFlow 将这些职责拆开，并让计算由当前几何驱动，而不是依赖计时器或排队动画。

## 架构

```text
Pager / Scroll Region
├── Content Channel（内容通道）
│   └── 使用产品逻辑视口严格裁切
│       ├── 卡片实体、图像、标签、palette 与命中测试
│       └── 当前页面以及可选的 snapshot/live 内容
├── Shadow Channel（阴影通道）
│   └── 独立阴影宿主，可配置 visual bleed
│       └── 每个稳定卡片 identity 对应一个 shadow descriptor
└── Visibility Controller（可见性控制器，纯计算）
    ├── 页面视觉透明度
    ├── 卡片与视口交集及边缘衰减
    └── snapshot/live 单一阴影所有权
```

- **Content Channel** 管理卡片表面、图像、标签、交互和逻辑裁切。为了显示阴影，不需要扩大内容裁切区。
- **Shadow Channel** 接收几何和解析后的阴影参数。平台适配层可以通过透明的原生 layer，在内容裁切之外绘制阴影。
- **Visibility Controller** 计算页面/卡片可见度并选择一个阴影 owner。它不拥有分页器、ViewModel、动画或数据源。

Package 只提供数学和 renderer contract。图示表达的是集成职责，并不代表这里附带了完整 UI 层级。

## 核心算法

水平转场中，测量卡片实体与逻辑视口的交集：

```text
visibleRatio = clamp(intersectionWidth / cardWidth, 0, 1)
shadowFactor = pow(visibleRatio, exponent)
```

指数 `8` 来自一个参考产品配置，可通过参数调整，不是通用默认值。完全不可见的实体不会产生阴影。完全可见卡片的比例为 `1`，所以转场因子仍为 `1`。转场结束后，ShadowFlow 将稳定态因子恢复到 `1`，不把转场衰减残留到稳定页面。

最终透明度可以组合为：

```text
effectiveOpacity = baseOpacity
                 × ownershipMultiplier
                 × pageVisualOpacity
                 × shadowFactor
```

各因子承担不同职责：

- `baseOpacity` 来自应用当前 resting 或 hover 阴影 token。
- `ownershipMultiplier` 对唯一活动来源（snapshot 或 live）取 `1`，另一方取 `0`。
- `pageVisualOpacity` 跟随所属页面的 presentation。
- `shadowFactor` 在转场期间衰减单张部分可见卡片的阴影。

页面因子和卡片因子都需要：当页面主体仍然不透明时，页边卡片也可能只露出很小一部分。

## 渲染架构

### 独立阴影宿主与 `CALayer.shadowPath`

原生适配器可以使用透明的 `CALayer`，并用 `shadowPath` 描述圆角卡片轮廓。独立宿主为逻辑内容视口之外的模糊阴影留出空间。宿主只在自身扩展边界内裁切；卡片实体仍由原逻辑视口裁切。

`shadowPath` 只描述阴影源的几何形状，**不会绕过祖先裁切**。每个应用都必须检查宿主插入位置、祖先 mask 和 z-order。

### Visual bleed

`visualBleed` 是阴影宿主相对逻辑视口的外扩量。它只为阴影留出渲染空间，不得改变页面宽度、内容裁切、命中测试或分页距离。应根据目标平台、阴影模糊半径、偏移、backing scale 和宿主裁切实测选择。

### Snapshot/live 所有权

当 snapshot 与 live 内容重叠存在时，应由单一决策者为某个 identity 选出唯一阴影 owner。Snapshot 已准备好，并不自动意味着它当前可见；所有权应和真实呈现生命周期一致。

### 稳定 identity 与 layer 复用

平台 renderer 应按稳定 descriptor ID 复用 layer，只在尺寸或圆角变化时重建 path。逐帧更新位置时应避免隐式 Core Animation 动画。层缓存的保留与清理策略由宿主产品决定。

## 安装

在 Xcode 中使用 **File → Add Package Dependencies…**，输入：

```text
https://github.com/hoshinomio0919/MioShadowFlow.git
```

或者在 Swift Package manifest 中添加：

```swift
.package(url: "https://github.com/hoshinomio0919/MioShadowFlow.git", from: "0.1.0")
```

然后将 `MioShadowFlow` product 添加到使用参考核心的 target。Package 的最低目标平台是 macOS 13。

当前内容是独立的数学/参考核心。要在具体视图层级中绘制阴影，仍需自行实现并集成 SwiftUI/AppKit renderer。

## 使用示例

下面的函数只使用 Package 的公开 API，可在依赖本 Package 的 macOS Swift target 中编译：

```swift
import CoreGraphics
import MioShadowFlow

func calculateCardShadow() -> (ratio: Double, opacity: Double, hostFrame: CGRect) {
    let configuration = ShadowFlowConfiguration(
        visualBleed: 29,                 // 示例配置；请为自己的 UI 重新测量
        baseOpacity: 0.045,
        radius: 14,
        offset: CGSize(width: 0, height: 6),
        cornerRadius: 19,
        visibilityExponent: 8,
        minimumVisibleExtent: 0.5,
        axis: .horizontal
    )

    let viewport = CGRect(x: 0, y: 0, width: 1_004, height: 700)
    let card = CGRect(x: -55, y: 80, width: 185, height: 190)

    let ratio = VisibilityCalculation.visibleFraction(
        cardFrame: card,
        viewport: viewport,
        axis: configuration.axis,
        minimumVisibleExtent: configuration.minimumVisibleExtent
    )
    let shadowFactor = VisibilityCalculation.cardShadowFactor(
        cardFrame: card,
        viewport: viewport,
        configuration: configuration,
        transitionIsActive: true
    )

    let ownership = ShadowOwnership(
        transitionIsActive: true,
        snapshotPagesArePrepared: true
    )
    let pageOpacity = VisibilityCalculation.pageVisualOpacity(
        visibleExtent: 18,
        fade: EdgeFadeConfiguration(zeroOpacityExtent: 2, fullOpacityExtent: 24),
        transitionIsActive: true
    )
    let presentation = ShadowPresentationState(
        baseOpacity: configuration.baseOpacity,
        ownershipMultiplier: ownership.snapshotMultiplier,
        pageVisualOpacity: pageOpacity,
        cardVisibilityFactor: shadowFactor
    )

    let mapping = ShadowGeometryMapping(logicalViewport: viewport, bleed: configuration.visualBleed)
    let hostFrame = mapping.hostFrame
    let hostLocalCardFrame = mapping.hostLocalFrame(for: card)
    let descriptor = ShadowDescriptor(
        id: "card-42",
        hostLocalFrame: hostLocalCardFrame,
        opacity: presentation.effectiveOpacity,
        radius: configuration.radius,
        offset: configuration.offset,
        cornerRadius: configuration.cornerRadius
    )
    _ = descriptor // 将 descriptor 交给自己的 ShadowRenderer 适配器。

    return (ratio, presentation.effectiveOpacity, hostFrame)
}
```

这段代码只计算参数，不会绘制阴影。应用需要在每次 presentation 更新时传入当前卡片/视口 frame，并通过自己的 AppKit/Core Animation layer tree 实现 `ShadowRenderer`。

## 性能

- 按稳定 descriptor identity 复用 renderer layer，不要每个动画采样都分配新 layer。
- 使用当前分页/滚动 presentation 更新几何。这里的数学没有动画队列、计时器或固定延迟。
- 当位置已由 SwiftUI presentation 值驱动时，禁用 Core Animation 隐式 actions。
- 只在卡片尺寸或 corner radius 变化时重建圆角 shadow path。
- 将业务数据投影、图像加载/解码和 palette 分析放在逐帧渲染更新之外。
- 分别测量 renderer CPU 时间和 compositor 帧耗时。layer 更新很快，不等于整帧流畅。

## 限制

- macOS 是主要目标；Package 要求 macOS 13 或更高版本。
- 水平方向可见度衰减已经在真实 macOS 产品流程中使用过。
- 纵向和双轴模式目前只有纯数学测试。在真实 `ScrollView`、`NSClipView` 祖先或嵌套分页器中的行为尚未验证。
- 尚未包含完整原生 `CALayer` renderer、可直接使用的 SwiftUI component 或分页器。
- 不同卡片尺寸、模糊半径、偏移、backing scale、裁切和 z-order 都需要项目级调参与视觉检查。
- Package 测试通过不代表宿主应用已通过视觉验收。

## 路线图

以下是计划，不代表功能已完成：

- **v0.1 Reference Core** — 可见性数学、所有权 helper、几何映射、renderer protocol、测试和文档。
- **v0.2 Native Renderer** — 探索具有生命周期和裁切测试的可复用 AppKit/Core Animation adapter。
- **v0.3 SwiftUI Integration** — 探索用于几何和 descriptor 更新的聚焦 SwiftUI bridge。
- **v1.0 Stable API** — 在 renderer 集成及多项目验证后再考虑 API 稳定性。

## 许可证

Mio ShadowFlow 使用 [MIT License](LICENSE) 发布。
