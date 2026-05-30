# Copilot Instructions: Secure Bidding API

> **#1 RULE — COMMIT AUTHORSHIP**
> Never add `Co-authored-by` trailers for Copilot, Cursor, or any AI tool.
> CI rejects them. The developer is the sole author and runs `git commit`.
> Read `.github/skills/commit-authorship.md` before every commit.

## How Copilot, skills, hooks, and CI relate

| Layer | What it does | When it runs |
| --- | --- | --- |
| **This file** | Copilot reads it automatically in this repo | Every Copilot session |
| **Skills** (`.github/skills/`) | Playbooks Copilot reads when pointed to them | When a task matches the trigger |
| **Git hooks** (`.githooks/`) | Block default-branch commits; strip AI trailers | Every local commit after hook setup |
| **GitHub Actions** | See [repo-policy-enforcement](.github/skills/repo-policy-enforcement.md) | Every push and PR |

Copilot does **not** automatically read every skill file — it follows this index.
Workflows do **not** instruct Copilot; they **enforce** rules after push.
Hooks only work locally after: `git config core.hooksPath .githooks`

Full parity table: [repo-policy-enforcement](.github/skills/repo-policy-enforcement.md)

## Hard Rules

1. **Commit authorship** — See skill: [commit-authorship](.github/skills/commit-authorship.md)
2. **Weekly scope** — Implement only the current week. See
   [weekly-scope-gating](.github/skills/weekly-scope-gating.md)
3. **Feature branches** — Never edit on `main`/`master`. See
   [feature-branch-workflow](.github/skills/feature-branch-workflow.md)
4. **Test-first** — Failing test before implementation. See
   [tdd-mastery](.github/skills/tdd-mastery.md)

## Skill Index

| Priority | Trigger | Skill |
| --- | --- | --- |
| **#1** | Before every commit | [commit-authorship](.github/skills/commit-authorship.md) |
| Required | Clone setup / CI failures | [repo-policy-enforcement](.github/skills/repo-policy-enforcement.md) |
| Required | Every task start | [weekly-scope-gating](.github/skills/weekly-scope-gating.md) |
| Required | New feature start | [feature-branch-workflow](.github/skills/feature-branch-workflow.md) |
| Required | Behavior changes | [tdd-mastery](.github/skills/tdd-mastery.md) |
| High | Routes or models | [mvc-architecture](.github/skills/mvc-architecture.md) |
| High | New/changed routes | [api-route-testing](.github/skills/api-route-testing.md) |
| High | Sensitive data | [security-first](.github/skills/security-first.md) |
| Medium | Schema/migrations | [sequel-db-setup](.github/skills/sequel-db-setup.md) |
| Medium | Task handoff | [delivery-checkpoint](.github/skills/delivery-checkpoint.md) |
| Medium | `.md` edits | [markdown-linting](.github/skills/markdown-linting.md) |
| Low | Manual CRUD checks | [console-data-inspection](.github/skills/console-data-inspection.md) |
| Low | Assignment completeness | [demo-alignment](.github/skills/demo-alignment.md) |
| Low | Path with spaces | [symlinked-test-runner](.github/skills/symlinked-test-runner.md) |

### Future capability (reference only)

- [crypto-bid-envelope](.github/skills/crypto-bid-envelope.md)
- [payment-gate-verification](.github/skills/payment-gate-verification.md)
- [atomic-reveal-timer](.github/skills/atomic-reveal-timer.md)
- [integrity-hash-publish](.github/skills/integrity-hash-publish.md)

## Commands

```bash
git config core.hooksPath .githooks          # Run once per clone
bundle exec rake spec
bundle exec rake spec && bundle-audit check  # "Check Progress"
npx markdownlint-cli2 "**/*.md" "#node_modules"
```

## Architecture (reference)

Ruby/Roda API — models in `app/models/`, routes in `app/controllers/`,
Sequel/SQLite in `app/db/`. Minitest spec DSL; happy + sad route tests.
See prior sections in git history for full conventions.
