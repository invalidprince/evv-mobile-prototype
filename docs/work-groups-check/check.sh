#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 126 — Work tab renders the grouped To-Do payload (server v0.4.833,
# focus-nexus evv-poc/docs/MOBILE_TODO_GROUPS.md; Nick #evv 2026-11-19 "Yes fix
# it on both").
#
# [0] EXECUTES the real decoders + list logic: WorkItem / WorkGroupFooter /
#     WorkTeamRollup / WorkDocSummary / WorkTodosResponse (brace-matched out of
#     APIClient.swift) and everything between BEGIN/END work-groups-source,
#     against de-identified fixtures (grouped, legacy, malformed) and — if
#     present — a real staging capture at /tmp/s013_todos.json (PHI, never
#     committed).
# [0b] NEGATIVE CONTROL: a WorkTodosResponse that ignores groupedItems (the
#     pre-126 shape) must FAIL section [A].
# [1] Source wiring in WorkView. [2] simulator compile, BOTH schemes (skip:
#     --no-build). SDK_STAT_CACHE_ENABLE=NO: clang-stat-cache hung >2 min on
#     this Mac on 2026-11-19 waiting on FSEvents.
# Visual proof (optional): WorkGroupsShotTests.swift + proxy.py (see headers).
#
# Run from anywhere:  bash docs/work-groups-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
API=EVVMobile/Services/APIClient.swift
WV=EVVMobile/Views/Work/WorkView.swift
HERE=docs/work-groups-check
WORK=/tmp/evv-work-groups
mkdir -p "$WORK"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

gen() { # $1 = output main.swift, $2 = optional replacement WorkTodosResponse source file
python3 - "$API" "$HERE/test.swift.txt" "$1" "${2:-}" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
def grab(name):
    i = src.index(name); depth = 0; j = i
    while True:
        if src[j] == '{': depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0: return src[i:j+1]
        j += 1
resp = pathlib.Path(sys.argv[4]).read_text() if sys.argv[4] else grab('struct WorkTodosResponse: Decodable')
b = src.index('// BEGIN work-groups-source'); e = src.index('// END work-groups-source')
parts = ['import Foundation', grab('struct WorkItem: Decodable, Identifiable'), grab('struct WorkGroupFooter: Decodable'),
         grab('struct WorkTeamRollup: Decodable'), grab('struct WorkDocSummary: Decodable'), resp, src[b:e]]
pathlib.Path(sys.argv[3]).write_text("\n".join(parts) + pathlib.Path(sys.argv[2]).read_text())
PY
}

echo "[0] THE REAL decoders + WorkListModel, extracted and EXECUTED"
gen "$WORK/main.swift"
if swiftc -O -o "$WORK/run" "$WORK/main.swift" 2>"$WORK/compile.log"; then
  if "$WORK/run" "$HERE" > "$WORK/out.log" 2>&1; then
    pass=$((pass+1)); sed 's/^/    /' "$WORK/out.log"; echo "  ✓ $(tail -1 "$WORK/out.log")"
  else
    fail=$((fail+1)); sed 's/^/    /' "$WORK/out.log"; echo "  ✗ swift suite failed"
  fi
else
  fail=$((fail+1)); echo "  ✗ swift harness did not compile"; tail -30 "$WORK/compile.log"
fi

echo "[0b] NEGATIVE CONTROL — a response that ignores groupedItems must FAIL [A]"
cat > "$WORK/old_resp.swift" <<'OLD'
struct WorkTodosResponse: Decodable {
    let items: [WorkItem]
    let teamRollup: WorkTeamRollup?
    let docSummary: WorkDocSummary?
    let openCount: Int
    var groupedItems: [WorkItem]? { nil }
    var groupedOpenCount: Int? { nil }
}
OLD
gen "$WORK/old_main.swift" "$WORK/old_resp.swift"
if swiftc -O -o "$WORK/old_run" "$WORK/old_main.swift" 2>"$WORK/old_compile.log"; then
  if "$WORK/old_run" "$HERE" > "$WORK/old_out.log" 2>&1; then
    fail=$((fail+1)); echo "  ✗ the pre-126 response PASSED — the suite does not detect grouping"
  else
    pass=$((pass+1)); echo "  ✓ the pre-126 response fails it: $(tail -1 "$WORK/old_out.log")"
  fi
else
  fail=$((fail+1)); echo "  ✗ could not compile the negative control"; tail -10 "$WORK/old_compile.log"
fi

echo "[1] WorkView wiring"
ok "renders WorkListModel.visibleRows when grouped"        'grep -q "WorkListModel.visibleRows(" $WV'
ok "flat path (openTodos + autoItems) kept for old servers" 'grep -q "ForEach(openTodos)" $WV && grep -q "ForEach(autoItems)" $WV'
ok "tab badge uses WorkListModel.badgeCount"                'grep -q "WorkListModel.badgeCount(response)" $WV'
ok "groups collapsed by default (empty expanded set)"       'grep -qF "expandedGroups: Set<String> = []" $WV'
ok "children route through autoRow (native first, webPath)" 'grep -A4 "case .child" $WV | grep -q "autoRow(item)"'
ok "footer row opens footer.webPath"                        'grep -A6 "func groupFooterRow" $WV | grep -q "openWeb(path)"'
ok "badge chip rendered on rows"                            'grep -q "if let badge = item.badge" $WV'
ok "Safari sheet dismissal refetches"                       'grep -qF "sheet(item: \$safariItem, onDismiss" $WV'
ok "native documentation dismissal still refetches"         'grep -A8 "sheet(item: .docVisit" $WV | grep -q "await load()"'
ok "native destinations resolved across group members"      'grep -q "let needsHistory = leaves.contains" $WV'
ok "Info.plist CFBundleVersion = 126" 'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>126</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[2] The project still COMPILES for the simulator (both schemes)"
  for SCHEME in EVVMobile EVVMobileStaging; do
    DEST_ID=$(xcodebuild -project EVVMobile.xcodeproj -scheme $SCHEME -showdestinations 2>/dev/null \
      | grep 'platform:iOS Simulator' | grep 'name:iPhone' | grep -v placeholder \
      | head -1 | sed -n 's/.*id:\([0-9A-Fa-f-]*\).*/\1/p')
    if [ -z "$DEST_ID" ]; then
      fail=$((fail+1)); echo "  ✗ no iPhone simulator destination found ($SCHEME)"
    elif xcodebuild -project EVVMobile.xcodeproj -scheme $SCHEME \
         -destination "platform=iOS Simulator,id=$DEST_ID" -configuration Debug SDK_STAT_CACHE_ENABLE=NO build \
         > "$WORK/build-$SCHEME.log" 2>&1; then
      pass=$((pass+1)); echo "  ✓ $SCHEME BUILD SUCCEEDED (sim $DEST_ID)"
    else
      fail=$((fail+1)); echo "  ✗ $SCHEME xcodebuild failed"; grep -E "error:" "$WORK/build-$SCHEME.log" | head -20
    fi
  done
fi

echo ""
echo "work-groups-check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
