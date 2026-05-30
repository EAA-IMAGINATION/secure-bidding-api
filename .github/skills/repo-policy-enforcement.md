# Repo Policy Enforcement Skill

**Shared rules for secure-bidding-api and secure-bidding-app.** Both repos use
the same local hooks, the same trailer CI check, and the same branch workflow.
Read this when setting up a clone, opening a PR, or debugging a CI failure.

## Hard rules (both repos)

1. **No AI co-author trailers** — see [commit-authorship](commit-authorship.md)
2. **No direct work on default branch** — `master` (API) or `main` (app)
3. **Hooks enabled** — `git config core.hooksPath .githooks` once per clone
4. **Merge via PR** — branch protection should require `check_trailers` status

## Enforcement parity

| Layer | API | App | Same? |
| --- | --- | --- | --- |
| `pre-commit` hook | Blocks `main`/`master`; markdownlint | Blocks `main`/`master`; markdownlint | Yes |
| `prepare-commit-msg` hook | Strips AI co-author trailers | Strips AI co-author trailers | Yes |
| `policy-check.yml` | `check_trailers` job | `check_trailers` job | Yes |
| CI spec run | `ci-spec.yml` | `ci-load-test-secrets.yml` | Yes (both run `rake spec`) |
| Default branch | `master` | `main` | Name differs only |
| Extra CI | `route_spec_coverage` job | — | API-only |

## One-time setup (each clone)

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/prepare-commit-msg
```

## GitHub Actions (both repos)

### policy-check.yml

Runs on every push and PR. Job `check_trailers` fails if commit history
contains `Co-authored-by` lines referencing Copilot, Cursor, OpenAI, or
Anthropic.

### CI spec workflows

| Repo | Workflow file | What it runs |
| --- | --- | --- |
| API | `.github/workflows/ci-spec.yml` | `db:migrate` + `rake spec` |
| App | `.github/workflows/ci-load-test-secrets.yml` | copy secrets + `rake spec` |

API additionally runs `route_spec_coverage` inside `policy-check.yml`.

## GitHub branch protection

Require PR + status check `check_trailers` + disable force push on the default
branch. See [feature-branch-workflow](feature-branch-workflow.md) for `gh api`
commands.

## How Copilot vs CI relate

- **Copilot** reads `copilot-instructions.md` — instructions only, not enforcement.
- **Hooks** enforce locally after `core.hooksPath` setup.
- **Actions** enforce on GitHub after push — Copilot cannot bypass these.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Commit blocked on main/master | `git checkout -b feature-name` |
| AI trailer in commit message | Remove line; hook should strip on retry |
| CI `check_trailers` failed | `git rebase -i` and reword offending commits |
| Hooks not running | Run `git config core.hooksPath .githooks` |
