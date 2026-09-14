# Changelog

What was decided, what failed, and why. Not a diary of work done: the
commit log has that. Newest first, one entry per day something in the
kit changed shape, each saying what a reader who set up a base earlier
would notice. The same rule the kit asks of your own changelog.

## 2026-09-14

- **First public version.** Eleven commands installed by one script,
  three tools, an eval suite in three tiers, and no `CLAUDE.md`: the
  rulebook is written by `/onboard`, which asks the five things only
  you can answer, a name from a family of names, the gates, your areas,
  a line on each, and the hour of the daily brief.
- **Decided:** the gates question offers eight, nothing pre-selected,
  the first four encouraged; and the archive rule is not a gate.
  Nothing under `4_Archive/` is edited or deleted, and the rulebook
  writes that as a refusal the interview never asks about.
- **Decided:** `schedule.sh` runs one command unattended, refuses to
  compute its own cadence, to treat silence as success, or to run
  before a rulebook exists; `install` writes a launchd file it labels
  as its own and loads it, and never edits a crontab. An unattended
  run never bumps a submodule pointer.
- **Decided:** `greet.sh` runs as a SessionStart hook. With no rulebook
  it puts one line in front of you and has the assistant offer the
  interview on your first message, which is as near as a hook can come
  to starting the onboarding.
- **Decided:** every note gets a stable id and a row in
  `5_System/INDEX.md`; briefs and reviews live under `5_System/`;
  project folders carry the area they are credited to; code lives under
  `_repos/` as submodules.
- **Decided:** `setup.sh --update` refreshes a base you already have,
  commits nothing and never touches the rulebook; a plain re-run on an
  existing base refuses.
- **Failed, then fixed:** the install line carried a `# or any empty
  folder` comment, which zsh does not treat as one when pasted, so the
  `cd` failed and the script laid out folders and installed eight
  commands into the home folder. `setup.sh` now refuses any folder
  with visible entries or a `.git`, hidden entries being allowed
  because a fresh volume has them, and the install line is chained
  with `&&` and carries no comment.
- **Decided:** a mark, `logo.svg`: three compiled notes standing on one
  original, the slab in six colours for six principles and no letters.
  The design note is inside the file.
- **Decided:** the onboarding page lives at
  [pardel.dev/govern/onboard](https://www.pardel.dev/govern/onboard/),
  where it can run, and the command explanations at
  [pardel.dev/govern](https://www.pardel.dev/govern/), so this README
  stays the part you read before running anything.
