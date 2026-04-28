# Project Context: Secure Bidding API

## Overview

Secure Bidding API is a Ruby/Roda service for encrypted bid submission with
ongoing security hardening and ORM-backed data for secure user accounts,
projects, and project-owned bid submissions.

## Current Implementation Status

### Completed

- Bid API (legacy file-backed):
  - `GET /`
  - `GET /api/v1/bids`
  - `GET /api/v1/bids/:id`
  - `POST /api/v1/bids`
- ORM-backed project and bid submission resources:
  - `GET /api/v1/projects`
  - `GET /api/v1/projects/:id`
  - `POST /api/v1/projects`
  - `GET /api/v1/projects/:id/bid_submissions`
  - `GET /api/v1/bid_submissions`
  - `GET /api/v1/bid_submissions/:id`
  - `POST /api/v1/bid_submissions`
- ORM-backed account resources:
  - `GET /api/v1/accounts`
  - `GET /api/v1/accounts/search`
  - `GET /api/v1/accounts/:id`
  - `POST /api/v1/accounts`
  - `PATCH /api/v1/accounts/:id`
  - `GET /api/v1/accounts/:id/system_roles`
  - `POST /api/v1/accounts/:id/system_roles`
- Role-aware project membership resources:
  - `GET /api/v1/projects/:id/memberships`
  - `POST /api/v1/projects/:id/memberships`
  - `POST /api/v1/projects/:id/bids`
- Payment placeholder resources:
  - `POST /api/v1/payments`
  - `GET /api/v1/payments/:id`
  - `PATCH /api/v1/payments/:id`
- Sequel + SQLite environment setup in `config/environments.rb`
- Migrations in `app/db/migrations/`:
  - `001_create_accounts.rb`
  - `002_create_secrets.rb`
  - `003_normalize_secret_foreign_key.rb`
  - `005_replace_accounts_with_projects_and_bid_submissions.rb`
  - `006_create_user_accounts_and_collaborations.rb`
  - `007_add_roles_memberships_and_payments.rb`
- Seed workflow:
  - `seeds/202604270001_create_all.rb`
  - `bundle exec rake db:seed`
- Test suite:
  - `bundle exec rake spec`
  - Current baseline: 57 runs, 204 assertions, 0 failures

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
  - Accounts/projects/bid submissions/payments are relational in SQLite

## Development Workflow Rules

1. Never implement on `main`/`master`.
2. Check current branch before edits (`git branch --show-current`).
3. If on `main`/`master`, switch to a feature branch first.
4. Never implement ahead of current weekly professor requirements.
5. Keep future-phase skills available, but use them only when weekly specs
   require them.
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

**Last Updated:** 2026-04-27  
**Status:** Role-aware account/project flow + payment placeholder implemented
