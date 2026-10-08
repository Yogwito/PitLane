struct SyntaxError: Error {
    let line: Int
    let message: String

    var description: String { "Syntax error on line \(line): \(message)" }
}

/// Descenso recursivo: una función por regla de la gramática del CLAUDE.md.
final class Parser {
    private let tokens: [Token]
    private var pos = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    // MARK: - Utilidades

    private static let blockEnd: Set<TokenType> = [
        .kwBanderaCuadros, .kwBanderaAmarilla, .kwBanderaAzul, .kwAccidente, .kwPodio,
    ]

    private static let lexemes: [TokenType: String] = {
        var d = Dictionary(uniqueKeysWithValues: keywords.map { ($0.value, $0.key) })
        let others: [TokenType: String] = [
            .plus: "+", .minus: "-", .star: "*", .slash: "/", .percent: "%",
            .lparen: "(", .rparen: ")", .lbracket: "[", .rbracket: "]",
            .colon: ":", .comma: ",", .dot: ".",
            .id: "identifier", .intNumber: "integer", .realNumber: "real number",
            .string: "string", .newline: "end of line",
        ]
        d.merge(others) { a, _ in a }
        return d
    }()

    private var current: Token? { pos < tokens.count ? tokens[pos] : nil }
    private var currentType: TokenType? { current?.type }

    /// Línea del token actual; al fin del archivo, la del último token real.
    private var errorLine: Int {
        if let t = current { return t.line }
        return tokens.last(where: { $0.type != .newline })?.line ?? tokens.last?.line ?? 1
    }

    private func error(_ message: String) -> SyntaxError {
        SyntaxError(line: errorLine, message: message)
    }

    @discardableResult
    private func advance() -> Token {
        let t = tokens[pos]
        pos += 1
        return t
    }

    private func match(_ type: TokenType) -> Bool {
        if currentType == type {
            pos += 1
            return true
        }
        return false
    }

    @discardableResult
    private func expect(_ type: TokenType) throws -> Token {
        guard currentType == type else {
            throw error("expected '\(Parser.lexemes[type] ?? type.rawValue)'")
        }
        return advance()
    }

    private func skipNewlines() {
        while currentType == .newline { pos += 1 }
    }

    private func endOfStatement() throws {
        if current == nil { return }
        guard match(.newline) else { throw error("expected end of line") }
    }

    // MARK: - Programa y bloques

    func parseProgram() throws -> Program {
        var statements: Block = []
        while true {
            skipNewlines()
            guard let t = current else { break }
            if Parser.blockEnd.contains(t.type) {
                throw error("unexpected '\(t.lexeme)'")
            }
            statements.append(try parseStatement())
            try endOfStatement()
        }
        return Program(statements: statements)
    }

    /// Termina (sin consumir) en un cierre de bloque o en el fin del archivo.
    private func parseBlock() throws -> Block {
        var statements: Block = []
        while true {
            skipNewlines()
            guard let t = current, !Parser.blockEnd.contains(t.type) else { return statements }
            statements.append(try parseStatement())
            try endOfStatement()
        }
    }

    // MARK: - Sentencias

    private func parseStatement() throws -> Stmt {
        guard let t = current else { throw error("expected statement") }
        let line = t.line
        let kind: StmtKind
        switch t.type {
        case .kwParrilla, .kwPole: kind = try parseDeclaration()
        case .kwBanderaVerde: kind = try parseIf()
        case .kwVuelta: kind = try parseWhile()
        case .kwCircuito: kind = try parseFor()
        case .kwBanderaRoja:
            advance()
            kind = .breakStmt
        case .kwPitStop:
            advance()
            kind = .continueStmt
        case .kwMeta: kind = try parseReturn()
        case .kwTransmision: kind = try parsePrint()
        case .kwBoxes: kind = .function(try parseFunction())
        case .kwEscuderia: kind = .classDecl(try parseClass())
        case .kwSafetyCar: kind = try parseTry()
        case .kwPenalizacion:
            advance()
            kind = .throwStmt(try parseExpr())
        default: kind = try parseAssignmentOrCall()
        }
        return Stmt(kind: kind, line: line)
    }

    private func parseDeclaration() throws -> StmtKind {
        let isConstant = advance().type == .kwPole
        let name = try expect(.id).lexeme
        var initial: Expr?
        if match(.kwAcelera) { initial = try parseExpr() }
        return .declaration(isConstant: isConstant, name: name, initial: initial)
    }

