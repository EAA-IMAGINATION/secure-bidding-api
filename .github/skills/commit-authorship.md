# Commit Authorship Skill

## When to use

- Before creating or amending any commit

## Rules

1. Commit only after running the project tests for the implemented change.
2. Keep commit messages short and meaningful.
3. Never include any AI co-author trailer in commit messages.
4. Hard stop: if a draft commit message contains `Co-authored-by: Copilot` (or any
   AI co-author trailer), remove it before presenting or running the commit.
5. The assistant should prepare the commit message and staged file set, then ask
   the developer to run the commit command manually.

## Notes

- Ask whether to push to remote after the commit is created.
