typealias Block = [Stmt]

enum BinaryOp: String {
    case or = "rival", and = "aliado"
    case eq = "empata", ne = "distinto"
    case gt = "supera", lt = "rezaga", ge = "alcanza", le = "cede"
    case add = "+", sub = "-", mul = "*", div = "/", mod = "%"
}

enum UnaryOp: String {
    case not = "contra", neg = "-"
}

// MARK: - Expresiones

struct Expr {
    let kind: ExprKind
    let line: Int
}

indirect enum ExprKind {
    case int(Int)
    case real(Double)
    case string(String)
    case bool(Bool)
    case variable(String)
    case selfRef                              // auto
    case binary(BinaryOp, Expr, Expr)
    case unary(UnaryOp, Expr)
    case call(callee: Expr, args: [Expr])
    case index(Expr, Expr)
    case member(Expr, String)                 // objeto.atributo
    case list([Expr])
    case new(className: String, args: [Expr]) // debut
    case readLine                             // radio()
}

// MARK: - Sentencias

/// Destino de una asignación.
indirect enum Target {
    case variable(String)
    case index(base: Expr, index: Expr)
    case member(object: Expr, name: String)   // incluye auto.atributo
}

struct Branch {
    let condition: Expr
    let body: Block
}

struct FunctionDecl {
    let name: String
    let params: [String]
    let body: Block
    let line: Int
}

struct ConstructorDecl {
    let params: [String]
    let body: Block
    let line: Int
}

struct ClassDecl {
    let name: String
    let constructor: ConstructorDecl?
    let methods: [FunctionDecl]
    let line: Int
}

struct Stmt {
    let kind: StmtKind
    let line: Int
}

indirect enum StmtKind {
    case declaration(isConstant: Bool, name: String, initial: Expr?)
    case assignment(target: Target, value: Expr)
    /// bandera_verde + bandera_amarilla* (branches) y bandera_azul opcional.
    case conditional(branches: [Branch], elseBody: Block?)
    case whileLoop(condition: Expr, body: Block)
    case forLoop(variable: String, from: Expr, to: Expr, body: Block)
    case breakStmt
    case continueStmt
    case returnStmt(Expr?)
    case print(Expr)
    case function(FunctionDecl)
    case classDecl(ClassDecl)
    case tryCatch(body: Block, errorName: String, handler: Block, finally: Block?)
    case throwStmt(Expr)
    case expression(Expr)                     // llamada suelta
}

struct Program {
    let statements: Block
}
