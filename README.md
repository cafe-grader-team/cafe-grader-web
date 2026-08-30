# Cafe-Grader

An online programming-contest and assignment-grading platform. Students submit code; the system compiles it, runs it against test cases, and reports scores. Instructors manage problems, contests, groups, users, and reports.

The project started at Kasetsart University by @jittat and @pkhungurn. The current maintainer is @nattee.

*Primary development happens at Chulalongkorn University on the [`nattee/cafe-grader-web`](https://github.com/nattee/cafe-grader-web) fork; upstream [`cafe-grader-team/cafe-grader-web`](https://github.com/cafe-grader-team/cafe-grader-web) receives stable cuts periodically. Both repos carry this same README, so it deliberately does not claim which one is newer — **check the latest release in whichever repo you are reading.** The fork is normally ahead.*

---

## Upgrading an older deployment? Read MIGRATION.md first

If your deployment predates 2023 — Rails 4.2 + Bootstrap 3, the `v1.0.0` era — **do not pull blindly.** v4.x is a multi-framework jump (Rails 4.2 → 8, Bootstrap 3 → 5, Sprockets → Propshaft, plus the project's first Active Job backend). It needs a maintenance window, a full database backup, and several config files updated by hand, none of which convert automatically.

**[MIGRATION.md](MIGRATION.md)** carries the whole procedure: the retroactive version tags (`v1.0.0` … `v4.x`) and what each era contains, a compatibility matrix, how to roll back, and how to pin to the old line if you cannot upgrade yet.

---

## Tech stack

- Ruby 3.4.4, Rails 8.0
- **MySQL 8.0+ only** (Oracle MySQL or Percona Server; primary DB `grader`, queue DB `grader_queue`).
  **MariaDB will NOT work**: every table uses the `utf8mb4_0900_ai_ci` collation (MySQL 8's default),
  which MariaDB does not implement — the schema will not even load. This is a deliberate decision
  (performance + modern Unicode/Thai handling); rationale in [doc/decisions.md](doc/decisions.md).
- Propshaft asset pipeline, ImportMap for JS, dartsass-rails for CSS
- Hotwire (Turbo + Stimulus), jQuery (legacy), Bootstrap 5, HAML
- Solid Queue (jobs), Solid Cache, Solid Cable
- Puma (Thruster is bundled but optional)
- External judge workers (separate processes; see `config/worker.yml`)

## Getting started

See the wiki: <https://github.com/cafe-grader-team/cafe-grader-web/wiki>

Quick local dev:

```bash
bundle install
bin/rails db:setup
bin/rails db:migrate:queue       # migrate the queue DB
bin/dev                          # web + dartsass watcher + queue
```

The test suite uses two databases (`grader_test` + `grader_queue_test`). Give the MySQL
user a wildcard grant so all `grader_*` databases work, current and future:

```sql
GRANT ALL PRIVILEGES ON `grader\_%`.* TO 'grader'@'localhost';
```

## Documentation

- **[Wiki](https://github.com/cafe-grader-team/cafe-grader-web/wiki)** — installation, judge-worker setup, problem authoring, roles & access control.
- **[Guides site](https://nattee.github.io/cafe-grader-web/)** — rendered visual companions to the wiki pages (role matrices, permission flowcharts). Served from the development fork.
- **[MIGRATION.md](MIGRATION.md)** — upgrading a pre-2023 (v1.x / Rails 4.2) deployment.
- **`/api-docs`** (running app) — Swagger UI for the JSON API.

## License

MIT. See `MIT-LICENSE`.

## Contributing

Issues and PRs welcome — for substantial changes please open an issue first, so scope can be discussed before you build. New development lands on the `nattee/cafe-grader-web` fork first and reaches `cafe-grader-team/cafe-grader-web` in periodic batches, so a PR against either repo is fine; it may be replayed onto the fork line before it ships.
