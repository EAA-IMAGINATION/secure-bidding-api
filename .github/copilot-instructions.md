# Copilot Instructions: Secure Bidding API

## Testing

Run all tests:
```bash
bundle exec ruby spec/bid_spec.rb
```

Run a single test file:
```bash
bundle exec ruby spec/<test_file>_spec.rb
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
- **Controllers** (`app/controllers/`): HTTP request handlers (empty currently, Roda integration pending)
- **DB/Store** (`app/db/store/`): File-based storage location

### Security Features
- RbNaCl (libsodium) is included for cryptographic operations
- UUIDs generated via `SecureRandom.uuid` for bid identifiers

## Key Conventions

### Model Patterns
- Models use keyword arguments in initializers (e.g., `Bid.new(amount: 100)`)
- All models implement `#save` to persist to `app/db/store/{id}.json`
- Models implement `#to_json` for serialization
- IDs are auto-generated UUIDs in the constructor via `#new_id`

### Code Organization
- Require statements use `require_relative` for internal files
- JSON serialization uses `JSON.generate` (not `to_json` string)
- File paths use string interpolation: `"app/db/store/#{id}.json"`

### Testing Patterns
- Use Minitest spec syntax: `describe` blocks with `it` statements
- Assertions use `_()` wrapper: `_(value).must_equal expected`
- Tests check file system state: `Dir.glob('app/db/store/*.json')`

## Dependencies

Core gems:
- `roda` - Web framework (not yet wired up)
- `json` - JSON serialization
- `rbnacl` - NaCl cryptography library

Test gems (`:test` group):
- `rack-test` - HTTP testing helpers
- `minitest` - Test framework
