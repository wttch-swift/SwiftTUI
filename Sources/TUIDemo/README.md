# TUIDemo 示例

`TUIDemo` 是 TerminalUI 的完整交互示例，不是框架内部实现。它只依赖最终
`TerminalUI` product，用来验证真实客户端无需导入 Layout、Render 或 Core。

## 运行

```bash
swift run TUIDemo
```

建议在支持 ANSI 颜色和 UTF-8 的交互终端中运行。程序读取当前终端大小；读取失败
时使用 108 x 32 的回退画布。

## 展示内容

示例采用观测站界面，包含四个标签页：

- 概览：GeometryReader、GroupBox、ProgressBar 和响应式宽窄布局。
- 动态：Table、宽字符文本、状态色和滚动内容。
- 设置：Toggle、TextField、Binding 和 FocusState。
- 智能对话：聊天记录、输入框、焦点切换和滚动窗口。

根视图还演示统一背景、全局按键、sheet、toast、状态刷新和文本装饰。布局全部使用
TerminalUI 的声明式 API，没有直接创建 `_LayoutNode` 或 Canvas。

## 作为客户端参考

入口遵循推荐宿主结构：

1. 用 `TerminalSizeReader` 获取 cell 尺寸。
2. 用 `TerminalApp(width:height:content:)` 创建根界面。
3. 在交互终端调用 `run()`。
4. 捕获输入错误并给出适当退化行为。

示例中的数据模型仅用于展示，不属于 TerminalUI API。新增框架功能时，可以先在此
模块增加一个真实使用场景，再在测试 target 中补充小尺寸和边界断言。

## 维护约束

- 本模块应始终只 `import TerminalUI`。
- 不使用 `@testable`，不引用 package 级实现。
- 示例文案需要考虑窄终端和 CJK 双宽字符。
- 新交互应提供明确焦点反馈，并确保 Esc 可以离开文本输入状态。

