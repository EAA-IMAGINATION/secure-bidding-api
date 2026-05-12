# Payment Gate Verification Skill

## When to use

- Only when weekly requirements explicitly introduce billing or budget verification

## Rule

Never reveal bid contents unless payment/budget checks succeed.

## Scope

- Verify payment status (Stripe/PayPal integration point)
- Verify minimum budget or viewing-fee eligibility
- Return explicit denial response on failed verification
- Log verification outcome without exposing sensitive provider secrets
