#!/usr/bin/env bash
# Governed second brain: the deterministic half of the setup.
# Folders, version control, and the prompts installed as Claude Code
# commands. The rulebook is written with you in the room, because
# its decisions are yours.
set -euo pipefail

# Run from a clone, the prompts and tools sit beside this script, so they
# are used rather than fetched again from GitHub. Piped from curl there
# is no clone, and GitHub is the source. Either way the summary says which.
here="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)"
if [ -z "${RAW:-}" ] && [ -f "$here/prompts/onboard.txt" ]; then
  RAW="file://$here/prompts"
  source_note="the clone at $here"
else
  source_note="github.com/pardel/govern"
fi
RAW="${RAW:-https://raw.githubusercontent.com/pardel/govern/main/prompts}"
TOOLS="${TOOLS:-${RAW%/prompts}/tools}"

# A second run on a base that exists refreshes the commands and the tools
# and touches nothing else: no folders, no git init, no skeleton commit,
# never the rulebook. It needs --update, so a stray run in the wrong
# folder cannot re-initialise a base by accident, and a clean tree, so
# the diff it leaves is the update and nothing of yours.
update=0; existing=0
if [ "${1:-}" = "--update" ]; then update=1; fi
if [ -d .git ] && [ -d .claude/skills ]; then existing=1; fi
if [ "$update" = 1 ] && [ "$existing" = 0 ]; then
  echo "Nothing to update: no base in $(pwd). Run without --update in an empty folder." >&2
  exit 1
fi
if [ "$update" = 0 ] && [ "$existing" = 1 ]; then
  echo "This folder already holds a base. To refresh its commands and tools:" >&2
  echo "  bash setup.sh --update" >&2
  exit 1
fi
if [ "$update" = 1 ] && [ -n "$(git status --porcelain --ignore-submodules=all 2>/dev/null)" ]; then
  echo "The tree has uncommitted changes. Commit or stash them first, so the" >&2
  echo "update's diff is the update and nothing of yours." >&2
  exit 1
fi

if [ "$update" = 0 ]; then
  for d in 0_Inbox 1_Projects 2_Areas 3_Resources 4_Archive \
           5_System/prompts; do
    mkdir -p "$d"
    touch "$d/.gitkeep"
  done
fi

# /rulebook became /onboard. A command this script wrote under the old
# name is removed on update; one you wrote yourself is not touched.
removed=""
if [ "$update" = 1 ] && grep -q '^name: rulebook$' .claude/skills/rulebook/SKILL.md 2>/dev/null \
   && grep -q '^description: Interview me for the gates list' .claude/skills/rulebook/SKILL.md; then
  rm -r .claude/skills/rulebook
  removed="/rulebook (it is /onboard now)"
fi

# Every prompt becomes a slash command, including the rulebook: it
# runs once rather than repeatedly, but it is an interview, and a
# command keeps it interactive where a pipe would not. Each grown
# prompt carries its own header saying what it assumes, and that
# header travels into the command with it.
installed=()
missing=()

install_command() {
  name="$1"
  source="$2"
  description="$3"
  dir=".claude/skills/$name"

  if ! body=$(curl -fsSL "$RAW/$source" 2>/dev/null); then
    missing+=("$name")
    return 0
  fi

  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    printf -- '---\n\n'
    # A leading "# " is a comment in the .txt but an H1 heading in
    # Markdown, so the caveat headers become blockquotes on the way in.
    while IFS= read -r line; do
      printf '%s\n' "${line/#\# /> }"
    done <<<"$body"
  } > "$dir/SKILL.md"
  installed+=("$name")
}

install_command onboard onboard.txt \
  "Onboard this knowledge base: ask what to call me, the gates, your areas, a line on each and whether to schedule the brief, then write CLAUDE.md. Run this once, first."
install_command process-inbox process-inbox.txt \
  "Process everything in 0_Inbox: archive each original untouched, classify it, compile a note that cites its source, and verify before reporting done."
install_command daily-brief daily-brief.txt \
  "Write today's brief: what matters today, commitments due, and every source consulted with its status."
install_command recruit recruit.txt \
  "Onboard a worker: interview me for the role, the name and above all what it must never do, then file a profile and a roster row. With no roster yet, agree a name family and hire the orchestrator and the recruiter first."
install_command correction-to-rule correction-to-rule.txt \
  "Turn a correction into a rule in CLAUDE.md, written so a fresh session would get it right first time."
install_command refute refute.txt \
  "Adversarially check a note against the archived original it cites: try to break each claim rather than confirm it, and say what should be cut or downgraded."
