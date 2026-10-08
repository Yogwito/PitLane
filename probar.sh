#!/bin/bash
# Corre cada ejemplos/*.txt que tenga .esperado con --solo-salida y compara solo stdout.
cd "$(dirname "$0")" || exit 1
swift build -q 2>&1 | grep -E "error" && exit 1
BIN=.build/debug/PitLane
fallas=0
for esperado in ejemplos/*.esperado; do
    base="${esperado%.esperado}"
    entrada=/dev/null
    [ -f "$base.in" ] && entrada="$base.in"
    real=$("$BIN" --solo-salida "$base.txt" < "$entrada" 2>/dev/null)
    if diff_out=$(diff <(printf '%s\n' "$real") "$esperado"); then
        echo "OK     $(basename "$base")"
    else
        echo "FALLA  $(basename "$base")"
        echo "$diff_out"
        fallas=$((fallas + 1))
    fi
done
echo "---"
[ "$fallas" -eq 0 ] && echo "Todo OK" || echo "$fallas programa(s) con FALLA"
exit $((fallas > 0))
