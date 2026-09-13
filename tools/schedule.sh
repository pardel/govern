#!/usr/bin/env bash
# Run one installed command once, the way a scheduler would.
#
#   bash 5_System/tools/schedule.sh run daily-brief   one run, unattended
#   bash 5_System/tools/schedule.sh                   how the last runs went
#   bash 5_System/tools/schedule.sh print daily-brief 6
#                                    the scheduler entry for this machine,
#                                    paths filled in, for you to paste
#   bash 5_System/tools/schedule.sh install daily-brief 6
#                                    on macOS, writes that entry as its own
#                                    launchd file and loads it; elsewhere,
#                                    prints the cron line, since a crontab
#                                    is not a file this may write
#
# `install` writes one file it labels as its own, and refuses to touch a
# file it did not write. It never edits a crontab, because a script that
# edits your crontab is a script that can eat an entry it did not write.
# Nothing schedules itself: setup.sh never calls this file, and /onboard
# runs `install` only after you have said yes to the hour.
#
# Three things this refuses to do, and each is the point.
#
# It will not compute its own cadence. The scheduler owns the calendar
# and this runs once when asked. Cadence written as "has it been a day
# since last time" is arithmetic, and arithmetic that floors elapsed
# seconds to whole days turns a daily job into an every-other-day job
# while reporting nothing wrong. The system this kit came from shipped
# exactly that bug.
#
# It will not treat silence as success. A run has to end with the command
# printing a marker, and one that finishes without it is logged failed.
# Otherwise a job that stopped firing and a job with nothing to say look
# identical, which is how a gate sits dead for weeks with nobody noticing.
#
# It will not run before there is a rulebook. An unattended session in a
# base whose gates list has not been written yet is this kit's own
# argument upside down. The same check catches an unmounted volume, which
# is the failure the README warns about and the one that would otherwise
# have this script write its logs into an empty mount point.
set -uo pipefail

ROOT="${GOVERN_ROOT:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
LOGS="$ROOT/5_System/logs"
MARKER="GOVERN_OK"

# The tools an unattended session gets: reading and writing files, and
# nothing that executes. This is the gates list enforced at the tool
# layer rather than asked for politely, which matters most at the moment
# nobody is there to say no. Without Bash there is no push and no delete,
# so the first gates the interview offers are not reachable.
#
# `--allowedTools` alone is a pre-approval, not a fence: with Bash left
# off it, a session still reached for Bash and got it. Naming it in the
# deny list is what actually removes it. Widen these if a grown command
# needs more, knowing what you are widening and when.
ALLOW="${GOVERN_ALLOW:-Read Glob Grep Write Edit}"
DENY="${GOVERN_DENY:-Bash}"

# A wall-clock bound. A hung run is the worst failure available here:
# launchd will not start a second copy of a job still running, so one
# hang is silence for good. Killed runs are failures like any other.
TIMEOUT="${GOVERN_TIMEOUT:-900}"

die() { echo "$*" >&2; exit 1; }

# CLAUDE.md rather than a folder, because folders can be created by
# accident. On macOS `/Volumes` is writable, so a path inside an
# unmounted image is a directory waiting to be made, and the real volume
# then arrives at `/Volumes/kb 1` while every absolute path still points
# at the empty one. Checking for a file that only the real base has is
# what stops this script writing into that hole.
[ -n "$ROOT" ] && [ -f "$ROOT/CLAUDE.md" ] || die \
"No rulebook at $ROOT/CLAUDE.md, so nothing will run.

Either the volume holding the knowledge base is not mounted, or you have
not run /onboard yet. Scheduling an unattended session before you have
said which actions must never happen without you is the wrong order."

# Scheduled jobs get a minimal PATH, so a command that works by hand and
# dies on schedule is nearly always this and nothing else. Resolved here
# rather than assumed, so the plist in the README needs no environment.
find_claude() {
  [ -n "${CLAUDE_BIN:-}" ] && { echo "$CLAUDE_BIN"; return; }
  # A terminal multiplexer or an IDE can put a shim on PATH that lives in
  # a temp folder and dies with the session. An entry that names it
  # works today and fails at six tomorrow, so anything under a temp
  # path is passed over for the stable places below.
  p="$(command -v claude 2>/dev/null)"
  case "$p" in
    ''|"${TMPDIR:-/tmp}"*|/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *) echo "$p"; return ;;
  esac
  for c in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude \
           "$HOME/.claude/local/claude"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
}

