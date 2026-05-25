# MVC Architecture Skill

## When to use

- When adding or modifying API routes
- When creating/updating models

## Rule

Maintain strict separation of concerns.

## Boundaries

- Models in `app/models/` handle domain and persistence behavior.
- Controllers in `app/controllers/app.rb` handle routing and HTTP responses.
- Keep business logic out of route handlers where possible.
