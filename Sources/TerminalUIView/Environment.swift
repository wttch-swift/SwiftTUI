

/// 定义了一个环境变量的属性包装器，用于在视图中访问环境值。
@propertyWrapper
struct Environment<Value> {

    /// 关联的环境键路径，用于获取环境值。
    let keyPath: KeyPath<EnvironmentValues, Value>
    /// 存储环境值的私有变量。
    private var value: Value!

    /// 包裹的值，返回当前环境值。
    var wrappedValue: Value {
        get { value }
    }
}

