# Development environment parity

This hub contains two deployable apps. Functionality should match across local dev,
GitHub default branches, and Heroku production. Data differs by design: only local
dev runs `rake db:seed` for demo accounts and sample projects.

## Release alignment

| Surface | API repo (`secure-bidding-api`) | App repo (`secure-bidding-app`) |
| --- | --- | --- |
| Default branch | `master` | `main` |
| Heroku app | `secure-bidding-api` | `secure-bidding-app` |
| Heroku git ref | `main` | `main` |

After pulling, confirm all three match:

```bash
# API
cd secure-bidding-api
git fetch origin heroku
git log -1 --oneline HEAD origin/master heroku/main

# App
cd ../secure-bidding-app
git fetch origin heroku
git log -1 --oneline HEAD origin/main heroku/main
```

All three SHAs should be identical for each repo.

## Local ports and URLs

| Service | Port | Base URL |
| --- | --- | --- |
| API | 3000 | `http://localhost:3000/api/v1` |
| App | 9292 | `http://localhost:9292` |

Copy `config/secrets.example.yml` → `config/secrets.yml` in each repo. The app
must point `API_URL` at the API port above (Figaro defaults dev/test to port
3000 in `config/environments.rb`).

## Bootstrap local dev

### API server

```bash
cd secure-bidding-api
bundle install
cp config/secrets-example.yml config/secrets.yml   # first time only
bundle exec rake db:migrate
bundle exec rake db:seed
bundle exec rackup -p 3000
```

Seeded admin: `scifithedev` / `President@1958` (verified). Demo users:
`demo-project-owner`, `demo-bidder` (verified). Two published seed projects with
memberships and sample bids.

### App server

```bash
cd secure-bidding-app
bundle install
cp config/secrets.example.yml config/secrets.yml   # first time only
bundle exec rake generate:session_secret           # first time only; paste into secrets.yml
bundle exec rackup -p 9292
```

## Production (Heroku)

| App | Public URL |
| --- | --- |
| API | `https://secure-bidding-api-035f47c69a7b.herokuapp.com/api/v1` |
| App | `https://www.freelanceprocurementhub.tech` |

Required coupling:

- App `API_URL` → production API base URL above.
- App `APP_URL` / Google `GOOGLE_REDIRECT_URI` → custom app domain.
- API `GOOGLE_CLIENT_ID` matches app SSO config.
- Postgres `schema_info.version` = latest migration (currently **19**).

Do **not** run `db:seed` on production. Schema changes:

```bash
heroku run rake db:migrate -a secure-bidding-api
```

(Uses `DATABASE_URL` on Heroku Postgres.)

Deploy after merging to default branch:

```bash
cd secure-bidding-api && git push origin master && git push heroku master:main
cd secure-bidding-app && git push origin main && git push heroku main:main
```

## Functional smoke test (dev or prod)

1. Sign in as admin or verified member.
2. **Projects**: list → open detail → create (verified member) → edit → delete.
3. **Auth**: registration / email verification / Google SSO (if env vars set).
4. Anonymous home lists **published** projects only.

## What intentionally differs

| Concern | Local dev | Production |
| --- | --- | --- |
| Database | SQLite (`development.db`) | Heroku Postgres |
| Seed data | `rake db:seed` | None (manual accounts only) |
| Email | Mailer To Go / Mailtrap sandbox | Mailer To Go / Mailtrap per env vars |
| Sessions | Rack session pool | Redis (`REDISCLOUD_URL`) on app |
