# Secure Bidding API

Secure Bidding API is a Ruby/Roda service with:

- file-based encrypted bid records (`app/db/store`)
- Sequel/SQLite-backed accounts, projects, and bid submissions (`app/db/*.db`)
- role-aware account/project membership and payment placeholders

## Quick Start (one command)

Run from the repository root:

```bash
bundle exec rake start
```

This will install dependencies, configure secrets, migrate the database, seed it
with demo data, and start the server on `http://localhost:3000`.

### Manual Setup (if needed)

Alternatively, run each step separately:

```bash
bundle install
cp config/secrets-example.yml config/secrets.yml
mkdir -p app/db/store
bundle exec rake db:migrate
bundle exec rake db:seed
bundle exec rackup -p 3000
```

## End-to-End Demo Flow

Use a second terminal for `curl` commands.

### 1. Health check

```bash
curl http://localhost:3000/
```

Expected:

```json
{
  "message": "Secure Bidding API v1.0",
  "status": "ok"
}
```

### 2. Verify seeded account/project/bid/payment metadata

```bash
curl http://localhost:3000/api/v1/accounts
curl http://localhost:3000/api/v1/projects
curl http://localhost:3000/api/v1/bid_submissions
curl http://localhost:3000/api/v1/payments/PAYMENT_ID
```

Expected: seeded account/project/bid/payment metadata is returned
(no plaintext/encrypted payload in response).

### 3. Create a new account

```bash
curl -X POST http://localhost:3000/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"demo-user","password":"demo-pass-123","email":"demo@local.test","phone":"+886900000999","system_role":"member"}'
```

Expected:

```json
{ "id": "UUID", "status": "created" }
```

### 4. Create a new project

```bash
curl -X POST http://localhost:3000/api/v1/projects \
  -H "Content-Type: application/json" \
  -d '{"title":"demo-project","budget_cents":120000}'
```

Expected:

```json
{ "id": "UUID", "status": "created" }
```

### 5. Create a bid submission for that project

Replace `PROJECT_ID` with the `id` returned above.

```bash
curl -X POST http://localhost:3000/api/v1/bid_submissions \
  -H "Content-Type: application/json" \
  -d '{"project_id":"PROJECT_ID","contractor_alias":"demo-freelancer","plaintext_bid":"top-secret"}'
```

Expected:

```json
{ "id": "UUID", "status": "created" }
```

### 6. Verify project-owned bid submission flow

```bash
curl http://localhost:3000/api/v1/projects/PROJECT_ID/bid_submissions
```

Expected: list includes your `demo-freelancer` entry.

### 7. Verify bid flow

Create bid:

```bash
curl -X POST http://localhost:3000/api/v1/bids \
  -H "Content-Type: application/json" \
  -d '{"contractor":"ABC Construction","project_id":"project-123","encrypted_bid":"base64_encrypted_data_here"}'
```

Then list and fetch by id:

```bash
curl http://localhost:3000/api/v1/bids
curl http://localhost:3000/api/v1/bids/BID_ID
```

### 8. Role-aware project memberships and project bids

Assign role to account (system scope):

```bash
curl -X POST http://localhost:3000/api/v1/accounts/ACCOUNT_ID/system_roles \
  -H "Content-Type: application/json" \
  -d '{"role":"project_owner"}'
```

Assign account to project (project scope):

```bash
curl -X POST http://localhost:3000/api/v1/projects/PROJECT_ID/memberships \
  -H "Content-Type: application/json" \
  -d '{"account_id":"ACCOUNT_ID","role":"bidder"}'
```

Create project bid as assigned bidder:

```bash
curl -X POST http://localhost:3000/api/v1/projects/PROJECT_ID/bids \
  -H "Content-Type: application/json" \
  -d '{"bidder_account_id":"ACCOUNT_ID","contractor_alias":"demo-bidder","plaintext_bid":"top-secret"}'
```

### 9. Payment placeholder status

Create placeholder payment:

```bash
curl -X POST http://localhost:3000/api/v1/payments \
  -H "Content-Type: application/json" \
  -d '{"bid_submission_id":"BID_SUBMISSION_ID","paid":false,"method":"placeholder","reference":"demo-ref"}'
```

Update paid status:

```bash
curl -X PATCH http://localhost:3000/api/v1/payments/PAYMENT_ID \
  -H "Content-Type: application/json" \
  -d '{"paid":true}'
```

## Test

```bash
RACK_ENV=test bundle exec rake db:migrate
bundle exec rake spec
```

## Enforce Markdown linting before commit

Install the repository pre-commit hook once:

```bash
git config core.hooksPath .githooks
```

The hook blocks commits when Markdown lint errors exist.

## Cleanup / Reset

Clear all app data in current environment (projects, bid submissions, bid files):

```bash
bundle exec rake db:clear
```

Reset databases (drop + migrate):

```bash
bundle exec rake db:reset
```

Remove database files:

```bash
bundle exec rake db:drop
```

## Useful Tasks

```bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake db:seed
bundle exec rake db:clear
bundle exec rake db:reset
bundle exec rake db:version
bundle exec rake console
bundle exec rake spec
```

## API Routes

- `GET /`
- `GET /api/v1/bids`
- `GET /api/v1/bids/:id`
- `POST /api/v1/bids`
- `GET /api/v1/accounts`
- `GET /api/v1/accounts/search`
- `GET /api/v1/accounts/:id`
- `POST /api/v1/accounts`
- `PATCH /api/v1/accounts/:id`
- `GET /api/v1/accounts/:id/system_roles`
- `POST /api/v1/accounts/:id/system_roles`
- `GET /api/v1/projects`
- `GET /api/v1/projects/:id`
- `POST /api/v1/projects`
- `GET /api/v1/projects/:id/memberships`
- `POST /api/v1/projects/:id/memberships`
- `POST /api/v1/projects/:id/bids`
- `GET /api/v1/projects/:id/bid_submissions`
- `GET /api/v1/bid_submissions`
- `GET /api/v1/bid_submissions/:id`
- `POST /api/v1/bid_submissions`
- `POST /api/v1/payments`
- `GET /api/v1/payments/:id`
- `PATCH /api/v1/payments/:id`
