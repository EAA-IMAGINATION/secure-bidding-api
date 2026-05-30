#!/bin/sh
# Shared: remove AI co-author trailers (Copilot, Cursor, etc.) from a commit message file.
# Used by prepare-commit-msg (before commit is created) and commit-msg (final gate).

strip_ai_trailers() {
  MSG_FILE="$1"
  [ -f "$MSG_FILE" ] || return 0

  sed -i.bak \
    -e '/^Co-authored-by:.*[Cc]opilot/d' \
    -e '/^Co-authored-by:.*[Cc]ursor/d' \
    -e '/^Co-authored-by:.*cursoragent/d' \
    -e '/^Co-authored-by:.*OpenAI/d' \
    -e '/^Co-authored-by:.*Anthropic/d' \
    "$MSG_FILE" && rm -f "$MSG_FILE.bak"

  sed -i.bak \
    -e 's/[[:space:]]*Co-authored-by:.*[Cc]opilot.*$//' \
    -e 's/[[:space:]]*Co-authored-by:.*[Cc]ursor.*$//' \
    -e 's/[[:space:]]*Co-authored-by:.*cursoragent.*$//' \
    -e 's/[[:space:]]*Co-authored-by:.*OpenAI.*$//' \
    -e 's/[[:space:]]*Co-authored-by:.*Anthropic.*$//' \
    "$MSG_FILE" && rm -f "$MSG_FILE.bak"
}

has_ai_trailers() {
  MSG_FILE="$1"
  [ -f "$MSG_FILE" ] || return 1
  grep -qiE 'Co-authored-by:.*(copilot|cursor|cursoragent|openai|anthropic)' "$MSG_FILE"
}
