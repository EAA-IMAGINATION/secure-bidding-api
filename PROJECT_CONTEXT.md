# Project Context: Secure Bidding API

## Overview

Secure Bidding API is a Ruby/Roda service for encrypted bid submission with
ongoing security hardening and ORM-backed data for account-owned secrets.

## Current Implementation Status

### Completed

- Bid API (legacy file-backed):
  - `GET /`
  - `GET /api/v1/bids`
  - `GET /api/v1/bids/:id`
  - `POST /api/v1/bids`
- ORM-backed account and secret resources:
  - `GET /api/v1/accounts`
  - `GET /api/v1/accounts/:id`
  - `POST /api/v1/accounts`
  - `GET /api/v1/accounts/:id/secrets`
  - `GET /api/v1/secrets`
  - `GET /api/v1/secrets/:id`
  - `POST /api/v1/secrets`
- Sequel + SQLite environment setup in `config/environments.rb`
- Migrations in `app/db/migrations/`:
  - `001_create_accounts.rb`
  - `002_create_secrets.rb`
  - `003_normalize_secret_foreign_key.rb`
- Seed workflow:
  - `app/db/seeds/accounts_seed.yml`
  - `app/db/seeds/secrets_seed.yml`
  - `bundle exec rake db:seed`
- Test suite:
  - `bundle exec rake spec`
  - Current baseline: 29 runs, 106 assertions, 0 failures

### Not Yet Implemented

- Authentication and authorization
- HTTPS enforcement and broader transport hardening
- Atomic reveal mechanism and payment verification flows

### Future Skill Library (Deferred Until Weekly Scope Requires)

- `.github/skills/crypto-bid-envelope.md`
- `.github/skills/payment-gate-verification.md`
- `.github/skills/atomic-reveal-timer.md`
- `.github/skills/integrity-hash-publish.md`

## Architecture

- **Framework:** Roda
- **ORM/DB:** Sequel + SQLite
- **Crypto:** RbNaCl
- **Tests:** Minitest + Rack::Test
- **Storage model:** Hybrid
  - Bids remain file-based in `app/db/store/`
  - Accounts/secrets are relational in SQLite

## Development Workflow Rules

1. Never implement on `main`/`master`.
2. Check current branch before edits (`git branch --show-current`).
3. If on `main`/`master`, switch to a feature branch first.
4. Never implement ahead of current weekly professor requirements.
5. Keep future-phase skills available, but use them only when weekly specs require them.
6. Run relevant tests before commit.
7. Use short meaningful commit messages.
8. Ask before pushing to remote.

## Core Commands

```bash
bundle install
bundle exec rake db:migrate
bundle exec rake db:seed
RACK_ENV=test bundle exec rake db:migrate
bundle exec rake spec
bundle exec rake console
```

## References

- Repo: <https://github.com/EAA-IMAGINATION/secure-bidding-api>
- Issues: <https://github.com/EAA-IMAGINATION/secure-bidding-api/issues>
- Project instructions: `.github/copilot-instructions.md`

---

**Last Updated:** 2026-04-15  
**Status:** ORM + seed workflow implemented; security roadmap still active
