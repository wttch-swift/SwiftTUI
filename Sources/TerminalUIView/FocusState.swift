/// 以声明式值描述当前焦点，API 语义与 SwiftUI `FocusState` 对齐。
@propertyWrapper
public final class FocusState<Value: Hashable> {
    public struct Binding {
        private let getter: () -> Value
        private let setter: (Value) -> Void

        fileprivate init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
            getter = get
            setter = set
        }

        public var wrappedValue: Value {
            get { getter() }
            nonmutating set { setter(newValue) }
        }
    }

    private let storage: State<Value>

    public var wrappedValue: Value {
        get { storage.wrappedValue }
        set {
            guard storage.wrappedValue != newValue else { return }
            storage.wrappedValue = newValue
        }
    }

    public var projectedValue: Binding {
        Binding(
            get: { [self] in wrappedValue },
            set: { [self] in wrappedValue = $0 }
        )
    }

    public init(wrappedValue: Value) {
        storage = State(wrappedValue: wrappedValue)
    }

    public convenience init() where Value == Bool {
        self.init(wrappedValue: false)
    }

    public convenience init<Wrapped: Hashable>() where Value == Wrapped? {
        self.init(wrappedValue: nil)
    }
}

package struct _FocusedView<Content: View>: View, _NeverView {
    public typealias Body = Never

    package let content: Content
    package let requestsFocus: () -> Bool
    package let updateFocus: (Bool) -> Void
}

public extension View {
    func focused(_ binding: FocusState<Bool>.Binding) -> some View {
        _FocusedView(
            content: self,
            requestsFocus: { binding.wrappedValue },
            updateFocus: { binding.wrappedValue = $0 }
        )
    }

    func focused<Field: Hashable>(
        _ binding: FocusState<Field?>.Binding,
        equals value: Field
    ) -> some View {
        _FocusedView(
            content: self,
            requestsFocus: { binding.wrappedValue == value },
            updateFocus: { focused in
                if focused {
                    binding.wrappedValue = value
                } else if binding.wrappedValue == value {
                    binding.wrappedValue = nil
                }
            }
        )
    }
}
