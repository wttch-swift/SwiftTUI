# TerminalUI

`TerminalUI` 是 package 唯一发布的 library product，也是应用应导入的最终 API。
它通过 `@_exported import TerminalUIView` 提供全部声明式 View，并用 `TerminalApp`
连接输入、状态、布局、渲染和终端输出。

客户端不需要也不应导入 Core、Layout 或 Render。

## 公共入口

### TerminalApp

`TerminalApp` 使用固定 cell 宽高托管一个根 View：

```swift
let app = TerminalApp(width: 80, height: 24) {
    VStack {
        Text("Hello")
        Spacer()
        Text("Press q to quit")
    }
}

try app.run()
```

`run(clearScreen:)` 配置终端输入模式，启动事件循环，并在退出时恢复自动换行和光标。
默认使用全屏清理和绝对行重绘；传入 `false` 可在非全屏情形输出帧内容。

`render()` 和 `send(_:)` 是 package 级测试与 demo 接口。外部应用通过 `run()` 工作，
不会获得 Canvas 或布局树。

### TerminalSizeReader

终端大小可能读取失败，因此推荐提供回退值：

```swift
let size = TerminalSizeReader.current(
    or: TerminalSize(columns: 100, rows: 30)
)
```

`TerminalSize.width/height` 分别是 columns/rows 的便捷别名。

## 事件循环

每一轮循环会在需要时重建 View 和布局树，然后：

- 迁移 TextField、ScrollView、TabView 等交互状态；
- 根据 `FocusState` 同步焦点；
- 布局并渲染 Canvas；
- 与上一帧比较，只输出变化的终端行；
- 以约 16 ms 的超时读取按键和后台动画事件。

按键处理优先级包括宿主级 Tab 焦点导航、TabView 左右切换、当前焦点控件处理，
最后才是普通 `onKeyPress` 从子树向外冒泡。Esc 会让当前输入控件失焦。

状态修改、动画帧和显式 action 通过 `TerminalStateRuntime` 唤醒事件循环。
`TerminalStateRuntime.stop()` 可请求应用正常退出。

## 信号处理

TerminalUI 会观察与终端生命周期相关的 POSIX 信号：

| 信号 | TerminalSignal | 默认处理 |
| --- | --- | --- |
| `SIGINT` | `.interrupt` | 恢复终端并结束 `run()` |
| `SIGTERM` | `.terminate` | 恢复终端并结束 `run()` |
| `SIGHUP` | `.hangup` | 恢复终端并结束 `run()` |
| `SIGQUIT` | `.quit` | 恢复终端并结束 `run()` |
| `SIGTSTP` | `.suspend` | 恢复 termios 和屏幕模式后挂起进程 |
| `SIGCONT` | `.resume` | 重新进入 raw mode、读取尺寸并完整重绘 |
| `SIGWINCH` | `.windowSizeChanged` | 更新画布行列数并完整重绘 |

应用可以通过公开接口观察信号：

```swift
let app = TerminalApp(width: size.width, height: size.height) {
    RootView()
}
.onSignal { signal in
    if signal == .windowSizeChanged {
        // 回调已位于 TerminalApp 主事件循环，可以更新普通 UI 状态。
    }
}

try app.run()
```

信号回调是观察接口，不会取代框架的终端清理。即使应用注册回调，Ctrl-Z 仍会先
恢复终端再挂起，终止信号也仍会让 `run()` 正常退出。

实现位置：

- `Input/TerminalSignalCoordinator.swift`：公开 `TerminalSignal`，安装 Dispatch signal
  source，保存和恢复原进程 signal disposition，并执行真正的 `SIGTSTP`。
- `TerminalApp.swift` 的 `run()`：在主事件循环消费信号，负责退出、挂起、恢复、
  更新尺寸和请求完整重绘。
- `Input/TerminalInput.swift`：保存、进入和恢复 POSIX termios 模式。

原始 Dispatch signal handler 只向线程安全事件队列投递值，不直接修改 View、Canvas
或 termios。这样应用回调不需要遵守 async-signal-safe 限制。

## 模块门面

`ModuleExports.swift` 只公开重新导出的 View API。Canvas 仅有 package typealias，
用于 TerminalApp 和同 package 测试连接 Core；LayoutNode 和 Render 同样保持 package
访问级别。

这种门面设计让未来可以替换布局或渲染实现，而不改变应用中的 View 声明。

## 错误处理

`run()` 可能抛出 `TerminalInputError.notTerminal`，例如标准输入不是 TTY。交互应用
可提示用户在终端运行；package 内示例也可以在该情况下渲染单帧用于快照输出。

应用退出和抛错路径都应保证恢复终端模式。不要绕过 TerminalApp 直接操作 termios
或从 View body 执行阻塞 I/O。
