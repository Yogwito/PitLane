import Foundation

final class Interpreter {
    private static let maxCallDepth = 1000

    private let globals = Environment()
    private var callDepth = 0
    private var loopDepth = 0

    init() {
        installBuiltins()
    }

    func run(_ program: Program) throws {
        _ = try execBlock(program.statements, Environment(parent: globals))
    }

    // MARK: - Sentencias

    private func execBlock(_ statements: Block, _ env: Environment) throws -> Completion {
        for statement in statements {
            let completion = try exec(statement, env)
            if case .normal = completion { continue }
            return completion
        }
        return .normal
    }

    private func exec(_ stmt: Stmt, _ env: Environment) throws -> Completion {
        let line = stmt.line
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
            print(display(try eval(expr, env)))
            return .normal

        case .function(let decl):
            try env.declare(decl.name, .function(Closure(decl: decl, env: env)), line: line)
            return .normal

        case .classDecl(let decl):
            var methods: [String: Closure] = [:]
            for method in decl.methods {
                methods[method.name] = Closure(decl: method, env: env)
            }
            let cls = ClassDef(
                name: decl.name, constructor: decl.constructor, methods: methods, env: env)
            try env.declare(decl.name, .classDef(cls), line: line)
            return .normal

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
            return .list(ListRef(try elementExprs.map { try eval($0, env) }))

        case .new(let className, let argExprs):
            guard case .classDef(let cls)? = env.lookup(className) else {
                throw RuntimeError(line: line, "undefined class '\(className)'")
            }
            let args = try argExprs.map { try eval($0, env) }
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
            return .string(readLine() ?? "")
        }
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
            return try builtin.body(args, line)
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
        callDepth += 1
        let savedLoopDepth = loopDepth
        loopDepth = 0
        defer {
            callDepth -= 1
            loopDepth = savedLoopDepth
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
            if case .string = left { return .string(display(left) + display(right)) }
            if case .string = right { return .string(display(left) + display(right)) }
            return try arithmetic(op, left, right, line: line)
        case .sub, .mul, .div, .mod:
            return try arithmetic(op, left, right, line: line)
        case .gt, .lt, .ge, .le:
            return try compare(op, left, right, line: line)
        case .eq: return .bool(valuesEqual(left, right))
        case .ne: return .bool(!valuesEqual(left, right))
        case .and, .or:
            preconditionFailure("aliado/rival se evalúan con cortocircuito en evalLogical")
        }
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
        case .add: return .real(a + b)
        case .sub: return .real(a - b)
        case .mul: return .real(a * b)
        case .div:
            if b == 0 { throw RuntimeError(line: line, "division by zero") }
            return .real(a / b)
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
                guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw RuntimeError(line: line, "invalid real '\(s)'")
                }
                return .real(d)
            default:
                throw RuntimeError(
                    line: line, "type error: cannot convert \(args[0].typeName) to real")
            }
        }

        define("a_texto", 1) { args, _ in .string(display(args[0])) }
    }
}