    /// Parsea primero un postfijo; si sigue "acelera" es asignación, si no se
    /// reinterpreta toda la sentencia como una expresión (llamada suelta).
    private func parseAssignmentOrCall() throws -> StmtKind {
        let start = pos
        let lhs = try parsePostfix()
        if match(.kwAcelera) {
            let target = try makeTarget(lhs)
            return .assignment(target: target, value: try parseExpr())
        }
        pos = start
        return .expression(try parseExpr())
    }

    private func makeTarget(_ e: Expr) throws -> Target {
        switch e.kind {
        case .variable(let name): return .variable(name)
        case .index(let base, let idx): return .index(base: base, index: idx)
        case .member(let obj, let name): return .member(object: obj, name: name)
        default: throw SyntaxError(line: e.line, message: "invalid assignment target")
        }
    }

    private func parseIf() throws -> StmtKind {
        advance()  // bandera_verde
        var branches: [Branch] = []
        var condition = try parseExpr()
        try expect(.colon)
        branches.append(Branch(condition: condition, body: try parseBlock()))
        while match(.kwBanderaAmarilla) {
            condition = try parseExpr()
            try expect(.colon)
            branches.append(Branch(condition: condition, body: try parseBlock()))
        }
        var elseBody: Block?
        if match(.kwBanderaAzul) {
            try expect(.colon)
            elseBody = try parseBlock()
        }
        try expect(.kwBanderaCuadros)
        return .conditional(branches: branches, elseBody: elseBody)
    }

    private func parseWhile() throws -> StmtKind {
        advance()  // vuelta
        let condition = try parseExpr()
        try expect(.colon)
        let body = try parseBlock()
        try expect(.kwBanderaCuadros)
        return .whileLoop(condition: condition, body: body)
    }

    private func parseFor() throws -> StmtKind {
        advance()  // circuito
        let variable = try expect(.id).lexeme
        try expect(.kwSalida)
        let from = try parseExpr()
        try expect(.kwLlegada)
        let to = try parseExpr()
        try expect(.colon)
        let body = try parseBlock()
        try expect(.kwBanderaCuadros)
        return .forLoop(variable: variable, from: from, to: to, body: body)
    }

    private func parseReturn() throws -> StmtKind {
        advance()  // meta
        if current == nil || currentType == .newline || Parser.blockEnd.contains(currentType!) {
            return .returnStmt(nil)
        }
        return .returnStmt(try parseExpr())
    }

    private func parsePrint() throws -> StmtKind {
        advance()  // transmision
        try expect(.lparen)
        let value = try parseExpr()
        try expect(.rparen)
        return .print(value)
    }

    private func parseParams() throws -> [String] {
        var params: [String] = []
        if currentType == .id {
            params.append(advance().lexeme)
            while match(.comma) { params.append(try expect(.id).lexeme) }
        }
        return params
    }

    private func parseFunction() throws -> FunctionDecl {
        let line = advance().line  // boxes
        let name = try expect(.id).lexeme
        try expect(.lparen)
        let params = try parseParams()
        try expect(.rparen)
        try expect(.colon)
        let body = try parseBlock()
        try expect(.kwBanderaCuadros)
        return FunctionDecl(name: name, params: params, body: body, line: line)
    }

    private func parseClass() throws -> ClassDecl {
        let line = advance().line  // escuderia
        let name = try expect(.id).lexeme
        try expect(.colon)
        var constructor: ConstructorDecl?
        var methods: [FunctionDecl] = []
        while true {
            skipNewlines()
            switch currentType {
            case .kwEnsamble:
                if constructor != nil { throw error("duplicate constructor 'ensamble'") }
                constructor = try parseConstructor()
                try endOfStatement()
            case .kwBoxes:
                methods.append(try parseFunction())
                try endOfStatement()
            default:
                try expect(.kwBanderaCuadros)
                return ClassDecl(name: name, constructor: constructor, methods: methods, line: line)
            }
        }
    }

    private func parseConstructor() throws -> ConstructorDecl {
        let line = advance().line  // ensamble
        try expect(.lparen)
        let params = try parseParams()
        try expect(.rparen)
        try expect(.colon)
        let body = try parseBlock()
        try expect(.kwBanderaCuadros)
        return ConstructorDecl(params: params, body: body, line: line)
    }

