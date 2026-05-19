# Crypto Bid Envelope Skill

## When to use

- Only when weekly requirements explicitly introduce encrypted bid payload workflows

## Rule

Treat bid confidentiality as payload-level encryption, not transport-only security.

## Scope

- Client-side encryption with NaCl public key
- Server-side storage of ciphertext and metadata only
- No plaintext bid amount persistence
- Decryption flow guarded by authorization and reveal conditions
