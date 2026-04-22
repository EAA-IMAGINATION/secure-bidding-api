---
name: tdd
description: "Test-first Red-Green-Refactor workflow for implementation tasks."
---

# TDD Skill — Red-Green-Refactor

Use this skill whenever implementation changes behavior.
Write tests first and let tests drive design decisions.

## The Iron Rule

**Never write implementation code without a failing test that demands it.**

A test written after implementation verifies.
A test written before implementation designs.

## The Cycle

Each loop is Red, then Green, then Refactor.

### Phase 1: RED — Write exactly one failing test

Write one test for one behavior increment.

The test must:

1. Follow requirements, not planned internals.
2. Assert behavior, not private structure.
3. Fail for the right reason (missing behavior).

After writing it:

1. Run tests with the real test runner.
2. Confirm the new test fails.
3. If it passes, stop and investigate why.

### Phase 2: GREEN — Write the minimum code to pass

Write the smallest code that makes the failing test pass.

1. Do not anticipate future tests.
2. Do not add behavior not required by current test.
3. Keep refactoring out of this phase.

Then:

1. Run the full suite.
2. Confirm new and existing tests pass.
3. If regressions appear, fix implementation first.

### Phase 3: REFACTOR — Improve structure, keep behavior

Refactor with a green suite as safety net:

- Remove duplication
- Improve naming
- Extract methods and simplify structure
- Do not add behavior in this phase

Then:

1. Run the full suite again.
2. Confirm all tests still pass.

### Then repeat

Repeat with the next small behavior increment.

## Practical Guidance

### Ordering test cases

Prefer this progression:

1. Null/empty/zero input.
2. Smallest meaningful case.
3. Typical happy path.
4. Edge/boundary cases.
5. Error/failure cases.

This keeps each Green step small.

### One test at a time

Do not batch many tests before coding.
Each Red-Green cycle should advance one test.

If a plan lists many scenarios, run them as separate cycles.

### What "minimal implementation" really means

Minimal can be temporary and simple.
Later tests force generalization.

Example:

1. `add(1, 1)` => `2` can pass with `return 2`.
2. `add(2, 3)` => `5` forces `return a + b`.

### When tests depend on infrastructure

If infra is required (DB/model files), add only enough setup so tests run.
Then let the behavior assertion fail first.

### Refactoring test code

Refactor tests too: extract helpers and reduce setup duplication.
Keep behavior assertions unchanged.

## Anti-Patterns to Avoid

Avoid:

- Testing private internals over observable behavior.
- Writing all tests first, then all implementation.
- Skipping real test runs.
- Weakening assertions to force pass.
- Sneaking extra behavior into Green.

## References

See `references/sources.md` for source material used in this skill.

## Integration with Branch Plans

For plan items labeled "FAILING test" or "test-first":

- These are Red-phase deliverables.
- The subsequent implementation task is the GREEN phase
- Run tests after each phase and update the plan with results
- Mark failing-test tasks done only after confirmed failure
- Mark the implementation task complete only after confirming all tests pass
