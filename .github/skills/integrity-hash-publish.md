# Integrity Hash Publish Skill

## When to use

- Only when weekly requirements explicitly introduce fairness/integrity proof publication

## Rule

Publish a reproducible hash snapshot at deadline to prove bid-set integrity.

## Scope

- Canonicalize submitted bids at reveal cut-off
- Generate public hash digest of bid-set
- Prevent inclusion of late entries after hash publication
- Expose verification endpoint/record for auditor checks
