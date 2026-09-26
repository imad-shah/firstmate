#!/bin/bash
# Live drive of the real away-return entrypoint on a disposable lab home under
# stock /bin/bash 3.2. Usage: live-drive.sh <checkout-root> <label> <stdout-mode: ro|closed>
set -u
ROOT=$1 LABEL=$2 MODE=${3:-ro}
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
rmdir "$LAB"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "lab create failed"; exit 1; }
export FM_HOME="$LAB"
echo "== [$LABEL] shell: $(/bin/bash --version | head -1); script shebang: $(head -1 "$ROOT/bin/fm-afk-return.sh")"
echo "== [$LABEL] away mode on (legacy flag) and a captain inbox note queued while away"
: > "$LAB/state/.afk"
"$ROOT/bin/fm-inbox.sh" note "check the release notes before merging" >/dev/null 2>&1; echo "inbox note rc=$?"
echo "queued wake rows: $(grep -c . "$LAB/state/"*wake* 2>/dev/null | tr '\n' ' ')"
: > "$LAB/read-only-output"
echo "== [$LABEL] begin with UNWRITABLE stdout ($MODE)"
if [ "$MODE" = ro ]; then
  "$ROOT/bin/fm-afk-return.sh" begin 3< "$LAB/read-only-output" >&3 2> "$LAB/begin.err"; rc=$?
else
  "$ROOT/bin/fm-afk-return.sh" begin >&- 2> "$LAB/begin.err"; rc=$?
fi
echo "begin rc=$rc (documented: 3 = catch-up remains pending)"
echo "-- begin stderr:"; sed 's/^/   /' "$LAB/begin.err"
echo "-- catch-up gate present: $([ -s "$LAB/state/.afk-return-catchup" ] && echo yes || echo no)"
[ -s "$LAB/state/.afk-return-catchup" ] && { echo "-- gate lifecycle evidence:"; grep 'lifecycle' "$LAB/state/.afk-return-catchup" | sed 's/^/   /'; }
echo "-- stray staged files in state: $(ls -a "$LAB/state" | grep -c '^\.afk-return-\(brief\|evidence\|blockers\|drain\)\.' )"
echo "== [$LABEL] check with writable stdout (the retry)"
"$ROOT/bin/fm-afk-return.sh" check > "$LAB/check.out" 2> "$LAB/check.err"; rc=$?
echo "check rc=$rc"
echo "-- check stdout:"; sed 's/^/   /' "$LAB/check.out"
echo "-- check stderr:"; sed 's/^/   /' "$LAB/check.err"
echo "-- catch-up gate present after check: $([ -e "$LAB/state/.afk-return-catchup" ] && echo yes || echo no)"
echo "-- stray staged files in state: $(ls -a "$LAB/state" | grep -c '^\.afk-return-\(brief\|evidence\|blockers\|drain\)\.' )"
rm -rf "$LAB"
echo "== [$LABEL] lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
