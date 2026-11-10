#!/usr/bin/env bash
# Tests for scripts/plan.sh (tier choice and budget ladder) and scripts/record-cost.sh
# (ledger writes). Fake `gh` and `date` commands go first on PATH, so nothing touches
# GitHub and the month is fixed. Needs bash, jq and awk.
#   bash tests/test_scripts.sh
set -uo pipefail   # no -e: a failed check is counted, not fatal

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# --- fakes ---------------------------------------------------------------------
# gh: prints what the real gh would print AFTER its --jq filter.
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $* [token=$GH_TOKEN]" >> "$FAKE_DIR/gh.calls"
case "$1 $2" in
  "pr view")  cat "$FAKE_DIR/files.json" ;;
  "api gists/"*)
    [ "${FAKE_LEDGER_FAIL:-0}" = 1 ] && exit 1
    cat "$FAKE_DIR/ledger.json" ;;
  "api -X")
    cat > "$FAKE_DIR/patch.json"
    [ "${FAKE_PATCH_FAIL:-0}" = 1 ] && exit 1
    true ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
esac
EOF
# date: answers from FAKE_NOW (YYYY-MM-DDTHH); fails on any format it doesn't know,
# so a new date call in the scripts can't slip past the tests.
cat > "$WORK/bin/date" <<'EOF'
#!/usr/bin/env bash
[ "$1" = -u ] || { echo "fake date: expected -u" >&2; exit 98; }
Y=${FAKE_NOW:0:4} M=${FAKE_NOW:5:2} D=${FAKE_NOW:8:2} H=${FAKE_NOW:11:2}
case "$2" in
  +%Y) echo "$Y" ;; +%m) echo "$M" ;; +%d) echo "$D" ;; +%H) echo "$H" ;;
  +%Y-%m) echo "$Y-$M" ;;
  +%FT%TZ) echo "$Y-$M-${D}T$H:00:00Z" ;;
  *) echo "fake date: unknown format $2" >&2; exit 98 ;;
esac
EOF
# sleep: records the wait instead of waiting, so the retry loop costs no time.
cat > "$WORK/bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "sleep $*" >> "$FAKE_DIR/sleep.calls"
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/date" "$WORK/bin/sleep"

export PATH="$WORK/bin:$PATH" FAKE_DIR="$WORK" REPO=example/repo
export LARGE_PR_LINES=300 BUDGET=180

PASS=0 FAIL=0
check() {  # name, expected, actual
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1))
  else FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected '$2', got '$3')"; fi
}

# --- plan.sh helpers -------------------------------------------------------------
pr_event()      { jq -n --argjson d "${1:-false}" '{pull_request: {number: 7, draft: $d}}' > "$WORK/event.json"; EVENT=pull_request; }
comment_event() { jq -n --arg b "$1" --arg a "${2:-OWNER}" \
  '{issue: {number: 7, pull_request: {}}, comment: {body: $b, author_association: $a}}' > "$WORK/event.json"; EVENT=issue_comment; }
files() { echo "$1" > "$WORK/files.json"; }  # post---jq: the files array
ledger_spent() { jq -n --argjson s "$1" --arg m "${FAKE_NOW:0:7}" '{($m): {spent: $s}}' > "$WORK/ledger.json"; }

tier() {  # runs plan.sh, prints the tier it wrote to GITHUB_OUTPUT
  : > "$WORK/out"
  GITHUB_OUTPUT="$WORK/out" EVENT_NAME="$EVENT" EVENT_PATH="$WORK/event.json" \
    bash "$ROOT/scripts/plan.sh" > /dev/null 2>"$WORK/err" || { echo "plan.sh exited non-zero: $(cat "$WORK/err")"; return; }
  sed -n 's/^tier=//p' "$WORK/out"
}

SMALL='[{"path":"src/app.py","additions":10,"deletions":2}]'
LARGE='[{"path":"src/app.py","additions":301,"deletions":0}]'
AT_LIMIT='[{"path":"src/app.py","additions":250,"deletions":50}]'
LOCK_ONLY_LARGE='[{"path":"package-lock.json","additions":5000,"deletions":0},{"path":"src/app.py","additions":10,"deletions":0}]'
RISKY='[{"path":"src/auth/session.py","additions":3,"deletions":0}]'

# --- plan.sh: events and size, no ledger ---------------------------------------
unset GIST_ID LEDGER_TOKEN
export FAKE_NOW=2026-11-30T23
files "$SMALL"
pr_event true;  check "draft PR"                none    "$(tier)"
pr_event;       check "small PR"                single  "$(tier)"
files "$LARGE"; check "large PR"                council "$(tier)"
files "$AT_LIMIT"; check "exactly 300 lines is not large" single "$(tier)"
files "$LOCK_ONLY_LARGE"; check "lockfile lines excluded" single "$(tier)"
files "$RISKY"; check "risky path"              council "$(tier)"
pr_event true; files "$LARGE"
comment_event "/review please";        check "/review on a large PR"   single  "$(tier)"
comment_event "/council";              check "/council requested"      council "$(tier)"
comment_event "/council" CONTRIBUTOR;  check "not owner, member or collaborator" none "$(tier)"
comment_event "/council" MEMBER;       check "organisation member"     council "$(tier)"
check "pr view asks for the files of PR 7" yes \
  "$(grep -qxF 'gh pr view 7 --repo example/repo --json files --jq .files [token=]' "$WORK/gh.calls" && echo yes || echo no)"
comment_event "looks good";            check "not a command"           none    "$(tier)"
EVENT=push; check "unsupported event" none "$(tier)"

