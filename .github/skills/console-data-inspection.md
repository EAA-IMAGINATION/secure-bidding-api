# Console Data Inspection Skill

## When to use

- When validating create/read/update/delete behavior manually

## Rules

- Use `bundle exec rake console` to preload application code
- Use `.pryrc` + Hirb for tabular output

## Example session

```ruby
SecureBidding::Account.create(username: 'demo', email: 'demo@example.com')
SecureBidding::Secret.all
```
