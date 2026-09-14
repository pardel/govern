#!/usr/bin/env bash
# Tier 2: does setup.sh do what the README says it does?
#
# Deterministic, no model, no network. Runs the real script twice in
# throwaway directories: once with the prompts reachable, once with them
# not. The second run matters more. A setup script that half-fails and
# says so is fine; one that half-fails and reports success is the exact
# failure this framework exists to prevent, and it shipped that way for
# about ten minutes on 2026-07-26 before being caught by running it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
checked=0

ok()  { checked=$((checked + 1)); }
bad() { checked=$((checked + 1)); fail=1; echo "- $1"; }
check() { if eval "$2"; then ok; else bad "$1"; fi; }

echo "# setup.sh behaviour"

# =========================================================== success path
echo
echo "## With the prompts reachable"
echo

# Stubs for every scheduler this machine might have, in front of the real
# ones on PATH, each recording the fact that it was called. Reading the
# developer's own crontab would assert something about whoever runs this
# rather than about the script.
stubs="$TMP/stubs"; mkdir -p "$stubs"
for s in crontab launchctl systemctl at; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/scheduler-touched"\n' "$s" "$TMP" > "$stubs/$s"
  chmod +x "$stubs/$s"
done

kb="$TMP/ok"; mkdir -p "$kb"; cd "$kb"
out="$TMP/ok.out"
PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" > "$out" 2>&1
rc=$?

check "setup.sh exited $rc, expected 0" "[ $rc -eq 0 ]"

for d in 0_Inbox 1_Projects 2_Areas 3_Resources 4_Archive 5_System/prompts; do
  check "\`$d/\` missing"          "[ -d '$kb/$d' ]"
  check "\`$d/.gitkeep\` missing"  "[ -f '$kb/$d/.gitkeep' ]"
done

n_commits=$(git -C "$kb" rev-list --count HEAD 2>/dev/null || echo 0)
check "expected exactly 1 commit, found $n_commits" "[ '$n_commits' = '1' ]"
check "working tree dirty after setup" "[ -z \"\$(git -C '$kb' status --porcelain)\" ]"

