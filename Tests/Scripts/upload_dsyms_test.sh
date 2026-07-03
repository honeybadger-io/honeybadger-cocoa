#!/bin/bash
# Tests for bin/upload-dsyms.sh using stubbed curl/dwarfdump.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPLOAD="$REPO_ROOT/bin/upload-dsyms.sh"
export PATH="$SCRIPT_DIR/stubs:$PATH"

PASS=0; FAIL=0

make_dsyms() {
    WORK=$(mktemp -d)
    mkdir -p "$WORK/dsyms/AppOne.dSYM/Contents/Resources/DWARF"
    echo fake > "$WORK/dsyms/AppOne.dSYM/Contents/Resources/DWARF/AppOne"
    mkdir -p "$WORK/dsyms/AppTwo.dSYM/Contents/Resources/DWARF"
    echo fake > "$WORK/dsyms/AppTwo.dSYM/Contents/Resources/DWARF/AppTwo"
}

check() {  # check <desc> <expected_exit> <actual_exit>
    if [[ "$2" == "$3" ]]; then
        echo "PASS: $1"; PASS=$((PASS+1))
    else
        echo "FAIL: $1 (expected exit $2, got $3)"; FAIL=$((FAIL+1))
    fi
}

make_dsyms
CURL_MODE=ok bash "$UPLOAD" --api-key test --dsym-path "$WORK/dsyms" > "$WORK/out1.log" 2>&1
check "all uploads succeed -> exit 0" 0 $?

CURL_MODE=http-fail bash "$UPLOAD" --api-key test --dsym-path "$WORK/dsyms" > "$WORK/out2.log" 2>&1
check "all uploads fail -> exit 1" 1 $?

CURL_MODE=http-fail bash "$UPLOAD" --api-key test --dsym-path "$WORK/dsyms" --warn-only > "$WORK/out3.log" 2>&1
check "all uploads fail with --warn-only -> exit 0" 0 $?

CURL_MODE=transport-fail bash "$UPLOAD" --api-key test --dsym-path "$WORK/dsyms" > "$WORK/out4.log" 2>&1
RC=$?
check "transport failure -> exit 1, not mid-loop abort" 1 $RC
if grep -q "AppTwo.dSYM" "$WORK/out4.log"; then
    echo "PASS: transport failure on first bundle still processes second"; PASS=$((PASS+1))
else
    echo "FAIL: script aborted before processing second bundle"; FAIL=$((FAIL+1)); cat "$WORK/out4.log"
fi

DWARFDUMP_MODE=fail CURL_MODE=ok bash "$UPLOAD" --api-key test --dsym-path "$WORK/dsyms" > "$WORK/out5.log" 2>&1
check "dwarfdump failure -> warn + exit 1, no abort" 1 $?

rm -rf "$WORK"
echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
