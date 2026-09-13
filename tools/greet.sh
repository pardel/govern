#!/usr/bin/env bash
# What a session should know before it does anything: what is waiting,
# what is overdue and what is still failing, counted off the disk.
# setup.sh installs it as a Claude Code SessionStart hook, so it runs
# itself when a session opens; run it by hand any time. It prints a few
# lines and always exits 0, because a greeting that breaks the session it
# greets is worse than none.
#
# With --hook it prints the same facts as the JSON a hook may return:
# `additionalContext` for the assistant, and one `systemMessage` line
# for you, the thing that most needs doing. A hook cannot start /onboard
# for you; the nearest it can come is to have the assistant offer it on
# your first message and run it on a yes.
set -u
ROOT="${GOVERN_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
cd "$ROOT" 2>/dev/null || exit 0

newest() { ls -t "$@" 2>/dev/null | head -1; }
days_since() {
  m=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || { echo 0; return; }
  echo $(( ( $(date +%s) - m ) / 86400 ))
}

lines=()
say() { lines+=("$1"); }

n_inbox=$(find 0_Inbox -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
brief=$(newest 5_System/briefs/brief-*.md)
lint=$(newest 5_System/memos/lint-*.md)
urgent=""

say "Knowledge base at $ROOT, $(date +%Y-%m-%d)."
if [ ! -f CLAUDE.md ]; then
  say "No rulebook yet. Run /onboard before anything else."
  urgent="No rulebook yet. Say anything and I will offer to run /onboard."
fi
if [ "$n_inbox" -gt 0 ]; then
  say "Inbox: $n_inbox item(s) waiting for /process-inbox."
  [ -n "$urgent" ] || urgent="Inbox: $n_inbox item(s) waiting for /process-inbox."
else
  say "Inbox: empty."
fi
if [ -n "$brief" ]; then
  say "Last brief: $(basename "$brief" .md | sed 's/^brief-//'), $(days_since "$brief") day(s) ago."
else
  say "No brief yet. /daily-brief writes the first."
fi
if [ -n "$lint" ]; then
  d=$(days_since "$lint")
  if [ "$d" -gt 7 ]; then say "Last lint: $d days ago, so one is due."; else say "Last lint: $d day(s) ago."; fi
else
  say "No lint memo yet."
fi
for f in 5_System/logs/FAILED-*; do
  [ -f "$f" ] || continue
  say "Still failing: $(sed -n 2p "$f")"
  [ -n "$urgent" ] || urgent="A scheduled run is still failing: $(sed -n 2p "$f")"
done

if [ "${1:-}" = "--hook" ]; then
  esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
  ctx=""
  for l in "${lines[@]}"; do ctx="$ctx$(esc "$l")\\n"; done
  [ -f CLAUDE.md ] || ctx="${ctx}\\nThere is no rulebook, so nothing else can be done properly yet. Whatever the first message says, reply with one question only: this base has no rulebook, run the onboarding now? On a yes, read .claude/skills/onboard/SKILL.md and carry out that interview exactly as written, then come back to whatever was asked. On a no, say that /onboard writes it whenever they are ready, and stop."
  printf '{"additionalContext": "%s"' "$ctx"
  [ -n "$urgent" ] && printf ', "systemMessage": "%s"' "$(esc "$urgent")"
  printf '}\n'
else
  printf '%s\n' "${lines[@]}"
fi
exit 0
