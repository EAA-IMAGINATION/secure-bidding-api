# Feature Branch Workflow Skill

## When to use

- At the start of every new feature, before any file edits

## Rule

Never work directly from `main`/`master`. All work merges via PR.

## Workflow

1. Check branch: `git branch --show-current`
2. If on `main` or `master`, create and switch immediately:

   ```bash
   git checkout -b feature-name
   ```

3. Implement and test on the feature branch only.
4. Open a PR for review before merging.

## Local protection

The `pre-commit` hook blocks commits on `main`/`master` when hooks are enabled:

```bash
git config core.hooksPath .githooks
```

See [repo-policy-enforcement](repo-policy-enforcement.md) for the full hook and
CI parity table.

## GitHub branch protection (remote)

Protect the default branch on GitHub so direct pushes are rejected even without
local hooks. As repo admin:

```bash
# API (default branch: master)
gh api -X PUT repos/EAA-IMAGINATION/secure-bidding-api/branches/master/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["check_trailers"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

# App (default branch: main)
gh api -X PUT repos/EAA-IMAGINATION/secure-bidding-app/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["check_trailers"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

Or use GitHub → Settings → Branches → Add rule: require PR, require
`check_trailers` status, disable force push.
