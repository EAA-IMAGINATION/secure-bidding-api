# Secure Bidding API

Secure Bidding API is a Ruby/Roda service with:

- file-based encrypted bid records (`app/db/store`)
- Sequel/SQLite-backed accounts and secrets (`app/db/*.db`)

## Quick Start (copy/paste)

Run from the repository root:

```bash
bundle install
mkdir -p app/db/store
bundle exec rake db:migrate
bundle exec rake db:seed
bundle exec rackup -p 9292
```

Server is now on `http://localhost:9292`.

## End-to-End Demo Flow

Use a second terminal for `curl` commands.

### 1. Health check

```bash
curl http://localhost:9292/
```

Expected:

```json
{"message":"Secure Bidding API v1.0","status":"ok"}
```

### 2. Verify seeded account/secret metadata

```bash
curl http://localhost:9292/api/v1/accounts
curl http://localhost:9292/api/v1/secrets
```

Expected: seeded accounts and secret metadata are returned
(no plaintext/encrypted payload in response).

### 3. Create a new account

```bash
curl -X POST http://localhost:9292/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"username":"demo-user","email":"demo@example.com"}'
```

Expected:

```json
{"id":3,"status":"created"}
```

### 4. Create a secret for that account

Replace `ACCOUNT_ID` with the `id` returned above.

```bash
curl -X POST http://localhost:9292/api/v1/secrets \
  -H "Content-Type: application/json" \
  -d '{"account_id":ACCOUNT_ID,"title":"demo-token","plaintext":"top-secret","key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
```

Expected:

```json
{"id":3,"status":"created"}
```

### 5. Verify account-owned secrets flow

```bash
curl http://localhost:9292/api/v1/accounts/ACCOUNT_ID/secrets
```

Expected: list includes your `demo-token` entry.

### 6. Verify bid flow

Create bid:

```bash
curl -X POST http://localhost:9292/api/v1/bids \
  -H "Content-Type: application/json" \
  -d '{"contractor":"ABC Construction","project_id":"project-123","encrypted_bid":"base64_encrypted_data_here"}'
```

Then list and fetch by id:

```bash
curl http://localhost:9292/api/v1/bids
curl http://localhost:9292/api/v1/bids/BID_ID
```

## Test

```bash
RACK_ENV=test bundle exec rake db:migrate
bundle exec rake spec
```

## Cleanup / Reset

Clear all app data in current environment (accounts, secrets, bid files):

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
- `GET /api/v1/accounts/:id`
- `POST /api/v1/accounts`
- `GET /api/v1/accounts/:id/secrets`
- `GET /api/v1/secrets`
- `GET /api/v1/secrets/:id`
- `POST /api/v1/secrets`
