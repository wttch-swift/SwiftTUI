# TerminalUIFoundation

`TerminalUIFoundation` 保存多个框架层都会使用、但不依赖 View 或渲染器的基础值类型。
它位于依赖图最底层，可同时被 Core、View、Layout、Render 和最终门面引用。

## 职责

- 描述布局提议和结果：`ProposedSize`、`Size`、`Offset`、`Rect`。
- 描述终端颜色：`Color`、`TerminalColorSupport` 及 ANSI 颜色降级。
- 描述边框字符风格：`BorderStyle`。
- 按扩展 grapheme cluster 拆分文本，并计算终端 cell 宽度。
- 在 cell 边界安全地截断字符串，避免显示半个宽字符。

本模块不负责 View、布局树、焦点、终端输入或实际绘制。

## Unicode 与单元格宽度

终端坐标使用字符单元格而不是 Swift 字符数量。`Segment.segment(_:)` 将文本拆成
可绘制片段，并通过 `cellLength` 区分零宽、单宽和双宽内容。它需要正确处理：

- ASCII 和普通拉丁字符；
- CJK 全角字符；
- Emoji 和 Emoji 序列；
- 基础字符后的组合标记；
- 换行、回车、制表符等终端控制字符。

布局和 Canvas 都应复用这里的测量结果，不能各自通过 `String.count` 推断宽度。
截断请使用 `Segment.truncate(_:to:)`，这样不会在双宽 grapheme 中间切开。

## 颜色模型

`Color` 支持 ANSI 基础色、256 色索引以及 RGB。`TerminalColorSupport` 表示终端的
颜色深度，并负责检测环境和生成匹配的前景、背景控制码。颜色能力不足时，RGB
会降级到当前终端可表达的近似颜色。

`TerminalUIView` 通过 typealias 重新提供这些类型，因此应用通常只需：

```swift
import TerminalUI

Text("状态正常")
    .foregroundColor(.rgb(34, 197, 94))
```

## 设计约束

- 保持无状态、可复用，不导入上层 target。
- 新类型应优先采用值语义，并在合理时遵循 `Sendable`、`Equatable`。
- 所有宽度单位都表示终端 cell，不表示 Unicode scalar、字节或像素。
- 修改字符分段和颜色编码时应同时补充 Foundation 与 Canvas 层测试。
