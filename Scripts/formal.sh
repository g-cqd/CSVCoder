#!/bin/sh
# Checks the formal models in Formal/: TLA+ with TLC, and Lean 4 proofs.
#
#   Scripts/formal.sh            run every model
#   Scripts/formal.sh tla        the TLA+ models only (swift-ci's `tla-models` command, as CI runs them)
#   Scripts/formal.sh lean       the Lean proofs only
#
# Every Formal/<Module>.cfg must hold. A Formal/<Module>.buggy.cfg is a control: it keeps the broken protocol on
# record (BackpressureOld deadlocks) and proves the checker can fail, so it must be refuted and a green run of its
# fixed twin means something. swift-ci runs TLC (tla2tools 1.7.4, pinned by SHA-256 in its tool lock) with Java,
# each model in a state directory of its own. The proofs need `lean` (via elan; Formal/lean-toolchain pins it).
#
# Exit: 0 every expectation held, 1 one did not, 2 a tool could not be installed or run.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit "${2:-1}"; }

run_tla() {
    .ci/swift-ci run tla-models || fail "a TLA+ model did not give its verdict"
}

run_lean() {
    command -v lean >/dev/null 2>&1 || fail "lean is not installed (elan)" 2
    for proof in Formal/*.lean; do
        printf '==> lean %s\n' "$proof"
        lean "$proof" || fail "$proof does not check"
    done
}

case "${1:-all}" in
    tla) run_tla ;;
    lean) run_lean ;;
    all) run_tla; run_lean ;;
    *) fail "usage: formal.sh [tla|lean]" 2 ;;
esac
printf '[OK] formal models hold\n'
