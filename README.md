# Secure Bidding API

A secure bidding platform API designed for students and freelancers to
submit project proposals and pricing without fear of bid leaking or
price-fixing. Contractors upload their bids encrypted with the client's NaCl
public key.

## Features

- **Encrypted Bid Submission**: All bids are encrypted using NaCl cryptography
- **Secure Storage**: File-based JSON storage for bid data
- **RESTful API**: Clean, simple API endpoints for bid management

## Setup

1. Install dependencies:

```bash
bundle install
```

1. Ensure the storage directory exists:

```bash
mkdir -p app/db/store
```

1. Run the application:

```bash
rackup -p 9292
```

## API Routes

### Health Check

#### GET /

```bash
curl http://localhost:9292/
```

Response:

```json
{
  "message": "Secure Bidding API v1.0",
  "status": "ok"
}
```

### Create a Bid

#### POST /api/v1/bids

Creates a new encrypted bid.

Request:

```bash
curl -X POST http://localhost:9292/api/v1/bids \
  -H "Content-Type: application/json" \
  -d '{
    "contractor": "ABC Construction",
    "project_id": "project-123",
    "encrypted_bid": "base64_encrypted_data_here"
  }'
```

Response (201 Created):

```json
{
  "bid_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "created"
}
```

Error Response (400 Bad Request):

```json
{
  "error": "encrypted_bid is required and cannot be empty"
}
```

### Get a Specific Bid

#### GET /api/v1/bids/:id

Retrieves details of a specific bid by ID.

Request:

```bash
curl http://localhost:9292/api/v1/bids/550e8400-e29b-41d4-a716-446655440000
```

Response (200 OK):

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "contractor": "ABC Construction",
  "project_id": "project-123",
  "encrypted_bid": "base64_encrypted_data_here"
}
```

Error Response (404 Not Found):

```json
{
  "error": "Bid not found"
}
```

### Get All Bid IDs

#### GET /api/v1/bids

Returns a list of all bid IDs in the system.

Request:

```bash
curl http://localhost:9292/api/v1/bids
```

Response (200 OK):

```json
{
  "bid_ids": [
    "550e8400-e29b-41d4-a716-446655440001",
    "550e8400-e29b-41d4-a716-446655440002",
    "550e8400-e29b-41d4-a716-446655440003"
  ]
}
```text

## Testing

Run all tests:

```bash
bundle exec ruby -I. -e 'Dir.glob("spec/*_spec.rb").sort.each { |f| require f }'
```

Run specific test file:

```bash
bundle exec ruby spec/api_spec.rb
bundle exec ruby spec/bid_spec.rb
```

## Project Structure

```text
.
├── app/
│   ├── controllers/
│   │   └── app.rb           # Roda API routes
│   ├── models/
│   │   └── bid.rb           # Bid model
│   └── db/
│       ├── store/           # JSON file storage
│       └── seeds/           # Seed data
│           └── bids_seed.yml
├── spec/
│   ├── api_spec.rb          # API endpoint tests
│   └── bid_spec.rb          # Bid model tests
├── config.ru                # Rack configuration
├── Gemfile                  # Ruby dependencies
└── README.md
```

## Security Considerations

See GitHub Issues for identified security vulnerabilities and planned improvements.

## License

See LICENSE file for details.
