# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

- **Ruby**: 3.3.4
- **Rails**: 8.1.3 (pure Rails, no frontend/backend separation)
- **Database**: PostgreSQL
- **CSS**: Tailwind CSS v4 (via tailwindcss-rails)
- **JS**: Importmap (no bundler)
- **Auth**: Rails built-in authentication generator (User + Session models)
- **Testing**: Minitest + Mocha (for mocking/stubbing) + WebMock
- **Factories**: Factory Bot (no fixtures — use factories in `test/factories/`)
- **Pagination**: [pagy](https://github.com/ddnexus/pagy)
- **Data migrations**: [data_migrate](https://github.com/ilyakatz/data-migrate)

## Development

```bash
bin/dev                  # starts Rails + Tailwind watcher (via foreman)
rails db:migrate         # schema migrations
rails data:migrate       # data migrations (data_migrate gem)
rails test               # full suite (parallel)
rails test test/models/example_test.rb                           # single file
rails test test/services/example_service_test.rb -n test_name    # single test
```

## Architecture

### Services

Service objects live under `app/services/`. Keep controllers thin; business logic that spans multiple models lives in service objects. Conventional shape: `MyService.call(...)` returning a model, result struct, or raising a domain-specific error class nested under the service.

### Controllers

- Protect controllers with `before_action :require_authentication` (default via the `Authentication` concern included in `ApplicationController`).
- For role/namespace-scoped sections, create a `Namespace::BaseController` that inherits from `ApplicationController` and enforces the role check; all controllers in that namespace inherit from it.

### Data Migrations

Uses the `data_migrate` gem for data-only changes (separate from schema migrations). Data migrations live in `db/data/` and are tracked in `db/data_schema.rb`. Use `rails generate data_migration <name>` to create one. For backfills, prefer calling existing service objects over raw SQL.

### Seed data

`db/seeds.rb` should be idempotent. Bootstrap secrets / admin credentials from `ENV.fetch(...)` — no fallbacks; missing envs should fail loudly.

### Testing conventions

- Framework: Minitest + Mocha + FactoryBot + WebMock
- Use Factory Bot (`create`, `build`) — do NOT use fixtures
- Mock HTTP with WebMock; set `WebMock.disable_net_connect!(allow_localhost: true)` in `test/test_helper.rb`.
- Controller tests: include a `SessionTestHelper` from `test/test_helpers/session_test_helper.rb` exposing `sign_in_as(user)` / `sign_out`.
- Parallel runner enabled (`parallelize(workers: :number_of_processors)`).

### Workflow Requirements

- Tests: Always write controller/model tests that confirm the proper function of any added or changed feature. Tests must pass before the work is considered done.
- Commit: Always create a git commit at the end of each task.
- Bug fix: Always write a test that reproduces the issue before fixing it.
- Documentation: Always use context7 when you need code generation, setup, configuration steps, ruby gem documentation, or library/API documentation.
- Ask the user: in case of doubts always ask the user for clarifications.

## Auth

Rails authentication is set up with:
- `User` model (`email_address`, `password_digest`, ...)
- `Session` model
- `Current` model (`CurrentAttributes`) carrying `Current.user` and `Current.session` for the request lifecycle
- `Authentication` concern included in `ApplicationController`
- `SessionsController` + `PasswordsController` (password reset via email)

If the app has roles, model them via `delegated_type` on `User` rather than a string column — each role gets its own model (e.g. `Admin`, `Member`) with `has_one :user, as: :rolable, touch: true`. Provide `admin?` / `member?` helpers on `User`.

## Code style

- ERB templates in `app/views/`
- Tailwind utility classes for all styling
- Keep controllers thin; business logic in models or service objects under `app/services/`
- Shared view partials in `app/views/shared/`
- Dates always in format `YYYY-MM-DD`
- `snake_case` for all field and method names (Rails convention)
