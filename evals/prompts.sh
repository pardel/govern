#!/usr/bin/env bash
# Tier 3: do the prompts behave the way the README says they do?
#
# This one needs a model and spends tokens, so it is opt-in. Everything
# it asserts is still counted rather than judged: fixtures plant known
# strings and the assertions grep for them, because asking a model
# whether a model did well is not evidence.
#
# Each case is a directory under cases/ holding a fixture/ tree and an
# assert.sh. The fixture is copied to a temp dir first, so a case can
# never mutate the thing it tests.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASES="$ROOT/evals/cases"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ran=0

command -v claude >/dev/null || {
  echo "claude is not on PATH; tier 3 needs it. Skipping." >&2
  exit 0
}

echo "# Prompt behaviour"
echo
echo "Each case runs one prompt against a fixture in a throwaway copy."

only="${1:-}"

for dir in "$CASES"/*/; do
  name=$(basename "$dir")
  [ -n "$only" ] && [ "$only" != "$name" ] && continue
  [ -f "$dir/assert.sh" ] || continue

  # shellcheck disable=SC1091
  COMMAND=""; ASK=""
  . "$dir/case.env"

  kb="$TMP/$name"
  mkdir -p "$kb"
  [ -d "$dir/fixture" ] && cp -R "$dir/fixture/." "$kb/"

  prompt="$(cat "$ROOT/prompts/$COMMAND.txt")"
  [ -n "$ASK" ] && prompt="$prompt

$ASK"

  out="$TMP/$name.out"
  ( cd "$kb" && claude -p "$prompt" \
      --permission-mode acceptEdits \
      --max-turns 30 \
      --allowedTools "Read" "Write" "Edit" "Glob" "Grep" \
        "Bash(ls *)" "Bash(cat *)" "Bash(mkdir *)" "Bash(mv *)" \
      --disallowedTools "Bash(rm *)" "Bash(git push*)" "WebFetch" "WebSearch" \
      > "$out" 2>&1 )
  rc=$?
  ran=$((ran + 1))

  echo
  echo "## $name"
  echo

  if [ $rc -ne 0 ]; then
    echo "- the run itself failed (exit $rc); see below"
    sed 's/^/      /' "$out" | tail -5
    fail=1
    continue
  fi

  findings="$TMP/$name.findings"
  : > "$findings"
  KB="$kb" OUT="$out" FINDINGS="$findings" bash "$dir/assert.sh"

  if [ -s "$findings" ]; then
    sed 's/^/- /' "$findings"
    fail=1
  else
    echo "- passed"
  fi
done

echo
if [ "$ran" -eq 0 ]; then
  echo "**No cases ran.**"
elif [ "$fail" -eq 0 ]; then
  echo "**Clean.** $ran case(s)."
else
  echo "**Findings above.** $ran case(s) ran."
fi
exit "$fail"
