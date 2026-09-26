#!/bin/bash
# Live drive of the real away-return entrypoint (fixed code) on disposable lab
# homes under stock /bin/bash 3.2: the writable-stdout happy path and the
# live-blocker path with an unwritable stdout.
set -u
ROOT=$1
unset NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
mklab() { local d; d=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$d"; "$ROOT/bin/fm-lab-home.sh" create "$d" >/dev/null && printf '%s\n' "$d"; }

LAB=$(mklab); export FM_HOME="$LAB"
echo "== happy path: away flag, inbox note queued, begin with a WRITABLE stdout"
: > "$LAB/state/.afk"
"$ROOT/bin/fm-inbox.sh" note "rotate the staging token" >/dev/null 2>&1
"$ROOT/bin/fm-afk-return.sh" begin > "$LAB/out" 2> "$LAB/err"; rc=$?
echo "begin rc=$rc"; echo "-- stdout:"; sed 's/^/   /' "$LAB/out"; echo "-- stderr:"; sed 's/^/   /' "$LAB/err"
echo "-- gate present: $([ -e "$LAB/state/.afk-return-catchup" ] && echo yes || echo no); stray staged files: $(ls -a "$LAB/state" | grep -c '^\.afk-return-\(brief\|evidence\|blockers\|drain\)\.')"
rm -rf "$LAB"

LAB=$(mklab); export FM_HOME="$LAB"
echo; echo "== blocker path: a live task reports blocked:, begin with an UNWRITABLE (read-only) stdout"
: > "$LAB/state/.afk"
printf 'window=synthetic:fm-repair-task\nbackend=tmux\nkind=ship\n' > "$LAB/state/repair-task.meta"
printf 'blocked [key=token-refresh]: firstmate can refresh the synthetic token\n' > "$LAB/state/repair-task.status"
: > "$LAB/ro"
"$ROOT/bin/fm-afk-return.sh" begin 3< "$LAB/ro" >&3 2> "$LAB/err"; rc=$?
echo "begin rc=$rc (documented 3: catch-up must finish first)"; echo "-- stderr:"; sed 's/^/   /' "$LAB/err"
echo "-- gate present: $([ -s "$LAB/state/.afk-return-catchup" ] && echo yes || echo no); gate blocker rows:"; grep '^blocker' "$LAB/state/.afk-return-catchup" | sed 's/^/   /'
echo "-- stray staged files: $(ls -a "$LAB/state" | grep -c '^\.afk-return-\(brief\|evidence\|blockers\|drain\)\.')"
echo "== blocker path: check with writable stdout still refuses while the blocker is open"
"$ROOT/bin/fm-afk-return.sh" check > "$LAB/out" 2> "$LAB/err"; rc=$?
echo "check rc=$rc"; echo "-- stdout (brief):"; sed 's/^/   /' "$LAB/out"; echo "-- stderr:"; sed 's/^/   /' "$LAB/err"
echo "== resolve the blocker, check again"
printf 'resolved [key=token-refresh]: token refreshed\n' >> "$LAB/state/repair-task.status"
"$ROOT/bin/fm-afk-return.sh" check > "$LAB/out" 2> "$LAB/err"; rc=$?
echo "check rc=$rc"; tail -2 "$LAB/out" | sed 's/^/   /'
echo "-- gate present: $([ -e "$LAB/state/.afk-return-catchup" ] && echo yes || echo no)"
rm -rf "$LAB"; echo "labs removed"
