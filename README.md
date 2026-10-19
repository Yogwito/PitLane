# PitLane

PitLane es un lenguaje de programación pequeño con vocabulario de Fórmula 1. Su base es Swift: se interpreta (análisis léxico, análisis sintáctico e intérprete) y todo el procesador está escrito en Swift. Los programas son archivos de texto `.txt`.

## Requisitos

- Swift 5.9 como versión mínima del paquete y de las pruebas. También se verifica con Swift 6.4 en macOS; las versiones anteriores a 5.9 se rechazan al ejecutar `probar.sh`.
- macOS o Linux.

## Compilar y ejecutar

```sh
swift build
swift run PitLane ejemplos/programa1.txt
```

Por defecto se muestran las tres fases, cada una con su encabezado:

```
=== Tokens ===
[line 1] KW_PARRILLA parrilla
[line 1] ID x
...

=== Sintaxis ===
Syntax OK

=== Salida ===
Mayor que 5
```

Con `--solo-salida` se imprime únicamente la salida del programa:

```sh
swift run PitLane --solo-salida ejemplos/programa1.txt
```

Si un programa lee del teclado (`radio()`), la entrada se pasa por la entrada estándar:

```sh
swift run PitLane --solo-salida ejemplos/p10_entrada.txt < ejemplos/p10_entrada.in
```

Un error en cualquier fase detiene el proceso con código de salida 1.

## Pruebas

```sh
./probar.sh
./probar.sh --release
./probar.sh --watch
```

El script compila el proyecto y recorre `ejemplos/`:

- `X.esperado`: ejecuta `X.txt` con `--solo-salida` (usando `X.in` como entrada si existe) y compara la salida. Los archivos `errores_*` además deben terminar con código de salida 1.
- `X.completo.esperado`: ejecuta `X.txt` sin `--solo-salida` y compara las tres fases completas.

Al final muestra un resumen `N OK, M FALLA` y devuelve un código distinto de 0 si algo falla. Las dos primeras invocaciones ejecutan la misma batería sobre los binarios de desarrollo y de publicación, respectivamente. `--watch` ejecuta ambas y las repite al detectar cambios en los archivos del proyecto mientras siga abierto; se detiene con Ctrl+C. Para validar una entrega en macOS y Linux, ejecute ambas configuraciones en cada sistema; cualquier código de salida distinto de cero rechaza el cambio.

## Estructura del repositorio

```
Package.swift
probar.sh                 script de pruebas
Sources/PitLane/
  Token.swift             tipos de token y palabras clave
  Lexer.swift             análisis léxico
  AST.swift               nodos del árbol sintáctico
  Parser.swift            análisis sintáctico (descenso recursivo)
  Value.swift             valores del lenguaje y reglas de impresión
  Environment.swift       ámbitos y variables
  RuntimeError.swift      errores de ejecución y señales de control
  Interpreter.swift       ejecución del árbol
  main.swift              línea de comandos y fases
ejemplos/
  programa1..3.txt        programas de ejemplo
  p04..p14_*.txt          una prueba por requisito (tipos, bucles, listas,
                          funciones, clases, excepciones, entrada, uso antes
                          de la definición, escapes, Unicode, tokens)
  errores_lexicos*.txt    errores léxicos
  errores_sintaxis*.txt   errores de sintaxis
  errores_ejecucion*.txt  errores de ejecución
  *.esperado              salida esperada de cada programa
  *.in                    entrada estándar para los programas que leen
```

## Vocabulario (PitLane = Swift)

| PitLane | Swift | PitLane | Swift |
|---|---|---|---|
| `parrilla` | `var` | `escuderia` | `class` |
| `pole` | `let` | `ensamble` | `init` |
| `acelera` | `=` | `debut` | crear objeto |
| `bandera_verde` | `if` | `auto` | `self` |
| `bandera_amarilla` | `else if` | `safety_car` | `do` / `try` |
| `bandera_azul` | `else` | `accidente` | `catch` |
| `vuelta` | `while` | `podio` | `finally` |
| `circuito` ... `salida` ... `llegada` | `for` con contador | `penalizacion` | `throw` |
| `bandera_roja` | `break` | `aliado` | `&&` |
| `pit_stop` | `continue` | `rival` | `\|\|` |
| `radio` | `readLine` | `contra` | `!` |
| `transmision` | `print` | `supera` | `>` |
| `boxes` | `func` | `rezaga` | `<` |
| `meta` | `return` | `alcanza` | `>=` |
| `gana` | `true` | `cede` | `<=` |
| `pierde` | `false` | `empata` | `==` |
| `bandera_cuadros` | fin de bloque | `distinto` | `!=` |

Los símbolos `+ - * / % ( ) [ ] , : .` no cambian. Los comentarios empiezan con `//` y llegan hasta el fin de línea. Los bloques se cierran siempre con `bandera_cuadros`.

Reservadas para uso futuro: `filial`, `estrategia`, `neumatico`, `comodin`, `reagrupar`.

## Ejemplo

```
boxes factorial(n):
    bandera_verde n cede 1:
        meta 1
    bandera_cuadros
    meta n * factorial(n - 1)
bandera_cuadros
circuito i salida 1 llegada 5:
    transmision("factorial de " + i + " = " + factorial(i))
bandera_cuadros
```

Salida:

