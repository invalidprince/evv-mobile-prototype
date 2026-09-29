#!/bin/bash
# build 105 — proof for the forced-update hard-block screen (Todoist 6hcHPc4VFcRcFPCH):
# "Sign out" on UpdateRequiredView is NOT a way to destroy queued punches.
# Source pins on the shipped files (never copies) + the REAL LocalCache queue
# envelope save/load executed standalone: save under staff A, clearAll-style
# wipe, re-save preserved punches, load as A (restored) and as B (refused).
#   bash docs/signout-queue-check/check.sh
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { local label=$1; shift; if eval "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $label"; else fail=$((fail+1)); echo "  ✗ $label"; fi; }
AS=EVVMobile/State/AppState.swift
LC=EVVMobile/Services/LocalCache.swift
GATE=EVVMobile/Services/AppUpdateGate.swift
TMP=/tmp/evv-signout-queue-check
mkdir -p $TMP

echo "[1] AppState.signOut() preserves queued punches (build 45 guarantee, unchanged)"
ok "captures the punches BEFORE the queue is emptied" "awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'preservedPunches = offlineQueue.filter' | cut -d: -f1 | xargs -I{} test {} -lt $(awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'offlineQueue.removeAll' | cut -d: -f1)"
ok "captures the owner staff id before serverStaff is cleared" "awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'queueOwner = serverStaff?.id' | cut -d: -f1 | xargs -I{} test {} -lt $(awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'serverStaff = nil' | cut -d: -f1)"
ok "re-saves the preserved punches AFTER LocalCache.clearAll() (so the wipe cannot eat them)" "awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'saveOfflineQueue(preservedPunches, staffId: owner)' | cut -d: -f1 | xargs -I{} test {} -gt $(awk '/func signOut\(\)/,/^    }$/' $AS | grep -n 'LocalCache.shared.clearAll()' | cut -d: -f1)"
ok "logs the preservation so a diagnostic submission shows it" "awk '/func signOut\(\)/,/^    }$/' $AS | grep -q 'Preserved .*queued punch'"

echo "[2] sign back in restores the queue for the SAME staff only"
ok "restoreOfflineQueue() loads by matching staff id" "grep -A4 'private func restoreOfflineQueue' $AS | grep -q 'loadOfflineQueue(matching: staffId)'"
ok "restoreOfflineQueue() is called from the login paths (at least two call sites)" "test $(grep -c 'self.restoreOfflineQueue()' $AS) -ge 2"
ok "restore re-arms pendingSyncCount and auto-sync" "grep -A8 'private func restoreOfflineQueue' $AS | grep -q 'pendingSyncCount = saved.count' && grep -A8 'private func restoreOfflineQueue' $AS | grep -q 'scheduleAutoSync()'"
ok "a different staff id leaves the file on disk untouched" "grep -A10 'func loadOfflineQueue' $LC | grep -q 'envelope.staffId == staffId'"

echo "[3] the block screen itself"
ok "Sign out is behind a confirmation dialog, not a bare tap" "grep -q 'Sign out of this phone?' $GATE && grep -q 'isPresented: \$confirmSignOut' $GATE"
ok "dialog tells the user their saved punches stay on the phone" "grep -q 'stay.* on this phone and will send after you sign back in' $GATE || grep -q 'on this phone and will send after you sign back in' $GATE"
ok "block screen drains the sync queue on its own (blocked != stranded)" "grep -q 'pendingSyncCount > 0, appState.effectivelyOnline, !appState.isSyncing' $GATE"
ok "hard verdict is cached in UserDefaults, not in the per-staff LocalCache (sign-out is not a bypass)" "grep -q 'UserDefaults.standard' $GATE && ! grep -q 'LocalCache' $GATE"

echo "[4] EXECUTE the real LocalCache queue envelope (lifted verbatim)"
{
  echo "import Foundation"
  echo "final class DiagnosticLogger { static let shared = DiagnosticLogger(); func logAPI(_ s: String) {}; func logSync(_ s: String) {} }"
  echo "struct QueuedAction: Codable, Equatable { let id: String; let isPunch: Bool }"
  echo "final class LocalCache {"
  echo "    let fileManager = FileManager.default"
  echo "    let cacheDir = URL(fileURLWithPath: \"$TMP/cache\", isDirectory: true)"
  echo "    init() { try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true) }"
  echo "    var offlineQueueURL: URL { cacheDir.appendingPathComponent(\"offline-queue.json\") }"
  awk '/private struct QueueEnvelope/,/^    }$/' $LC
  awk '/func saveOfflineQueue/,/^    }$/' $LC
  awk '/func loadOfflineQueue/,/^    }$/' $LC
  echo "    func clearAll() { try? fileManager.removeItem(at: offlineQueueURL) }"
  echo "}"
  cat <<'SWIFT'
var pass = 0, fail = 0
func check(_ label: String, _ cond: Bool) { if cond { pass += 1; print("  ✓ \(label)") } else { fail += 1; print("  ✗ \(label)") } }
let lc = LocalCache()
lc.clearAll()
let queue = [QueuedAction(id: "in", isPunch: true), QueuedAction(id: "note", isPunch: false), QueuedAction(id: "out", isPunch: true)]
lc.saveOfflineQueue(queue, staffId: "staff-A")
// --- what signOut() does, in the same order as the shipped source ---
let preserved = queue.filter { $0.isPunch }
let owner: String? = "staff-A"
lc.clearAll()
check("after clearAll() the queue file is gone (the wipe is real)", lc.loadOfflineQueue(matching: "staff-A") == nil)
if let owner = owner, !preserved.isEmpty { lc.saveOfflineQueue(preserved, staffId: owner) }
// --- sign back in ---
let restoredA = lc.loadOfflineQueue(matching: "staff-A")
check("same staff signs back in -> punches restored", restoredA == preserved)
check("both punches survive, the non-punch note does not", restoredA?.count == 2 && restoredA?.allSatisfy { $0.isPunch } == true)
check("a different staff id does NOT get them", lc.loadOfflineQueue(matching: "staff-B") == nil)
check("...and the file is still there for the owner", lc.loadOfflineQueue(matching: "staff-A") == preserved)
lc.saveOfflineQueue([], staffId: "staff-A")
check("empty save removes the file (no stale envelope)", lc.loadOfflineQueue(matching: "staff-A") == nil)
print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
SWIFT
} > $TMP/main.swift
if swiftc -O -o $TMP/queue $TMP/main.swift 2>$TMP/compile.log; then
  pass=$((pass+1)); echo "  ✓ real saveOfflineQueue/loadOfflineQueue compile standalone (lifted verbatim)"
  if $TMP/queue > $TMP/run.log 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); fi
  sed -n 's/^  \(✓\|✗\) /      /p' $TMP/run.log; tail -1 $TMP/run.log | sed 's/^/      /'
else
  fail=$((fail+1)); echo "  ✗ standalone compile failed — see $TMP/compile.log"
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
