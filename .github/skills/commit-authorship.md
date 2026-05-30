# Commit Authorship Skill

**Highest-priority skill.** Read this before every commit.

## Hard rule (course policy — Copilot AND Cursor)

Never include AI co-author trailers:

```text
Co-authored-by: GitHub Copilot
Co-authored-by: Copilot <...@users.noreply.github.com>
Co-authored-by: Cursor <cursoragent@cursor.com>
```

Agents must **not** add these lines when drafting or running `git commit`.

## Before every commit (you + hooks)

1. Run tests when code changed (`bundle exec rake spec`).
2. Draft a message with **no** Copilot/Cursor `Co-authored-by` lines.
3. Commit locally — hooks enforce authorship **before the commit is created**:

| Order | Hook | Effect |
| --- | --- | --- |
| 1 | `pre-commit` | Markdownlint on staged `.md` only |
| 2 | `prepare-commit-msg` | Strip Copilot/Cursor/AI trailers from message file |
| 3 | `commit-msg` | Strip again; **abort** if any AI trailer remains |

Never use `git commit --no-verify` to skip trailer checks.

## One-time setup (each clone)

```bash
git config core.hooksPath .githooks
chmod +x .githooks/strip-ai-trailers.sh .githooks/pre-commit .githooks/prepare-commit-msg .githooks/commit-msg
```

## CI (advisory)

`policy-check.yml` warns on push/PR if history contains Copilot/Cursor trailers.

## Agent commits

Direct commits on `master` are allowed. Never add AI trailers; hooks run automatically
when `core.hooksPath` is set.

See [repo-policy-enforcement](repo-policy-enforcement.md).