# --- plan.sh: budget ladder (late in the month, so pace ~= share spent) --------
export GIST_ID=gist123 LEDGER_TOKEN=token
files "$RISKY"; pr_event   # wants an automatic council
ledger_spent 0;      check "ledger empty"                 council     "$(tier)"
check "ledger read uses the gist id and ledger token" yes \
  "$(grep -qF "gh api gists/gist123 --jq .files[\"ledger.json\"].content [token=token]" "$WORK/gh.calls" && echo yes || echo no)"
echo "" > "$WORK/ledger.json"; check "ledger blank"       council     "$(tier)"
echo "not json" > "$WORK/ledger.json"; check "ledger corrupt" single "$(tier)"
echo "[]" > "$WORK/ledger.json";       check "ledger not an object" single "$(tier)"
echo "null" > "$WORK/ledger.json";     check "ledger file missing (null)" council "$(tier)"
echo '{"2026-11": 5}' > "$WORK/ledger.json"; check "ledger month not an object" single "$(tier)"
echo '{"2026-11": {"spent": "x"}}' > "$WORK/ledger.json"; check "ledger spent not a number" single "$(tier)"
echo '{"2026-11": {"spent": 1, "runs": {}}}' > "$WORK/ledger.json"; check "ledger runs not a list" single "$(tier)"
FAKE_LEDGER_FAIL=1;  export FAKE_LEDGER_FAIL
                     check "ledger unreadable"            single      "$(tier)"
unset FAKE_LEDGER_FAIL
ledger_spent 106.2;  check "59% auto council"             council     "$(tier)"
ledger_spent 108;    check "60% auto council"             single      "$(tier)"
ledger_spent 160;    check "89% auto council"             single      "$(tier)"
ledger_spent 171;    check "95% holds"                    budget-hold "$(tier)"
comment_event "/council"
ledger_spent 108;    check "60% requested council"        council     "$(tier)"
ledger_spent 153;    check "85% requested council"        single      "$(tier)"

# --- plan.sh: pace ---------------------------------------------------------------
files "$RISKY"; pr_event
FAKE_NOW=2026-11-01T00; ledger_spent 18;  check "day 1 floor: 10% spent is on pace" council "$(tier)"
FAKE_NOW=2026-11-10T00; ledger_spent 72;  check "40% spent by day 10 is ahead"      single  "$(tier)"
# Day 14 of February, 57% spent: ahead of pace in a 29-day month, not in a 28-day one.
FAKE_NOW=2028-02-14T00; ledger_spent 102.6; check "leap February"   single  "$(tier)"
FAKE_NOW=2026-02-14T00; ledger_spent 102.6; check "normal February" council "$(tier)"

# --- record-cost.sh --------------------------------------------------------------
record() {
  rm -f "$WORK/patch.json" "$WORK/gh.calls" "$WORK/sleep.calls"
  PR=7 bash "$ROOT/scripts/record-cost.sh" > /dev/null 2>&1; echo $?
}
spent_after() { jq -r '.files["ledger.json"].content | fromjson | .["2026-11"] | "\(.spent) \(.runs | length) \(.runs[-1].cost + 0) \(.runs[-1].estimated)"' "$WORK/patch.json"; }

export FAKE_NOW=2026-11-30T23
jq -n '{"2026-11": {spent: 1.5, runs: []}}' > "$WORK/ledger.json"
check "record: exit" 0 "$(TIER=single COST_USD=0.1234 record)"
check "record: cost added" "1.6234 1 0.1234 false" "$(spent_after)"
check "record: no cost, council estimate" 0 "$(TIER=council COST_USD='' record)"
check "record: estimate added" "6.5 1 5 true" "$(spent_after)"
check "record: writes to the gist with the ledger token" yes \
  "$(grep -qxF 'gh api -X PATCH gists/gist123 --input - [token=token]' "$WORK/gh.calls" && echo yes || echo no)"

FAKE_PATCH_FAIL=1; export FAKE_PATCH_FAIL
check "record: write keeps failing" 1 "$(TIER=single COST_USD=1 record)"
check "record: three write attempts" 3 "$(grep -c 'api -X PATCH' "$WORK/gh.calls")"
check "record: waits 3 then 6 seconds between tries" "sleep 3,sleep 6" "$(paste -sd, "$WORK/sleep.calls")"
unset FAKE_PATCH_FAIL

echo "not json" > "$WORK/ledger.json"
check "record: corrupt ledger is an error" 1 "$(TIER=single COST_USD=1 record)"
check "record: corrupt ledger is never overwritten" no "$([ -e "$WORK/patch.json" ] && echo yes || echo no)"
check "record: corrupt ledger is not retried" no "$([ -e "$WORK/sleep.calls" ] && echo yes || echo no)"

echo '{"2026-11": 5}' > "$WORK/ledger.json"
check "record: damaged month is an error" 1 "$(TIER=single COST_USD=1 record)"
check "record: damaged month is never overwritten" no "$([ -e "$WORK/patch.json" ] && echo yes || echo no)"

echo "null" > "$WORK/ledger.json"
check "record: missing ledger.json starts a fresh one" 0 "$(TIER=single COST_USD=0.25 record)"
check "record: fresh ledger has this run only" "0.25 1 0.25 false" "$(spent_after)"

unset GIST_ID
check "record: no ledger exits cleanly" 0 "$(TIER=single COST_USD=1 record)"
check "record: no ledger makes no gh call" no "$([ -s "$WORK/gh.calls" ] && echo yes || echo no)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
