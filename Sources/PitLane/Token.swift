enum TokenType: String {
    // Palabras clave
    case kwParrilla = "KW_PARRILLA", kwPole = "KW_POLE", kwAcelera = "KW_ACELERA"
    case kwBanderaVerde = "KW_BANDERA_VERDE", kwBanderaAmarilla = "KW_BANDERA_AMARILLA"
    case kwBanderaAzul = "KW_BANDERA_AZUL", kwVuelta = "KW_VUELTA"
    case kwCircuito = "KW_CIRCUITO", kwSalida = "KW_SALIDA", kwLlegada = "KW_LLEGADA"
    case kwBanderaRoja = "KW_BANDERA_ROJA", kwPitStop = "KW_PIT_STOP"
    case kwRadio = "KW_RADIO", kwTransmision = "KW_TRANSMISION"
    case kwBoxes = "KW_BOXES", kwMeta = "KW_META"
    case kwEscuderia = "KW_ESCUDERIA", kwEnsamble = "KW_ENSAMBLE", kwDebut = "KW_DEBUT", kwAuto = "KW_AUTO"
    case kwSafetyCar = "KW_SAFETY_CAR", kwAccidente = "KW_ACCIDENTE", kwPodio = "KW_PODIO"
    case kwPenalizacion = "KW_PENALIZACION"
    case kwAliado = "KW_ALIADO", kwRival = "KW_RIVAL", kwContra = "KW_CONTRA"
    case kwSupera = "KW_SUPERA", kwRezaga = "KW_REZAGA", kwAlcanza = "KW_ALCANZA", kwCede = "KW_CEDE"
    case kwEmpata = "KW_EMPATA", kwDistinto = "KW_DISTINTO"
    case kwGana = "KW_GANA", kwPierde = "KW_PIERDE", kwBanderaCuadros = "KW_BANDERA_CUADROS"
    // Bonus reservados
    case kwFilial = "KW_FILIAL", kwEstrategia = "KW_ESTRATEGIA", kwNeumatico = "KW_NEUMATICO"
    case kwComodin = "KW_COMODIN", kwReagrupar = "KW_REAGRUPAR"
    // Literales e identificadores
    case id = "ID", intNumber = "INT_NUMBER", realNumber = "REAL_NUMBER", string = "STRING"
    case newline = "NEWLINE"
    // Símbolos
    case plus = "PLUS", minus = "MINUS", star = "STAR", slash = "SLASH", percent = "PERCENT"
    case lparen = "LPAREN", rparen = "RPAREN", lbracket = "LBRACKET", rbracket = "RBRACKET"
    case colon = "COLON", comma = "COMMA", dot = "DOT"
}

struct Token {
    let type: TokenType
    let lexeme: String
    let line: Int
}

// tabla de palabras reservadas. Si una palabra no esta aqui es un ID
let keywords: [String: TokenType] = [
    "parrilla": .kwParrilla, "pole": .kwPole, "acelera": .kwAcelera,
    "bandera_verde": .kwBanderaVerde, "bandera_amarilla": .kwBanderaAmarilla,
    "bandera_azul": .kwBanderaAzul, "vuelta": .kwVuelta,
    "circuito": .kwCircuito, "salida": .kwSalida, "llegada": .kwLlegada,
    "bandera_roja": .kwBanderaRoja, "pit_stop": .kwPitStop,
    "radio": .kwRadio, "transmision": .kwTransmision,
    "boxes": .kwBoxes, "meta": .kwMeta,
    "escuderia": .kwEscuderia, "ensamble": .kwEnsamble, "debut": .kwDebut, "auto": .kwAuto,
    "safety_car": .kwSafetyCar, "accidente": .kwAccidente, "podio": .kwPodio,
    "penalizacion": .kwPenalizacion,
    "aliado": .kwAliado, "rival": .kwRival, "contra": .kwContra,
    "supera": .kwSupera, "rezaga": .kwRezaga, "alcanza": .kwAlcanza, "cede": .kwCede,
    "empata": .kwEmpata, "distinto": .kwDistinto,
    "gana": .kwGana, "pierde": .kwPierde, "bandera_cuadros": .kwBanderaCuadros,
    "filial": .kwFilial, "estrategia": .kwEstrategia, "neumatico": .kwNeumatico,
    "comodin": .kwComodin, "reagrupar": .kwReagrupar,
]
