# Repo Policy Enforcement Skill

**Shared rules for secure-bidding-api and secure-bidding-app.**

## Hard rules (always — course policy)

1. **No Copilot or Cursor co-author trailers** in commit messages — see
   [commit-authorship](commit-authorship.md)
2. **Hooks enabled** — `git config core.hooksPath .githooks` once per clone
3. **Never use `--no-verify`** to bypass trailer hooks

## Before each local commit (hook order)

Git runs hooks in this order; authorship is enforced **before the commit lands**:

1. **`pre-commit`** — lint staged `.md` files only
2. **`prepare-commit-msg`** — strip AI trailers (Copilot, Cursor, OpenAI, Anthropic)
3. **`commit-msg`** — strip again; fail if Copilot/Cursor trailers remain

Implementation: `.githooks/strip-ai-trailers.sh` (shared by both message hooks).

## Relaxed rules (current)

- Direct commits on `master` / `main` are allowed
- CI `check_trailers` warns only (does not fail the workflow)

## One-time setup (each clone)

```bash
git config core.hooksPath .githooks
chmod +x .githooks/strip-ai-trailers.sh .githooks/pre-commit .githooks/prepare-commit-msg .githooks/commit-msg
```

## CI (advisory)

`policy-check.yml` scans pushed commits for `Co-authored-by` lines mentioning
copilot, cursor, openai, or anthropic and prints a warning.
