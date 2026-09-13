#!/usr/bin/env bash
# Tier 1: does the repo describe itself accurately?
#
# Deterministic, no model, no network. Every finding here is a number or
# a path that can be counted, which is the Evidence principle applied to
# the repo itself. Exits non-zero if anything is wrong, unlike the
# report-style checkers this was modelled on, because a suite nobody can
# consume programmatically is a suite that rots.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

section() {  # section <title> <bodyfile> — prints "- none" when clean
  echo
  echo "## $1"
  echo
  if [ -s "$2" ]; then
    sed 's/^/- /' "$2"
    echo
    echo "**$(grep -c . "$2") finding(s).**"
    fail=1
  else
    echo "- none"
  fi
}

spell() {  # spell <n> -> english words, 0..999, matching README prose
  n=$1
  ones="zero one two three four five six seven eight nine ten eleven \
twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen"
  tens="- - twenty thirty forty fifty sixty seventy eighty ninety"
  word() { echo $2 | cut -d' ' -f$(($1 + 1)); }
  if [ "$n" -lt 20 ]; then word "$n" "$ones"; return; fi
  if [ "$n" -lt 100 ]; then
    t=$((n / 10)); r=$((n % 10))
    if [ "$r" -eq 0 ]; then word "$t" "$tens"
    else echo "$(word "$t" "$tens")-$(word "$r" "$ones")"; fi
    return
  fi
  h=$((n / 100)); r=$((n % 100))
  if [ "$r" -eq 0 ]; then echo "$(word "$h" "$ones") hundred"
  else echo "$(word "$h" "$ones") hundred and $(spell "$r")"; fi
}

echo "# Consistency"
echo
echo "Repo at \`$ROOT\`, checked $(date +%Y-%m-%d)."

# ---------------------------------------------------------------- counts
: > "$TMP/f_counts"

n_cmd=$(grep -c '^install_command ' setup.sh)
if ! grep -qF "one commit, $(spell "$n_cmd") commands" README.md; then
  echo "README does not say \"$(spell "$n_cmd") commands\"; setup.sh installs $n_cmd" \
    >> "$TMP/f_counts"
fi

n_lines=$(wc -l < setup.sh | tr -d ' ')
if ! grep -qF "is $(spell "$n_lines") lines" README.md; then
  echo "README does not say \"$(spell "$n_lines") lines\"; setup.sh is $n_lines" \
    >> "$TMP/f_counts"
fi

n_later=$(find prompts/later -name '*.txt' | wc -l | tr -d ' ')
if ! grep -qF "what $(spell "$n_later") of these grow into" README.md; then
  echo "README's prompts/later count disagrees; there are $n_later" \
    >> "$TMP/f_counts"
fi

section "Counts stated in the README (must match what is on disk)" "$TMP/f_counts"

# ----------------------------------------------------- prompts are linked
: > "$TMP/f_unlinked"
for f in $(cd prompts && find . -name '*.txt' | sed 's|^\./||' | sort); do
  grep -qF "prompts/$f" README.md || echo "\`prompts/$f\` is in the repo but linked from no README line" \
    >> "$TMP/f_unlinked"
done
section "Prompts reachable from the README" "$TMP/f_unlinked"

# ------------------------------------------------------ tools are linked
: > "$TMP/f_tools"
for f in $(cd tools && ls ./*.sh | sed 's|^\./||' | sort); do
  grep -qF "tools/$f" README.md || echo "\`tools/$f\` is in the repo but linked from no README line" \
    >> "$TMP/f_tools"
done
section "Tools reachable from the README" "$TMP/f_tools"

# The scheduler entry no longer lives in the README: schedule.sh print
# generates it with the real paths, and setup-behaviour.sh checks the
# hour it carries and that the plist parses.

# ------------------------------------------- install_command sources exist
: > "$TMP/f_sources"
grep '^install_command ' setup.sh | awk '{print $2, $3}' | while read -r name src; do
  [ -f "prompts/$src" ] || echo "\`/$name\` installs from \`prompts/$src\`, which does not exist" \
    >> "$TMP/f_sources"
done
section "Every command has a prompt file behind it" "$TMP/f_sources"

# ------------------------------------------------- repo links resolve locally
: > "$TMP/f_links"
grep -o 'blob/main/[A-Za-z0-9_./-]*' README.md | sed 's|blob/main/||' | sort -u \
  | while read -r p; do
      [ -e "$p" ] || echo "README links \`$p\`, which is not in the repo" >> "$TMP/f_links"
    done
grep -o 'tree/main/[A-Za-z0-9_./-]*' README.md | sed 's|tree/main/||' | sort -u \
  | while read -r p; do
      [ -d "$p" ] || echo "README links directory \`$p\`, which is not in the repo" >> "$TMP/f_links"
    done
section "GitHub links point at files that exist here" "$TMP/f_links"

# ------------------------------------------------ the changelog holds
# The kit asks your rulebook for a changelog of decisions and failures,
# newest first, so it keeps one itself: every entry heading is a date,
# and they run newest first.
: > "$TMP/f_log"
if [ ! -s CHANGELOG.md ]; then
  echo "CHANGELOG.md is missing or empty" >> "$TMP/f_log"
else
  grep -E '^## ' CHANGELOG.md | sed 's/^## //' > "$TMP/log_heads"
  grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$TMP/log_heads" | while read -r h; do
    echo "changelog heading is not a date: \`$h\`" >> "$TMP/f_log"
  done
  if ! diff -q "$TMP/log_heads" <(sort -r "$TMP/log_heads") >/dev/null; then
    echo "changelog entries are not newest first" >> "$TMP/f_log"
  fi
fi
section "The changelog holds" "$TMP/f_log"

# ------------------------------------------- internal anchors resolve
# Added when the README grew a commands-at-a-glance list: every entry
# links to a heading further down, and a list of eleven anchors is a
# list of eleven things that can silently stop matching.
: > "$TMP/f_anchors"
# GitHub builds an anchor by lowercasing a heading, dropping anything
# that is not alphanumeric, space or hyphen, then spacing to hyphens.
grep -E '^#{1,6} ' README.md \
  | sed -E 's/^#+ +//' \
  | tr '[:upper:]' '[:lower:]' \
  | sed -e 's/[^a-z0-9 -]//g' -e 's/^ *//' -e 's/ *$//' -e 's/ /-/g' \
  | sort -u > "$TMP/anchors"
grep -o '](#[a-z0-9-]*)' README.md | sed -e 's/](#//' -e 's/)//' | sort -u \
  > "$TMP/targets"
comm -23 "$TMP/targets" "$TMP/anchors" | while read -r a; do
  echo "\`#$a\` is linked but no heading generates that anchor" >> "$TMP/f_anchors"
done
section "Internal anchors resolve to a heading" "$TMP/f_anchors"

echo
if [ "$fail" -eq 0 ]; then
  echo "**Clean.** Checked: command count, line count, later/ count, $(find prompts -name '*.txt' | wc -l | tr -d ' ') prompt files linked, $n_cmd command sources, $(grep -c 'blob/main/\|tree/main/' README.md) repo links."
else
  echo "**Findings above.** Fix the repo or fix the README; do not relax the check."
fi
exit "$fail"