    private func parseTry() throws -> StmtKind {
        advance()  // safety_car
        try expect(.colon)
        let body = try parseBlock()
        try expect(.kwAccidente)
        let errorName = try expect(.id).lexeme
        try expect(.colon)
        let handler = try parseBlock()
        var finally: Block?
        if match(.kwPodio) {
            try expect(.colon)
            finally = try parseBlock()
        }
        try expect(.kwBanderaCuadros)
        return .tryCatch(body: body, errorName: errorName, handler: handler, finally: finally)
    }

    // MARK: - Expresiones (de menor a mayor precedencia)

    func parseExpr() throws -> Expr {
        try parseBinary([.kwRival: .or], next: parseAnd)
    }

    private func parseAnd() throws -> Expr {
        try parseBinary([.kwAliado: .and], next: parseEquality)
    }

    private func parseEquality() throws -> Expr {
        try parseBinary([.kwEmpata: .eq, .kwDistinto: .ne], next: parseRelational)
    }

    private func parseRelational() throws -> Expr {
        try parseBinary(
            [.kwSupera: .gt, .kwRezaga: .lt, .kwAlcanza: .ge, .kwCede: .le], next: parseAdditive)
    }

    private func parseAdditive() throws -> Expr {
        try parseBinary([.plus: .add, .minus: .sub], next: parseTerm)
    }

    private func parseTerm() throws -> Expr {
        try parseBinary([.star: .mul, .slash: .div, .percent: .mod], next: parseUnary)
    }

    /// Nivel binario asociativo a la izquierda.
    private func parseBinary(
        _ ops: [TokenType: BinaryOp], next: () throws -> Expr
    ) throws -> Expr {
        var left = try next()
        while let t = current, let op = ops[t.type] {
            advance()
            let right = try next()
            left = Expr(kind: .binary(op, left, right), line: t.line)
        }
        return left
    }

    private func parseUnary() throws -> Expr {
        if let t = current, t.type == .kwContra || t.type == .minus {
            advance()
            let operand = try parseUnary()
            return Expr(kind: .unary(t.type == .minus ? .neg : .not, operand), line: t.line)
        }
        return try parsePostfix()
    }

    private func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        while let t = current {
            switch t.type {
            case .lparen:
                advance()
                let args = try parseArgs(closing: .rparen)
                expr = Expr(kind: .call(callee: expr, args: args), line: t.line)
            case .lbracket:
                advance()
                let idx = try parseExpr()
                try expect(.rbracket)
                expr = Expr(kind: .index(expr, idx), line: t.line)
            case .dot:
                advance()
                let name = try expect(.id).lexeme
                expr = Expr(kind: .member(expr, name), line: t.line)
            default:
                return expr
            }
        }
        return expr
    }

    /// args = expr { "," expr }, opcional, y consume el delimitador de cierre.
    private func parseArgs(closing: TokenType) throws -> [Expr] {
        var args: [Expr] = []
        if match(closing) { return args }
        args.append(try parseExpr())
        while match(.comma) { args.append(try parseExpr()) }
        try expect(closing)
        return args
    }

    private func parsePrimary() throws -> Expr {
        guard let t = current else { throw error("expected expression") }
        let line = t.line
        switch t.type {
        case .intNumber:
            advance()
            guard let value = Int(t.lexeme) else {
                throw SyntaxError(line: line, message: "integer out of range '\(t.lexeme)'")
            }
            return Expr(kind: .int(value), line: line)
        case .realNumber:
            advance()
            return Expr(kind: .real(Double(t.lexeme) ?? 0), line: line)
        case .string:
            advance()
            return Expr(kind: .string(t.lexeme), line: line)
        case .kwGana:
            advance()
            return Expr(kind: .bool(true), line: line)
        case .kwPierde:
            advance()
            return Expr(kind: .bool(false), line: line)
        case .id:
            advance()
            return Expr(kind: .variable(t.lexeme), line: line)
        case .kwAuto:
            advance()
            return Expr(kind: .selfRef, line: line)
        case .lparen:
            advance()
            let inner = try parseExpr()
            try expect(.rparen)
            return inner
        case .lbracket:
            advance()
            return Expr(kind: .list(try parseArgs(closing: .rbracket)), line: line)
        case .kwDebut:
            advance()
            let name = try expect(.id).lexeme
            try expect(.lparen)
            let args = try parseArgs(closing: .rparen)
            return Expr(kind: .new(className: name, args: args), line: line)
        case .kwRadio:
            advance()
            try expect(.lparen)
            try expect(.rparen)
            return Expr(kind: .readLine, line: line)
        default:
            throw error("expected expression")
        }
    }
}
