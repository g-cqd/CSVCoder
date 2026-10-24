#!/bin/sh
# Checks the formal models in Formal/: TLA+ with TLC, and Lean 4 proofs.
#
#   Scripts/formal.sh            run every model
#
# Each TLA+ model states what TLC must report. A model that is expected to FAIL is a control: it keeps
# the broken protocol on record and proves the checker can fail, so a green run of its fixed twin means
# something. Java 17+ and, for the proofs, `lean` (via elan; Formal/lean-toolchain pins the version) must be
# installed. TLC is downloaded once, pinned by SHA-256.
#
# Exit: 0 every expectation held, 1 one did not, 2 a tool could not be installed or run.
set -eu

TLA_VERSION=1.7.4
TLA_SHA=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
case "$(uname -s)" in
    Darwin) CACHE="${CSVCODER_FORMAL_DIR:-$HOME/Library/Caches/csvcoder/formal}" ;;
    *) CACHE="${CSVCODER_FORMAL_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/csvcoder/formal}" ;;
esac

fail() { printf '[FAIL] %s\n' "$1" >&2; exit "${2:-1}"; }

sha256() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1; }

JAR="$CACHE/tla2tools-$TLA_VERSION.jar"
if [ ! -f "$JAR" ]; then
    mkdir -p "$CACHE"
    printf '==> installing TLA+ tools %s\n' "$TLA_VERSION"
    curl -fsSL --retry 3 -o "$JAR.part" \
        "https://github.com/tlaplus/tlaplus/releases/download/v$TLA_VERSION/tla2tools.jar" \
        || fail "tla2tools: download failed" 2
    [ "$(sha256 "$JAR.part")" = "$TLA_SHA" ] || { rm -f "$JAR.part"; fail "tla2tools: hash is not the pinned $TLA_SHA" 2; }
    mv "$JAR.part" "$JAR"
fi
command -v java >/dev/null 2>&1 || fail "java is not installed" 2

# tlc MODEL EXPECTATION: EXPECTATION is `pass` or a phrase TLC must print.
tlc() {
    model=$1 expect=$2
    printf '==> TLC %s (expects %s)\n' "$model" "$expect"
    out=$(mktemp)
    # TLC exits non-zero on a violation, so judge by its report, not its status.
    java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -nowarning -workers 1 \
        -config "Formal/$model.cfg" "Formal/$model.tla" >"$out" 2>&1 || true
    if [ "$expect" = pass ]; then
        grep -q "Model checking completed. No error has been found." "$out" \
            || { cat "$out"; rm -f "$out"; fail "$model: TLC found an error in a model that must hold"; }
    else
        grep -q "$expect" "$out" \
            || { cat "$out"; rm -f "$out"; fail "$model: TLC did not report '$expect'; the control no longer fails"; }
    fi
    rm -f "$out"
}

tlc BackpressureOld "Error: Deadlock reached."
tlc BackpressureNew pass

command -v lean >/dev/null 2>&1 || fail "lean is not installed (elan)" 2
for proof in Formal/*.lean; do
    printf '==> lean %s\n' "$proof"
    lean "$proof" || fail "$proof does not check"
done
printf '[OK] formal models hold\n'
