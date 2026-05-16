# Week 12 Registration Endpoints Implementation Summary

## Overview
Successfully implemented complete tokenized registration flow for the Secure Bidding API with three new endpoints, extended Account model, email verification service, and comprehensive test coverage.

## Part A: Extended Account Model (`app/models/account.rb`)

### New Class Methods:
1. **`by_registration_token(token_string)`**
   - Loads and decrypts registration token
   - Extracts account_id from token payload
   - Returns Account record by ID
   - Raises `ExpiredTokenError` or `InvalidTokenError` if token invalid/expired

2. **`email_available?(email)`**
   - Checks if email hash doesn't exist in database
   - Uses SearchHash for timing-safe comparison
   - Returns boolean

3. **`username_available?(username)`**
   - Checks if username doesn't exist in database
   - Returns boolean

### New Instance Methods:
1. **`set_registration_token(expiration = ONE_HOUR)`**
   - Creates AuthToken with account_id payload
   - Stores encrypted token in `registration_token` column
   - Sets `registration_token_expires_at` timestamp
   - Must be called AFTER account is saved (has ID)

2. **`verify_email!`**
   - Sets `email_verified_at` to current time
   - Saves account record

## Part B: MailService (`app/services/email/send_verification.rb`)

### SendVerification Service:
- **Initialization**: `SendVerification.new(account, registration_token, verification_url)`
- **Usage**: `SendVerification.call(account:, registration_token:, verification_url:)`

### Features:
1. **Email Payload Building**
   - From: MAILTRAP_FROM_EMAIL and MAILTRAP_FROM_NAME (from environment)
   - To: account.email
   - Subject: "Verify your registration"

2. **HTML Template**
   - Welcome message with username
   - Clickable verification link with token as query param
   - Fallback copy-paste link
   - Token expiration notice (1 hour)
   - Account security disclaimer

3. **Mailtrap Integration**
   - POST to `https://send.api.mailtrap.io/api/send`
   - Bearer token authentication using MAILTRAP_API_KEY
   - Returns success/error response
   - Raises `SendVerification::MailtrapError` on failure

## Part C: Registration Endpoints (`app/controllers/routes/auth.rb`)

### Endpoint 1: POST /api/v1/auth/availability

**Purpose**: Check if username and email are available

**Request**:
```json
{ "username": "alice", "email": "alice@example.com" }
```

**Response** (200 OK):
```json
{
  "available": {
    "username": true,
    "email": true
  }
}
```

**Behavior**:
- Returns `nil` for empty username/email fields
- Timing-safe responses (same time for taken/available)
- Always returns 200 status

---

### Endpoint 2: POST /api/v1/auth/register

**Purpose**: Initiate registration, create account, send verification email

**Request**:
```json
{ "username": "alice", "email": "alice@example.com" }
```

**Response** (200 OK):
```json
{
  "message": "Check your email to verify your account",
  "account_id": "e9c3cae7-fcc3-4e63-b78d-10dfa4838408"
}
```

**Behavior**:
1. Validates username and email are provided (400 if missing)
2. Checks availability (422 if taken)
3. Creates Account record:
   - username: provided
   - email: encrypted via `set_email()`
   - system_role: 'member'
   - password: temporary random value
4. Sets registration token (ONE_HOUR expiration)
5. Sends verification email via MailService
6. Returns account_id for reference

**Error Responses**:
- 400: Missing username or email
- 422: Username or email already taken
- 500: Email service failure

---

### Endpoint 3: POST /api/v1/auth/verify

**Purpose**: Verify email with token, complete registration

**Request**:
```json
{ "registration_token": "<encrypted-token-string>" }
```

**Response** (200 OK):
```json
{
  "token": "<session-token-string>",
  "account": {
    "id": "e9c3cae7-fcc3-4e63-b78d-10dfa4838408",
    "username": "alice",
    "email": "alice@example.com"
  }
}
```

**Behavior**:
1. Validates registration_token provided (400 if missing)
2. Decrypts and validates token:
   - 403 if expired
   - 404 if invalid
