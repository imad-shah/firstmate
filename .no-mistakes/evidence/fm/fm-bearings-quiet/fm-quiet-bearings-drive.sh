#!/usr/bin/env bash
# Drive /quiet -> /bearings, /afk -> /bearings, /quiet off, and adversarial
# flag contents against a disposable marked lab home, with the real scripts at
# HEAD and (for contrast) at the base commit.
set -u
HEAD_ROOT=$1
BASE_ROOT=$2

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$HEAD_ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT

run() { # <root> <cmd...>  run a firstmate script against the lab home
  local root=$1; shift
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" "$root/$@"
}

bearings() { # <label> <root>
  local label=$1 root=$2 out err rc
  err=$(mktemp); set +e
  out=$(run "$root" bin/fm-bearings-snapshot.sh --json 2>"$err"); rc=$?
  set -e
  printf '  [%s] fm-bearings-snapshot.sh --json -> exit %s\n' "$label" "$rc"
  if [ -s "$err" ]; then sed 's/^/    stderr: /' "$err"; fi
  if [ -n "$out" ]; then
    printf '%s' "$out" | jq -c '{schema, return_catchup: (.return_catchup // null), fm_home: (.fm_home // .home // null)}' 2>/dev/null \
      | sed 's/^/    stdout: /' || printf '    stdout (non-JSON): %.200s\n' "$out"
  else
    printf '    stdout: <empty - no snapshot>\n'
  fi
  rm -f "$err"
}

flag() { printf '  state/.afk first line: %s | record present: %s\n' \
  "$( [ -e "$LAB/state/.afk" ] && head -n1 "$LAB/state/.afk" || echo '<absent>')" \
  "$( [ -e "$LAB/state/.afk-contract" ] && echo yes || echo no)"; }

set -e
echo "== S1: /quiet entered through the real lifecycle (enter + start-native, FM_AFK_MODE=quiet)"
FM_AFK_MODE=quiet run "$HEAD_ROOT" bin/fm-afk-launch.sh enter --words "quiet please, I am staying here" | sed 's/^/  enter: /'
FM_AFK_MODE=quiet run "$HEAD_ROOT" bin/fm-afk-launch.sh start-native 2>&1 | sed 's/^/  start-native: /'
flag
bearings "HEAD $(git -C "$HEAD_ROOT" rev-parse --short HEAD)" "$HEAD_ROOT"
bearings "BASE d1a332cd" "$BASE_ROOT"
flag

echo
echo "== S2: guard stays read-only in quiet mode"
touch "$LAB/.before-guard"; sleep 1
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard; rc=$?; set -e
echo "  guard exit: $rc"
changed=$(find "$LAB" -newer "$LAB/.before-guard" | sed "s#^$LAB#.#")
echo "  files created/modified under the lab home by guard: ${changed:-<none>}"
rm -f "$LAB/.before-guard"
flag

echo
echo "== S3: ordinary Bearings run does not end quiet mode (flag/record untouched)"
bearings "HEAD again" "$HEAD_ROOT"
flag

echo
echo "== S4: /quiet off runs the unchanged return, which ends quiet mode"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh > "$LAB/return.out" 2>&1; rc=$?; set -e
echo "  fm-afk-return.sh exit: $rc"; sed -n '1,12p' "$LAB/return.out" | sed 's/^/    /'
flag
echo "  catch-up file: $( [ -e "$LAB/state/.afk-return-catchup" ] && echo present || echo absent)"
bearings "HEAD after /quiet off" "$HEAD_ROOT"

echo
echo "== S5: /afk (away) entered through the real lifecycle keeps refusing"
run "$HEAD_ROOT" bin/fm-afk-launch.sh enter --words "back in an hour" | sed 's/^/  enter: /'
run "$HEAD_ROOT" bin/fm-afk-launch.sh start-native 2>&1 | sed 's/^/  start-native: /'
flag
bearings "HEAD" "$HEAD_ROOT"
bearings "BASE d1a332cd" "$BASE_ROOT"

echo
echo "== S6: adversarial flag contents with the away-posture record present (all must read as away)"
cp "$LAB/state/.afk" "$LAB/.afk.saved"
for content in 'quiet ' 'QUIET' 'Quiet' ' quiet' 'quiet\t' "$(date +%s)" '' 'away\nquiet' 'quietly'; do
  printf "$content\n$(date +%s)\n" > "$LAB/state/.afk"
  printf '  -- first line %q\n' "$(head -n1 "$LAB/state/.afk")"
  bearings "HEAD" "$HEAD_ROOT"
done
cp "$LAB/.afk.saved" "$LAB/state/.afk"

echo
echo "== S7: record present but no flag (quiet mode cannot be proven) keeps refusing"
mv "$LAB/state/.afk" "$LAB/.afk.hidden"
flag
bearings "HEAD" "$HEAD_ROOT"
echo "== S7b: flag says quiet, no record"
mv "$LAB/.afk.hidden" "$LAB/state/.afk"
mv "$LAB/state/.afk-contract" "$LAB/.contract.hidden"
printf 'quiet\n%s\n' "$(date +%s)" > "$LAB/state/.afk"
flag
bearings "HEAD" "$HEAD_ROOT"
bearings "BASE d1a332cd" "$BASE_ROOT"
mv "$LAB/.contract.hidden" "$LAB/state/.afk-contract"
printf 'away\n%s\n' "$(date +%s)" > "$LAB/state/.afk"

echo
echo "== S8: return from away, then a pending return catch-up keeps its own handling"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh > "$LAB/return2.out" 2>&1; rc=$?; set -e
echo "  fm-afk-return.sh exit: $rc"
flag
printf 'schema\tfm-afk-return.v1\nphase\tblocked\n' > "$LAB/state/.afk-return-catchup"
echo "  seeded state/.afk-return-catchup (phase blocked)"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard 2>&1 | sed 's/^/    guard stderr: /'; echo "  guard exit (HEAD): ${PIPESTATUS[0]}"; set -e
bearings "HEAD catch-up, no flag" "$HEAD_ROOT"
bearings "BASE catch-up, no flag" "$BASE_ROOT"
printf 'quiet\n%s\n' "$(date +%s)" > "$LAB/state/.afk"
echo "  plus state/.afk=quiet"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard >/dev/null 2>&1; echo "  guard exit (HEAD, quiet + catch-up): $?"; set -e
bearings "HEAD catch-up + quiet" "$HEAD_ROOT"
printf 'away\n%s\n' "$(date +%s)" > "$LAB/state/.afk"
echo "  plus state/.afk=away"
bearings "HEAD catch-up + away" "$HEAD_ROOT"
echo
echo "lab removed on exit: $LAB"
