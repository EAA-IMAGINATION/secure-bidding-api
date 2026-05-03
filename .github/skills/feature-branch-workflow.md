# Feature Branch Workflow Skill

## When to use

- At the start of every new feature

## Rule

Never work directly from `main`/`master`.

## Workflow

1. Before any edits, check branch with `git branch --show-current`.
2. If branch is `main` or `master`, create/switch to a feature branch immediately.
3. Create a new branch named for the feature (example: `1-db-orm`).
4. Implement and test on that branch only.
5. Merge back through review.
