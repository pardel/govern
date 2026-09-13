#!/usr/bin/env bash
# $KB is the throwaway knowledge base, $OUT the model's output,
# $FINDINGS the file to append failures to. Silence means passed.

want="ZEBRAFINCH-7734"

# The point of the guard: the existing rulebook survives untouched.
if ! grep -q "$want" "$KB/CLAUDE.md" 2>/dev/null; then
  echo "CLAUDE.md was overwritten: the planted gate \`$want\` is gone" >> "$FINDINGS"
fi

# A second CLAUDE.md written elsewhere would be the same failure wearing
# a different filename.
stray=$(find "$KB" -name 'CLAUDE.md' | wc -l | tr -d ' ')
if [ "$stray" != "1" ]; then
  echo "expected exactly 1 CLAUDE.md, found $stray" >> "$FINDINGS"
fi

# It has to say it noticed, not just silently decline.
if ! grep -qiE 'already|existing|exists' "$OUT"; then
  echo "output never mentions that a rulebook already exists" >> "$FINDINGS"
fi

# It has to ask rather than decide for me.
if ! grep -qiE '\?|would you|shall I|do you want|confirm|replace' "$OUT"; then
  echo "output does not ask before replacing anything" >> "$FINDINGS"
fi

# And it should show me what I already have, gates included.
if ! grep -q "$want" "$OUT"; then
  echo "output does not show the current gates list back to me" >> "$FINDINGS"
fi
