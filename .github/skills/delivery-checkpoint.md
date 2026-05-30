# Delivery Checkpoint Skill

## When to use

- At the end of any implementation task before handoff

## Checklist

1. Run the test suite (`bundle exec rake spec` or a targeted spec file).
2. If any `.md` files changed, run [markdown-linting](markdown-linting.md).
3. Stage files and draft a short commit message — follow
   [commit-authorship](commit-authorship.md).
4. Hand off to the developer to run `git commit`.
5. Ask whether to push after the commit succeeds.

## App-only (when UI changed)

Manually verify flash messages and key browser flows before handoff.

## CI expectations

Both repos run `policy-check.yml` (`check_trailers`) and a spec workflow on
push/PR. See [repo-policy-enforcement](repo-policy-enforcement.md).
