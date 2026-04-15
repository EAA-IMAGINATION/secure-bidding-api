# Sequel DB Setup Skill

## When to use

- When adding/changing schema, migrations, or environment DB config

## Rules

- Keep migration files in `app/db/migrations/`
- Use plural table names and singular foreign keys (e.g., `account_id`)
- Keep `config/environments.rb` as the source for environment-aware DB URLs

## Commands

- `bundle exec rake db:migrate`
- `RACK_ENV=test bundle exec rake db:migrate`
- `bundle exec rake db:reset`
