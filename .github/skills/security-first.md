# Security-First Skill

## When to use

- For every new route and data model
- Before persisting or returning sensitive information

## Rule

Every route and model change must satisfy the security patterns in hub
`PROJECT_STATUS.md` and the repo policy objects under `app/policies/`.

## Checklist

- Validate required input and data type
- Return correct HTTP status codes
- Encrypt sensitive data at rest
- Avoid exposing secret material in API responses
