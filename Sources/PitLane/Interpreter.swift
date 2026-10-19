import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class Interpreter {
    private static let maxCallDepth = 1000
    private static let maxNesting = 128
    private static let maxSteps = 100_000_000
    /// Antes de que el supervisor corte a los 5 s, para informar la línea del bucle.
    private static let maxSeconds = 4.0
    private static let maxOutputBytes = 1_000_000
    private static let maxValueBytes = 1_000_000
    private static let maxAllocatedBytes = 64 * 1024 * 1024
    private static let maxResidentBytes = 256 * 1024 * 1024

    private let globals = Environment()
    private var callDepth = 0
    private var loopDepth = 0
    private var blockDepth = 0
    private var evalDepth = 0
    private var steps = 0
    private var outputBytes = 0
    private var allocatedBytes = 0
    private let startTime = ProcessInfo.processInfo.systemUptime

    init() {
        installBuiltins()
    }

    func run(_ program: Program) throws {
        _ = try execBlock(program.statements, Environment(parent: globals))
    }

    // MARK: - Sentencias

    private func execBlock(_ statements: Block, _ env: Environment) throws -> Completion {
        blockDepth += 1
        defer { blockDepth -= 1 }
        if blockDepth > Interpreter.maxNesting {
            throw RuntimeError(line: statements.first?.line ?? 1, "nesting limit exceeded")
        }
        try hoistDeclarations(statements, env)
        for statement in statements {
            let completion = try exec(statement, env)
            if case .normal = completion { continue }
            return completion
        }
        return .normal
    }

    /// Registra boxes y escuderia del bloque antes de ejecutarlo, para poder usarlos
    /// antes de su definición. Las variables (parrilla/pole) no se elevan.
    private func hoistDeclarations(_ statements: Block, _ env: Environment) throws {
        for statement in statements {
            switch statement.kind {
            case .function(let decl):
                try charge(128, line: statement.line)
                try env.declare(
                    decl.name, .function(Closure(decl: decl, env: env)), line: statement.line)
            case .classDecl(let decl):
                try charge(128 + decl.methods.count * 128, line: statement.line)
                var methods: [String: Closure] = [:]
                for method in decl.methods {
                    methods[method.name] = Closure(decl: method, env: env)
                }
                let cls = ClassDef(
                    name: decl.name, constructor: decl.constructor, methods: methods, env: env)
                try env.declare(decl.name, .classDef(cls), line: statement.line)
            default:
                break
            }
        }
    }

    private func exec(_ stmt: Stmt, _ env: Environment) throws -> Completion {
        let line = stmt.line
        try tick(line)
        switch stmt.kind {
        case .declaration(let isConstant, let name, let initial):
            var value = Value.none
            if let initial = initial { value = try eval(initial, env) }
            try env.declare(name, value, isConstant: isConstant, line: line)
            return .normal

        case .assignment(let target, let valueExpr):
            try assign(target, valueExpr, env, line: line)
            return .normal

        case .conditional(let branches, let elseBody):
            for branch in branches where try condition(branch.condition, env) {
                return try execBlock(branch.body, Environment(parent: env))
            }
            if let elseBody = elseBody {
                return try execBlock(elseBody, Environment(parent: env))
            }
            return .normal

        case .whileLoop(let cond, let body):
            loopDepth += 1
            defer { loopDepth -= 1 }
            while try condition(cond, env) {
                try tick(line)
                let completion = try execBlock(body, Environment(parent: env))
                switch completion {
                case .breakLoop: return .normal
                case .returnValue: return completion
                case .normal, .continueLoop: break
                }
            }
            return .normal

        case .forLoop(let variable, let fromExpr, let toExpr, let body):
            let fromValue = try eval(fromExpr, env)
            let toValue = try eval(toExpr, env)
            guard case .int(let from) = fromValue, case .int(let to) = toValue else {
                throw RuntimeError(line: line, "type error: loop bounds must be integers")
            }
            if from > to { return .normal }
            loopDepth += 1
            defer { loopDepth -= 1 }
            var i = from
            while true {
                try tick(line)
                let scope = Environment(parent: env)
                try scope.declare(variable, .int(i), line: line)
                let completion = try execBlock(body, scope)
                switch completion {
                case .breakLoop: return .normal
                case .returnValue: return completion
                case .normal, .continueLoop: break
                }
                if i == to { break }
                i += 1
            }
            return .normal

        case .breakStmt:
            guard loopDepth > 0 else { throw RuntimeError(line: line, "break outside loop") }
            return .breakLoop

        case .continueStmt:
            guard loopDepth > 0 else { throw RuntimeError(line: line, "continue outside loop") }
            return .continueLoop

        case .returnStmt(let valueExpr):
            guard callDepth > 0 else { throw RuntimeError(line: line, "return outside function") }
            var value = Value.none
            if let valueExpr = valueExpr { value = try eval(valueExpr, env) }
            return .returnValue(value)

        case .print(let expr):
            let result = try eval(expr, env)
            guard let value = displayLimited(result, maxBytes: Interpreter.maxOutputBytes - outputBytes - 1) else {
                throw RuntimeError(line: line, "output limit exceeded")
            }
            let bytes = value.utf8.count + 1
            outputBytes += bytes
            print(value)
            return .normal

        case .function, .classDecl:
            return .normal  // ya registradas por hoistDeclarations

        case .tryCatch(let body, let errorName, let handler, let finallyBlock):
            var result = Completion.normal
            var pending: Error?
            do {
                result = try execBlock(body, Environment(parent: env))
            } catch let thrown as RuntimeError {
                do {
                    let scope = Environment(parent: env)
                    try scope.declare(errorName, thrown.value, line: line)
                    result = try execBlock(handler, scope)
                } catch {
                    pending = error
                }
            }
            // podio siempre se ejecuta; si termina de forma abrupta, reemplaza lo pendiente.
            if let finallyBlock = finallyBlock {
                let completion = try execBlock(finallyBlock, Environment(parent: env))
                if case .normal = completion {} else {
                    result = completion
                    pending = nil
                }
            }
            if let pending = pending { throw pending }
            return result

        case .throwStmt(let expr):
            throw RuntimeError(value: try eval(expr, env), line: line)

        case .expression(let expr):
            _ = try eval(expr, env)
            return .normal
        }
    }

    private func condition(_ expr: Expr, _ env: Environment) throws -> Bool {
        guard case .bool(let b) = try eval(expr, env) else {
            throw RuntimeError(line: expr.line, "condition must be boolean")
        }
        return b
    }

    private func assign(_ target: Target, _ valueExpr: Expr, _ env: Environment, line: Int) throws {
        switch target {
        case .variable(let name):
            let value = try eval(valueExpr, env)
            try env.assign(name, value, line: line)
        case .index(let baseExpr, let indexExpr):
            let base = try eval(baseExpr, env)
            let index = try eval(indexExpr, env)
            let value = try eval(valueExpr, env)
            guard case .list(let list) = base else {
                throw RuntimeError(line: line, "type error: cannot index \(base.typeName)")
            }
            list.items[try listIndex(list, index, line: line)] = value
        case .member(let objectExpr, let name):
            let object = try eval(objectExpr, env)
            let value = try eval(valueExpr, env)
            guard case .object(let instance) = object else {
                throw RuntimeError(
                    line: line, "type error: cannot set attribute '\(name)' on \(object.typeName)")
            }
            if instance.attributes[name] == nil { try charge(64, line: line) }
            instance.attributes[name] = value
        }
    }

    private func listIndex(_ list: ListRef, _ index: Value, line: Int) throws -> Int {
        guard case .int(let i) = index, i >= 0, i < list.items.count else {
            throw RuntimeError(line: line, "index out of range")
        }
        return i
    }

    // MARK: - Expresiones

    private func eval(_ expr: Expr, _ env: Environment) throws -> Value {
        let line = expr.line
        try tick(line)
        evalDepth += 1
        defer { evalDepth -= 1 }
        if evalDepth > Interpreter.maxNesting {
            throw RuntimeError(line: line, "nesting limit exceeded")
        }
        switch expr.kind {
        case .int(let v): return .int(v)
        case .real(let v): return .real(v)
        case .string(let v): return .string(v)
        case .bool(let v): return .bool(v)

        case .variable(let name):
            guard let value = env.lookup(name) else {
                throw RuntimeError(line: line, "undeclared variable '\(name)'")
            }
            return value

        case .selfRef:
            guard let value = env.lookup("auto") else {
                throw RuntimeError(line: line, "'auto' used outside a method")
            }
            return value

        case .binary(let op, let leftExpr, let rightExpr):
            if op == .and || op == .or {
                return try evalLogical(op, leftExpr, rightExpr, env, line: line)
            }
            let left = try eval(leftExpr, env)
            let right = try eval(rightExpr, env)
            return try binary(op, left, right, line: line)

        case .unary(let op, let operandExpr):
            let operand = try eval(operandExpr, env)
            switch (op, operand) {
            case (.not, .bool(let b)): return .bool(!b)
            case (.neg, .int(let i)):
                let (result, overflow) = (0).subtractingReportingOverflow(i)
                if overflow { throw RuntimeError(line: line, "integer overflow") }
                return .int(result)
            case (.neg, .real(let d)): return .real(-d)
            default:
                throw RuntimeError(
                    line: line, "type error: cannot apply '\(op.rawValue)' to \(operand.typeName)")
            }

        case .call(let callee, let argExprs):
            return try evalCall(callee, argExprs, env, line: line)

        case .index(let baseExpr, let indexExpr):
            let base = try eval(baseExpr, env)
            let index = try eval(indexExpr, env)
            guard case .list(let list) = base else {
                throw RuntimeError(line: line, "type error: cannot index \(base.typeName)")
            }
            return list.items[try listIndex(list, index, line: line)]

        case .member(let objectExpr, let name):
            let object = try eval(objectExpr, env)
            guard case .object(let instance) = object else {
                throw RuntimeError(
                    line: line, "type error: cannot read attribute '\(name)' of \(object.typeName)")
            }
            guard let value = instance.attributes[name] else {
                throw RuntimeError(line: line, "undefined attribute '\(name)'")
            }
            return value

        case .list(let elementExprs):
            try charge(64 + elementExprs.count * 64, line: line)
            return .list(ListRef(try elementExprs.map { try eval($0, env) }))

        case .new(let className, let argExprs):
            guard case .classDef(let cls)? = env.lookup(className) else {
                throw RuntimeError(line: line, "undefined class '\(className)'")
            }
            let args = try argExprs.map { try eval($0, env) }
            try charge(128, line: line)
            let instance = Instance(cls: cls)
            if let ctor = cls.constructor {
                _ = try invoke(
                    params: ctor.params, body: ctor.body, parentEnv: cls.env,
                    selfObject: instance, args: args, line: line)
            } else if !args.isEmpty {
                throw RuntimeError(line: line, "expected 0 arguments but got \(args.count)")
            }
            return .object(instance)

        case .readLine:
            return try readInput(line: line)
        }
    }

    private func readInput(line: Int) throws -> Value {
        var bytes = Data()
        while true {
            let next = FileHandle.standardInput.readData(ofLength: 1)
            if next.isEmpty || next[0] == 10 { break }
            if bytes.count >= Interpreter.maxValueBytes {
                throw RuntimeError(line: line, "input line limit exceeded")
            }
            bytes.append(next)
        }
        if bytes.last == 13 { bytes.removeLast() }
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw RuntimeError(line: line, "invalid UTF-8 input")
        }
        try charge(value.utf8.count, line: line)
        return .string(value)
    }

    private func tick(_ line: Int) throws {
        steps += 1
        if steps > Interpreter.maxSteps {
            throw RuntimeError(line: line, "execution limit exceeded")
        }
        if steps % 256 == 0 {
            if ProcessInfo.processInfo.systemUptime - startTime > Interpreter.maxSeconds {
                throw RuntimeError(line: line, "execution limit exceeded")
            }
            var usage = rusage()
            #if os(Linux)
            let result = getrusage(RUSAGE_SELF.rawValue, &usage)
            #else
            let result = getrusage(RUSAGE_SELF, &usage)
            #endif
            if result == 0 {
                #if os(Linux)
                let residentBytes = Int(usage.ru_maxrss) * 1024
                #else
                let residentBytes = Int(usage.ru_maxrss)
                #endif
                if residentBytes > Interpreter.maxResidentBytes {
                    throw RuntimeError(line: line, "memory limit exceeded")
                }
            }
        }
    }

    private func charge(_ bytes: Int, line: Int) throws {
        if bytes > Interpreter.maxAllocatedBytes - allocatedBytes {
            throw RuntimeError(line: line, "memory limit exceeded")
        }
        allocatedBytes += bytes
    }

    private func evalLogical(
        _ op: BinaryOp, _ leftExpr: Expr, _ rightExpr: Expr, _ env: Environment, line: Int
    ) throws -> Value {
        let notBoolean = RuntimeError(
            line: line, "type error: operands of '\(op.rawValue)' must be boolean")
        guard case .bool(let left) = try eval(leftExpr, env) else { throw notBoolean }
        if op == .and && !left { return .bool(false) }
        if op == .or && left { return .bool(true) }
        guard case .bool(let right) = try eval(rightExpr, env) else { throw notBoolean }
        return .bool(right)
    }

    private func evalCall(
        _ callee: Expr, _ argExprs: [Expr], _ env: Environment, line: Int
    ) throws -> Value {
        // objeto.metodo(args): auto = objeto
        if case .member(let objectExpr, let name) = callee.kind {
            let object = try eval(objectExpr, env)
            let args = try argExprs.map { try eval($0, env) }
            guard case .object(let instance) = object else {
                throw RuntimeError(
                    line: line, "type error: cannot call method '\(name)' on \(object.typeName)")
            }
            guard let method = instance.cls.methods[name] else {
                throw RuntimeError(line: line, "undefined method '\(name)'")
            }
            return try invoke(
                params: method.decl.params, body: method.decl.body, parentEnv: method.env,
                selfObject: instance, args: args, line: line)
        }

        let calleeValue = try eval(callee, env)
        let args = try argExprs.map { try eval($0, env) }
        switch calleeValue {
        case .function(let closure):
            return try invoke(
                params: closure.decl.params, body: closure.decl.body, parentEnv: closure.env,
                selfObject: nil, args: args, line: line)
        case .builtin(let builtin):
            guard args.count == builtin.arity else {
                throw RuntimeError(
                    line: line, "expected \(builtin.arity) arguments but got \(args.count)")
            }
            if builtin.name == "agregar" { try charge(64, line: line) }
            let result = try builtin.body(args, line)
            if case .string(let value) = result { try charge(value.utf8.count, line: line) }
            return result
        default:
            throw RuntimeError(line: line, "not callable")
        }
    }

    private func invoke(
        params: [String], body: Block, parentEnv: Environment, selfObject: Instance?,
        args: [Value], line: Int
    ) throws -> Value {
        guard args.count == params.count else {
            throw RuntimeError(line: line, "expected \(params.count) arguments but got \(args.count)")
        }
        // El límite de anidamiento es por función; la recursión la limita maxCallDepth.
        callDepth += 1
        let savedLoopDepth = loopDepth
        let savedBlockDepth = blockDepth
        let savedEvalDepth = evalDepth
        loopDepth = 0
        blockDepth = 0
        evalDepth = 0
        defer {
            callDepth -= 1
            loopDepth = savedLoopDepth
            blockDepth = savedBlockDepth
            evalDepth = savedEvalDepth
        }
        guard callDepth <= Interpreter.maxCallDepth else {
            throw RuntimeError(line: line, "stack overflow")
        }
        let scope = Environment(parent: parentEnv)
        if let selfObject = selfObject {
            try scope.declare("auto", .object(selfObject), line: line)
        }
        for (param, arg) in zip(params, args) {
            try scope.declare(param, arg, line: line)
        }
        if case .returnValue(let value) = try execBlock(body, scope) { return value }
        return .none
    }

    // MARK: - Operadores binarios

    private func binary(_ op: BinaryOp, _ left: Value, _ right: Value, line: Int) throws -> Value {
        switch op {
        case .add:
            if case .string = left { return try concat(left, right, line: line) }
            if case .string = right { return try concat(left, right, line: line) }
            return try arithmetic(op, left, right, line: line)
        case .sub, .mul, .div, .mod:
            return try arithmetic(op, left, right, line: line)
        case .gt, .lt, .ge, .le:
            return try compare(op, left, right, line: line)
        case .eq, .ne:
            guard let equal = valuesEqual(left, right) else {
                throw RuntimeError(line: line, "comparison limit exceeded")
            }
            return .bool(op == .eq ? equal : !equal)
        case .and, .or:
            preconditionFailure("aliado/rival se evalúan con cortocircuito en evalLogical")
        }
    }

    private func concat(_ left: Value, _ right: Value, line: Int) throws -> Value {
        guard let a = displayLimited(left, maxBytes: Interpreter.maxValueBytes),
              let b = displayLimited(right, maxBytes: Interpreter.maxValueBytes) else {
            throw RuntimeError(line: line, "text limit exceeded")
        }
        if a.utf8.count > Interpreter.maxValueBytes - b.utf8.count {
            throw RuntimeError(line: line, "text limit exceeded")
        }
        try charge(a.utf8.count + b.utf8.count, line: line)
        return .string(a + b)
    }

    private func real(_ result: Double, line: Int) throws -> Value {
        guard result.isFinite else { throw RuntimeError(line: line, "real out of range") }
        return .real(result)
    }

    private func typeError(_ op: BinaryOp, _ left: Value, _ right: Value, line: Int) -> RuntimeError {
        RuntimeError(
            line: line,
            "type error: cannot apply '\(op.rawValue)' to \(left.typeName) and \(right.typeName)")
    }

    private func checked(_ result: (partialValue: Int, overflow: Bool), line: Int) throws -> Value {
        if result.overflow { throw RuntimeError(line: line, "integer overflow") }
        return .int(result.partialValue)
    }

    private func toDouble(_ value: Value) -> Double? {
        switch value {
        case .int(let i): return Double(i)
        case .real(let d): return d
        default: return nil
        }
    }

    private func arithmetic(_ op: BinaryOp, _ left: Value, _ right: Value, line: Int) throws -> Value {
        if case .int(let a) = left, case .int(let b) = right {
            switch op {
            case .add: return try checked(a.addingReportingOverflow(b), line: line)
            case .sub: return try checked(a.subtractingReportingOverflow(b), line: line)
            case .mul: return try checked(a.multipliedReportingOverflow(by: b), line: line)
            case .div:
                if b == 0 { throw RuntimeError(line: line, "division by zero") }
                return try checked(a.dividedReportingOverflow(by: b), line: line)
            case .mod:
                if b == 0 { throw RuntimeError(line: line, "division by zero") }
                return .int(a.remainderReportingOverflow(dividingBy: b).partialValue)
            default: preconditionFailure("operador no aritmético")
            }
        }
        if op == .mod {
            throw RuntimeError(line: line, "type error: '%' requires integers")
        }
        guard let a = toDouble(left), let b = toDouble(right) else {
            throw typeError(op, left, right, line: line)
        }
        switch op {
        case .add: return try real(a + b, line: line)
        case .sub: return try real(a - b, line: line)
        case .mul: return try real(a * b, line: line)
        case .div:
            if b == 0 { throw RuntimeError(line: line, "division by zero") }
            return try real(a / b, line: line)
        default: preconditionFailure("operador no aritmético")
        }
    }

    private func compare(_ op: BinaryOp, _ left: Value, _ right: Value, line: Int) throws -> Value {
        func test<T: Comparable>(_ a: T, _ b: T) -> Value {
            switch op {
            case .gt: return .bool(a > b)
            case .lt: return .bool(a < b)
            case .ge: return .bool(a >= b)
            default: return .bool(a <= b)
            }
        }
        switch (left, right) {
        case let (.int(a), .int(b)): return test(a, b)
        case let (.string(a), .string(b)): return test(a, b)
        default:
            guard let a = toDouble(left), let b = toDouble(right) else {
                throw typeError(op, left, right, line: line)
            }
            return test(a, b)
        }
    }

    // MARK: - Funciones predefinidas

    private func installBuiltins() {
        func define(_ name: String, _ arity: Int, _ body: @escaping ([Value], Int) throws -> Value) {
            let builtin = Builtin(name: name, arity: arity, body: body)
            try? globals.declare(name, .builtin(builtin), isConstant: true, line: 0)
        }

        define("longitud", 1) { args, line in
            switch args[0] {
            case .list(let list): return .int(list.items.count)
            case .string(let s): return .int(s.count)
            default:
                throw RuntimeError(
                    line: line, "type error: longitud expects a list or text, got \(args[0].typeName)")
            }
        }

        define("agregar", 2) { args, line in
            guard case .list(let list) = args[0] else {
                throw RuntimeError(
                    line: line, "type error: agregar expects a list, got \(args[0].typeName)")
            }
            list.items.append(args[1])
            return .none
        }

        define("a_entero", 1) { args, line in
            switch args[0] {
            case .int: return args[0]
            case .real(let d):
                guard let i = Int(exactly: d.rounded(.towardZero)) else {
                    throw RuntimeError(line: line, "invalid integer '\(display(args[0]))'")
                }
                return .int(i)
            case .string(let s):
                guard let i = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw RuntimeError(line: line, "invalid integer '\(s)'")
                }
                return .int(i)
            default:
                throw RuntimeError(
                    line: line, "type error: cannot convert \(args[0].typeName) to integer")
            }
        }

        define("a_real", 1) { args, line in
            switch args[0] {
            case .int(let i): return .real(Double(i))
            case .real: return args[0]
            case .string(let s):
                let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
                let significand = text.split(whereSeparator: { $0 == "e" || $0 == "E" }).first ?? ""
                let hasNonzeroDigit = significand.contains(where: { $0 >= "1" && $0 <= "9" })
                guard let d = Double(text), d.isFinite, d != 0 || !hasNonzeroDigit else {
                    throw RuntimeError(line: line, "invalid real '\(s)'")
                }
                return .real(d)
            default:
                throw RuntimeError(
                    line: line, "type error: cannot convert \(args[0].typeName) to real")
            }
        }

        define("a_texto", 1) { args, line in
            guard let text = displayLimited(args[0], maxBytes: Interpreter.maxValueBytes) else {
                throw RuntimeError(line: line, "text limit exceeded")
            }
            return .string(text)
        }
    }
}
