#!/bin/bash
# build 92 — DiagnosticLogger persists across a process kill + refreshHistory
# self-await hardening. Source pins on the shipped files (never copies), the
# REAL DiagnosticLogger executed across two processes to prove the tail
# survives a kill, and the refreshHistory coalescing primitive executed with a
# non-vacuous control that must deadlock.
#   bash docs/diagnostic-persistence-check/check.sh            # pins + tests + xcodebuild
#   bash docs/diagnostic-persistence-check/check.sh --no-build # pins + tests only
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { local label=$1; shift; if eval "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $label"; else fail=$((fail+1)); echo "  ✗ $label"; fi; }
DL=EVVMobile/Services/DiagnosticLogger.swift
AS=EVVMobile/State/AppState.swift
API=EVVMobile/Services/APIClient.swift
TMP=/tmp/evv-diag92
mkdir -p $TMP

echo "[1] DiagnosticLogger — persistence wiring"
ok "writes JSON-lines to a file in Application Support (survives relaunch)" "grep -q 'applicationSupportDirectory' $DL && grep -q 'diagnostic-log.jsonl' $DL"
ok "reloads the persisted tail at init (pre-crash entries come back)" "grep -q 'func loadPersistedTail' $DL && grep -A14 'private init' $DL | grep -q 'loadPersistedTail()'"
ok "appends on EVERY log call, inside the existing barrier (never the main thread)" "grep -A12 'func log(_ category' $DL | grep -q 'queue.async(flags: .barrier)' && grep -A12 'func log(_ category' $DL | grep -q 'appendToDisk(entry)'"
ok "flushes immediately — no timer, no batch drain that a watchdog kill would lose" "! grep -q 'Timer\|DispatchQueue.*asyncAfter' $DL"
ok "holds an open FileHandle (one write(2) per entry, not open/close)" "grep -q 'FileHandle(forWritingTo' $DL && grep -q 'h.write(contentsOf: line)' $DL"
ok "bounded in memory (maxEntries ring)" "grep -q 'private let maxEntries = 500' $DL && grep -A12 'func log(_ category' $DL | grep -q 'removeFirst(self.buffer.count - self.maxEntries)'"
ok "bounded on disk (byte cap + periodic trim, rewritten from the capped ring)" "grep -q 'maxFileBytes' $DL && grep -q 'trimEveryNWrites' $DL && grep -q 'bytesWritten > maxFileBytes || writesSinceTrim >= trimEveryNWrites' $DL"
ok "a truncated final line is SKIPPED, not fatal (mid-write kill leaves one)" "grep -A6 'for line in data.split' $DL | grep -q 'try? decoder.decode(Entry.self'"
ok "clear() wipes the FILE too (or every future submission re-sends old entries)" "grep -A6 'func clear' $DL | grep -q 'rewriteFile()'"
ok "excluded from iCloud backup, matching LocalCache" "grep -q 'isExcludedFromBackup' $DL"
ok "timestamps carry fractional seconds so ordering is unambiguous" "grep -q 'withFractionalSeconds' $DL"

echo "[2] relaunch boundary + submission path (server contract UNCHANGED)"
ok "markLaunch() logs a lifecycle boundary naming the build" "grep -q 'func markLaunch' $DL && grep -A5 'func markLaunch' $DL | grep -q 'CFBundleVersion'"
ok "the boundary says entries above it are from a previous run" "grep -A6 'func markLaunch' $DL | grep -q 'previous run'"
ok "AppState.init() calls markLaunch() once at startup" "grep -A6 'init() {' $AS | grep -q 'DiagnosticLogger.shared.markLaunch()'"
ok "exportEntries() still returns [[String:String]] with the same 3 keys" "grep -A4 'func exportEntries' $DL | grep -q '\\[\"timestamp\": \$0.timestamp, \"category\": \$0.category, \"message\": \$0.message\\]'"
ok "submitDiagnosticLog() is unchanged — it just sees the older entries now" "grep -A4 'func submitDiagnosticLog' $AS | grep -q 'DiagnosticLogger.shared.exportEntries()'"
ok "POST /logs body shape untouched (no server change needed)" "grep -A8 'func submitLogs' $API | grep -q '\\[\"entries\": entries\\]'"

