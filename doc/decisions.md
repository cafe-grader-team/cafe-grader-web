# Engineering Decisions

Major, hard-to-reverse decisions and their reasoning. Newest first.
(Deferred work goes in `backlog.md`; this file is for decisions already made.)

## 2026-06-10 — Canonical MySQL collation: `utf8mb4_0900_ai_ci` (MySQL-only; MariaDB unsupported)

**Decision.** Every table and string column in the primary database uses
`utf8mb4_0900_ai_ci`. The database default is pinned to it (migration
`20260610120000_unify_collations_to_utf8mb4_0900`), connections request it
(`collation:` in `database.yml`), and `test/schema_collation_test.rb` fails
the suite the moment any table or column drifts.

**Consequence — supported database servers.**
**This repo REQUIRES MySQL 8.0+ — Oracle MySQL or Percona Server. MariaDB is
NOT supported and WILL NOT work.** MariaDB has no `utf8mb4_0900_*` collations,
so loading the schema (or any dump of it) fails immediately. Percona Server is
a drop-in MySQL fork and supports the 0900 family fully, so Percona remains an
option. This was already de-facto true before the decision (28 of 45 tables
were on 0900), but it is now intentional, documented, and enforced.

**Why (decided by @nattee):**

1. **No MariaDB in deployment planning; Percona remains possible.** We control
   the deployment on MySQL 8. Keeping a MariaDB exit open would have meant
   standardizing on `utf8mb4_unicode_ci` instead — converting the largest,
   hottest tables (including `submissions`, which carries every source file
   and binary upload) and fighting MySQL's default collation forever.
2. **Faster.** The 0900 family is MySQL 8's rewritten collation
   implementation and benchmarks significantly faster for comparisons and
   sorts than `utf8mb4_unicode_ci`.
3. **Better Thai (and general Unicode) handling.** `utf8mb4_unicode_ci`
   implements UCA 4.0.0 (2004); `utf8mb4_0900_ai_ci` implements UCA 9.0.0 —
   twelve years of added characters and collation fixes, including improved
   Thai handling. (For strict Thai dictionary *ordering*, the same family
   offers `utf8mb4_th_0900_ai_ci` per column/query if a report ever needs it.)
4. **It is the MySQL 8 default.** Tables created without an explicit
   `COLLATE` — future migrations, `solid_queue`/`solid_cache` schemas,
   dump-restores onto fresh servers, ad-hoc DBA tables — are born conforming.
   Standardizing on anything else regenerates drift forever.

**History this resolves.** Charset/collation mismatches were fixed at least
three times before (2025-07 `alter_utf8_for_comments`, 2026-03
`convert_utf8mb3_tables_to_utf8mb4`, 2026-04 rev 1586 which pinned the DB
default after new tables kept reverting to utf8mb3). Each round converted the
tables failing *that day* to `utf8mb4_unicode_ci`, while MySQL 8 kept minting
new tables as `0900_ai_ci`. The two populations (17 vs 28 tables) collided in
`ReportController#cheat_report` (`logins.ip_address` joined against
`submissions.ip_address` → "Illegal mix of collations"). The durable fix is a
single canonical collation **plus an enforced invariant** (the guard test) —
not another one-off conversion.

**Behavior notes.** `ai_ci` = accent- and case-insensitive, same class as
before. The 0900 family is NO PAD (trailing spaces are significant in
comparisons) unlike unicode_ci's PAD SPACE; this is the SQL-standard behavior
and nothing in the app relies on the old padding semantics.
