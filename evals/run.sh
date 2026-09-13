#!/usr/bin/env bash
# Run the eval suite.
#
#   bash evals/run.sh              tiers 1 and 2: deterministic, free, seconds
#   bash evals/run.sh --prompts    adds tier 3, which needs a model and
#                                  spends tokens
#
# Exits non-zero if anything fails, so a future session or a CI job can
# consume the result rather than having to read it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

run() {
  echo
  echo "═══ $1"
  bash "$ROOT/evals/$2" "${3:-}" || fail=1
}

run "Tier 1: does the repo describe itself accurately?" consistency.sh
run "Tier 2: does setup.sh do what the README says?"    setup-behaviour.sh

if [ "${1:-}" = "--prompts" ]; then
  run "Tier 3: do the prompts behave as described?" prompts.sh "${2:-}"
else
  echo
  echo "═══ Tier 3: skipped"
  echo
  echo "Prompt behaviour needs a model and spends tokens."
  echo "Run it with: bash evals/run.sh --prompts"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL"
fi
exit "$fail"
