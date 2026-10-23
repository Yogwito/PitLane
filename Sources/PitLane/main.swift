import Foundation

// errores al usar el comando mal (faltan argumentos, no existe el archivo...). Van por stderr
func failUsage(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// errores lexicos, de sintaxis y de ejecucion. Van por stdout para que salgan
// en orden con lo que ya imprimio el programa
func fail(_ message: String) -> Never {
    print(message)
    fflush(stdout)
    exit(1)
}

Platform.configureStdout()

var arguments = Array(CommandLine.arguments.dropFirst())
let soloSalida = arguments.contains("--solo-salida")
arguments.removeAll { $0 == "--solo-salida" }

guard arguments.count == 1 else {
    failUsage("Usage: PitLane [--solo-salida] <archivo.txt>")
}

// maximo de CPU. El interprete ya se corta solo a los 4 s (diciendo la linea),
// esto es por si acaso algo se escapa
let maxCPUSeconds = 5

if ProcessInfo.processInfo.environment["PITLANE_WORKER"] != "1" {
    let child = Process()
    child.executableURL = Bundle.main.executableURL
    child.arguments = Array(CommandLine.arguments.dropFirst())
    var environment = ProcessInfo.processInfo.environment
    environment["PITLANE_WORKER"] = "1"
    child.environment = environment
    child.standardInput = FileHandle.standardInput
    child.standardOutput = FileHandle.standardOutput
    child.standardError = FileHandle.standardError
    do {
        try child.run()
    } catch {
        failUsage("Error: cannot start interpreter")
    }
    if Platform.waitForExit(child, cpuLimit: maxCPUSeconds) {
        fail("Runtime error: time limit exceeded")
    }
    if child.terminationReason != .exit {
        fail("Runtime error: process terminated unexpectedly")
    }
    exit(child.terminationStatus)
}

if !Platform.limitAddressSpace(bytes: 1_073_741_824) {
    failUsage("Error: cannot set memory limit")
}
if !Platform.limitCPUTime(seconds: maxCPUSeconds) {
    failUsage("Error: cannot set time limit")
}

let path = arguments[0]
let maxSourceBytes = 1_000_000
if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
   let size = attributes[.size] as? NSNumber, size.intValue > maxSourceBytes {
    failUsage("Error: source file exceeds \(maxSourceBytes) bytes")
}
guard let data = FileManager.default.contents(atPath: path),
      let source = decodeSource(data) else {
    failUsage("Error: cannot read file '\(path)'")
}
if data.count > maxSourceBytes {
    failUsage("Error: source file exceeds \(maxSourceBytes) bytes")
}

func header(_ title: String, first: Bool = false) {
    guard !soloSalida else { return }
    if !first { print("") }
    print("=== \(title) ===")
}

// para imprimir un string en la lista de tokens volvemos a poner los \n, \t...
// asi cada token queda en una sola linea
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

// Corremos todo en un hilo con una pila grande. Si no, con muchas llamadas recursivas
// Swift se caeria antes de llegar a nuestro error de "stack overflow" (1000 llamadas)
let pipelineDone = DispatchSemaphore(value: 0)
let pipelineThread = Thread {
    runPipeline()
    pipelineDone.signal()
}
pipelineThread.stackSize = 512 * 1024 * 1024
pipelineThread.start()
pipelineDone.wait()
