# Commit Authorship Skill

## When to use

- Before creating or amending any commit

## Hard rule (course policy — always enforced)

Never include AI co-author trailers in commit messages (`Co-authored-by: Copilot`,
`Co-authored-by: Cursor`, etc.). Agents must **not** add these lines when committing.

## Before every commit

1. Run tests when code changed (`bundle exec rake spec`).
2. Keep messages short with **no** AI `Co-authored-by` lines.
3. Commit; hooks strip accidental trailers and block if any remain.

## Local hooks (enable once per clone)

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/prepare-commit-msg .githooks/commit-msg
```

| Hook | Effect |
| --- | --- |
| `prepare-commit-msg` | Removes AI `Co-authored-by` lines before the message is saved |
| `commit-msg` | Fails the commit if AI trailers are still present |
| `pre-commit` | Markdownlint on staged `.md` only |

## CI (relaxed)

`policy-check.yml` prints a **warning** if trailers appear in pushed commits; it
does not fail the workflow.

## Agent commits

When the user asks you to commit and push: commit on `master` is allowed; never
use `--no-verify` to bypass trailer hooks; never force-push default branches unless
the user explicitly requests a history rewrite.
