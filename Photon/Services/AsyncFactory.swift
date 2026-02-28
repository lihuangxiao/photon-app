import Foundation

/// Thread-safe lazy async factory for expensive initializations (like ML models)
/// From Apple's official MobileCLIP demo app
public actor AsyncFactory<T> {
    private enum State {
        case idle(() -> T)
        case initializing(Task<T, Never>)
        case initialized(T)
    }
    private var state: State

    public init(factory: @escaping () -> T) {
        self.state = .idle(factory)
    }

    public func get() async -> T {
        switch state {
        case .idle(let factory):
            let task = Task { factory() }
            self.state = .initializing(task)
            let value = await task.value
            self.state = .initialized(value)
            return value
        case .initializing(let task):
            return await task.value
        case .initialized(let v):
            return v
        }
    }
}
