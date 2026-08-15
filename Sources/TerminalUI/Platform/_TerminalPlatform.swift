/// 平台后端统一协议:一个 backend 同时负责输入、信号、输出准备与尺寸读取。
///
/// 生命周期约定:
/// - `startInput` / `stopInput`:进入/退出原始输入模式,`stopInput` 幂等;
/// - `startSignals` / `stopSignals`:注册/释放信号处理器,两者均幂等;
/// - `prepareOutput` / `restoreOutput`:进入终端屏幕前的控制台输出准备,
///   `restoreOutput` 幂等;
/// - `currentSize` 是静态纯函数,可在一个实例都不存在时被调用(`TerminalSizeReader`
///   在宿主创建前使用它)。
protocol _TerminalPlatformBackend {
    // MARK: - 尺寸读取(静态、无状态)

    static func currentSize(fileDescriptor: Int32?) -> TerminalSize?

    // MARK: - 输入(原始模式)

    func startInput() throws
    func stopInput()
    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress?

    // MARK: - 信号

    func startSignals(handler: @escaping @Sendable (TerminalSignal) -> Void)
    func stopSignals()
    func suspendCurrentProcess()

    // MARK: - 输出(Windows VT 准备)

    func prepareOutput()
    func restoreOutput()
}

/// 共享平台门面:外部代码只认识一个统一的 `_TerminalPlatform`,真正的平台实现被拆到
/// `_TerminalPlatformUnix` / `_TerminalPlatformWindows`,避免跨平台条件编译把输入、
/// 信号、尺寸与输出的逻辑混在一处。
///
/// 设计约束:
/// - 上层(例如 `TerminalApp`)不允许依赖 WinSDK / POSIX 头;
/// - 平台差异必须收敛在 `_TerminalPlatformBackend` 实现中;
/// - 新平台接入时,只增加一个 backend 文件和一个 `#if` 分支即可。
final class _TerminalPlatform {
    private let backend: any _TerminalPlatformBackend

    init() {
        #if os(Windows)
        self.backend = _TerminalPlatformWindows()
        #elseif canImport(Darwin) || canImport(Glibc)
        self.backend = _TerminalPlatformUnix()
        #else
        self.backend = _TerminalPlatformNoop()
        #endif
    }

    /// 读取终端尺寸。尺寸读取是无状态纯函数,且需要在任何宿主实例存在前被调用
    /// (`TerminalApp.main()` 与 demo 的 init 都会先读尺寸),因此这里静态选择具体
    /// 平台实现,而不是创建一次性实例。静态协议要求不能通过 `any` existential
    /// 调用,所以直接用具体类型。
    static func currentSize(fileDescriptor: Int32? = nil) -> TerminalSize? {
        #if os(Windows)
        return _TerminalPlatformWindows.currentSize(fileDescriptor: fileDescriptor)
        #elseif canImport(Darwin) || canImport(Glibc)
        return _TerminalPlatformUnix.currentSize(fileDescriptor: fileDescriptor)
        #else
        return _TerminalPlatformNoop.currentSize(fileDescriptor: fileDescriptor)
        #endif
    }

    // MARK: - 输入

    func startInput() throws {
        try backend.startInput()
    }

    func stopInput() {
        backend.stopInput()
    }

    /// 等待至多 timeoutMilliseconds;超时返回 nil。
    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress? {
        try backend.readKey(timeoutMilliseconds: timeoutMilliseconds)
    }

    // MARK: - 信号

    func startSignals(handler: @escaping @Sendable (TerminalSignal) -> Void) {
        backend.startSignals(handler: handler)
    }

    func stopSignals() {
        backend.stopSignals()
    }

    func suspendCurrentProcess() {
        backend.suspendCurrentProcess()
    }

    // MARK: - 输出

    func prepareOutput() {
        backend.prepareOutput()
    }

    func restoreOutput() {
        backend.restoreOutput()
    }

    deinit {
        // 与旧版各 facade 的 deinit 对齐;各 stop 幂等,run() 的 defer 已调用过时安全。
        stopInput()
        stopSignals()
        restoreOutput()
    }
}

/// 最坏情况下的降级实现:不支持终端能力时全部静默空操作,尺寸读取返回 nil。
private struct _TerminalPlatformNoop: _TerminalPlatformBackend {
    static func currentSize(fileDescriptor: Int32?) -> TerminalSize? { nil }
    func startInput() throws {}
    func stopInput() {}
    func readKey(timeoutMilliseconds: Int32) throws -> KeyPress? { nil }
    func startSignals(handler: @escaping @Sendable (TerminalSignal) -> Void) {}
    func stopSignals() {}
    func suspendCurrentProcess() {}
    func prepareOutput() {}
    func restoreOutput() {}
}
