# Atomic Reveal Timer Skill

## When to use

- Only when weekly requirements explicitly introduce deadline-locked reveal behavior

## Rule

No bid reveal is allowed before deadline, regardless of user role.

## Scope

- Deadline timestamp as authoritative lock condition
- Pre-deadline requests return deterministic rejection
- Reveal window opens atomically at or after deadline
- Tests cover both pre-deadline and post-deadline behavior
