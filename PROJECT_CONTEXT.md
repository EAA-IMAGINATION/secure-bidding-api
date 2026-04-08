# Project Context: Secure Bidding API

## Overview
A secure bidding platform API for students and freelancers to submit project proposals without fear of bid leaking or price-fixing. Features encrypted bid submission using NaCl cryptography and planned atomic reveal mechanism.

## Project Vision
**Core Features (Planned):**
1. **Encrypted Bid Submission** - Contractors encrypt bids with client's public key
2. **Atomic Reveal & Integrity Timer** - Cryptographic lock prevents early bid access; public hash proves no late entries
3. **Payment Integration** - PayPal/Stripe verification for viewing fees and budget checks
4. **Fair & Transparent Process** - Blockchain/ledger proof of fairness

## Current Status

### ✅ Week 1: COMPLETE (100%)
**Completed:** April 8, 2026

**Deliverables:**
- ✅ Basic domain resource entity (Bid model)
  - Instance methods: `#initialize`, `#new_id`, `#to_json`, `#save`
  - Class methods: `::find(id)`, `::all`
- ✅ Web API with Roda
  - `GET /` - Health check
  - `POST /api/v1/bids` - Create bid (returns 201)
  - `GET /api/v1/bids/:id` - Get bid details
  - `GET /api/v1/bids` - List all bid IDs
- ✅ Tests: 14 tests, 54 assertions, 0 failures
  - HAPPY tests: root, POST, GET single, GET all
  - SAD tests: 404 for missing, 400 for invalid input
- ✅ Project files
  - README.md with full API documentation
  - LICENSE (MIT)
  - config.ru
  - .gitignore
  - Seed data (bids_seed.yml)
- ✅ Security analysis
  - bundler-audit: 0 vulnerabilities in dependencies
  - SECURITY.md: 10 documented vulnerabilities
  - 10 GitHub Issues created and triaged

**Repository:** https://github.com/EAA-IMAGINATION/secure-bidding-api

**Status:** API is live (locally), all tests passing, ready for team collaboration

### 🔒 Security Issues (GitHub Issues #1-#10)

**CRITICAL** (Must fix before production):
- #1 🔒 No Authentication or Authorization
- #4 🔒 No HTTPS Enforcement

**HIGH** (Core features + security):
- #2 ⚠️ Missing Input Validation
- #3 ⚠️ No Encryption at Rest
- #8 ⚠️ No Atomic Reveal Mechanism (Core Feature)
- #9 ⚠️ No Payment Verification Integration (Core Feature)

**MEDIUM** (Important improvements):
- #5 ⚠️ No Rate Limiting
- #6 ⚠️ No Audit Logging
- #10 ⚠️ Directory Traversal Risk

**LOW** (Nice to have):
- #7 ℹ️ Weak ID Generation Predictability

## Technology Stack

**Backend:**
- Ruby 3.x
- Roda (web framework)
- RbNaCl (cryptography)
- Minitest (testing)

**Storage:**
- File-based JSON (current)
- Database (planned for Week 2+)

**Deployment:**
- GitHub: EAA-IMAGINATION/secure-bidding-api
- Production: TBD

## Team Structure
- **Organization:** EAA-IMAGINATION
- **Repository:** secure-bidding-api
- **Members:** TBD (invite team members)

## Development Workflow

**TDD Approach (Red-Green-Refactor):**
1. Write failing test in `spec/`
2. Write minimal code to pass
3. Refactor while keeping tests green

**Code Organization:**
- Models: `app/models/` (data logic, file storage)
- Controllers: `app/controllers/app.rb` (Roda routes, JSON responses)
- Tests: `spec/` (Minitest with spec DSL)

**Quality Checks:**
```bash
# Run all tests
bundle exec ruby -I. -e 'Dir.glob("spec/*_spec.rb").sort.each { |f| require f }'

# Check for security vulnerabilities
bundle-audit check --update
```

## Next Steps (Week 2 and Beyond)

**Immediate Priorities:**
1. Fix CRITICAL security issues (#1, #4)
2. Implement core features (#8 Atomic Reveal, #9 Payments)
3. Add database integration (replace file storage)
4. Create additional models (Client, Project)

**Future Enhancements:**
- User authentication and authorization
- HTTPS deployment
- Rate limiting and audit logging
- Blockchain integration for transparency
- Payment gateway integration

## Project Guidelines

### Security-First Development
- Every new route must consider the 10 identified security issues
- Always validate input (format, length, type)
- Use proper HTTP status codes
- Use RbNaCl for encryption

### Maintain MVC Separation
- Models handle data logic
- Controllers handle HTTP routing
- No business logic in controllers
- No HTTP concerns in models

### Testing Requirements
- Write tests before implementation (TDD)
- Test both HAPPY and SAD paths
- Clean up test data in `before` blocks
- Aim for high test coverage

## Resources
- **Repository:** https://github.com/EAA-IMAGINATION/secure-bidding-api
- **Issues:** https://github.com/EAA-IMAGINATION/secure-bidding-api/issues
- **Documentation:** README.md, SECURITY.md
- **Copilot Instructions:** .github/copilot-instructions.md

---

**Last Updated:** April 8, 2026  
**Status:** Week 1 Complete, Ready for Week 2
