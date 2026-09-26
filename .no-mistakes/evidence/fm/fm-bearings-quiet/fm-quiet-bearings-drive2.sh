#!/usr/bin/env bash
# S2 (guard read-only in quiet mode) and S8 (return catch-up handling unchanged)
set -u
HEAD_ROOT=$1 BASE_ROOT=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$HEAD_ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
run() { local root=$1; shift
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$root/$@"; }
tree_state() { (cd "$LAB" && find . -print0 | xargs -0 stat -f '%N %z %Sm' -t '%s' | sort); }
catchup_row() { # <label> <root>
  local out rc; set +e; out=$(run "$2" bin/fm-bearings-snapshot.sh --json 2>/dev/null); rc=$?; set -e
  printf '  [%s] exit %s; (return-catchup) rows: %s\n' "$1" "$rc" \
    "$(printf '%s' "$out" | jq -c '[.. | objects | select(.id? == "(return-catchup)")]' 2>/dev/null || echo '<no snapshot>')"
}
set -e
FM_AFK_MODE=quiet run "$HEAD_ROOT" bin/fm-afk-launch.sh enter --words "quiet" >/dev/null
FM_AFK_MODE=quiet run "$HEAD_ROOT" bin/fm-afk-launch.sh start-native >/dev/null 2>&1
echo "== S2: guard in quiet mode is read-only (full lab-home listing with size+mtime before/after)"
before=$(tree_state); sleep 1.1
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard; rc=$?; set -e
after=$(tree_state)
echo "  state/.afk: $(head -n1 "$LAB/state/.afk"); guard exit: $rc"
if [ "$before" = "$after" ]; then echo "  lab home unchanged by guard ($(printf '%s\n' "$before" | wc -l | tr -d ' ') entries compared)"; else echo "  CHANGED:"; diff <(echo "$before") <(echo "$after") | sed 's/^/    /'; fi

echo
echo "== S8: return catch-up handling unchanged (seeded durable catch-up gate after /quiet off)"
run "$HEAD_ROOT" bin/fm-afk-return.sh >/dev/null 2>&1
printf 'schema\tfm-afk-return.v1\nphase\tblocked\n' > "$LAB/state/.afk-return-catchup"
catchup_row "HEAD, no flag" "$HEAD_ROOT"
catchup_row "BASE, no flag" "$BASE_ROOT"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard >/dev/null 2>&1; echo "  guard exit HEAD no flag: $?"
run "$BASE_ROOT" bin/fm-afk-return.sh guard >/dev/null 2>&1; echo "  guard exit BASE no flag: $?"; set -e
printf 'quiet\n%s\n' "$(date +%s)" > "$LAB/state/.afk"
set +e; run "$HEAD_ROOT" bin/fm-afk-return.sh guard >/dev/null 2>&1; echo "  guard exit HEAD quiet flag + catch-up: $?"; set -e
catchup_row "HEAD, quiet flag + catch-up" "$HEAD_ROOT"
