#!/bin/bash
# Build the suite's own install_runner layout (extracted from the named test
# file) and run the real begin path once, reporting whether the brief's
# supervision-engine source resolved.
set -u
ROOT=$1 TESTFILE=$2
T=$(mktemp -d "${TMPDIR:-/tmp}/fm-runner.XXXXXX")
eval "$(sed -n '/^install_runner() {/,/^}/p' "$TESTFILE")"
install_runner "$T/case"
echo "runner has fm-supervision-engine-lib.sh: $([ -f "$T/case/bin/fm-supervision-engine-lib.sh" ] && echo yes || echo no)"
FM_HOME="$T/case/home" FM_STATE_OVERRIDE="$T/case/home/state" "$T/case/bin/fm-afk-return.sh" begin > "$T/out" 2> "$T/err"; echo "begin rc=$?"
echo "stderr lines naming the lib:"; if grep -q supervision-engine "$T/err"; then grep supervision-engine "$T/err" | sed "s#$T#<runner>#g; s/^/   /"; else echo "   (none)"; fi
rm -rf "$T"
