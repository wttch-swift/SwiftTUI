import Dispatch
import TerminalUIFoundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

package extension TerminalSignal {
    init?(signalNumber: Int32) {
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
    }

    var signalNumber: Int32 {
        switch self {
        case .interrupt: SIGINT
        case .terminate: SIGTERM
        case .hangup: SIGHUP
        case .quit: SIGQUIT
        case .suspend: SIGTSTP
        case .resume: SIGCONT
        case .windowSizeChanged: SIGWINCH
        }
    }
}

#if canImport(Darwin)
private typealias _PlatformSignalHandler = sig_t?

private func _installSignalHandler(
    _ signalNumber: Int32,
    _ handler: _PlatformSignalHandler
) -> _PlatformSignalHandler {
    Darwin.signal(signalNumber, handler)
}

private func _raiseSignal(_ signalNumber: Int32) {
    _ = Darwin.raise(signalNumber)
}
#elseif canImport(Glibc)
private typealias _PlatformSignalHandler = sighandler_t?

private func _installSignalHandler(
    _ signalNumber: Int32,
    _ handler: _PlatformSignalHandler
) -> _PlatformSignalHandler {
    Glibc.signal(signalNumber, handler)
}

private func _raiseSignal(_ signalNumber: Int32) {
    _ = Glibc.raise(signalNumber)
}
#endif

private struct _PreviousSignalHandler {
    // SIG_DFL can be represented by nil, so wrap it in a struct before storing it
    // in a Dictionary; assigning nil directly would remove the dictionary entry.
    let value: _PlatformSignalHandler
}

/// Converts process-wide POSIX signals into serial Dispatch events.
///
/// DispatchSource requires the observed signal to be ignored at the POSIX layer.
/// The previous disposition is retained and restored when TerminalApp.run exits,
/// so running an app does not permanently alter the embedding process.
final class _TerminalSignalCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TerminalUI.signals")
    private var sources: [any DispatchSourceSignal] = []
    private var previousHandlers: [Int32: _PreviousSignalHandler] = [:]

    func start(handler: @escaping @Sendable (TerminalSignal) -> Void) {
        guard sources.isEmpty else { return }

        for terminalSignal in Self.observedSignals {
            let number = terminalSignal.signalNumber
            let previous = _installSignalHandler(number, SIG_IGN)
            previousHandlers[number] = _PreviousSignalHandler(value: previous)

            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                handler(terminalSignal)
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()

        for (number, previous) in previousHandlers {
            _ = _installSignalHandler(number, previous.value)
        }
        previousHandlers.removeAll()
    }

    /// Temporarily restores SIGTSTP's default disposition and actually suspends
    /// the process. Execution continues after this call when the shell sends
    /// SIGCONT (for example through `fg`).
    func suspendCurrentProcess() {
        _ = _installSignalHandler(SIGTSTP, SIG_DFL)
        _raiseSignal(SIGTSTP)
        _ = _installSignalHandler(SIGTSTP, SIG_IGN)
    }

    deinit {
        stop()
    }

    private static let observedSignals: [TerminalSignal] = [
        .interrupt,
        .terminate,
        .hangup,
        .quit,
        .suspend,
        .resume,
        .windowSizeChanged,
    ]
}
