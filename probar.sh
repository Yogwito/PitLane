#!/bin/bash
# Corre los ejemplos de ejemplos/ y compara contra su .esperado:
#   X.esperado          -> X.txt con --solo-salida, solo stdout (con X.in por stdin si existe).
#                          Si X empieza con "errores_", el código de salida debe ser 1.
#   X.completo.esperado -> X.txt SIN --solo-salida, compara toda la salida.
cd "$(dirname "$0")" || exit 1
if [ "${1:-}" = '--watch' ]; then
    firma() {
        find Package.swift README.md probar.sh Sources ejemplos -type f -print | LC_ALL=C sort | while IFS= read -r archivo; do
            cksum "$archivo"
        done | cksum
    }
    anterior=$(firma)
    while true; do
        "$0"
        "$0" --release
        echo 'Esperando cambios (Ctrl+C para terminar)...'
        while true; do
            sleep 2
            actual=$(firma)
            [ "$actual" != "$anterior" ] && break
        done
        anterior=$actual
    done
fi
case "${1:-}" in
    '') configuracion=debug ;;
    --release) configuracion=release ;;
    *) echo 'Usage: ./probar.sh [--release|--watch]' >&2; exit 1 ;;
esac
version=$(swift --version | sed -n 's/.*Swift version \([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p' | head -n 1)
read -r mayor menor <<<"$version"
if [ -z "$mayor" ] || (( mayor < 5 || (mayor == 5 && menor < 9) )); then
    echo 'Se requiere Swift 5.9 o superior.' >&2
    exit 1
fi
swift build --disable-sandbox -c "$configuracion" -q || exit 1
# En Windows .build/debug no siempre existe (no se pudo crear el enlace): se pregunta la ruta real.
BIN="$(swift build --disable-sandbox -c "$configuracion" --show-bin-path)/PitLane"
ok=0
falla=0
temporal=$(mktemp -d "${TMPDIR:-/tmp}/pitlane-tests.XXXXXX") || exit 1
trap 'rm -rf "$temporal"' EXIT

# En Windows (Git Bash) el intérprete recibe y muestra las rutas como C:/...
ruta_nativa() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

comparar() {  # nombre esperado codigo_esperado codigo_real
    local nombre="$1" esperado="$2" cod_esp="$3" cod_real="$4" d
    if ! d=$(diff "$temporal/stdout" "$esperado"); then
        echo "FALLA  $nombre"
        echo "$d"
        falla=$((falla + 1))
    elif [ "$cod_real" != "$cod_esp" ]; then
        echo "FALLA  $nombre (código de salida $cod_real, se esperaba $cod_esp)"
        falla=$((falla + 1))
    elif [ -s "$temporal/stderr" ]; then
        echo "FALLA  $nombre (salida inesperada por stderr)"
        cat "$temporal/stderr"
        falla=$((falla + 1))
    else
        echo "OK     $nombre"
        ok=$((ok + 1))
    fi
}