install_command lint lint.txt \
  "Lint the knowledge base: dangling links, missing sources, notes older than what they cite, orphaned originals, and claims labelled verified with nothing behind them."
install_command memory-consolidation memory-consolidation.txt \
  "Sweep the memories carried between sessions for ones that are no longer true, propose merges and removals for me to confirm, and mine the changelog for corrections that never became rules."
install_command daily-brief-grown later/daily-brief.txt \
  "The grown daily brief, for later: deterministic state from a pulse script, goals cited by name, and escalation when a ritual is overdue. Assumes a pulse script, a goals file, a commitments register and a changelog."
install_command weekly-review later/weekly-review.txt \
  "The weekly review, for later, and interactive by design: area verdicts, every flag decided, next week's top three. Assumes a pulse script, a run of daily briefs and a commitments register."
install_command retrieval-metrics later/retrieval-metrics.txt \
  "Retrieval quality, for later: run a fixed set of test queries, resolve every miss by hand, and record the miss rate and the direction it is moving. Assumes a stable query set and enough notes to measure."

# Three scripts, copied in and never called from here. One reads the base
# and writes an HTML page. One runs a command unattended, once, when a
# scheduler asks it to. One greets a new session with what is overdue.
# This script starts nothing and schedules nothing.
mkdir -p 5_System/tools
for t in status schedule greet; do
  curl -fsSL "$TOOLS/$t.sh" > "5_System/tools/$t.sh" 2>/dev/null \
    || rm -f "5_System/tools/$t.sh"
done

# The greeting runs itself at the start of every Claude Code session,
# through a hook. Written only when no settings file exists, so a file
# of yours is never touched.
if [ -s 5_System/tools/greet.sh ] && [ ! -f .claude/settings.json ]; then
  mkdir -p .claude
  printf '{\n  "hooks": {\n    "SessionStart": [\n      { "hooks": [ { "type": "command", "command": "bash 5_System/tools/greet.sh --hook" } ] }\n    ]\n  }\n}\n' \
    > .claude/settings.json
fi

if [ "$update" = 1 ]; then
  echo "Updated from $source_note. Nothing committed, nothing of yours touched."
  [ -n "$removed" ] && echo "Removed: $removed"
  changed="$(git status --porcelain --ignore-submodules=all | wc -l | tr -d ' ')"
  if [ "$changed" = 0 ]; then
    echo "Already current: no command or tool changed."
  else
    echo "$changed file(s) changed; git diff shows exactly what. A command you had"
    echo "reshaped is in git: git checkout -- <file> keeps yours. Commit when you"
    echo "have read the diff. CHANGELOG.md in the repo says what changed and why."
  fi
  exit 0
fi

git init --quiet
printf '.DS_Store\nkb-status.html\n5_System/logs/\n' > .gitignore
git add -A
git commit --quiet -m "governed second brain: skeleton"

echo "Skeleton in place. Prompts and tools from $source_note."

if [ ${#installed[@]} -gt 0 ]; then
  echo "Commands installed: $(printf '/%s ' "${installed[@]}")"
  echo
  echo "/daily-brief-grown, /weekly-review and /retrieval-metrics are"
  echo "the grown ones. They assume scripts and registers you do not"
  echo "have yet, and each says so when you run it. Start with"
  echo "/daily-brief, /process-inbox and /correction-to-rule."
fi

if [ -s 5_System/tools/status.sh ]; then
  echo
  echo "For a look at what you have, any time:"
  echo "  bash 5_System/tools/status.sh > kb-status.html && open kb-status.html"
fi

if [ -s 5_System/tools/schedule.sh ]; then
  echo
  echo "Nothing was scheduled by this script, and nothing runs on its own."
  echo "/onboard offers to schedule the daily brief at the end of its"
  echo "interview, once the rulebook exists; 5_System/tools/schedule.sh is"
  echo "the runner, and the README's \"Running it unattended\" has the rest."
fi

if [ ${#missing[@]} -eq 0 ]; then
  echo
  echo "Now start Claude Code here and run /onboard. It will ask you"
  echo "the five questions only you can answer."
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo
  echo "Could not fetch: $(printf '%s ' "${missing[@]}")"
  echo "Nothing was installed for those. They are plain text at"
  echo "github.com/pardel/govern/tree/main/prompts if you want them."
  echo
  echo "Start Claude Code here and paste the onboarding prompt by hand:"
  echo "it will ask you the five questions only you can answer."
fi
