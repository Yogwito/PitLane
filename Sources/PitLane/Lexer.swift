struct LexicalError: Error {
    let line: Int
    let message: String

    var description: String { "Lexical error on line \(line): \(message)" }
}

struct Lexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1

    init(source: String) {
        // "\r\n" es un solo Character en Swift; se normaliza a "\n".
        chars = Array(source.replacingOccurrences(of: "\r\n", with: "\n"))
    }

    private func peek(_ offset: Int = 0) -> Character? {
        let i = pos + offset
        return i < chars.count ? chars[i] : nil
    }

    private static func isDigit(_ c: Character?) -> Bool {
        guard let c = c, let a = c.asciiValue else { return false }
        return a >= 48 && a <= 57
    }

    private static func isLetter(_ c: Character?) -> Bool {
        guard let c = c, let a = c.asciiValue else { return false }
        return (a >= 65 && a <= 90) || (a >= 97 && a <= 122) || a == 95
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while let c = peek() {
            switch c {
            case " ", "\t", "\r":
                pos += 1
            case "\n":
                tokens.append(Token(type: .newline, lexeme: "\\n", line: line))
                line += 1
                pos += 1
            case "/" where peek(1) == "/":
                while let n = peek(), n != "\n" { pos += 1 }
            case "\"":
                tokens.append(try readString())
            default:
                if Lexer.isDigit(c) {
                    tokens.append(readNumber())
                } else if Lexer.isLetter(c) {
                    tokens.append(readWord())
                } else if let type = Lexer.symbols[c] {
                    tokens.append(Token(type: type, lexeme: String(c), line: line))
                    pos += 1
                } else {
                    throw LexicalError(line: line, message: "unrecognized symbol '\(c)'")
                }
            }
        }
        return tokens
    }

    private static let symbols: [Character: TokenType] = [
        "+": .plus, "-": .minus, "*": .star, "/": .slash, "%": .percent,
        "(": .lparen, ")": .rparen, "[": .lbracket, "]": .rbracket,
        ":": .colon, ",": .comma, ".": .dot,
    ]

    private mutating func readString() throws -> Token {
        let startLine = line
        pos += 1  // comilla de apertura
        var text = ""
        while let c = peek() {
            if c == "\"" {
                pos += 1
                return Token(type: .string, lexeme: text, line: startLine)
            }
            if c == "\n" { break }
            text.append(c)
            pos += 1
        }
        throw LexicalError(line: startLine, message: "unterminated string")
    }

    /// REAL ([0-9]+\.[0-9]+) se prueba antes que INT.
    private mutating func readNumber() -> Token {
        let start = pos
        while Lexer.isDigit(peek()) { pos += 1 }
        var type = TokenType.intNumber
        if peek() == ".", Lexer.isDigit(peek(1)) {
            type = .realNumber
            pos += 1
            while Lexer.isDigit(peek()) { pos += 1 }
        }
        return Token(type: type, lexeme: String(chars[start..<pos]), line: line)
    }

    private mutating func readWord() -> Token {
        let start = pos
        while Lexer.isLetter(peek()) || Lexer.isDigit(peek()) { pos += 1 }
        let word = String(chars[start..<pos])
        return Token(type: keywords[word] ?? .id, lexeme: word, line: line)
    }
}
