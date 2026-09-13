#!/usr/bin/env bash
# Write a status page for this knowledge base to stdout as one
# self-contained HTML file.
#
#   bash 5_System/tools/status.sh > kb-status.html && open kb-status.html
#
# Read-only. Every number here is counted off the disk rather than
# estimated, which is the Evidence principle applied to the thing that
# displays it. No server, no build step, nothing fetched: the page is a
# file you can open, mail to yourself, or throw away.
set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" || { echo "cannot read $ROOT" >&2; exit 1; }

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Directories that belong to something else. A knowledge base can hold
# co-located code repositories, and walking into one turns "archived
# originals" into a number that is thousands too large: on the base this
# was written against it read 64,284 instead of 2,604, because a retired
# project's node_modules sat under the archive. A confidently wrong count
# is the exact failure this page exists to avoid.
PRUNE=( -name repos -o -name node_modules -o -name .git -o -name vendor )

count() {  # count <dir> [find-expression...]
  d="$1"; shift
  find "$d" \( "${PRUNE[@]}" \) -prune -o \( "$@" \) -print 2>/dev/null \
    | wc -l | tr -d ' '
}

# `stat -f` is BSD and `stat -c` is GNU. Both, because the scheduled runs
# reported further down are meant to work on either.
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

days_since() {  # days_since <file> -> integer, or "" if absent
  [ -e "$1" ] || return 0
  echo $(( ( $(date +%s) - $(mtime "$1") ) / 86400 ))
}

newest() {  # newest <dir> <pattern> -> path of most recently modified
  find "$1" \( "${PRUNE[@]}" \) -prune -o -name "$2" -type f -print 2>/dev/null \
    | while read -r f; do echo "$(mtime "$f") $f"; done \
    | sort -rn | head -1 | cut -d' ' -f2-
}

# ------------------------------------------------------------------ data
has_rulebook=no; [ -f CLAUDE.md ] && has_rulebook=yes
n_notes=$(find 1_Projects 2_Areas 3_Resources \( "${PRUNE[@]}" \) -prune -o \
            -name '*.md' -type f -print 2>/dev/null \
          | xargs grep -l '^id: ' 2>/dev/null | wc -l | tr -d ' ')
n_orig=$(count 4_Archive -type f ! -name '.gitkeep')
n_inbox=$(count 0_Inbox -type f ! -name '.gitkeep')
n_cmds=$(count .claude/skills -name SKILL.md)
n_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
# From the commit itself, not from .git/HEAD. HEAD's mtime is when the ref
# was last rewritten, so on a branch that has not been switched in months
# it reported "last commit 115 days ago" on a base committed that morning.
last_commit_ts=$(git log -1 --format=%ct 2>/dev/null || true)
last_commit_days=""
[ -n "$last_commit_ts" ] && \
  last_commit_days=$(( ( $(date +%s) - last_commit_ts ) / 86400 ))
newest_note=$(newest . '*.md')

