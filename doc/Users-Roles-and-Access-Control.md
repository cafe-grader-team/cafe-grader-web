# Users, Roles & Access Control

This page explains **who can see and do what** in Cafe-Grader: the roles a
user can hold, and the three on/off switches that decide whether a problem or a
whole course is visible. If you've ever wondered *"why does my TA see an empty
report?"* — the answer is here.

## Two layers of access

Access is decided by **two independent things**:

1. **Your global role** — almost everyone has *none*. The only one that changes
   what problems/reports you see is **Admin**.
2. **Your role *within each group*** — you can be a **Member**, a **Reporter**,
   or an **Editor** of a group, and this can differ from group to group. (You
   might be a Member of one course and a Reporter of another.)

So "being a reporter" is **not** a global switch — it's something you are *in a
specific group*. To let someone report on a course, you add them **to that
group** with the Reporter role.

## Roles at a glance

| Role | Where it applies | What they can do |
|---|---|---|
| **Member** (student) | per group | Submit to the course's problems; see their own submissions. |
| **Reporter** | per group | **Read-only, live courses only.** View reports — best scores, activity, submissions — for *available* problems in *active* groups. Cannot edit; loses access once a course is archived. |
| **Editor** | per group | Their group's **curator**: sees, edits, and reports on **every** problem in the group — including draft (unavailable) problems and archived (disabled) courses — plus manages membership. A strict superset of Reporter. |
| **Admin** | global | Everything, in every group, **plus** user management. The only role that bypasses the switches below *everywhere* — an editor bypasses them only *within their own groups*. |

Admin is deliberately powerful — it's the *user-management* tier. Prefer a
per-group **Editor** or **Reporter** for course staff who shouldn't manage
accounts.

## The three visibility switches

Even with the right role, three on/off switches decide whether content is
actually visible. Understanding these explains almost every "I see nothing"
question.

### 1. Problem → **Available**
The master switch for a single problem.
- **OFF** ⇒ hidden from **students and reporters**. The group's **editors still
  see it** (so they can work on a draft or a taken-down problem), and admins see
  it everywhere.
- Use it to take a problem out of circulation.

### 2. Group → **Enabled**
Whether a course/group is active.
- **OFF** (disabled / archived) ⇒ the course disappears for its **members and
  reporters**. Its **editors keep full access** — an archived course is still
  theirs to view, edit, and report on; it just drops out of everyone else's
  view. Admins see it everywhere.
- Use it to archive a finished course.

### 3. Problem-in-group → **Enabled**
A softer, **student-only** hide for one problem *within one group*.
- **OFF** ⇒ students in that group can't see or submit the problem, **but
  reporters and editors still can** (for a reporter, provided the problem is
  *Available* and the group is *Enabled*; an editor always can).
- Use it to hide a problem from students while staff keep visibility.

## Who sees what — the effect of each switch

**When a problem is `Available = OFF`:**

| Function | Member | Reporter | Editor | Admin |
|---|:--:|:--:|:--:|:--:|
| View statement / download PDF | ✗ | ✗ | ✓ | ✓ |
| View reports (scores) | — | ✗ | ✓ | ✓ |
| View others' submissions | ✗ | ✗ | ✓ | ✓ |
| Edit the problem | — | — | ✓ | ✓ |
| Submit the problem | ✗ | ✗ | ✗ | ✗ |

→ Hidden from **students and reporters**; the group's **editors** (and admins)
still see and manage it. Nobody can *submit* an unavailable problem — it's out
of circulation.

**When a group is `Enabled = OFF` (archived):**

| Function | Member | Reporter | Editor | Admin |
|---|:--:|:--:|:--:|:--:|
| Anything in that group | ✗ | ✗ | ✓ | ✓ |

→ An archived course stays fully accessible to its **editors** (and admins);
members and reporters lose access. In the report filters it's shown to editors
tagged **"archived"**; reporters don't see it at all.

**When a problem's in-group switch is `Enabled = OFF`:**

| Function | Member | Reporter | Editor | Admin |
|---|:--:|:--:|:--:|:--:|
| Submit / see the problem | ✗ | — | — | ✓ |
| View reports / submissions / edit | — | ✓ | ✓ | ✓ |

→ Hides the problem from **students only**; staff keep access.

## Common tasks

- **Let a TA view an active course's reports** → add them to the group as a **Reporter**.
- **Let a TA manage a course's problems, or see a finished/archived course** →
  add them as an **Editor**. Editors keep access after a course is archived;
  reporters do not.
- **Hide a problem from students but keep staff access** → set the problem's
  *in-group* switch OFF (leave the problem *Available* and the group *Enabled*).
- **Take a problem out of circulation** → set the problem *Available* OFF
  (editors can still open it to fix or re-release it).
- **Archive a finished course** → set the group *Enabled* OFF (its editors keep
  access; it's tagged *archived* in the report filters).

## "My reporter sees an empty report" — why?

A reporter only sees **live** content: available problems in an enabled group.
So a reporter's report comes back empty when the problems have been set
**unavailable** (even if the group is still enabled) — the report page shows a
short notice explaining this rather than a silent blank. And once a course is
**archived** (group disabled), it drops out of a reporter's filters entirely.

If a staff member needs to pull a **finished course's** reports, make them an
**editor** of that group — the reporter role is scoped to live courses by design.

## Finished / archived courses

To retire a course, disable its group. It vanishes for students and reporters,
but its **editors keep full read / edit / report access** — an archived course
is still theirs to look back on. In the report filters an editor's archived
groups appear with an **"archived"** tag, so active and finished courses are
easy to tell apart. Only admins bypass everything everywhere; for a non-admin
who needs finished-course access, **Editor** is the tier to grant.