# ------------------------------------------------------------------ run
do_run() {
  cmd="$1"
  skill="$ROOT/.claude/skills/$cmd/SKILL.md"
  [ -f "$skill" ] || die "No command called /$cmd. What is installed is in .claude/skills/."
  bin="$(find_claude)"
  [ -n "$bin" ] || die "Cannot find claude. Set CLAUDE_BIN to its full path."

  mkdir -p "$LOGS"
  out="$LOGS/$cmd-$(date +%Y-%m-%d).log"
  short="5_System/logs/$(basename "$out")"

  # cron, unlike launchd, will happily start a second copy of a job whose
  # first copy is still going. mkdir is the atomic test-and-set every
  # system has. A lock left behind by a SIGKILL is never broken on age,
  # because deciding a lock is stale is the same elapsed-time arithmetic
  # this file refuses to do anywhere else. It fails loudly instead, and
  # names the directory to remove.
  lock="$LOGS/.running-$cmd"
  mkdir "$lock" 2>/dev/null || {
    record "$cmd" "already running, or $lock was left behind by a killed run" "$short"
    exit 1
  }
  req="$(mktemp)"
  trap 'rm -rf "$lock" "$req"' EXIT
  # A logout, a shutdown or a `launchctl bootout` mid-run kills this
  # script and nothing else, so without this the run leaves no line at
  # all: the quietest death of the lot, and the one the log exists for.
  # It takes the session down with it rather than orphaning it.
  trap on_signal INT TERM

  # Whatever the tree already carries is the reader's, not this run's.
  dirty_before="$(git -C "$ROOT" status --porcelain --ignore-submodules=all 2>/dev/null | wc -l | tr -d ' ')"

  # Everything after the frontmatter, then the one line this script adds.
  # The prompt comes from the installed command rather than from the repo,
  # so a command you have reshaped is the one that runs. The marker
  # belongs to the runner and not to the prompt: it is what the runner
  # needs to tell a finished pass from a dead one, and putting it in the
  # prompt would print it at you every interactive run as well.
  awk 'n>=2 { print } /^---$/ { n++ }' "$skill" > "$req"
  printf '\nThis run is unattended and nobody will answer a question. If something stops you, still write the file you were asked to write, with status: blocked at the top and a section saying what failed and what the next step is, then stop. If you skipped a check or covered less than the command asked, say so in one line even when the work is otherwise done.\nPrint %s on a line of its own once the work is done and you have confirmed on disk that what you were asked to write is there. Print it at no other time.\n' \
    "$MARKER" >> "$req"

  # Job control on, so the call gets its own process group and a timeout
  # kills the tools it spawned rather than orphaning them.
  set -m
  # shellcheck disable=SC2086  # ALLOW and DENY are lists, and must split
  "$bin" -p --allowedTools $ALLOW --disallowedTools $DENY \
    < "$req" > "$out" 2>&1 &
  pid=$!
  set +m

  reason=""; waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$TIMEOUT" ]; then
      kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
      sleep 3
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
      reason="no answer within ${TIMEOUT}s, killed"
      break
    fi
    sleep 1; waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null; rc=$?

  if [ -n "$reason" ]; then :
  elif [ "$rc" -ne 0 ]; then reason="claude exited $rc"
  elif ! grep -qE "^[[:space:]]*${MARKER}[[:space:]]*$" "$out"; then
    reason="finished without printing $MARKER, so it did not reach the end"
  fi

  [ -n "$reason" ] && { record "$cmd" "$reason" "$short"; exit 1; }

  # The marker is a session reporting on itself, which this kit does not
  # accept as evidence anywhere else. So the log carries a counted number
  # beside it. A week of clean runs that changed nothing is a thing you
  # can see here without this script having to guess what it means.
  # Code lives under _repos/ as submodules, and a submodule whose own
  # HEAD moved shows up here as a pointer to stage. An unattended run
  # never bumps one: a pointer pinned to a commit no clone can fetch is
  # the failure the convention exists to prevent, and only a person
  # decides it. So the count ignores submodules and the add excludes them.
  changed="$(git -C "$ROOT" status --porcelain --ignore-submodules=all 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$dirty_before" != 0 ]; then
    note="$changed file(s) changed, left uncommitted: the tree was already dirty"
  elif [ "$changed" = 0 ]; then
    note="changed nothing"
  elif git -C "$ROOT" add -A -- ':!*/_repos/*' >/dev/null 2>&1 &&
       git -C "$ROOT" commit -q -m "unattended: /$cmd $(date +%Y-%m-%d)" >/dev/null 2>&1; then
    note="$changed file(s) changed, committed"
  else
    note="$changed file(s) changed, left uncommitted: git would not commit them"
  fi

  printf '%s  %-20s OK      %s\n' "$(date '+%Y-%m-%d %H:%M')" "$cmd" "$note" >> "$LOGS/schedule.log"
  rm -f "$LOGS/FAILED-$cmd"
  echo "/$cmd ran: $note. Output in $short"
}

on_signal() {
  [ -n "${pid:-}" ] && { kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null; }
  record "$cmd" "killed by a signal before it finished" "$short"
  rm -rf "$lock" "$req"
  exit 1
}

# A failure has to be findable without anyone remembering to look. One
# line in the log, a file named for the command that the next good run
# deletes, and a block on the status page, which you open anyway.
record() {
  mkdir -p "$LOGS"
  stamp="$(date '+%Y-%m-%d %H:%M')"
  printf '%s  %-20s FAILED  %s\n' "$stamp" "$1" "$2" >> "$LOGS/schedule.log"
  printf '%s\n/%s failed: %s\nWhatever it printed is in %s\nAnything it half-wrote is uncommitted, so `git diff` shows it.\n' \
    "$stamp" "$1" "$2" "$3" > "$LOGS/FAILED-$1"
  echo "/$1 FAILED: $2" >&2
}

