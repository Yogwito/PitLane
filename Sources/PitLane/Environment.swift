final class Environment {
    private struct Binding {
        var value: Value
        let isConstant: Bool
    }

    private var bindings: [String: Binding] = [:]
    let parent: Environment?

    init(parent: Environment? = nil) {
        self.parent = parent
    }

    func declare(_ name: String, _ value: Value, isConstant: Bool = false, line: Int) throws {
        guard bindings[name] == nil else {
            throw RuntimeError(line: line, "'\(name)' already declared")
        }
        bindings[name] = Binding(value: value, isConstant: isConstant)
    }

    func lookup(_ name: String) -> Value? {
        var env: Environment? = self
        while let e = env {
            if let b = e.bindings[name] { return b.value }
            env = e.parent
        }
        return nil
    }

    func assign(_ name: String, _ value: Value, line: Int) throws {
        var env: Environment? = self
        while let e = env {
            if let b = e.bindings[name] {
                if b.isConstant {
                    throw RuntimeError(line: line, "cannot assign to constant '\(name)'")
                }
                e.bindings[name] = Binding(value: value, isConstant: false)
                return
            }
            env = e.parent
        }
        throw RuntimeError(line: line, "undeclared variable '\(name)'")
    }
}
