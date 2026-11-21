# Exam slip passwords: CU-net off per contest, and a Check step for user import

Date: 2026-11-21. Status: approved by dae 2026-11-21 (rev 2305).

## Why

For some exams (CEDT, not DS or Algo) the operations team ("ops") does the
seating and gives every student a new 6-digit password printed on a slip at
their seat. Ops builds one Excel file with seats and passwords; an admin
imports it on the Import Users page, then imports each contest's students on
the contest's Import tab. CEDT splits the cohort into a morning and an
afternoon contest with the same problems, so one file feeds three imports.

The point is defence in depth: a student must not be able to share a password
before the exam. If student A (stronger) knows student B's password, A can sit
B's exam, and A makes up the missing score in a later quiz. A slip password
seen for the first time at the seat cannot be shared in advance.

That only holds while CU-net login is off for those students. Today the admin
turns CU-net off with one site-wide switch, which:

1. turns it off for every class on the server, not just the exam;
2. has to be turned back on by hand, and can be forgotten in either direction;
3. if it is still on after the password import, lets any CU-net login quietly
   replace the slip password (`User.authenticate` on chula_cp saves the CU-net
   password as the local one). The student then can't log in at the seat, or
   someone who knows their CU-net password can;
4. makes CU-net passwords typed during the exam count as wrong passwords, and
   a room behind one gateway address can lock itself out (DS Quiz 2,
   2026-10-07, see `app/controllers/concerns/login_throttling.rb`).

dae's constraint: **don't change how ops works.** Tools may help, but ops keeps
making the file and the admin keeps importing it.

## Words used in this document

- **CU-net login**: logging in with the university password, checked by
  CUCAS. Exists only on `chula_cp`.
- **Site switch**: the configuration row `chula.allow_cu_net_password`. It
  says whether CU-net login works on this server at all. Unchanged.
- **Contest setting**: the new checkbox on a contest, "Turn off CU-net login
  for this contest's students until the contest ends".
- **Slip password**: the password the admin imported from ops' file.
- **Blocked student**: a student the contest setting currently covers (exact
  rule in Part 1).
- **Check**: the new button on the Import Users page that shows what an import
  would do without saving anything.

## Goals

1. An admin can turn CU-net off for one contest's students. It comes back on
   its own when the contest ends.
2. While a student is blocked, a CU-net login cannot replace their slip
   password.
3. A blocked student who types their CU-net password is told to use the slip,
   and that attempt does not count toward the login lockout.
4. Before an import, the admin can see what it will do: new passwords, random
   passwords, new accounts, duplicates, name changes, ignored lines.
5. The Import Users page looks like the contest page's Import tab instead of
   a wall of text on a yellow card.

## Non-goals