# ----------------------------------------------------------------- show
do_show() {
  echo "Last runs:"
  if [ -s "$LOGS/schedule.log" ]; then
    tail -8 "$LOGS/schedule.log" | sed 's/^/  /'
  else
    echo "  none yet. If something is scheduled and this stays empty past"
    echo "  the hour you set, the job is not firing."
  fi
  for f in "$LOGS"/FAILED-*; do
    [ -f "$f" ] || continue
    echo; echo "Still failing:"; sed 's/^/  /' "$f"
  done
}

# ---------------------------------------------------------------- print
# The scheduler entry for this machine with the real paths filled in.
# `print` hands it to you to paste; `install` writes and loads it on
# macOS. The editing either one saves is the part people get wrong,
# three absolute paths and where `claude` actually lives.
check_args() {
  cmd="$1"; hour="$2"
  case "$hour" in ''|*[!0-9]*) die "Hour must be a number from 0 to 23, got '$hour'." ;; esac
  [ "$hour" -le 23 ] || die "Hour must be a number from 0 to 23, got '$hour'."
  [ -f "$ROOT/.claude/skills/$cmd/SKILL.md" ] || die "No command called /$cmd. What is installed is in .claude/skills/."
  bin="$(find_claude)"
  at="$(printf '%02d:00' "$hour")"
  label="govern.$cmd"
  plist="$HOME/Library/LaunchAgents/$label.plist"
}

claude_note() {
  [ -n "$bin" ] && return
  echo "Note: claude was not found on PATH or in the usual places, so the"
  echo "entry below does not name it. The job will refuse until it can be"
  echo "found; set CLAUDE_BIN in the entry once you know where it is."
  echo
}

plist_text() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/5_System/tools/schedule.sh</string>
    <string>run</string>
    <string>$cmd</string>
  </array>
  <key>WorkingDirectory</key><string>$ROOT</string>
EOF
  [ -n "$bin" ] && cat <<EOF
  <key>EnvironmentVariables</key>
  <dict><key>CLAUDE_BIN</key><string>$bin</string></dict>
EOF
  cat <<EOF
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$ROOT/5_System/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$ROOT/5_System/logs/launchd.log</string>
</dict>
</plist>
EOF
}

cron_line() {
  printf '0 %s * * * %s/bin/bash %s/5_System/tools/schedule.sh run %s >> %s/5_System/logs/cron.log 2>&1\n' \
    "$hour" "${bin:+CLAUDE_BIN=$bin }" "$ROOT" "$cmd" "$ROOT"
}

do_print() {
  check_args "$1" "$2"
  claude_note
  if [ "$(uname -s)" = Darwin ]; then
    echo "Save this as $plist"
    echo
    plist_text
    echo
    echo "Then load it, and it fires at $at every day the machine is awake:"
    echo "  launchctl bootstrap gui/\$(id -u) $plist"
    echo "To stop it again:"
    echo "  launchctl bootout gui/\$(id -u)/$label"
  else
    echo "Add this line with crontab -e, and it fires at $at every day:"
    echo
    cron_line
  fi
  echo
  echo "Nothing was scheduled by this. The paste is yours."
}

# -------------------------------------------------------------- install
do_install() {
  check_args "$1" "$2"
  claude_note
  if [ "$(uname -s)" != Darwin ]; then
    echo "This machine schedules with cron, and a crontab is not a file this"
    echo "script will write: an edit there can eat an entry it did not make."
    echo "Add this line yourself with crontab -e, and it fires at $at every day:"
    echo
    cron_line
    echo
    echo "Nothing was scheduled by this. The paste is yours."
    return
  fi
  # Only a file carrying this label is ours to replace. Anything else at
  # that path was put there by someone, and it stays.
  if [ -f "$plist" ] && ! grep -q "<string>$label</string>" "$plist"; then
    die "$plist exists and was not written by this script, so it stays. Move it, or pick another command name."
  fi
  mkdir -p "$(dirname "$plist")" "$LOGS"
  plist_text > "$plist"
  echo "Written: $plist"
  # A second install replaces the first: unload whatever is there under
  # this label, then load the file just written. bootout of a label that
  # is not loaded fails, and that is fine.
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "$plist"; then
    echo "Loaded. /$cmd runs at $at every day this machine is awake, and"
    echo "\`bash 5_System/tools/schedule.sh\` shows how each run went."
    echo "To stop it: launchctl bootout gui/\$(id -u)/$label"
  else
    echo "The file is written but launchctl would not load it. Try by hand:"
    echo "  launchctl bootstrap gui/\$(id -u) $plist"
    exit 1
  fi
}

case "${1:-show}" in
  run)     [ $# -eq 2 ] || die "Usage: $0 run <command>"; do_run "$2" ;;
  print)   do_print "${2:-daily-brief}" "${3:-6}" ;;
  install) do_install "${2:-daily-brief}" "${3:-6}" ;;
  show)    do_show ;;
  *)       die "Usage: $0 [show | run <command> | print [command] [hour] | install [command] [hour]]" ;;
esac
