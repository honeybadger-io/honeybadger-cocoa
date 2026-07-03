#!/bin/bash
# Compiles the SDK + harness, crashes it for real, relaunches, and asserts the
# replayed report carries the CRASHED run's binary images (not the replay
# run's). macOS only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Isolate NSCachesDirectory (~/Library/Caches) under a throwaway HOME.
# CFFIXED_USER_HOME must be set alongside HOME: on modern macOS,
# NSHomeDirectory() resolves via getpwuid() and ignores a bare $HOME
# override; CFFIXED_USER_HOME (the mechanism the iOS Simulator uses for the
# same purpose) is what Foundation actually honors.
export HOME="$WORK/home"
export CFFIXED_USER_HOME="$HOME"
mkdir -p "$HOME"
REPORT_DIR="$HOME/Library/Caches/HoneybadgerCrashReports"

echo "Building harness..."
clang -fobjc-arc -framework Foundation \
    -I "$REPO_ROOT/Sources/ObjC/include" -I "$REPO_ROOT/Sources/ObjC" \
    "$REPO_ROOT/Sources/ObjC/Honeybadger.m" "$SCRIPT_DIR/crash_harness.m" \
    -o "$WORK/harness" || { echo "FAIL: harness build"; exit 1; }

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "Run 1: crash via SIGSEGV..."
"$WORK/harness" crash "$WORK" && bad "crash run should exit nonzero" || ok "crash run died as expected"
[[ -f "$REPORT_DIR/signal_crash.bin" ]] && ok "signal_crash.bin written" || bad "signal_crash.bin missing"
CRASH_LOAD=$(cat "$WORK/load_address_crash.txt")

echo "Run 2: replay..."
"$WORK/harness" replay "$WORK" || bad "replay run should exit 0"
REPLAY_LOAD=$(cat "$WORK/load_address_replay.txt")
JSON=$(ls "$REPORT_DIR"/crash_signal_*.json 2>/dev/null | head -1)
[[ -n "$JSON" ]] && ok "converted crash_signal_*.json exists" || { bad "no crash_signal_*.json produced"; exit 1; }
[[ -f "$REPORT_DIR/signal_crash.bin" ]] && bad "signal_crash.bin should be deleted after conversion" || ok "signal_crash.bin deleted"

echo "Crashed-run load address: $CRASH_LOAD; replay-run: $REPLAY_LOAD"
python3 - "$JSON" "$CRASH_LOAD" "$REPLAY_LOAD" "$WORK/harness" <<'EOF'
import json, sys
payload = json.load(open(sys.argv[1]))
crash_load, replay_load, harness = sys.argv[2], sys.argv[3], sys.argv[4]
images = payload.get("binary_images", [])
mains = [i for i in images if i.get("name", "").endswith("/harness")]
assert mains, "harness image missing from binary_images"
got = mains[0]["load_address"]
assert got == crash_load, f"binary_images has {got}, want crashed-run {crash_load}"
if crash_load != replay_load:
    assert got != replay_load, "binary_images came from the replay process (ASLR bug regressed)"
frames = payload["error"]["backtrace"]
assert frames, "no frames in replayed report"
assert payload["error"]["message"].startswith("Signal SIGSEGV"), payload["error"]["message"]
print("PASS: replayed report symbolication data comes from the crashed process")
EOF
[[ $? -eq 0 ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo "Run 3: stack overflow (requires SA_ONSTACK)..."
rm -f "$REPORT_DIR"/signal_crash.bin "$REPORT_DIR"/crash_signal_*.json
"$WORK/harness" overflow "$WORK" && bad "overflow run should exit nonzero" || ok "overflow run died as expected"
[[ -f "$REPORT_DIR/signal_crash.bin" ]] && ok "stack-overflow crash captured (alt stack works)" || bad "stack-overflow crash NOT captured"

echo ""
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
