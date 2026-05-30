# Feature Branch Workflow Skill

## When to use

- When you want an isolated branch or PR review
- **Not required** for every change while workflow is relaxed

## Current rule (relaxed)

Direct commits and pushes to `master` are **allowed** so agents and developers
can ship without opening a PR every time. Prefer feature branches for large work.

## Optional workflow

1. Check branch: `git branch --show-current`
2. For larger features: `git checkout -b feature-name`
3. Implement, test, commit, push (or merge via PR if you prefer review)

## Hard rule (unchanged — course policy)

Never put AI `Co-authored-by` lines in commit messages. Hooks strip them locally;
see [commit-authorship](commit-authorship.md).

## Branch protection (optional)

GitHub branch protection and required `check_trailers` are **not** required while
relaxed. `policy-check.yml` logs warnings only and does not fail the workflow.
