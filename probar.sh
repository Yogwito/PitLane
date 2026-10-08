#!/bin/bash
# Corre los ejemplos de ejemplos/ y compara contra su .esperado:
#   X.esperado          -> X.txt con --solo-salida, solo stdout (con X.in por stdin si existe).
#                          Si X empieza con "errores_", el código de salida debe ser 1.
#   X.completo.esperado -> X.txt SIN --solo-salida, compara toda la salida.
cd "$(dirname "$0")" || exit 1
swift build -q 2>&1 | grep -E "error" && exit 1
BIN=.build/debug/PitLane
ok=0
falla=0

comparar() {  # nombre  real  esperado  [codigo_esperado  codigo_real]
    local nombre="$1" real="$2" esperado="$3" cod_esp="$4" cod_real="$5" d
    if ! d=$(diff <(printf '%s\n' "$real") "$esperado"); then
        echo "FALLA  $nombre"
        echo "$d"
        falla=$((falla + 1))
    elif [ -n "$cod_esp" ] && [ "$cod_real" != "$cod_esp" ]; then
        echo "FALLA  $nombre (código de salida $cod_real, se esperaba $cod_esp)"
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
            real=$("$BIN" "$base.txt" 2>/dev/null </dev/null)
            comparar "$nombre" "$real" "$esperado"
            ;;
        *)
            base="ejemplos/$nombre"
            entrada=/dev/null
            [ -f "$base.in" ] && entrada="$base.in"
            real=$("$BIN" --solo-salida "$base.txt" 2>/dev/null <"$entrada")
            codigo=$?
            cod_esp=""
            [[ "$nombre" == errores_* ]] && cod_esp=1
            comparar "$nombre" "$real" "$esperado" "$cod_esp" "$codigo"
            ;;
    esac
done

echo "---"
echo "$ok OK, $falla FALLA"
exit $((falla > 0))