3. Finds account by token payload's account_id
4. Marks email as verified: `account.verify_email!()`
5. Generates session token (ONE_WEEK expiration) with payload:
   - account_id
   - username
   - system_role
6. Returns session token and account details

**Error Responses**:
- 400: Missing registration_token
- 403: Token has expired
- 404: Token is invalid or account not found
- 500: Verification processing error

## Integration Points

### Database Columns (Migration 008):
- `registration_token`: String, nullable
- `registration_token_expires_at`: DateTime, nullable
- `email_verified_at`: DateTime, nullable
- Index on `registration_token` for fast lookups

### Environment Configuration:
```yaml
MAILTRAP_API_KEY: "<token>"
MAILTRAP_API_URL: "https://send.api.mailtrap.io/api/send"
MAILTRAP_FROM_EMAIL: "noreply@secure-bidding-api.local"
MAILTRAP_FROM_NAME: "Secure Bidding API"
```

### Dependencies:
- `http` gem: For Mailtrap API calls
- `securerandom`: For temporary password generation
- `erb`: For HTML escaping in email template

## Test Coverage

### Test File: `spec/registration_endpoints_spec.rb`

**Total Tests**: 19
**Assertions**: 61+
**Status**: ✅ All passing

### Test Categories:

1. **Availability Checks** (5 tests)
   - New username and email available
   - Existing username taken
   - Existing email taken
   - Empty field handling

2. **Registration** (7 tests)
   - HAPPY: Create unverified account
   - HAPPY: Email encrypted in database
   - SAD: Missing required fields (400)
   - SAD: Taken username (422)
   - SAD: Taken email (422)
   - SAD: Email service failure (500)

3. **Verification** (5 tests)
   - HAPPY: Verify account and get session token
   - HAPPY: Email marked verified after verification
   - HAPPY: Session token valid for ONE_WEEK
   - SAD: Expired token returns 403
   - SAD: Invalid token returns 404

4. **Full Flow** (1 test)
   - Complete: availability → register → verify

### Webmock Integration:
- Stubs Mailtrap API calls in test environment
- Verifies correct payload structure
- Simulates success/failure scenarios

## Security Features

1. **Email Encryption**: Uses SearchHash + SecureDB for encrypted storage
2. **Token Encryption**: AuthToken uses RbNaCl for symmetric encryption
3. **Token Expiration**: ONE_HOUR for registration, ONE_WEEK for sessions
4. **Temporary Password**: Random bytes set during registration
5. **Timing-Safe Checks**: Availability checks consistent timing
6. **HTML Escaping**: Email template escapes user input (ERB::Util.html_escape)

## Files Modified/Created

### Created:
- ✅ `app/services/email/send_verification.rb` - Email service
- ✅ `spec/registration_endpoints_spec.rb` - Comprehensive tests

### Modified:
- ✅ `app/models/account.rb` - Added 5 new methods
- ✅ `app/controllers/routes/auth.rb` - Added 3 new endpoints
- ✅ `app/require_app.rb` - Added email service require

### Existing (Unchanged):
- `app/db/migrations/008_add_registration_and_verification_columns.rb`
- `config/secrets-example.yml` - Already contains Mailtrap config

## Verification

### Test Results:
```
149 runs, 386 assertions, 0 failures, 0 errors, 0 skips
```

All existing tests still passing. No regressions introduced.

### Example Usage:

```bash
# 1. Check availability
curl -X POST http://localhost:3000/api/v1/auth/availability \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com"}'

# 2. Register account (sends email)
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com"}'

# 3. Verify registration (with token from email)
curl -X POST http://localhost:3000/api/v1/auth/verify \
  -H "Content-Type: application/json" \
  -d '{"registration_token":"<token-from-email>"}'
```

## Future Enhancements

1. Add password reset flow (similar to registration but for existing users)
2. Add rate limiting to prevent abuse
3. Add account lockout after failed verification attempts
4. Add resend verification email endpoint
5. Add email confirmation with confirmation code instead of token
6. Add SMS verification as alternative