n_want=$(grep -c '^install_command ' "$ROOT/setup.sh")
n_got=$(find "$kb/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
check "expected $n_want commands, installed $n_got" "[ '$n_got' = '$n_want' ]"

for s in "$kb"/.claude/skills/*/SKILL.md; do
  [ -f "$s" ] || continue
  name=$(basename "$(dirname "$s")")
  check "\`/$name\` has no name: in its frontmatter"        "grep -q '^name: ' '$s'"
  check "\`/$name\` has no description: in its frontmatter" "grep -q '^description: ' '$s'"
  check "\`/$name\` frontmatter is not delimited"           "[ \"\$(head -1 '$s')\" = '---' ]"
done

# The .txt prompts use "# " as a comment. SKILL.md is Markdown, where the
# same line is an H1. Anything still starting "# " means the conversion
# regressed and the caveat headers are rendering as giant headings.
stray=$(grep -rl '^# ' "$kb/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')
check "$stray SKILL.md file(s) still contain an H1 from a .txt comment" "[ '$stray' = '0' ]"

for n in daily-brief-grown weekly-review retrieval-metrics; do
  s="$kb/.claude/skills/$n/SKILL.md"
  check "\`/$n\` lost its caveat header" "grep -q '^> ' '$s'"
done

# The status tool, and the page it writes. Generating it here is the only
# way to know the script runs at all rather than merely being copied.
check "status.sh was not installed" "[ -s '$kb/5_System/tools/status.sh' ]"
check "greet.sh was not installed" "[ -s '$kb/5_System/tools/greet.sh' ]"

# Run from the clone with no RAW override, the script uses the prompts
# beside it and says so, rather than fetching the same files from GitHub.
kb_local="$TMP/local"; mkdir -p "$kb_local"
( cd "$kb_local" && PATH="$stubs:$PATH" bash "$ROOT/setup.sh" ) > "$TMP/local.out" 2>&1
check "run from the clone, setup.sh installed no commands" "grep -q 'Commands installed' '$TMP/local.out'"
check "run from the clone, setup.sh did not say the prompts came from the clone" "grep -q 'from the clone' '$TMP/local.out'"

# A new base goes in an empty folder only. A `cd` that failed leaves the
# terminal in the home folder, and a script that lays out a base there
# anyway is how a home folder grows a 0_Inbox and eight user-wide commands.
kb_full="$TMP/full"; mkdir -p "$kb_full"; echo mine > "$kb_full/notes.txt"
( cd "$kb_full" && PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" ) > "$TMP/full.out" 2>&1
rc_full=$?
check "setup.sh ran in a folder that was not empty, exiting $rc_full" "[ $rc_full -ne 0 ]"
check "setup.sh laid out folders in a folder that was not empty" "[ ! -d '$kb_full/0_Inbox' ]"
check "setup.sh installed commands in a folder that was not empty" "[ ! -d '$kb_full/.claude' ]"
kb_hidden="$TMP/hidden"; mkdir -p "$kb_hidden/.fseventsd"
( cd "$kb_hidden" && PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" ) > "$TMP/hidden.out" 2>&1
rc_hidden=$?
check "setup.sh refused a folder holding only hidden entries, as a fresh volume does, exiting $rc_hidden" "[ $rc_hidden -eq 0 ]"
check "the session hook was not written" "grep -q 'greet.sh' '$kb/.claude/settings.json' 2>/dev/null"
( cd "$kb" && bash 5_System/tools/greet.sh > "$TMP/greet.out" 2>"$TMP/greet.err" )
rc_g=$?
check "greet.sh exited $rc_g" "[ $rc_g -eq 0 ]"
check "greet.sh wrote to stderr: $(head -1 "$TMP/greet.err" 2>/dev/null)" "[ ! -s '$TMP/greet.err' ]"
check "greet.sh did not report the inbox" "grep -qi 'inbox' '$TMP/greet.out'"
check "greet.sh did not say there is no rulebook yet" "grep -qi 'rulebook' '$TMP/greet.out'"
( cd "$kb" && bash 5_System/tools/greet.sh --hook > "$TMP/greet-hook.out" 2>/dev/null )
check "greet.sh --hook did not return JSON" "python3 -c 'import json,sys; json.load(open(sys.argv[1]))' '$TMP/greet-hook.out'"
check "greet.sh --hook carries no systemMessage about the missing rulebook" \
  "python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if \"onboard\" in d.get(\"systemMessage\",\"\") else 1)' '$TMP/greet-hook.out'"
page="$TMP/kb-status.html"
( cd "$kb" && bash 5_System/tools/status.sh > "$page" 2>"$TMP/status.err" )
check "status.sh exited non-zero" "[ $? -eq 0 ]"
check "status.sh wrote to stderr: $(head -1 "$TMP/status.err" 2>/dev/null)" \
  "[ ! -s '$TMP/status.err' ]"
check "status page is not HTML" "grep -q '<!doctype html>' '$page'"
check "status page does not report the installed commands" \
  "grep -q '/process-inbox' '$page'"
check "status page fetches something external, so it is not self-contained" \
  "! grep -qE '<(script|link|img)[^>]+(src|href)=\"http' '$page'"
check "status page does not say a rulebook is still missing" \
  "grep -q 'No rulebook yet' '$page'"

# ------------------------------------------------- the unattended runner
# The kit promises a brief written before you wake, so it ships a runner.
# Nothing below needs a model: a stub in place of claude is what makes the
# failure path testable, and the failure path is the one that matters. A
# runner whose quiet death looks like a quiet success is the shape of
# defect this whole file exists to rule out.

check "setup.sh reached for a scheduler; it must schedule nothing" \
  "[ ! -f '$TMP/scheduler-touched' ]"
check "schedule.sh was not installed" "[ -s '$kb/5_System/tools/schedule.sh' ]"

sched="$kb/5_System/tools/schedule.sh"

# Setup deliberately writes no CLAUDE.md, and an unattended session in a
# base with no gates list is this framework inside out. The same check
# catches an unmounted volume, so it has to hold before anything else.
( cd "$kb" && bash "$sched" run daily-brief ) > "$TMP/norule.out" 2>&1
rc_nr=$?
check "schedule.sh ran with no rulebook present, exiting $rc_nr" "[ $rc_nr -ne 0 ]"
check "schedule.sh refused without saying a rulebook was what was missing" \
  "grep -qi 'rulebook' '$TMP/norule.out'"

printf '# Rulebook\n\n## Gates\n\n- Pushing to a git remote.\n' > "$kb/CLAUDE.md"
( cd "$kb" && git add -A && git commit -q -m "rulebook" )

( cd "$kb" && bash "$sched" run no-such-command ) > "$TMP/nocmd.out" 2>&1
rc_nc=$?
check "schedule.sh accepted a command that is not installed, exiting $rc_nc" "[ $rc_nc -ne 0 ]"

# `print` hands you the scheduler entry with the paths filled in. It has
# to name this base and this claude, honour the hour, refuse a bad one,
# and touch no scheduler while doing it.
printf '#!/bin/sh\necho stub\n' > "$TMP/claude-here"; chmod +x "$TMP/claude-here"
( cd "$kb" && PATH="$stubs:$PATH" CLAUDE_BIN="$TMP/claude-here" bash "$sched" print daily-brief 7 ) \
  > "$TMP/print.out" 2>&1
rc_pr=$?
check "schedule.sh print exited $rc_pr" "[ $rc_pr -eq 0 ]"
check "the printed entry does not point at this base" "grep -qF '$kb/5_System/tools/schedule.sh' '$TMP/print.out'"
check "the printed entry does not carry the hour asked for" \
  "grep -qE '<integer>7</integer>|^0 7 \\* \\* \\*' '$TMP/print.out'"
check "the printed entry does not name the claude it found" "grep -qF '$TMP/claude-here' '$TMP/print.out'"
if command -v plutil >/dev/null 2>&1; then
  awk '/^<\?xml/ { f=1 } f { print } /^<\/plist>/ { f=0 }' "$TMP/print.out" > "$TMP/print.plist"
  check "the printed plist does not parse" "plutil -lint '$TMP/print.plist' >/dev/null 2>&1"
fi
check "print reached for a scheduler; it must schedule nothing" "[ ! -f '$TMP/scheduler-touched' ]"
( cd "$kb" && bash "$sched" print daily-brief 25 ) > /dev/null 2>&1
rc_ph=$?
check "schedule.sh print accepted hour 25, exiting $rc_ph" "[ $rc_ph -ne 0 ]"

# `install` writes its own launchd file and loads it, and touches nothing
# it did not write. HOME is pointed into the temp tree so the file lands
# there, and the launchctl on PATH is the stub above.
if [ "$(uname -s)" = Darwin ]; then
  fakehome="$TMP/home"; mkdir -p "$fakehome/Library/LaunchAgents"
  printf '<plist><dict><key>Label</key><string>someone.else</string></dict></plist>\n' \
    > "$fakehome/Library/LaunchAgents/govern.lint.plist"
  ( cd "$kb" && HOME="$fakehome" PATH="$stubs:$PATH" bash "$sched" install lint 6 ) > "$TMP/install-foreign.out" 2>&1
  rc_if=$?
  check "install overwrote a launchd file it did not write, exiting $rc_if" "[ $rc_if -ne 0 ]"
  check "the foreign file was changed" \
    "grep -q 'someone.else' '$fakehome/Library/LaunchAgents/govern.lint.plist'"
  ( cd "$kb" && HOME="$fakehome" PATH="$stubs:$PATH" CLAUDE_BIN="$TMP/claude-here" bash "$sched" install daily-brief 7 ) \
    > "$TMP/install.out" 2>&1
  rc_in=$?
  check "schedule.sh install exited $rc_in" "[ $rc_in -eq 0 ]"
  check "install wrote no launchd file" "[ -s '$fakehome/Library/LaunchAgents/govern.daily-brief.plist' ]"
  check "the written file does not point at this base" \
    "grep -qF '$kb/5_System/tools/schedule.sh' '$fakehome/Library/LaunchAgents/govern.daily-brief.plist'"
  check "install did not ask launchctl to load the file" \
    "grep -q 'launchctl bootstrap' '$TMP/scheduler-touched'"
fi

printf '#!/bin/sh\ncat >/dev/null\necho "I could not reach one of the sources, so I stopped."\n' \
  > "$TMP/claude-quiet"
printf '#!/bin/sh\ncat >/dev/null\nmkdir -p 5_System/briefs\necho brief > 5_System/briefs/brief-eval.md\necho GOVERN_OK\n' \
  > "$TMP/claude-ok"
chmod +x "$TMP/claude-quiet" "$TMP/claude-ok"

( cd "$kb" && CLAUDE_BIN="$TMP/claude-quiet" bash "$sched" run daily-brief ) \
  > "$TMP/quiet.out" 2>&1
rc_q=$?
check "a run that printed no marker was reported as a success, exiting $rc_q" "[ $rc_q -ne 0 ]"
check "a failed run left no FAILED- file to find it by" \
  "[ -f '$kb/5_System/logs/FAILED-daily-brief' ]"
check "the run log does not record the failure" \
  "grep -q 'FAILED' '$kb/5_System/logs/schedule.log'"

( cd "$kb" && CLAUDE_BIN="$TMP/claude-ok" bash "$sched" run daily-brief ) \
  > "$TMP/good.out" 2>&1
rc_g=$?
check "a run that printed the marker was reported as a failure, exiting $rc_g" "[ $rc_g -eq 0 ]"
check "a good run did not clear the FAILED- file left by the one before" \
  "[ ! -f '$kb/5_System/logs/FAILED-daily-brief' ]"

# A repo under _repos/ is a submodule, and its pointer moves only when a
# person bumps it. Plant one, move its HEAD, run a good pass, and the
# brief is committed while the pointer stays where it was.
sub="$kb/1_Projects/work-thing/_repos/thing"; mkdir -p "$sub"
( cd "$sub" && git init -q && git commit -q --allow-empty -m one )
( cd "$kb" && git -c protocol.file.allow=always submodule add -q "$sub" 1_Projects/work-thing/_repos/thing >/dev/null 2>&1 \
    && git commit -q -m "add submodule" )
pinned="$(cd "$kb" && git ls-tree HEAD 1_Projects/work-thing/_repos/thing | awk '{print $3}')"
( cd "$kb/1_Projects/work-thing/_repos/thing" && git commit -q --allow-empty -m two )
printf '#!/bin/sh\ncat >/dev/null\nmkdir -p 5_System/briefs\necho brief > 5_System/briefs/brief-eval-2.md\necho GOVERN_OK\n' \
  > "$TMP/claude-ok2"; chmod +x "$TMP/claude-ok2"
( cd "$kb" && CLAUDE_BIN="$TMP/claude-ok2" bash "$sched" run daily-brief ) > "$TMP/good2.out" 2>&1
rc_g2=$?
check "a good run with a moved submodule pointer failed, exiting $rc_g2" "[ $rc_g2 -eq 0 ]"
check "the moved pointer made the run treat the tree as dirty" "grep -q 'brief-eval-2' <(cd '$kb' && git show --name-only --format= HEAD)"
now="$(cd "$kb" && git ls-tree HEAD 1_Projects/work-thing/_repos/thing | awk '{print $3}')"
check "an unattended run bumped a submodule pointer ($pinned -> $now)" "[ '$pinned' = '$now' ]"
# No pipe into `grep -q` here. It closes the pipe on its first match, git
# takes SIGPIPE, and `pipefail` hands back 141 for a condition that was
# in fact true, which is a green check reading as a finding.
check "a good run left what it wrote uncommitted" \
  "[ -n \"\$(git -C '$kb' log --format=%s --grep='^unattended: /daily-brief')\" ]"
check "the run log does not record the success as a counted change" \
  "grep -qF '1 file(s) changed, committed' '$kb/5_System/logs/schedule.log'"

# A log nobody opens is where a dead job hides, so it has to reach the
# page the reader already looks at.
page2="$TMP/kb-status-2.html"
( cd "$kb" && bash 5_System/tools/status.sh > "$page2" 2>/dev/null )
check "the status page does not report scheduled runs" "grep -q 'Scheduled runs' '$page2'"

# Logs are machine-local noise, and `git add -A` runs in both setup and
# the runner, so an unignored log folder ends up in history for good.
check "5_System/logs/ is not ignored, so run logs would be committed" \
  "grep -q '5_System/logs/' '$kb/.gitignore'"
# --update on an existing base refreshes commands and tools, commits
# nothing, never touches the rulebook, removes a kit-written /rulebook,
# and refuses both a plain re-run and a dirty tree.
( cd "$kb" && git add -A -- ':!*/_repos/*' && git commit -q -m "before update" ) >/dev/null 2>&1 || true
commits_before="$(cd "$kb" && git rev-list --count HEAD)"
rb_before="$(cd "$kb" && cat CLAUDE.md)"
mkdir -p "$kb/.claude/skills/rulebook"
printf -- '---\nname: rulebook\ndescription: Interview me for the gates list, then write CLAUDE.md.\n---\nold\n' > "$kb/.claude/skills/rulebook/SKILL.md"
( cd "$kb" && git add -A -- ':!*/_repos/*' && git commit -q -m "stale rulebook" ) >/dev/null 2>&1
( cd "$kb" && PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" ) > "$TMP/rerun.out" 2>&1
rc_rr=$?
check "a plain re-run on an existing base did not refuse, exiting $rc_rr" "[ $rc_rr -ne 0 ]"
check "the refusal did not name --update" "grep -q -- '--update' '$TMP/rerun.out'"
echo scratch > "$kb/0_Inbox/dirty.txt"
( cd "$kb" && PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" --update ) > "$TMP/dirty.out" 2>&1
rc_dt=$?
check "--update ran on a dirty tree, exiting $rc_dt" "[ $rc_dt -ne 0 ]"
rm -f "$kb/0_Inbox/dirty.txt"
( cd "$kb" && PATH="$stubs:$PATH" RAW="file://$ROOT/prompts" bash "$ROOT/setup.sh" --update ) > "$TMP/update.out" 2>&1
rc_up=$?
check "--update failed, exiting $rc_up" "[ $rc_up -eq 0 ]"
check "--update made a commit" "[ \"$(cd "$kb" && git rev-list --count HEAD)\" = '$((commits_before + 1))' ]"
check "--update touched the rulebook" "[ \"$(cd "$kb" && cat CLAUDE.md)\" = \"$rb_before\" ]"
check "--update left the stale /rulebook in place" "[ ! -d '$kb/.claude/skills/rulebook' ]"
check "--update did not reinstall /onboard" "grep -q 'name: onboard' '$kb/.claude/skills/onboard/SKILL.md'"
check "--update reached for a scheduler" "[ ! -f '$TMP/scheduler-touched' ] || ! grep -q 'setup' '$TMP/scheduler-touched'"
( cd "$kb" && git checkout -q -- . 2>/dev/null; git clean -qfd .claude 2>/dev/null ) || true

# Submodules ignored: the moved pointer planted above is meant to be
# left unstaged, and this check is about the runner's logs.
check "the runner's own logs made it into the tree" \
  "[ -z \"\$(git -C '$kb' status --porcelain --ignore-submodules=all)\" ]"

# A prompt with no comment header must survive byte-for-byte.
body="$TMP/body"
awk 'BEGIN{n=0} /^---$/{n++; next} n>=2 { if (s || $0 != "") { s=1; print } }' \
  "$kb/.claude/skills/process-inbox/SKILL.md" > "$body"
check "process-inbox body was altered on the way into SKILL.md" \
  "diff -q '$ROOT/prompts/process-inbox.txt' '$body' >/dev/null"

# =========================================================== failure path
echo
echo "## With the prompts unreachable"
echo

kb2="$TMP/fail"; mkdir -p "$kb2"; cd "$kb2"
out2="$TMP/fail.out"
PATH="$stubs:$PATH" RAW="file:///nonexistent-govern-eval" \
  bash "$ROOT/setup.sh" > "$out2" 2>&1
rc2=$?

check "setup.sh exited $rc2 with prompts unreachable, expected 0" "[ $rc2 -eq 0 ]"
check "no skeleton was created when prompts were unreachable" "[ -d '$kb2/0_Inbox' ]"
check "no commit was made when prompts were unreachable" \
  "[ \"\$(git -C '$kb2' rev-list --count HEAD 2>/dev/null)\" = '1' ]"

# The whole point: it must not claim to have installed anything.
check "output claims commands were installed when none were" \
  "! grep -q 'Commands installed' '$out2'"
check "output does not say which prompts it could not fetch" \
  "grep -q 'Could not fetch' '$out2'"

for n in $(grep '^install_command ' "$ROOT/setup.sh" | awk '{print $2}'); do
  check "\`$n\` missing from the could-not-fetch list" "grep -q '$n' '$out2'"
done

# An empty .claude/skills/<name>/ would look like a broken install.
check "left an empty .claude directory behind" "[ ! -d '$kb2/.claude' ]"

echo
if [ "$fail" -eq 0 ]; then
  echo "**Clean.** $checked assertions across both paths."
else
  echo "**Findings above.** $checked assertions ran."
fi
exit "$fail"
