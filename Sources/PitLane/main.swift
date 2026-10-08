import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: PitLane <archivo.txt>")
}

let path = CommandLine.arguments[1]
guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
    fail("Error: cannot read file '\(path)'")
}

var lexer = Lexer(source: source)
do {
    let tokens = try lexer.tokenize()
    for token in tokens where token.type != .newline {
        print("[line \(token.line)] \(token.type.rawValue) \(token.lexeme)")
    }
    _ = try Parser(tokens: tokens).parseProgram()
    print("Syntax OK")
} catch let error as LexicalError {
    fail(error.description)
} catch let error as SyntaxError {
    fail(error.description)
}
