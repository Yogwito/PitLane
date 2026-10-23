# PitLane

Intérprete del lenguaje PitLane, escrito en Swift. Los programas son archivos de texto `.txt`.

## Requisitos

- Swift 5.9 o superior.
- macOS, Linux o Windows. En Windows, `probar.sh` se ejecuta desde Git Bash.

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

En Windows, si `swift build` no puede crear el enlace `.build/debug`, el ejecutable queda en la ruta que indica `swift build --show-bin-path`.

## Pruebas

```sh
./probar.sh             # compila en modo desarrollo y corre todas las pruebas
./probar.sh --release   # lo mismo, con el binario de publicación
./probar.sh --watch     # repite ambas cada vez que cambia un archivo (Ctrl+C para salir)
```

Al final se muestra un resumen `N OK, M FALLA`. Si algo falla, el código de salida es distinto de 0.
