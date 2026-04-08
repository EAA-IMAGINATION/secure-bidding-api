# Copilot Instructions: Secure Bidding API

## Project Skills and Rules

### 1. TDD Mastery Skill
**Rule:** Always use Red-Green-Refactor.

**Action:** Before writing any application logic, create a failing test in `spec/api_spec.rb`. Only after the test fails, write the minimum code in `app/` to pass it.

**Workflow:**
1. 🔴 RED: Write a failing test
2. 🟢 GREEN: Write minimal code to pass the test
3. 🔵 REFACTOR: Clean up code while keeping tests green

### 2. MVC Architecture Skill
**Rule:** Maintain strict separation of concerns.

**Action:** 
- **Models** in `app/models/` handle data logic and file storage
- **Controllers** in `app/controllers/app.rb` handle Roda routing and JSON responses
- **Views** are JSON responses (no HTML templates)

**Never mix concerns:**
- Models should not know about HTTP
- Controllers should not contain business logic
- Keep file I/O in models

### 3. Security-First Skill
**Rule:** Every new route must consider the 10 identified security issues.

**Action:** 
- Ensure input validation on all parameters
- Use proper HTTP status codes (201, 400, 404, etc.)
- Use RbNaCl for sensitive data encryption
- Check SECURITY.md before adding new features

**Security Checklist for New Routes:**
- [ ] Input validation (format, length, type)
- [ ] Authentication required? (when implemented)
- [ ] Authorization check? (when implemented)
- [ ] Audit logging? (when implemented)
- [ ] Rate limiting consideration?

### 4. Repetitive Tasks Automation
**Action:** When asked to "Check Progress," run:
```bash
bundle exec ruby spec/api_spec.rb && bundle-audit check
```

This ensures the project remains stable and secure.

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

This is a secure bidding API built with Ruby and Roda. The system is designed to handle encrypted bids with the following structure:

### Data Storage
- **File-based persistence**: Uses JSON files stored in `app/db/store/`
- **File naming**: Each bid is stored as `{uuid}.json` where the UUID is the bid's ID
- **No database**: Currently uses filesystem storage; database integration is planned

### Module Structure
- All classes are namespaced under `SecureBidding` module
- **Models** (`app/models/`): Domain objects (e.g., `Bid`)
- **Controllers** (`app/controllers/`): HTTP request handlers (Roda-based API)
- **DB/Store** (`app/db/store/`): File-based storage location

### Security Features
- RbNaCl (libsodium) is included for cryptographic operations
- UUIDs generated via `SecureRandom.uuid` for bid identifiers
- 10 security issues documented in SECURITY.md and GitHub Issues

## Key Conventions

### Model Patterns
- Models use keyword arguments in initializers (e.g., `Bid.new(contractor: 'ABC', project_id: '123', encrypted_bid: 'data')`)
- All models implement:
  - `#save` to persist to `app/db/store/{id}.json`
  - `#to_json` for serialization
  - `#new_id` for UUID generation
  - `::find(id)` class method to retrieve by ID
  - `::all` class method to list all IDs

### Code Organization
- Require statements use `require_relative` for internal files
- JSON serialization uses `JSON.generate` (not `to_json` string)
- File paths use string interpolation: `"app/db/store/#{id}.json"`

### Testing Patterns
- Use Minitest spec syntax: `describe` blocks with `it` statements
- Assertions use `_()` wrapper: `_(value).must_equal expected`
- Tests check file system state: `Dir.glob('app/db/store/*.json')`
- Always clean up test data in `before` blocks
- Write HAPPY and SAD path tests for all routes

### API Response Patterns
- Success responses return JSON with 200/201 status
- Error responses return JSON with 400/404 status and `{ error: "message" }`
- All routes use Roda's JSON plugin for automatic response serialization

## Dependencies

Core gems:
- `roda` - Web framework
- `json` - JSON serialization
- `rbnacl` - NaCl cryptography library

Development gems:
- `bundler-audit` - Security vulnerability scanning

Test gems (`:test` group):
- `rack-test` - HTTP testing helpers
- `minitest` - Test framework

## Current Status

**Week 1: COMPLETE** ✅
- 14 tests passing (54 assertions)
- 4 API routes implemented
- 10 security issues documented and triaged on GitHub
- Repository: https://github.com/EAA-IMAGINATION/secure-bidding-api
