// Error que puede atrapar accidente. Sale de un penalizacion o de un error al ejecutar.
// Si es error de ejecucion, value es solo el mensaje (ej: "division by zero")
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

// bandera_roja, pit_stop y meta. Van aparte de los errores para que accidente no las atrape
enum Completion {
    case normal
    case breakLoop
    case continueLoop
    case returnValue(Value)
}