```
factorial de 1 = 1
factorial de 2 = 2
factorial de 3 = 6
factorial de 4 = 24
factorial de 5 = 120
```

## Detalles del lenguaje

- **Tipos:** entero, real, texto, booleano (`gana` / `pierde`), lista, objeto y función. Una variable declarada sin valor vale `nada`.
- **Impresión:** los reales siempre llevan punto (`3.0`, `2.5`); las listas se muestran como `[4, 8, 15]`, con los textos entre comillas dobles; los objetos como `<NombreClase>`.
- **Aritmética:** como en Swift. Entero entre entero es división entera; si algún operando es real, el resultado es real. `+` concatena cuando algún operando es texto.
- **Textos:** admiten las secuencias `\n`, `\t`, `\"` y `\\`.
- **Identificadores:** letras (incluidas `ñ` y vocales con tilde), dígitos y `_`, sin empezar por dígito.
- **Funciones y clases:** se pueden usar antes del punto del archivo donde se definen. Las variables no.
- **Excepciones:** `penalizacion` lanza cualquier valor; `safety_car` / `accidente` / `podio` captura también los errores de ejecución (el mensaje llega como texto, por ejemplo `division by zero`).

### Funciones predefinidas

| Función | Descripción |
|---|---|
| `longitud(x)` | Cantidad de elementos de una lista o de caracteres de un texto |
| `agregar(lista, valor)` | Agrega un elemento al final de la lista |
| `a_entero(x)` | Convierte a entero (`a_entero("abc")` es un error de ejecución) |
| `a_real(x)` | Convierte a real |
| `a_texto(x)` | Convierte a texto con las reglas de impresión |

## Errores

Los errores léxicos, sintácticos y de ejecución se imprimen por la salida estándar, indican la línea y terminan el proceso con código de salida 1. El límite de tiempo también se informa por la salida estándar, sin línea porque puede vencer durante la lectura del archivo o de `radio()`. Lo que el programa ya había impreso se conserva.

El contrato de la línea de comandos es `PitLane [--solo-salida] <archivo.txt>`. La falta de archivo, una ruta ilegible, un archivo que excede el límite o una combinación inválida de argumentos terminan con código 1 y un mensaje por la salida de errores, sin ejecutar el programa. Al invocarse desde otra carpeta o mediante `PATH`, se aplican los mismos resultados y límites. Si `radio()` encuentra el fin de la entrada estándar, devuelve texto vacío. La salida estándar se emite inmediatamente: si vence el tiempo, se conservan las líneas completas impresas antes del bloqueo y se añade `Runtime error: time limit exceeded`.

```
Lexical error on line 2: unrecognized symbol '#'
Lexical error on line 3: unterminated string
Lexical error on line 2: invalid escape sequence '\q'
Syntax error on line 4: expected 'bandera_cuadros'
Syntax error on line 3: expected expression
Runtime error on line 4: division by zero
```

Ejemplos de errores de ejecución: `division by zero`, `index out of range`, `undeclared variable 'x'`, `cannot assign to constant 'x'`, `'x' already declared`, `expected N arguments but got M`, `not callable`, `stack overflow`, `undefined attribute 'x'`, `undefined method 'm'`, `undefined class 'X'`, `condition must be boolean`. Una `penalizacion` que nadie captura se informa como `Runtime error on line N:` seguido del valor lanzado.

Para evitar bloqueos y consumo excesivo de recursos, cada archivo fuente puede ocupar hasta 1 000 000 de bytes. Un proceso supervisor termina al intérprete después de 5 segundos; la ejecución también se detiene con `execution limit exceeded` después de 100 000 000 de pasos o de 4 segundos ejecutando. El análisis y la ejecución admiten hasta 128 niveles de anidamiento (en la ejecución, dentro de cada función), la recursión hasta 1000 llamadas anidadas (`stack overflow`) y una comparación hasta 1 000 000 de pares de valores. Una línea leída por `radio()`, un texto construido y la salida del programa tienen un límite de 1 000 000 de bytes cada uno. El intérprete limita las asignaciones acumuladas de valores a 64 MiB y comprueba periódicamente si el pico de memoria residente supera 256 MiB. En Linux, el proceso intérprete también tiene un límite de 1 GiB de espacio de direcciones impuesto por el sistema operativo. Al alcanzar un límite se informa un error; las listas cíclicas se muestran con `[<cycle>]`.

`./probar.sh` comprueba los ejemplos, casos adversariales, 160 programas generados con resultados esperados (incluidas combinaciones de funciones, listas, bucles y condiciones), transformaciones que conservan la salida, 200 mutaciones de caracteres y casos de ejecución desde `PATH`, entrada cerrada y tiempo agotado. La generación usa una semilla fija para reproducir los fallos.

La compatibilidad se evalúa contra Swift 5.9. Un cambio de sintaxis, resultados, mensajes de error, límites o códigos de salida exige actualizar esta descripción y los resultados esperados junto con el código. Los archivos de evaluación externos deben ejecutarse con las dos configuraciones; no forman parte de esta batería mientras no se proporcionen.

## Estado

- Implementado: recursión.
- No implementado: interfaz gráfica, base de datos, herencia, `do-while`, `switch` y errores semánticos en una fase previa a la ejecución. Los errores de tipo, de variables no declaradas y de constantes se detectan al ejecutar.
