#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package extension TerminalSignal {
    init?(signalNumber: Int32) {
        #if os(Windows)
        // Windows 会映射到控制台事件而不是 POSIX 信号编号,因此这里保留 nil。
        // 换言之:Windows 路径不会通过此构造函数做反向解码。
        return nil
        #else
        switch signalNumber {
        case SIGINT: self = .interrupt
        case SIGTERM: self = .terminate
        case SIGHUP: self = .hangup
        case SIGQUIT: self = .quit
        case SIGTSTP: self = .suspend
        case SIGCONT: self = .resume
        case SIGWINCH: self = .windowSizeChanged
        default: return nil
        }
        #endif
    }

    var signalNumber: Int32 {
        #if os(Windows)
        // Windows 不使用 integer signal number 语义,保守地返回 0。
        // 仅用于满足统一 API;Windows 实际发送路径不依赖该值。
        return 0
        #else
        switch self {
        case .interrupt: SIGINT
        case .terminate: SIGTERM
        case .hangup: SIGHUP
        case .quit: SIGQUIT
        case .suspend: SIGTSTP
        case .resume: SIGCONT
        case .windowSizeChanged: SIGWINCH
        }
        #endif
    }
}
