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
    displayLimited(value, maxBytes: 1_000_000, quoted: quoted) ?? "<value too large>"
}

func displayLimited(_ value: Value, maxBytes: Int, quoted: Bool = false) -> String? {
    var active: Set<ObjectIdentifier> = []
    var remaining = maxBytes
    var result = ""
    guard appendDisplay(value, quoted: quoted, active: &active, depth: 0,
                        remaining: &remaining, result: &result) else { return nil }
    return result
}

private func appendDisplay(_ value: Value, quoted: Bool, active: inout Set<ObjectIdentifier>,
                           depth: Int, remaining: inout Int, result: inout String) -> Bool {
    func append(_ text: String) -> Bool {
        let count = text.utf8.count
        if count > remaining { return false }
        remaining -= count
        result.append(text)
        return true
    }
    switch value {
    case .int(let i): return append(String(i))
    case .real(let d): return append(String(d))
    case .string(let s):
        if !quoted { return append(s) }
        return append("\"") && append(s) && append("\"")
    case .bool(let b): return append(b ? "gana" : "pierde")
    case .list(let l):
        let id = ObjectIdentifier(l)
        if active.contains(id) { return append("[<cycle>]") }
        if depth >= 128 { return append("[<depth limit>]") }
        active.insert(id)
        defer { active.remove(id) }
        if !append("[") { return false }
        for (index, item) in l.items.enumerated() {
            if index > 0 && !append(", ") { return false }
            if !appendDisplay(item, quoted: true, active: &active, depth: depth + 1,
                              remaining: &remaining, result: &result) { return false }
        }
        return append("]")
    case .object(let o): return append("<\(o.cls.name)>")
    case .function(let f): return append("<function \(f.decl.name)>")
    case .builtin(let b): return append("<function \(b.name)>")
    case .classDef(let c): return append("<class \(c.name)>")
    case .none: return append("nada")
    }
}

/// empata/distinto: entero y real se comparan numéricamente, listas por contenido, objetos por identidad.
private struct ListPair: Hashable {
    let left: ObjectIdentifier
    let right: ObjectIdentifier
}

func valuesEqual(_ a: Value, _ b: Value) -> Bool? {
    var pending: [(Value, Value)] = [(a, b)]
    var seen: Set<ListPair> = []
    var comparisons = 0
    while let (left, right) = pending.popLast() {
        comparisons += 1
        if comparisons > 1_000_000 { return nil }
        switch (left, right) {
        case let (.int(x), .int(y)): if x != y { return false }
        case let (.real(x), .real(y)): if x != y { return false }
        case let (.int(x), .real(y)): if Double(x) != y { return false }
        case let (.real(x), .int(y)): if x != Double(y) { return false }
        case let (.string(x), .string(y)): if x != y { return false }
        case let (.bool(x), .bool(y)): if x != y { return false }
        case let (.list(x), .list(y)):
            if x === y { continue }
            if x.items.count != y.items.count { return false }
            let pair = ListPair(left: ObjectIdentifier(x), right: ObjectIdentifier(y))
            if seen.insert(pair).inserted { pending.append(contentsOf: zip(x.items, y.items)) }
        case let (.object(x), .object(y)): if x !== y { return false }
        case let (.function(x), .function(y)): if x !== y { return false }
        case let (.classDef(x), .classDef(y)): if x !== y { return false }
        case let (.builtin(x), .builtin(y)): if x !== y { return false }
        case (.none, .none): break
        default: return false
        }
    }
    return true
}
