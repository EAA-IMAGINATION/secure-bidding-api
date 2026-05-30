# Copilot Instructions: Secure Bidding API

## Hard Rules (read first)

1. **Weekly scope** — Implement only what the current week requires. Defer everything
   else as roadmap notes. See `.github/skills/weekly-scope-gating.md`.
2. **Commit authorship** — Never add AI co-author trailers (course rule). Hooks
   enforce locally. See `.github/skills/commit-authorship.md`.
3. **Branches** — Direct commits on `master` are OK (relaxed). See
   `.github/skills/feature-branch-workflow.md`.
4. **Test-first** — Write a failing test before implementation code. See
   `.github/skills/tdd-mastery.md`.

## Skill Index

Use the smallest skill set that covers the task. Read the linked file when the
trigger applies.

| Priority | Trigger | Skill |
| --- | --- | --- |
| Required | Every task start | [weekly-scope-gating](.github/skills/weekly-scope-gating.md) |
| Required | Before commits | [commit-authorship](.github/skills/commit-authorship.md) |
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

Use only when the weekly spec explicitly requires them:

- [crypto-bid-envelope](.github/skills/crypto-bid-envelope.md)
- [payment-gate-verification](.github/skills/payment-gate-verification.md)
- [atomic-reveal-timer](.github/skills/atomic-reveal-timer.md)
- [integrity-hash-publish](.github/skills/integrity-hash-publish.md)

## Commands

```bash
bundle exec rake spec                              # Full test suite
bundle exec ruby spec/api_spec.rb                  # API route tests
bundle exec ruby spec/bid_spec.rb                  # Model tests
bundle exec rake spec && bundle-audit check        # "Check Progress"
npx markdownlint-cli2 "**/*.md" "#node_modules"    # After .md edits
```

If the repo path contains spaces, use `script/run-tests-from-symlinked-path`
instead of `bundle exec rake spec` directly.

## Architecture (reference)

Ruby/Roda API with file-based legacy storage and Sequel/SQLite persistence.

| Layer | Location | Role |
| --- | --- | --- |
| Models | `app/models/` | Domain + persistence (`SecureBidding::` namespace) |
| Controllers | `app/controllers/` | Roda routes and HTTP responses |
| DB | `app/db/` | SQLite files, migrations, seeds |
| Legacy store | `app/db/store/` | JSON bid files |

**Conventions:** keyword-arg model initializers; plural tables / singular FKs;
`require_relative` for internal requires; Minitest spec DSL with `_()` assertions;
happy + sad route tests; JSON errors as `{ error: "message" }`.

**Stack:** roda, json, rbnacl, sequel, sqlite3; test with rack-test + minitest.

**Current focus:** assignment-aligned ORM (`Account` + `Secret`), complete route
tests, README synced with implemented behavior.
