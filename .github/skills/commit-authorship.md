# Commit Authorship Skill

**Highest-priority skill.** Read this before every commit — AI tools frequently
inject co-author trailers unless explicitly blocked.

## Hard rule

Never include AI co-author trailers in commit messages:

```text
Co-authored-by: GitHub Copilot
Co-authored-by: Cursor
Co-authored-by: OpenAI
```

The developer is the sole author. CI fails PRs that contain these trailers.

## Before every commit

1. Run tests (`bundle exec rake spec`).
2. Draft a short commit message — **no** `Co-authored-by` lines.
3. If the draft contains any AI trailer, delete it before committing.
4. Prepare staged files; the developer runs `git commit` unless they explicitly
   ask the assistant to commit.
5. Ask whether to push after a successful commit.

## Three layers of protection

| Layer | Setup | Effect |
| --- | --- | --- |
| **Instructions** | This skill + copilot-instructions | Tells Copilot/Cursor not to add trailers |
| **Local hook** | `git config core.hooksPath .githooks` | Strips AI trailers; blocks commits on `main`/`master` |
| **CI** | `.github/workflows/policy-check.yml` | Fails push/PR if trailers appear in commit history |

Run the hook setup **once per clone** in each repo:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/prepare-commit-msg
```

## What Copilot cannot do for you

Copilot reads `.github/copilot-instructions.md` and skills when pointed to them,
but it does **not** run hooks or workflows. Hooks are local git. Workflows run on
GitHub after push. Both must be configured separately from Copilot instructions.
