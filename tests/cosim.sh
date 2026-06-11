#!/bin/bash
# Co-simulation check: run the same program on three independent engines
# (C++ simulator, Icarus Verilog, Verilator) and verify identical output.
# Usage: tests/cosim.sh <program.hex>
set -e
cd "$(dirname "$0")/.."

prog="$1"
[ -z "$prog" ] && { echo "Usage: tests/cosim.sh <program.hex>"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

norm() { grep -E '^(OUT |R[1-7]=|PC=|SP=)'; }

./cpp/simulator "$prog" --cosim                    > "$tmp/cpp.txt"
vvp sim/run_tb +hex="$prog"           | norm       > "$tmp/icarus.txt"
./obj_dir/Vrun_tb +hex="$prog"        | norm       > "$tmp/verilator.txt"

ok=1
diff "$tmp/cpp.txt" "$tmp/icarus.txt"    > /dev/null || { echo "MISMATCH: C++ vs Icarus";     diff "$tmp/cpp.txt" "$tmp/icarus.txt" || true; ok=0; }
diff "$tmp/cpp.txt" "$tmp/verilator.txt" > /dev/null || { echo "MISMATCH: C++ vs Verilator"; diff "$tmp/cpp.txt" "$tmp/verilator.txt" || true; ok=0; }

if [ "$ok" = 1 ]; then
    echo "COSIM PASS ($prog): C++ simulator, Icarus, and Verilator all agree:"
    cat "$tmp/cpp.txt" | sed 's/^/  /'
else
    exit 1
fi
