# Markdown Linting Skill

## When to use

- Immediately after editing any `.md` file

## Rule

- Never finish Markdown changes without running markdown linting

## Command

```bash
npx markdownlint-cli "**/*.md"
```

## Notes

- Uses repository rules from `.markdownlint.json`
- Fix lint issues before considering Markdown edits complete
