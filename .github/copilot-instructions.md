# Copilot Instructions: Secure Bidding API

## Project Skills and Rules

### 1. Feature Branch Workflow
**Rule:** Never work directly from `main`/`master`. Always create a branch named for the feature before implementation.

**When to look at this skill:** At the start of every new feature.

**Skill file:** `.github/skills/feature-branch-workflow.md`

### 2. TDD Mastery Skill
**Rule:** Always use Red-Green-Refactor and start with failing tests.

**When to look at this skill:** Before writing application logic for routes, models, or migrations.

**Skill file:** `.github/skills/tdd-mastery.md`

### 3. MVC Architecture Skill
**Rule:** Maintain strict separation of concerns.

**When to look at this skill:** When modifying route handlers and model logic together.

**Skill file:** `.github/skills/mvc-architecture.md`

### 4. Security-First Skill
**Rule:** Every new route must consider the 10 identified security issues.

**When to look at this skill:** Before persisting or returning sensitive data.

**Skill file:** `.github/skills/security-first.md`

### 5. Sequel DB Setup Skill
**Rule:** Keep migrations and environment DB config aligned with Sequel conventions.

**When to look at this skill:** Before changing schema, migrations, or DB configuration.

**Skill file:** `.github/skills/sequel-db-setup.md`

### 6. Console Data Inspection Skill
**Rule:** Use preloaded pry console for DB exploration and sanity checks.

**When to look at this skill:** When manually validating create/read/update/delete behavior.

**Skill file:** `.github/skills/console-data-inspection.md`

### 7. API Route Testing Skill
**Rule:** Test routes first with happy/sad paths and environment expectations.

**When to look at this skill:** Before adding new GET/POST routes.

**Skill file:** `.github/skills/api-route-testing.md`

### 8. Markdown Linting Skill
**Rule:** After editing any `.md` file, always run markdown linting before finishing.

**When to look at this skill:** Every time a Markdown file is added or modified.

**Skill file:** `.github/skills/markdown-linting.md`

### 9. Repetitive Tasks Automation
**Action:** When asked to "Check Progress," run:
```bash
bundle exec ruby -I. -e 'Dir.glob("spec/*_spec.rb").sort.each { |f| require f }' && bundle-audit check
```

This ensures the project remains stable and secure.

**Recurring Markdown task:** After any `.md` edit, run:
```bash
npx markdownlint "**/*.md"
```

## Testing

Run all tests:
```bash
bundle exec ruby -I. -e 'Dir.glob("spec/*_spec.rb").sort.each { |f| require f }'
```

Run API tests only:
```bash
bundle exec ruby spec/api_spec.rb
```

Run model tests only:
```bash
bundle exec ruby spec/bid_spec.rb
```

Tests use Minitest with the spec DSL. Test files are located in `spec/` and follow the naming convention `*_spec.rb`.

## Architecture

This is a secure bidding API built with Ruby and Roda. The system now uses both file-based and Sequel/SQLite persistence.

### Data Storage
- **Legacy file persistence**: Bid JSON files stored in `app/db/store/`
- **Sequel + SQLite persistence**: `app/db/development.db` and `app/db/test.db`
- **Migrations**: Schema changes are in `app/db/migrations/`
- **Environment config**: `config/environments.rb` controls environment-aware DB URL

### Module Structure
- All classes are namespaced under `SecureBidding` module
- **Models** (`app/models/`): Domain objects (e.g., `Bid`, `Account`, `Secret`)
- **Controllers** (`app/controllers/`): HTTP request handlers (Roda-based API)
- **DB** (`app/db/`): SQLite files + Sequel migrations
- **DB/Store** (`app/db/store/`): Legacy file-based bid storage

### Security Features
- RbNaCl (libsodium) is included for cryptographic operations
- UUIDs generated via `SecureRandom.uuid` for bid identifiers
- 10 security issues documented in SECURITY.md and GitHub Issues

## Key Conventions

### Model Patterns
- Models use keyword arguments in initializers (e.g., `Bid.new(contractor: 'ABC', project_id: '123', encrypted_bid: 'data')`)
- Bid model (legacy storage) implements:
  - `#save` to persist to `app/db/store/{id}.json`
  - `#to_json` for serialization
  - `#new_id` for UUID generation
  - `::find(id)` class method to retrieve by ID
  - `::all` class method to list all IDs
- Sequel models use table-backed associations (`Account` has many `Secret`, `Secret` belongs to `Account`)
- Follow naming convention: plural tables and singular foreign keys (e.g., `account_id`)

### Code Organization
- Require statements use `require_relative` for internal files
- JSON serialization uses `JSON.generate` (not `to_json` string)
- File paths use string interpolation: `"app/db/store/#{id}.json"`

### Testing Patterns
- Use Minitest spec syntax: `describe` blocks with `it` statements
- Assertions use `_()` wrapper: `_(value).must_equal expected`
- Always clean up test data in `before` blocks (DB tables and file store as applicable)
- Write HAPPY and SAD path tests for all routes
- Include route tests for list, single-fetch, and create operations for each resource
- Include a happy-path test that app works without `DATABASE_URL` in environment

### API Response Patterns
- Success responses return JSON with 200/201 status
- Error responses return JSON with 400/404 status and `{ error: "message" }`
- All routes use Roda's JSON plugin for automatic response serialization

## Dependencies

Core gems:
- `roda` - Web framework
- `json` - JSON serialization
- `rbnacl` - NaCl cryptography library
- `sequel` - ORM and migrations
- `sqlite3` - SQLite adapter

Development gems:
- `bundler-audit` - Security vulnerability scanning
- `pry` - Interactive console
- `hirb` - Tabular console output

Test gems (`:test` group):
- `rack-test` - HTTP testing helpers
- `minitest` - Test framework

## Current Status

**Week 1: COMPLETE** ✅
- 14 tests passing (54 assertions)
- 4 API routes implemented
- 10 security issues documented and triaged on GitHub
- Repository: https://github.com/EAA-IMAGINATION/secure-bidding-api

**Week 2: ACTIVE** 🚧
- Branch: `1-db-orm`
- Focus: Sequel ORM migrations, `Account` + `Secret` models, encrypted secret API routes, route-first tests, and DB console workflow
