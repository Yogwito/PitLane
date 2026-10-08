/// Excepción de PitLane: la lanza `penalizacion` o un error de ejecución.
/// Para un error de ejecución, `value` es el texto del mensaje sin prefijo.
struct RuntimeError: Error {
    let value: Value
    let line: Int

    init(value: Value, line: Int) {
        self.value = value
        self.line = line
    }

    init(line: Int, _ message: String) {
        self.init(value: .string(message), line: line)
    }
}

/// Señales de control, distintas de las excepciones: `accidente` no las captura.
enum Completion {
    case normal
    case breakLoop
    case continueLoop
    case returnValue(Value)
}
