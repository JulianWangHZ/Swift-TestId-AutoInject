#!/bin/bash
set -u
cd "$(dirname "$0")/.."
SP="${TMPDIR:-/tmp}/swift-testid-autoinject"; mkdir -p "$SP"
DD=$SP/DD-phase; rm -rf $DD
DEST="${DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
# TESTID_INJECTOR points at a local build when testid-inject is not on PATH.
INJ="${TESTID_INJECTOR:+TESTID_INJECTOR=$TESTID_INJECTOR}"
X="xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Debug -derivedDataPath $DD $INJ"
BIN=$DD/Build/Products/Debug-iphonesimulator/Demo.app/Demo.debug.dylib
F=Demo/Demo/LoginView.swift

echo "== 1. clean test"
$X -destination "$DEST" test > "$SP/v1.log" 2>&1; echo "exit=$?"
grep -E "Test [Cc]ase .*(passed|failed)|\*\* " "$SP/v1.log" | sed 's/ on .*//'
echo "phase before compile?"; grep -nE "^PhaseScriptExecution|^SwiftCompile normal arm64 /" "$SP/v1.log" | head -3 | cut -c1-90

echo "== 2. no-op rebuild"
$X -destination "$DEST" build > "$SP/v2.log" 2>&1; echo "exit=$?"
echo "SwiftCompile tasks: $(grep -cE '^SwiftCompile normal arm64 /' "$SP/v2.log")"

echo "== 3. edit source -> incremental"
cp $F $SP/LoginView.bak; trap 'cp $SP/LoginView.bak $F' EXIT
sed -i '' 's/Button("Sign In")/Button("Log In")/' $F
$X -destination "$DEST" build > "$SP/v3.log" 2>&1; echo "exit=$?"
echo "SwiftCompile tasks: $(grep -cE '^SwiftCompile normal arm64 /' "$SP/v3.log")"
strings $BIN | grep -E "LoginView\.button\.(sign-in|log-in)"
cp $SP/LoginView.bak $F
echo "source restored: $(grep -c 'Sign In' $F)"

echo "== 4. Release (no injection)"
xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Release -destination "$DEST" -derivedDataPath $DD build > "$SP/v4.log" 2>&1; echo "exit=$?"
echo "IDs in Release binary: $(strings $DD/Build/Products/Release-iphonesimulator/Demo.app/Demo | grep -c 'LoginView\.button')"

echo "== 5. tool missing -> warning, build still passes"
DD2=$SP/DD-missing; rm -rf $DD2
xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Debug -destination "$DEST" -derivedDataPath $DD2 TESTID_INJECTOR=/nonexistent build > "$SP/v5.log" 2>&1; echo "exit=$?"
grep -m1 -o "warning: testid-inject is not installed[^\"]*" "$SP/v5.log"
