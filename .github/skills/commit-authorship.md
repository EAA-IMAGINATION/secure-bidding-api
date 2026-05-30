# Commit Authorship Skill

## When to use

- Before creating or amending any commit

## Rules

1. Commit only after tests pass for the implemented change.
2. Keep commit messages short and meaningful.
3. **Never** include AI co-author trailers (`Co-authored-by: Copilot`, etc.).
4. Prepare the staged file set and message; the developer runs `git commit`.
5. Ask whether to push after the commit succeeds.

## Hook setup

```bash
git config core.hooksPath .githooks
```

`.githooks/prepare-commit-msg` strips AI co-author trailers automatically.
CI rejects commits that include them.
