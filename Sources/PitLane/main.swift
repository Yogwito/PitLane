import Foundation

/// Errores de uso de la línea de comandos: van por stderr.
func failUsage(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Errores léxicos, de sintaxis y de ejecución: van por stdout, en orden con la salida del programa.
func fail(_ message: String) -> Never {
    print(message)
    fflush(stdout)
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let soloSalida = arguments.contains("--solo-salida")
arguments.removeAll { $0 == "--solo-salida" }

guard arguments.count == 1 else {
    failUsage("Usage: PitLane [--solo-salida] <archivo.txt>")
}

let path = arguments[0]
guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
    failUsage("Error: cannot read file '\(path)'")
}

func header(_ title: String, first: Bool = false) {
    guard !soloSalida else { return }
    if !first { print("") }
    print("=== \(title) ===")
}

/// Los strings ya interpretados se muestran con sus escapes para mantener una sola línea por token.
func printable(_ token: Token) -> String {
    guard token.type == .string else { return token.lexeme }
    var out = ""
    for c in token.lexeme {
        switch c {
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        default: out.append(c)
        }
    }
    return out
}

func runPipeline() {
    header("Tokens", first: true)
    var lexer = Lexer(source: source)
    let tokens: [Token]
    do {
        tokens = try lexer.tokenize()
    } catch let error as LexicalError {
        fail(error.description)
    } catch {
        fail("\(error)")
    }
    if !soloSalida {
        for token in tokens where token.type != .newline {
            print("[line \(token.line)] \(token.type.rawValue) \(printable(token))")
        }
    }

    header("Sintaxis")
    let program: Program
    do {
        program = try Parser(tokens: tokens).parseProgram()
    } catch let error as SyntaxError {
        fail(error.description)
    } catch {
        fail("\(error)")
    }
    if !soloSalida { print("Syntax OK") }

    header("Salida")
    do {
        try Interpreter().run(program)
    } catch let error as RuntimeError {
        fail("Runtime error on line \(error.line): \(display(error.value))")
    } catch {
        fail("\(error)")
    }
}

// La recursión profunda necesita más pila que el hilo principal.
let finished = DispatchSemaphore(value: 0)
let worker = Thread {
    runPipeline()
    finished.signal()
}
worker.stackSize = 512 * 1024 * 1024
worker.start()
finished.wait()
exit(0)
