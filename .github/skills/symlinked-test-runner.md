---
name: symlinked-test-runner
description: Use the space-free symlink test wrapper for this repo's Ruby specs.
---

# Symlinked Test Runner

## When to use

- Before running the Ruby test suite in this repository
- When the repo path contains spaces and `bundle exec rake spec` fails

## Rule

- Run tests with `script/run-tests-from-symlinked-path` instead of calling
  `bundle exec rake spec` directly.
- Use the script for full-suite runs and for targeted spec files.
- Prefer the script whenever a shell command needs to exercise the test suite
  from this workspace.
