# Sequel DB Setup Skill

## When to use

- When adding/changing schema, migrations, or environment DB config

## Rules

- Keep migration files in `app/db/migrations/`
- Use plural table names and singular foreign keys (e.g., `account_id`)
- Prefer explicit relational constraints (`foreign_key`) over plain integer references
- Keep `config/environments.rb` as the source for environment-aware DB URLs
- Keep model seed files in `app/db/seeds/` and maintain a `db:seed` task

## Commands

- `bundle exec rake db:migrate`
- `RACK_ENV=test bundle exec rake db:migrate`
- `bundle exec rake db:reset`
- `bundle exec rake db:seed`
