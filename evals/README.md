# Evals

A framework about trusting what a system tells you should be able to
show its own work. These are the checks that keep this repo honest.

```bash
bash evals/run.sh              # tiers 1 and 2: free, deterministic, seconds
bash evals/run.sh --prompts    # adds tier 3, which needs a model
```

Anything failing exits non-zero, which is the one place this departs from
the checkers it was modelled on. Those print a report for a person to
read and always exit 0. A suite has to be consumable by something other
than a reader.

## The three tiers

**Tier 1, `consistency.sh`.** Does the repo describe itself accurately?
Command counts, the stated length of `setup.sh`, every prompt reachable
from the README, every command backed by a file that exists, every
GitHub link pointing at something real, and the launchd plist the README
hands out, parsed and asked what time it actually fires. Free, offline,
sub-second.

**Tier 2, `setup-behaviour.sh`.** Does `setup.sh` do what the README
says? Runs the real script twice in throwaway directories, once with the
prompts reachable and once without, then drives the unattended runner
through a quiet death and a good run with a stub in place of `claude`,
and its `print` and `install` verbs against stub schedulers.
A hundred and twenty-eight assertions. The second run matters more: a setup script that
half-fails and says so is fine, and one that half-fails and reports
success is the failure this whole framework exists to prevent.

**Tier 3, `prompts.sh`.** Do the prompts behave as described? Each case
under `cases/` is a fixture plus an `assert.sh`. The fixture is copied to
a temp directory first, so a case can never mutate what it tests.

## Why the assertions never ask a model to judge

Fixtures plant known strings and the assertions grep for them. Asking a
model whether a model did well is not evidence, and this repo argues that
if a thing can be counted it should be counted.

`refute-catches-invention` is the shape to copy. The two `onboard-` cases
cover the interview from both sides: one plants a grown rulebook and
checks it is shown back and not replaced; the other hands every answer
over up front on an empty skeleton and checks the rulebook records the
name, the gates word for word, the areas as folders and the archive
rule as a refusal, with nothing scheduled on "not yet". The note carries three
claims its source states verbatim and one it never made. A pass names the
invented claim **and leaves the other three alone**, so the case can fail
in both directions. A checker that flags everything scores full marks on
recall and is worthless.

## Do not edit a fixture to make a case pass

Borrowed from the retrieval test set this repo came from. If a case
fails, the fix belongs in the prompt or in the assertion. A fixture
edited to fit the result measures nothing.

The corollary: when a case fails for a reason you did not expect, that is
the eval working. Removing the planted claim from
`refute-catches-invention` on 2026-07-26 made `/refute` flag three sound
claims as unsupported, which is worth knowing about the prompt and would
never have surfaced from reading it.

That one played out in three moves, and the last two are the useful part.

**The prompt was half the problem.** "Try to break this note" and "assume
the note is wrong" had no counterweight, so with nothing to find it found
something anyway. It now carries the other side: a claim the original
supports is not a finding, and calling one unsupported is a worse failure
than missing a real one, because a checker that flags everything is one
you stop reading. False positives went from three to one.

**The assertion was the other half.** The remaining one was not the
prompt's fault at all. The output said "Exact. Holds" and "all six appear
in the original", and the check fired anyway, because it matched any line
carrying both a figure and a defect word. Fixing an assertion is allowed
where fixing a fixture is not, but only after you have read the output
and know the behaviour was right. Changing a check you have not
understood is the same move as editing a fixture, wearing a better hat.

**Assert what was done, not how it was said.** A check for the words
"checked" and "each claim" failed a run that had gone through every
figure in a table without using either. It now counts how many of the
note's five figures appear in the report, which is evidence of a
claim-by-claim read. Model output varies between runs; behaviour is
stabler than vocabulary, so test the behaviour.

## Adding a case

```
cases/<name>/
  fixture/      the starting knowledge base, copied before each run
  case.env      COMMAND=<prompt name>, and an optional ASK for context
  assert.sh     append failures to $FINDINGS; silence means passed
```

`assert.sh` gets `$KB` (the throwaway copy), `$OUT` (what the model
printed) and `$FINDINGS`. Say what failed and why, in the same voice as
the rest: a reader should be able to act on the line without opening the
fixture.
