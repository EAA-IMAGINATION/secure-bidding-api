# Secure Bidding API

Secure Bidding API is a Ruby/Roda service with:

- file-based encrypted bid records (`app/db/store`)
- Sequel/SQLite-backed projects and bid submissions (`app/db/*.db`)

## Quick Start (copy/paste)

Run from the repository root:

```bash
bundle install
cp config/secrets-example.yml config/secrets.yml
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

### 2. Verify seeded project/bid submission metadata

```bash
curl http://localhost:9292/api/v1/projects
curl http://localhost:9292/api/v1/bid_submissions
```

Expected: seeded accounts and secret metadata are returned
(no plaintext/encrypted payload in response).

### 3. Create a new project

```bash
curl -X POST http://localhost:9292/api/v1/projects \
  -H "Content-Type: application/json" \
  -d '{"title":"demo-project","budget_cents":120000}'
```

Expected:

```json
{"id":"UUID","status":"created"}
```

### 4. Create a bid submission for that project

Replace `PROJECT_ID` with the `id` returned above.

```bash
curl -X POST http://localhost:9292/api/v1/bid_submissions \
  -H "Content-Type: application/json" \
  -d '{"project_id":"PROJECT_ID","contractor_alias":"demo-freelancer","plaintext_bid":"top-secret"}'
```

Expected:

```json
{"id":"UUID","status":"created"}
```

### 5. Verify project-owned bid submission flow

```bash
curl http://localhost:9292/api/v1/projects/PROJECT_ID/bid_submissions
```

Expected: list includes your `demo-freelancer` entry.

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
- `GET /api/v1/projects`
- `GET /api/v1/projects/:id`
- `POST /api/v1/projects`
- `GET /api/v1/projects/:id/bid_submissions`
- `GET /api/v1/bid_submissions`
- `GET /api/v1/bid_submissions/:id`
- `POST /api/v1/bid_submissions`