for esperado in ejemplos/*.esperado; do
    nombre=$(basename "$esperado" .esperado)
    case "$nombre" in
        *.completo)
            base="ejemplos/${nombre%.completo}"
            "$BIN" "$base.txt" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
            codigo=$?
            comparar "$nombre" "$esperado" 0 "$codigo"
            ;;
        *)
            base="ejemplos/$nombre"
            entrada=/dev/null
            [ -f "$base.in" ] && entrada="$base.in"
            "$BIN" --solo-salida "$base.txt" >"$temporal/stdout" 2>"$temporal/stderr" <"$entrada"
            codigo=$?
            cod_esp=0
            [[ "$nombre" == errores_* ]] && cod_esp=1
            comparar "$nombre" "$esperado" "$cod_esp" "$codigo"
            ;;
    esac
done

adversarial() {  # nombre programa salida_esperada codigo_esperado
    printf '%s' "$2" >"$temporal/programa.txt"
    printf '%s\n' "$3" >"$temporal/esperado"
    "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
    comparar "$1" "$temporal/esperado" "$4" "$?"
}

adversarial ciclo_lista $'parrilla x acelera []\nagregar(x, x)\ntransmision(x)\n' '[[<cycle>]]' 0
adversarial igualdad_ciclica $'parrilla x acelera []\nagregar(x, x)\nparrilla y acelera []\nagregar(y, y)\ntransmision(x empata y)\n' 'gana' 0
adversarial real_fuera_de_rango $'transmision(a_real("1e400"))\n' "Runtime error on line 1: invalid real '1e400'" 1
adversarial real_subdesbordado $'transmision(a_real("1e-400"))\n' "Runtime error on line 1: invalid real '1e-400'" 1
adversarial bucle_sin_fin $'vuelta gana:\nbandera_cuadros\n' 'Runtime error on line 1: execution limit exceeded' 1
adversarial parentesis_sin_cerrar $'transmision(1 + 2\nparrilla y acelera 3\n' "Syntax error on line 2: expected ')'" 1
adversarial romper_fuera_de_bucle $'transmision("a")\nbandera_verde gana:\nbandera_roja\nbandera_cuadros\n' "Syntax error on line 3: 'bandera_roja' outside loop" 1
adversarial continuar_fuera_de_bucle $'pit_stop\n' "Syntax error on line 1: 'pit_stop' outside loop" 1
adversarial meta_fuera_de_funcion $'transmision("a")\nmeta 5\n' "Syntax error on line 2: 'meta' outside function" 1
adversarial romper_en_funcion_dentro_de_bucle $'vuelta gana:\nboxes f():\nbandera_roja\nbandera_cuadros\nbandera_cuadros\n' "Syntax error on line 3: 'bandera_roja' outside loop" 1
adversarial parametro_repetido $'boxes f(a, b, a):\nmeta a\nbandera_cuadros\n' "Syntax error on line 1: duplicate parameter 'a'" 1
adversarial metodo_repetido $'escuderia C:\nboxes m():\nmeta 1\nbandera_cuadros\nboxes m(a):\nmeta 2\nbandera_cuadros\nbandera_cuadros\n' "Syntax error on line 5: duplicate method 'm'" 1
adversarial fin_de_linea_cr $'parrilla x acelera 1\rtransmision(x)\r' '1' 0
adversarial fuente_con_bom $'\xEF\xBB\xBFparrilla a\xC3\xB1o acelera "canci\xC3\xB3n"\ntransmision(a\xC3\xB1o)\n' 'canción' 0
adversarial fuente_windows_1252 $'parrilla a\xF1o acelera "canci\xF3n \x80"\ntransmision(a\xF1o)\n' 'canción €' 0
apertura=''
cierre=''
for ((i=0; i<140; i++)); do apertura+='('; cierre+=')'; done
adversarial anidamiento "transmision(${apertura}1${cierre})" 'Syntax error on line 1: nesting limit exceeded' 1
compartida=$'parrilla x acelera [1]\n'
for ((i=0; i<23; i++)); do compartida+=$'x acelera [x, x]\n'; done
adversarial texto_grande "${compartida}transmision(a_texto(x))" 'Runtime error on line 25: text limit exceeded' 1
comparacion=$'parrilla xs acelera []\nparrilla ys acelera []\n'
for longitud in 1000 1001; do
    if [ "$longitud" -eq 1000 ]; then lista=xs; else lista=ys; fi
    ultimo=$((longitud - 1))
    comparacion+="circuito i salida 0 llegada ${ultimo}:"$'\n'
    comparacion+="agregar(${lista}, [])"$'\n'
    comparacion+=$'bandera_cuadros\n'
    comparacion+="circuito i salida 0 llegada ${ultimo}:"$'\n'
    comparacion+="agregar(${lista}[i], ${lista}[(i + 1) % ${longitud}])"$'\n'
    comparacion+=$'bandera_cuadros\n'
done
adversarial comparacion_ciclica "${comparacion}transmision(xs[0] empata ys[0])" 'Runtime error on line 15: comparison limit exceeded' 1
printf -v bloque '%10000s' ''
# Retiene unos 400 MB de textos distintos: supera los 256 MiB de memoria residente.
# El cuerpo va en la línea del circuito para que el error tenga siempre la misma línea.
adversarial memoria "parrilla xs acelera []
parrilla bloque acelera \"${bloque}\"
circuito i salida 1 llegada 40000: agregar(xs, bloque + a_texto(i))
bandera_cuadros
transmision(longitud(xs))" 'Runtime error on line 3: memory limit exceeded' 1
# Lo que se libera no cuenta: armar un texto o crear listas temporales en un bucle no agota la memoria.
adversarial texto_en_bucle $'parrilla s acelera ""\ncircuito i salida 1 llegada 300000:\ns acelera s + "x"\nbandera_cuadros\ntransmision(longitud(s))\n' '300000' 0
adversarial texto_en_bucle_compuesto $'parrilla s acelera ""\ncircuito i salida 1 llegada 50000:\ns acelera s + i + ","\nbandera_cuadros\ntransmision(longitud(s))\n' '288894' 0
adversarial listas_temporales $'parrilla xs acelera []\ncircuito i salida 1 llegada 300000:\nxs acelera [i, i, i]\nbandera_cuadros\ntransmision(xs)\n' '[300000, 300000, 300000]' 0
adversarial texto_maximo $'parrilla s acelera ""\ncircuito i salida 1 llegada 100001:\ns acelera s + "xxxxxxxxxx"\nbandera_cuadros\n' 'Runtime error on line 3: text limit exceeded' 1

# El límite de tiempo es de CPU: esperar el teclado más de 5 s no cuenta, y un bucle
# infinito posterior se sigue cortando con su línea.
printf '%s\n' 'parrilla x acelera radio()' 'transmision("leido: " + x)' >"$temporal/programa.txt"
printf '%s\n' 'leido: hola' >"$temporal/esperado"
{ sleep 6; printf 'hola\n'; } | "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr"
comparar espera_radio "$temporal/esperado" 0 "$?"

printf '%s\n' 'parrilla x acelera radio()' 'transmision("antes")' 'vuelta gana:' 'bandera_cuadros' >"$temporal/programa.txt"
printf '%s\n' 'antes' 'Runtime error on line 3: execution limit exceeded' >"$temporal/esperado"
{ sleep 6; printf 'hola\n'; } | "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr"
comparar bucle_tras_radio "$temporal/esperado" 1 "$?"

# El ejecutable debe relanzarse aunque se invoque desde otra carpeta por PATH.
printf '%s\n' 'Mayor que 5' >"$temporal/esperado"
bin_dir=$(cd "$(dirname "$BIN")" && pwd)
repo_dir=$(pwd)
(cd "$temporal" && PATH="$bin_dir:$PATH" PitLane --solo-salida "$repo_dir/ejemplos/programa1.txt") >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
comparar ejecutable_en_path "$temporal/esperado" 0 "$?"

printf '%s\n' "Error: cannot read file '$(ruta_nativa "$temporal")/inexistente.txt'" >"$temporal/esperado"
"$BIN" --solo-salida "$temporal/inexistente.txt" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
if [ "$?" -eq 1 ] && [ ! -s "$temporal/stdout" ] && diff -q "$temporal/stderr" "$temporal/esperado" >/dev/null; then
    ok=$((ok + 1))
else
    echo 'FALLA  archivo_inexistente'
    falla=$((falla + 1))
fi

error_de_uso() {  # nombre mensaje argumentos...
    local nombre="$1" mensaje="$2"
    shift 2
    printf '%s\n' "$mensaje" >"$temporal/esperado"
    "$BIN" "$@" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
    if [ "$?" -eq 1 ] && [ ! -s "$temporal/stdout" ] && diff -q "$temporal/stderr" "$temporal/esperado" >/dev/null; then
        ok=$((ok + 1))
    else
        echo "FALLA  $nombre"
        falla=$((falla + 1))
    fi
}
error_de_uso argumentos_invalidos 'Usage: PitLane [--solo-salida] <archivo.txt>'
# 0x81 no es UTF-8 válido ni está asignado en Windows-1252.
printf '\201' >"$temporal/invalido.txt"
error_de_uso fuente_ilegible "Error: cannot read file '$(ruta_nativa "$temporal")/invalido.txt'" "$temporal/invalido.txt"
printf -v relleno '%1000001s' ''
printf '%s' "$relleno" >"$temporal/excesivo.txt"
unset relleno
error_de_uso fuente_excesiva 'Error: source file exceeds 1000000 bytes' "$temporal/excesivo.txt"

generado() {  # nombre programa salida_esperada
    printf '%s\n' "$2" >"$temporal/programa.txt"
    printf '%s\n' "$3" >"$temporal/esperado"
    "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
    codigo=$?
    if [ "$codigo" -ne 0 ] || [ -s "$temporal/stderr" ] || ! diff -q "$temporal/stdout" "$temporal/esperado" >/dev/null; then
        echo "FALLA  $1 (código $codigo)"
        diff "$temporal/stdout" "$temporal/esperado" || true
        cat "$temporal/stderr"
        falla=$((falla + 1))
    else
        ok=$((ok + 1))
    fi
}

generado entrada_cerrada 'transmision(radio())' ''

for ((caso=0; caso<20; caso++)); do
    a=$(((caso * 7) % 31))
    b=$(((caso * 11) % 17 + 1))
    c=$((caso % 5 + 1))
    generado "aritmetica_$caso" "transmision((${a} + ${b}) * ${c})" "$(((a + b) * c))"
    if [ "$a" -gt "$b" ]; then esperado_condicion=$a; else esperado_condicion=$b; fi
    generado "condicion_$caso" "bandera_verde ${a} supera ${b}:
transmision(${a})
bandera_azul:
transmision(${b})
bandera_cuadros" "$esperado_condicion"
    generado "bucle_$caso" "parrilla total acelera 0
circuito i salida 1 llegada ${c}:
total acelera total + i
bandera_cuadros
transmision(total)" "$((c * (c + 1) / 2))"
    generado "lista_$caso" "parrilla xs acelera [${a}, ${b}]
agregar(xs, ${c})
transmision(xs[2])" "$c"
    generado "funcion_$caso" "boxes doble(x):
meta x * 2
bandera_cuadros
transmision(doble(${a}))" "$((a * 2))"
    generado "clase_$caso" "escuderia Caja:
ensamble(v):
auto.v acelera v
bandera_cuadros
boxes leer():
meta auto.v
bandera_cuadros
bandera_cuadros
parrilla obj acelera debut Caja(${a})
transmision(obj.leer())" "$a"
    generado "excepcion_$caso" "safety_car:
penalizacion ${a}
accidente e:
transmision(e)
bandera_cuadros" "$a"
    if [ "$a" -gt "$b" ]; then esperado_mixto=$((a + b + c)); else esperado_mixto=$c; fi
    generado "combinado_$caso" "boxes sumar(xs):
parrilla total acelera 0
circuito i salida 0 llegada 2:
total acelera total + xs[i]
bandera_cuadros
meta total
bandera_cuadros
parrilla xs acelera [${a}, ${b}, ${c}]
bandera_verde ${a} supera ${b}:
transmision(sumar(xs))
bandera_azul:
transmision(xs[2])
bandera_cuadros" "$esperado_mixto"
done

for base in ejemplos/*.txt; do
    case "$base" in ejemplos/errores_*) continue ;; esac
    entrada=/dev/null
    [ -f "${base%.txt}.in" ] && entrada="${base%.txt}.in"
    "$BIN" --solo-salida "$base" >"$temporal/original" 2>"$temporal/original.err" <"$entrada"
    codigo_original=$?
    awk '{ print; print ""; print "// comentario" }' "$base" >"$temporal/programa.txt"
    "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr" <"$entrada"
    codigo=$?
    if [ "$codigo" -ne "$codigo_original" ] || [ -s "$temporal/stderr" ] || ! diff -q "$temporal/stdout" "$temporal/original" >/dev/null; then
        echo "FALLA  metamorfica_$(basename "$base")"
        falla=$((falla + 1))
    else
        ok=$((ok + 1))
    fi
done

estado=20261019
simbolos=(a b x 0 1 9 + - '*' / % '(' ')' '[' ']' ':' ',' '.' '#' '@' '"' $'\n' 'ñ' '😀')
semilla=$(cat ejemplos/programa1.txt)
for ((caso=0; caso<200; caso++)); do
    estado=$(((estado * 1103515245 + 12345) % 2147483648))
    longitud=$((estado % 120))
    programa=''
    if ((caso % 2 == 0)); then
        posicion=$((estado % ${#semilla}))
        programa="${semilla:0:posicion}${simbolos[estado % ${#simbolos[@]}]}${semilla:posicion+1}"
    else
        for ((j=0; j<longitud; j++)); do
            estado=$(((estado * 1103515245 + 12345) % 2147483648))
            programa+="${simbolos[estado % ${#simbolos[@]}]}"
        done
    fi
    printf '%s' "$programa" >"$temporal/programa.txt"
    "$BIN" --solo-salida "$temporal/programa.txt" >"$temporal/stdout" 2>"$temporal/stderr" </dev/null
    codigo=$?
    if { [ "$codigo" -ne 0 ] && [ "$codigo" -ne 1 ]; } || [ -s "$temporal/stderr" ]; then
        echo "FALLA  mutacion $caso (código $codigo)"
        cat "$temporal/stderr"
        falla=$((falla + 1))
        break
    fi
    ok=$((ok + 1))
done

echo "---"
echo "$ok OK, $falla FALLA"
exit $((falla > 0))
