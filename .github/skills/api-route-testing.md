# API Route Testing Skill

## When to use

- Before implementing new API routes

## Rules

- Write tests first for each route (RED-GREEN-REFACTOR)
- Include HAPPY and SAD paths
- Clear database tables in `before` blocks for route specs
- Cover list (`GET /resource`), single (`GET /resource/:id`),
  and create (`POST /resource`)
- Include a test that `DATABASE_URL` is not required in local test setup