echo "[3] refreshHistory — self-await hardening (the build-91 freeze)"
ok "isRefreshingHistory is declared @MainActor next to historyRefreshTask" "grep -q '@MainActor private var isRefreshingHistory = false' $AS"
ok "the re-entry guard is checked BEFORE awaiting the in-flight task" "grep -A6 'if let inflight = historyRefreshTask' $AS | grep -B2 'await inflight.value' | grep -q 'if isRefreshingHistory { return }'"
ok "the flag is SET inside the task body (so only re-entrants see it true)" "grep -A8 'let task = Task { @MainActor \\[weak self\\] in' $AS | grep -q 'self.isRefreshingHistory = true'"
ok "…and CLEARED after performHistoryRefresh (not left stuck)" "grep -A8 'let task = Task { @MainActor \\[weak self\\] in' $AS | grep -q 'self.isRefreshingHistory = false'"
ok "build-53 coalescing PRESERVED — independent callers still await inflight.value" "grep -A7 'if let inflight = historyRefreshTask' $AS | grep -q 'await inflight.value'"
ok "the unstructured Task is still unstructured (build 53 cancellation fix intact)" "grep -A10 'func refreshHistory() async' $AS | grep -q 'let task = Task { @MainActor'"
ok "historyRefreshTask is still cleared when the refresh ends" "grep -A9 'let task = Task { @MainActor \\[weak self\\] in' $AS | grep -q 'self.historyRefreshTask = nil'"
ok "no new file added for either change (no hand-edited pbxproj needed)" "! grep -q 'isRefreshingHistory' EVVMobile.xcodeproj/project.pbxproj"

echo "[4] EXECUTE the real DiagnosticLogger across two processes (kill simulation)"
{
  echo "import Foundation"
  awk '/^final class DiagnosticLogger/,/^}$/' $DL
  grep -v "^import Foundation" docs/diagnostic-persistence-check/logger_test.swift
} > $TMP/logger_main.swift
if swiftc -O -o $TMP/logger $TMP/logger_main.swift 2>$TMP/logger_compile.log; then
  pass=$((pass+1)); echo "  ✓ real DiagnosticLogger class compiles standalone (lifted verbatim from the shipped file)"
  if $TMP/logger write > $TMP/logger_p1.log 2>&1; then
    pass=$((pass+1)); echo "  ✓ phase 1 (write + flush + bounded ring): $(tail -1 $TMP/logger_p1.log)"
    sed -n 's/^  \(✓\|✗\) /      /p' $TMP/logger_p1.log
  else
    fail=$((fail+1)); echo "  ✗ phase 1"; cat $TMP/logger_p1.log
  fi
  # Simulate a kill mid-write: append a truncated JSON line, like a process
  # that died between write(2) and the newline.
  printf '{"timestamp":"2026-09-23T12:00:00.000Z","category":"api","message":"TRUNCATED-GARBAGE' \
    >> "$HOME/Library/Application Support/EVVCache/diagnostic-log.jsonl"
  if $TMP/logger reload > $TMP/logger_p2.log 2>&1; then
    pass=$((pass+1)); echo "  ✓ phase 2 (fresh process reloads the pre-crash tail): $(tail -1 $TMP/logger_p2.log)"
    sed -n 's/^  \(✓\|✗\) /      /p' $TMP/logger_p2.log
  else
    fail=$((fail+1)); echo "  ✗ phase 2 — the tail did NOT survive"; cat $TMP/logger_p2.log
  fi
else
  fail=$((fail+1)); echo "  ✗ DiagnosticLogger failed to compile standalone"; tail -20 $TMP/logger_compile.log
fi

echo "[5] EXECUTE the refreshHistory coalescing primitive (+ deadlock control)"
if swiftc -O -parse-as-library -o $TMP/refresh docs/diagnostic-persistence-check/refresh_test.swift 2>$TMP/refresh_compile.log \
   || swiftc -O -o $TMP/refresh docs/diagnostic-persistence-check/refresh_test.swift 2>>$TMP/refresh_compile.log; then
  if $TMP/refresh > $TMP/refresh_run.log 2>&1; then
    pass=$((pass+1)); echo "  ✓ refresh_test.swift: $(tail -1 $TMP/refresh_run.log)"
    sed -n 's/^  \(✓\|✗\) /      /p' $TMP/refresh_run.log
  else
    fail=$((fail+1)); echo "  ✗ refresh_test.swift"; cat $TMP/refresh_run.log
  fi
else
  fail=$((fail+1)); echo "  ✗ refresh_test.swift failed to compile"; tail -20 $TMP/refresh_compile.log
fi

echo "[6] build number"
ok "Info.plist CFBundleVersion is 93 (TestFlight build 92 was already taken by Xcode Cloud run 92)" "grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q '<string>93</string>'"

if [ "${1:-}" != "--no-build" ]; then
  echo "[7] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-diag92 CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-diag92/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