cat <<'HTML'
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Knowledge base status</title>
<style>
  :root { color-scheme: light dark; --fg:#111; --dim:#666; --line:#e2e2e2;
          --bg:#fff; --card:#fafafa; --ok:#1a7f4b; --warn:#9a6700; --gap:#a33; }
  @media (prefers-color-scheme: dark) {
    :root { --fg:#e8e8e8; --dim:#9a9a9a; --line:#2c2c2c; --bg:#141414;
            --card:#1c1c1c; --ok:#4ac585; --warn:#d9a531; --gap:#e57373; }
  }
  * { box-sizing: border-box; }
  body { margin:0; padding:2.5rem 1.25rem 4rem; background:var(--bg); color:var(--fg);
         font:16px/1.55 ui-sans-serif,-apple-system,"Segoe UI",sans-serif; }
  main { max-width: 54rem; margin: 0 auto; }
  h1 { font-size:1.6rem; margin:0 0 .25rem; letter-spacing:-.02em; }
  h2 { font-size:.8rem; text-transform:uppercase; letter-spacing:.09em;
       color:var(--dim); margin:2.5rem 0 .75rem; font-weight:600; }
  .sub { color:var(--dim); margin:0 0 1rem; font-size:.92rem; }
  .grid { display:grid; gap:.75rem; grid-template-columns:repeat(auto-fit,minmax(8.5rem,1fr)); }
  .stat { background:var(--card); border:1px solid var(--line); border-radius:.6rem; padding:.85rem 1rem; }
  .stat b { display:block; font-size:1.7rem; font-weight:650; letter-spacing:-.03em; }
  .stat span { color:var(--dim); font-size:.82rem; }
  ul { margin:0; padding-left:1.1rem; }
  li { margin:.3rem 0; }
  code { background:var(--card); border:1px solid var(--line); border-radius:.3rem;
         padding:.08em .38em; font-size:.88em; }
  .check { list-style:none; padding:0; }
  .check li { display:flex; gap:.6rem; align-items:baseline; padding:.45rem 0;
              border-bottom:1px solid var(--line); }
  .check li:last-child { border-bottom:0; }
  .mark { font-weight:700; min-width:1.2rem; }
  .done .mark { color:var(--ok); } .todo .mark { color:var(--gap); }
  .bad { color:var(--gap); }
  .note { color:var(--dim); font-size:.88rem; }
  footer { margin-top:3rem; padding-top:1rem; border-top:1px solid var(--line);
           color:var(--dim); font-size:.82rem; }
  .empty { color:var(--dim); font-style:italic; }
</style>
<main>
HTML

echo "<h1>Knowledge base status</h1>"
echo "<p class=\"sub\">$(pwd | esc) &middot; generated $(date '+%Y-%m-%d %H:%M')</p>"

# ----------------------------------------------------------------- stats
echo '<h2>Counted off the disk</h2><div class="grid">'
printf '<div class="stat"><b>%s</b><span>compiled notes</span></div>' "$n_notes"
printf '<div class="stat"><b>%s</b><span>archived originals</span></div>' "$n_orig"
printf '<div class="stat"><b>%s</b><span>waiting in inbox</span></div>' "$n_inbox"
printf '<div class="stat"><b>%s</b><span>commands installed</span></div>' "$n_cmds"
printf '<div class="stat"><b>%s</b><span>commits</span></div>' "$n_commits"
echo '</div>'

# ----------------------------------------------------------------- gates
echo '<h2>Your gates</h2>'
if [ "$has_rulebook" = yes ]; then
  # Any heading naming gates, not only one titled exactly "Gates": a grown
  # rulebook is as likely to call it "Confirmation-gated actions".
  gates=$(awk '/^#+ .*[Gg]ate/{f=1;next} /^#+ /{f=0} f && /^[-*] /' CLAUDE.md)
  if [ -n "$gates" ]; then
    echo '<p class="sub">Nothing here happens without you saying yes. Read from your <code>CLAUDE.md</code>.</p><ul>'
    # A bullet in a grown rulebook is usually "**The gate.** Then the
    # reasoning", and only the bolded lead belongs on a status page. Take it
    # when it is there, and keep the whole line when it is not. Without this
    # the page printed literal asterisks and a sentence cut off mid-clause.
    echo "$gates" | sed 's/^[-*] *//' | esc \
      | sed -e 's|^\*\*\([^*]*\)\*\*.*|\1|' -e 's|\*\*\([^*]*\)\*\*|\1|g' \
      | sed 's|`\([^`]*\)`|<code>\1</code>|g' | sed 's|.*|<li>&</li>|'
    echo '</ul>'
  else
    echo '<p class="empty">A CLAUDE.md exists but no gates list was found under a "Gates" heading.</p>'
  fi
else
  echo '<p class="empty">No rulebook yet. Run <code>/onboard</code>: it asks what to call the assistant, which actions must never happen without your explicit yes, what you are responsible for and what good looks like there, and whether to schedule the brief; your gates answer becomes this list.</p>'
fi

# -------------------------------------------------------------- commands
echo '<h2>Commands</h2>'
if [ "$n_cmds" -gt 0 ]; then
  echo '<ul>'
  for s in .claude/skills/*/SKILL.md; do
    [ -f "$s" ] || continue
    n=$(basename "$(dirname "$s")")
    d=$(sed -n 's/^description: //p' "$s" | head -1 | cut -c1-110)
    printf '<li><code>/%s</code> <span class="note">%s</span></li>' \
      "$(echo "$n" | esc)" "$(echo "$d" | esc)"
  done
  echo '</ul>'
else
  echo '<p class="empty">No commands installed. Re-run setup.sh, or copy the prompts in by hand.</p>'
fi

# ------------------------------------------------------------- checklist
echo '<h2>Where you are</h2><ul class="check">'
row() {  # row <done?> <text>
  if [ "$1" = yes ]; then printf '<li class="done"><span class="mark">&check;</span><span>%s</span></li>' "$2"
  else printf '<li class="todo"><span class="mark">&middot;</span><span>%s</span></li>' "$2"; fi
}
row "$([ -d 0_Inbox ] && echo yes || echo no)" "The folder skeleton exists"
row "$([ "$n_commits" -gt 0 ] && echo yes || echo no)" "Under version control, so a bad write can be undone"
row "$has_rulebook" "A rulebook with your gates list (<code>/onboard</code>)"
row "$([ "$n_cmds" -gt 0 ] && echo yes || echo no)" "Prompts installed as commands"
row "$([ "$n_orig" -gt 0 ] && echo yes || echo no)" "Something archived, so there is an original to cite"
row "$([ "$n_notes" -gt 0 ] && echo yes || echo no)" "Something compiled from it (<code>/process-inbox</code>)"
echo '</ul>'

# ------------------------------------------------------- scheduled runs
# Only once there is something to report: the folder appears the first
# time schedule.sh runs anything. A job that has stopped firing shows up
# here as an age rather than as nothing at all, which is the whole reason
# the block is on the page a reader already opens.
if [ -d 5_System/logs ]; then
  echo '<h2>Scheduled runs</h2>'
  if [ -s 5_System/logs/schedule.log ]; then
    echo "<p class=\"sub\">Most recent last. Last logged $(days_since 5_System/logs/schedule.log) day(s) ago.</p><ul>"
    tail -5 5_System/logs/schedule.log | esc | sed 's|.*|<li><code>&</code></li>|'
    echo '</ul>'
  else
    echo '<p class="empty">Nothing has run yet. If something is scheduled and this stays empty past the hour you set it for, the job is not firing.</p>'
  fi
  for f in 5_System/logs/FAILED-*; do
    [ -f "$f" ] || continue
    printf '<p class="bad">%s</p>' "$(sed -n 2p "$f" | esc)"
  done
fi

# ------------------------------------------------------------- staleness
echo '<h2>Recently</h2><ul>'
[ -n "$last_commit_days" ] && echo "<li>Last commit: ${last_commit_days} day(s) ago</li>"
[ -n "$newest_note" ] && echo "<li>Newest file: <code>$(echo "$newest_note" | esc)</code>, $(days_since "$newest_note") day(s) ago</li>"
[ "$n_inbox" -gt 0 ] && echo "<li>$n_inbox item(s) waiting in <code>0_Inbox/</code> &mdash; run <code>/process-inbox</code></li>"
[ "$n_inbox" -eq 0 ] && echo "<li>Inbox is empty</li>"
echo '</ul>'

cat <<HTML
<footer>
Generated by <code>5_System/tools/status.sh</code>, read-only. Every figure
above was counted, not estimated. Re-run it whenever you want a fresh one:
this file does not update itself.
</footer>
</main>
HTML
