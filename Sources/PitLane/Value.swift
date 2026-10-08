final class ListRef {
    var items: [Value]
    init(_ items: [Value]) { self.items = items }
}

final class Closure {
    let decl: FunctionDecl
    let env: Environment
    init(decl: FunctionDecl, env: Environment) {
        self.decl = decl
        self.env = env
    }
}

final class ClassDef {
    let name: String
    let constructor: ConstructorDecl?
    let methods: [String: Closure]
    let env: Environment
    init(name: String, constructor: ConstructorDecl?, methods: [String: Closure], env: Environment) {
        self.name = name
        self.constructor = constructor
        self.methods = methods
        self.env = env
    }
}

final class Instance {
    let cls: ClassDef
    var attributes: [String: Value] = [:]
    init(cls: ClassDef) { self.cls = cls }
}

final class Builtin {
    let name: String
    let arity: Int
    let body: (_ args: [Value], _ line: Int) throws -> Value
    init(name: String, arity: Int, body: @escaping (_ args: [Value], _ line: Int) throws -> Value) {
        self.name = name
        self.arity = arity
        self.body = body
    }
}

enum Value {
    case int(Int)
    case real(Double)
    case string(String)
    case bool(Bool)
    case list(ListRef)
    case object(Instance)
    case function(Closure)
    case classDef(ClassDef)
    case builtin(Builtin)
    case none

    var typeName: String {
        switch self {
        case .int: return "integer"
        case .real: return "real"
        case .string: return "text"
        case .bool: return "boolean"
        case .list: return "list"
        case .object: return "object"
        case .function, .builtin: return "function"
        case .classDef: return "class"
        case .none: return "nothing"
        }
    }
}

/// Reglas de impresión del lenguaje. `quoted` pone comillas a los textos (dentro de listas).
func display(_ value: Value, quoted: Bool = false) -> String {
    switch value {
    case .int(let i): return String(i)
    case .real(let d): return String(d)
    case .string(let s): return quoted ? "\"\(s)\"" : s
    case .bool(let b): return b ? "gana" : "pierde"
    case .list(let l): return "[" + l.items.map { display($0, quoted: true) }.joined(separator: ", ") + "]"
    case .object(let o): return "<\(o.cls.name)>"
    case .function(let f): return "<function \(f.decl.name)>"
    case .builtin(let b): return "<function \(b.name)>"
    case .classDef(let c): return "<class \(c.name)>"
    case .none: return "nada"
    }
}

/// empata/distinto: entero y real se comparan numéricamente, listas por contenido, objetos por identidad.
func valuesEqual(_ a: Value, _ b: Value) -> Bool {
    switch (a, b) {
    case let (.int(x), .int(y)): return x == y
    case let (.real(x), .real(y)): return x == y
    case let (.int(x), .real(y)): return Double(x) == y
    case let (.real(x), .int(y)): return x == Double(y)
    case let (.string(x), .string(y)): return x == y
    case let (.bool(x), .bool(y)): return x == y
    case let (.list(x), .list(y)):
        return x === y
            || (x.items.count == y.items.count
                && zip(x.items, y.items).allSatisfy { valuesEqual($0, $1) })
    case let (.object(x), .object(y)): return x === y
    case let (.function(x), .function(y)): return x === y
    case let (.classDef(x), .classDef(y)): return x === y
    case let (.builtin(x), .builtin(y)): return x === y
    case (.none, .none): return true
    default: return false
    }
}
