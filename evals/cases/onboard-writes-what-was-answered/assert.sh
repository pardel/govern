#!/usr/bin/env bash
# $KB is the throwaway knowledge base, $OUT the model's output,
# $FINDINGS the file to append failures to. Silence means passed.

rb="$KB/CLAUDE.md"
if [ ! -s "$rb" ]; then
  echo "no CLAUDE.md was written" >> "$FINDINGS"
  exit 0
fi
n=$(find "$KB" -name 'CLAUDE.md' | wc -l | tr -d ' ')
[ "$n" = "1" ] || echo "expected exactly 1 CLAUDE.md, found $n" >> "$FINDINGS"

# The name and the family, as answered.
grep -q 'Buzz' "$rb"      || echo "the rulebook does not carry the name Buzz" >> "$FINDINGS"
grep -q 'Toy Story' "$rb" || echo "the rulebook does not carry the name family" >> "$FINDINGS"

# Every gate verbatim, the planted one included.
for g in 'deleting files' 'pushing to GitHub' 'GRANITE-4410'; do
  grep -qF "$g" "$rb" || echo "gate \`$g\` is missing from the rulebook" >> "$FINDINGS"
done

# The archive rule as a refusal, not a gate.
grep -q '4_Archive' "$rb" || echo "the rulebook never mentions 4_Archive" >> "$FINDINGS"
grep -qiE 'never (be )?(edited|deleted|changed)|refus|not (a )?gate' "$rb" \
  || echo "the archive rule is not written as a refusal" >> "$FINDINGS"

# The areas exist as folders, as the rulebook says they are created.
for a in Personal Work Beekeeping; do
  [ -d "$KB/2_Areas/$a" ] || echo "no folder for area $a under 2_Areas/" >> "$FINDINGS"
done
grep -q 'Beekeeping' "$rb" || echo "the rulebook does not list the area Beekeeping" >> "$FINDINGS"
grep -qF 'HIVE-LOG-2291' "$rb" || echo "the area description for Beekeeping did not reach the rulebook" >> "$FINDINGS"

# "Not yet" means nothing scheduled and a pointer at the by-hand run.
[ -e "$HOME/Library/LaunchAgents/govern.daily-brief.plist" ] && [ "$HOME/Library/LaunchAgents/govern.daily-brief.plist" -nt "$rb" ] \
  && echo "a launchd entry was written despite 'not yet'" >> "$FINDINGS"
grep -qi 'daily-brief' "$OUT" || echo "output never points at /daily-brief for the by-hand run" >> "$FINDINGS"
