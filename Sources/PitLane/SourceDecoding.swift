import Foundation

// Tabla para los bytes 0x80 a 0x9F de Windows-1252 (los demas son iguales a Latin-1).
// Los nil son bytes que no significan nada; si aparecen el archivo no se puede leer
private let windows1252High: [Unicode.Scalar?] = [
    "\u{20AC}", nil, "\u{201A}", "\u{0192}", "\u{201E}", "\u{2026}", "\u{2020}", "\u{2021}",
    "\u{02C6}", "\u{2030}", "\u{0160}", "\u{2039}", "\u{0152}", nil, "\u{017D}", nil,
    nil, "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{2022}", "\u{2013}", "\u{2014}",
    "\u{02DC}", "\u{2122}", "\u{0161}", "\u{203A}", "\u{0153}", nil, "\u{017E}", "\u{0178}",
]

// Primero intentamos UTF-8 (quitando el BOM si lo tiene). Si no sirve, Windows-1252,
// que es el "ANSI" del bloc de notas. Usamos la tabla de arriba porque Foundation
// no trae Windows-1252 en todos los sistemas
func decodeSource(_ data: Data) -> String? {
    var bytes = Array(data)
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
    if let text = decodeUTF8(bytes) { return text }
    var text = String.UnicodeScalarView()
    for byte in bytes {
        if (0x80...0x9F).contains(byte) {
            guard let scalar = windows1252High[Int(byte - 0x80)] else { return nil }
            text.append(scalar)
        } else {
            text.append(Unicode.Scalar(byte))
        }
    }
    return String(text)
}

// UTF-8 estricto: si hay un byte malo devuelve nil (no lo reemplaza por nada)
func decodeUTF8(_ bytes: [UInt8]) -> String? {
    var text = String.UnicodeScalarView()
    var iterator = bytes.makeIterator()
    var decoder = UTF8()
    while true {
        switch decoder.decode(&iterator) {
        case .scalarValue(let scalar): text.append(scalar)
        case .emptyInput: return String(text)
        case .error: return nil
        }
    }
}
