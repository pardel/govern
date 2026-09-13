#!/usr/bin/env bash
# Recall: does it find the planted claim?
# Precision: does it leave the three sound ones alone?

if ! grep -qiE '1\.8|tidal flow|flow rate' "$OUT"; then
  echo "missed the planted claim: a tidal flow rate the source says was never measured" >> "$FINDINGS"
fi

if ! grep -qiE 'not (in|measured|supported)|no measurement|never measured|absent|unsupported|invented|cut|downgrad' "$OUT"; then
  echo "found something but never says it should be cut or downgraded" >> "$FINDINGS"
fi

# False positives. Each of these is in the original verbatim, so calling
# any of them unsupported means the check is noise rather than signal.
#
# Tightened 2026-07-26. The first version matched any line carrying both
# a number and a defect word, which fired on lines *discussing* a figure
# and clearing it ("all six appear in the original", "Exact. Holds.").
# The prompt was behaving correctly and the assertion was not, so the
# assertion moved, not the fixture. It now needs a verdict against the
# number on the same line, with no exculpating word alongside it.
for sound in "4.2" "78 per cent" "40 metre"; do
  if grep -iE '\b(unsupported|not supported|invented|fabricat|should be (cut|downgraded)|no basis)\b' "$OUT" \
     | grep -viE '\b(holds?|not a finding|is supported|supported by|exact|verified against|appears? in the (original|source))\b' \
     | grep -qF "$sound"; then
    echo "flagged \`$sound\` as unsupported, but the original states it verbatim" >> "$FINDINGS"
  fi
done

# The prompt says "looks fine" is not an outcome: it has to show its
# working. Rewritten 2026-07-26 to test that rather than the words used
# to describe it. The first version grepped for "checked", "each claim"
# and two more, and failed a run that had gone through every figure in a
# table without using any of them. Counting which figures actually appear
# is evidence of a claim-by-claim read; vocabulary is not.
seen=0
for fig in "4.2" "3.1" "2.4" "78" "40"; do
  grep -qF "$fig" "$OUT" && seen=$((seen + 1))
done
if [ "$seen" -lt 4 ]; then
  echo "only $seen of the note's 5 figures appear in the report, so it did not go through them one by one" >> "$FINDINGS"
fi
