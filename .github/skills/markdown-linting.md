---
description: Run markdownlint for markdown changes with strict pre-commit gate.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
---

# Markdown Linting

## Rule

When any `.md` file is added or edited, markdown lint is mandatory before done.

Use this command:

```shell
npx markdownlint-cli2 "**/*.md" "#node_modules" 2>&1
```

## Required workflow

1. Run markdownlint after markdown edits.
2. If there are errors in files changed by this task, fix them now.
3. Re-run markdownlint until changed files are clean.
4. If errors are only from pre-existing unrelated files, do not block task
   progress; record that they are baseline debt.

## Guardrail

Never skip this check silently. Always run it whenever markdown changed.