- Generating passwords or printing slips: ops does that.
- Changing ops' file, the import line format, or what an import does.
- One import for both contests (deferred: needs the header row of ops' file).
- Renaming or removing the site switch.

## Anti-goals (failure even if it "works")

- Anything that makes ops log in or change their steps.
- A ticked contest that still lets a student in with a CU-net password.
- A Check step that is required, or that slows down today's import.
- Two controls whose combination an admin has to puzzle out.

## Approaches considered

- **Contest generates the passwords (earlier option A).** Dropped: it moves
  password-making from ops into the system, reversing their process.
- **Generate on the import page / fix Bulk Manage (options B and C).** Dropped
  for the same reason, and neither touched the CU-net problems.
- **Block users implicitly** (for example, anyone whose password was imported
  in the last N hours). Rejected: invisible to the admin, and it breaks the
  "turn CU-net off" mental model.
- **Picked: keep ops' flow and add two helpers**: the per-contest setting
  (Part 1) and the Check step (Part 2), plus the restyle (Part 3). dae
  approved this on 2026-11-21.

## Part 1: turn CU-net off per contest

### What the admin sees

On the contest edit form, below Enabled:

```
[ ] Turn off CU-net login for this contest's students until the contest ends
    CU-net login is currently ON for the rest of the site.
    Ticked now, it covers this contest's students until <stop, plus the
    longest extra time>.
```

- The second line shows the site switch's live value (ON / OFF).
- **Only admins can tick or untick it.** Group editors can manage contests
  and add any user to them, so an editor-tickable box would let a TA turn off
  CU-net for any student on the server. Editors see the box read-only. (My
  call, leaning toward less access; the site switch is admin-only too.)
- Ticking requires a Stop time. A contest with no Stop can't be ticked, so no
  block is open-ended.
- When the box is ticked, the contest's show page carries a small badge,
  "CU-net off for students", next to the other contest facts.
- **Clone copies the setting**, so an afternoon contest cloned from the
  morning one is covered too.
- The new column is added to Contest's `audited only:` list, so ticking and
  unticking show in the contest's change history.
- On a deployment with no outside login (any `master` deployment), the
  checkbox and badge are not shown.

### One rule for the two controls

**A student can use CU-net only when the site switch is on and the student is
not blocked.** The contest setting can only turn CU-net off, and only for its
own students. It never turns CU-net on.

| Site switch | Contest setting | Result |
|---|---|---|
| on | ticked | Exam students blocked; everyone else keeps CU-net. The intended exam-day setup. |
| off | any | CU-net off for everyone (today's behaviour). An admin who still flips the switch out of habit breaks nothing. |
| switched back on mid-exam | ticked | Exam students stay blocked. |

### Who is blocked, and when

A user is blocked at time `now` when they have a `contests_users` row such that:

1. the row's role is `user` (editors are staff and are never blocked);
2. the row's contest has the setting ticked;
3. `now` is before the contest's `stop` plus that row's `extra_time_second`.

There is no start time: the block begins as soon as both the row and the tick
exist. That is deliberate. The danger is a CU-net login between the password
import and the exam, which a start-time rule would leave open.

The `enabled` flags on the contest and on the row are ignored, also on
purpose: an admin often keeps a contest disabled until the exam starts, and
the block must already hold then. When unsure, the rule leans toward blocking
(less access), not toward letting CU-net through.

### Login behaviour (web login and API login alike)

Both doors call the same model method, so they behave the same.

| Case | Result |
|---|---|
| Local password matches | Logged in, blocked or not. The slip password always works. |
| Site switch off | "Wrong password", counted toward lockout (today). |
| Switch on, not blocked, CU-net password correct | Logged in; local password replaced by the CU-net one (today). |
| Switch on, **blocked**, CU-net password correct | **Refused.** Message below. Local password untouched. Lockout counters **not** increased; a failed `Login` row is still written. |
| Switch on, blocked, CU-net password wrong | "Wrong password", counted (today). |

Message on the web login page:

> This exam uses the password on your seat slip. Your CU-net password will
> work again after the exam ends.

The API returns 401 with the same sentence in `error`.

Checking whether the typed password is the correct CU-net password costs one
CUCAS call. That call already happens today on every failed local password
while the site switch is on, so it adds no new external traffic.

### Where the code lives

- **`master`**: the column and migration; the "is blocked" rule; a
  login-result flow with one seam ("is this the user's outside password?")
  that is dormant on master. Also both controllers' handling of the refusal,
  the form checkbox, the badge, clone, audit and tests. This follows the
  provider-placement rule (`doc/decisions.md` 2026-07-30): code any
  deployment could use lives on master, dormant until configured.
- **`chula_cp`**: one small Chula-only commit that plugs CUCAS and the
  `chula.allow_cu_net_password` key into that seam. It replaces the CU-net
  branch of its own `User.authenticate`, and sets the outside login's display
  name to "CU-net". Chula-only commits like this already land on chula_cp
  (e.g. revs 1945, 2273). The next `merge master` will conflict in
  `User.authenticate`; resolve it by keeping master's flow.
- The old `LoginController.add_authenticator` hook is not reused: it covers
  only the web door, not the API, and nothing uses it.

### Security notes

- The throttle check still runs first, before any password check, so a
  locked-out address or account never reaches CUCAS.
- Only a *correct* CU-net password skips the lockout counters. Guessing still
  counts as usual.
- The refusal message confirms that a typed CU-net password was right. Today,
  with the switch on, a right guess logs the guesser straight in, so this
  reveals strictly less than now.
- **Logins made before the password import stay logged in.** Until the
  import, a student's local password equals their CU-net password, and an
  import ends no sessions, so someone who logs in as B the night before keeps
  that browser logged in as B. This design adds nothing for it. CEDT exams
  run in an exam room with the IP whitelist on (dae, 2026-11-21), and
  `check_valid_login` checks the whitelist on every request, not only at
  login. A session from home or phone data is refused in the exam. If an
  exam ever runs on students' own laptops on an allowed network, revisit
  this: the fix would be "a blocked student's password change ends their
  older sessions and API tokens".

## Part 2: Check step on the Import Users page

### What the admin sees

A **Check** button sits beside **Create following users**. Pressing it shows
a result panel and saves nothing. The textarea keeps its text. The panel lists
counts, each with up to 10 logins and a "show all" toggle:

| Line in the panel | Kind |
|---|---|
| N existing users get a new password | info |
| N existing users get a **random** password (row has only login and name) | warning |
| N existing users keep their password (empty password field) | info |
| N **new accounts** will be created; on an exam import this usually means a mistyped login | warning |
| N logins are listed **more than once** (the last row wins) | warning |
| N existing users' **names** will change | info |
| N existing users' remarks will change | info |
| N lines will be **ignored** (fewer than two fields), with line numbers | warning |
| N users get a new password but are **not yet covered** by a contest with CU-net turned off; a CU-net login before they are covered replaces the new password (shown only where an outside login exists) | warning |
| "These users will also be added to group X" when the group box is ticked | info |

- If the admin edits the text after pressing Check, the panel marks itself
  out of date ("The list changed. Press Check again").
- Check writes no audit row and changes nothing.
- **Create following users** behaves exactly as today. Pressing Check is
  optional.

### Rule: one parser

Check and Create must read the text the same way, or the preview lies. The
line parsing in `User.create_from_list` moves into a shared parser used by
both. Create's behaviour stays identical. Tests that pin today's behaviour are
written **before** the parser is moved:

- the random password for a two-field row;
- an empty password keeps the old one;
- alias and remark handling;
- two-field lines silently skipped.

## Part 3: restyle the Import Users page

Match the contest show page's Import tab (`#tab-add-users`):

- **Left column**: the textarea, the Check button (outline), **Create
  following users** (success), and the group option.
- **Right column**: the instruction card in the Import tab's style
  (`.card.border-0.shadow-sm.border-start.border-4.border-info`, lightbulb
  icon, "Import Instructions" heading). It holds the format line
  `user_id,name[,passwd[,alias[,remark]]]`, short bullets, and the two
  examples (they explain the random-password rule, so they stay). The Check
  result panel appears above the card.
- The card gets a short "For an exam import" note: press Check first. When
  the students already have accounts, add them to the contest (with CU-net
  turned off) *before* importing passwords, because a CU-net login in between
  replaces the new password. New accounts can't be added to a contest before
  they exist (`Contest#add_users_from_csv` skips unknown logins), so import
  them first and add them to the contest straight after. The "not yet
  covered" Check line shows who is still exposed. (My call: this is advice
  on the page, not an enforced order.)
- Before and after screenshots go to dae for approval before the restyle is
  committed.

## Testing

- **Model:** the blocked rule.
  - Inside the window, and inside extra time.
  - After stop plus extra time.
  - Editor role.
  - Box unticked.
  - Contest or row disabled: still blocked.
  - Two contests.
- **Model:** the login flow, every row of the behaviour table, with the seam
  stubbed on master.
- **Controller (web and API):**
  - the refusal message and status;
  - lockout counters unchanged on a refusal;
  - a `Login` row written;
  - counters still increased for a wrong CU-net password.
- **Contest:** clone copies the setting; ticking writes an audit row; the
  checkbox is hidden when no outside login exists; a group editor cannot
  change it (the param is dropped, the box is read-only); ticking without a
  Stop time is refused.
- **Import:** pinning tests for `create_from_list` (before the parser moves);
  every Check category; Check saves nothing.
- **System:** Check shows the panel and the out-of-date note.
- **chula_cp:** the CUCAS wiring, with CUCAS stubbed.
- The full suite (`bin/rails check`) passes on both branches.

## Rollout

- No deploy on 2026-11-21 (exam day).
- The migration adds one boolean column, default false, to the small
  `contests` table.
- Nothing changes until an admin ticks the box. Ops' process does not change.
- Exam-day steps for the admin:
  1. Leave the site switch on.
  2. Create both CEDT contests and tick the box on each.
  3. Add the students to each contest (the contest Import tab, as today).
  4. Import the passwords on Import Users, pressing Check first. The
     "not yet covered" line should be zero.

  The imports themselves are unchanged; only their order moves.
- CHANGELOG `Added` bullets go into the commits that build each part.

## Left to the builder

- Method, column and route names (keep "outside login" for the generic code,
  "CU-net" for anything a Chula user sees).
- Exact markup, badge placement and panel layout. Screenshots decide.
- How the Check result reaches the page (a Turbo Stream response, by the
  page's existing patterns).

## Noticed, not in scope

- The contest form shows Pre/Post contest seconds, but `contests_params`
  doesn't permit them, so edits to those fields are silently dropped. Goes to
  `doc/backlog.md`.
- One import for both CEDT contests: deferred until we have the header row of
  ops' file.
