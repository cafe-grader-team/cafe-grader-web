# Instructor Guide: Running a Viva Exam

A **viva** is an oral-style exam done as a text conversation instead of a
code submission. The student reads a short scenario you write, then answers
questions from an AI examiner about it. When the examiner judges it has
enough to go on, the interview ends automatically and an AI grader reads the
whole conversation and produces a score with a written breakdown. The
student never talks to a raw, unscoped chatbot — every session follows the
persona, rules, and rubric you set up.

## Authoring a viva problem

Create a problem as usual, and set its type to a viva exam instead of a
normal coding problem. Two fields matter most. (This section covers the
fields; for the *craft* — choosing a scenario, writing the interview plan
and rubric, the conduct profile, piloting, and the pitfalls we have seen on
real sessions — read the [Authoring Guide](Viva-Authoring-Guide). What
students are told is in the [Student Guide](Viva-Student-Guide).)

**Scenario (the Description tab).** This is the exam paper. Write it in
plain markdown. It is sent to the AI examiner word for word as the opening
of the interview, and the examiner refers back to it throughout the
conversation. Nothing in this tab is secret — treat it like a document you
could hand a student on paper.

**Examiner briefing.** This is the rubric and your private instructions for
the examiner: what a good answer looks like, what to watch for, how to
score partial understanding, and the tone the examiner should take.
Students never see this text.

Your examiner briefing **must** include a heading that starts with "Rubric"
(for example a line reading `# Rubric`). The system checks for this before
it lets a student start the viva, and refuses with a clear error if it's
missing. Without an explicit rubric, the grader has nothing to score
against.

**One hard rule: never put security, alert, or output-format instructions
in the briefing.** Things like "if the student asks for the answer, say X"
or "always end your reply with a special marker" are the platform's job,
not yours — the platform already injects its own anti-cheating rules and
output-format instructions into every session, kept carefully in sync with
the code that reads them. Anything you add along those lines competes with
the platform's own instructions and can break grading.

*This happened for real:* a leftover "ALERT" rule from an older briefing —
written only for the examiner persona — turned out to also be visible to
the AI grader, which obeyed it instead of returning a score, and the
session failed. Write your briefing as pure content — rubric, model
answers, persona — and leave the guardrails to the platform.

### Test-driving a viva

Before students see a viva, sit it yourself. The problem edit page shows a
**Test-drive** button for viva problems (editors of the problem's group and
admins). It starts a normal interview with the normal examiner and grader,
but the session is marked as a test-drive: it is left out of every report,
score table and cost figure, it does not count against your daily starts,
and you can restart it as often as you like. Test-drives are listed under
**Test-drives** in the Viva Exam card of the edit page; students cannot see
them, even on problems that share transcripts.

## Conduct profiles

If you're writing several vivas for the same course and want them to share
one examiner "voice" — tone, how much to prompt a stuck student, how strict
to be — you don't need to repeat that text in every problem. Create a
reusable conduct profile once and attach it to as many viva problems as you
like. It's layered in ahead of your problem-specific briefing: think of it
as the course's house style, and the briefing as this problem's specifics.

## Grounding materials

Grounding material is reference content you want the examiner and grader to
treat as authoritative — lecture notes, a model solution, a supplementary
reading. It has its own small library so you can write or upload it once
and reuse it across several problems. It's optional: a clear scenario plus
a clear briefing is often all a viva needs.

## Daily start limit

Every viva has a "how many sessions per day can a student take" setting.
Only sessions the student has actually answered count: a session they open
and never answer is free.

- Leave it **blank** to use the site default (a small number, typically 3
  per day).
- Set a specific **number** to allow that many sessions per day. **For an
  exam, use 1**: one session, and staff can allow a second one by hand if
  something goes wrong.
- Set it to **0** to make the viva contest-only: students can start it only
  while the site is in contest mode and the contest is running, and then
  only one session, the same as 1. The difference from 1: under 0 the
  student has no "End interview & get graded" button, so they cannot end
  early to lock in a score before the harder questions.

A session the student restarts or throws away still counts for that day,
once they have answered in it. This stops a student from grinding through
unlimited attempts by discarding every one that goes badly. The count is
per day, not per contest: practice sessions earlier the same day count
against the limit, so keep an exam viva hidden from students until the
exam starts.

## Turn caps: soft and hard

Two settings control how long an interview can run.

- The **soft cap** (default 10) is a pacing hint. The examiner is told to
  aim to wrap up within about this many questions, but it's a suggestion,
  not a hard stop.
- The **hard cap** (default 15) is enforced by the system. Once the student
  has answered this many questions, their next answer automatically ends
  the interview and starts grading. This is a safety net against a
  runaway or stuck conversation, independent of whether the examiner
  follows the soft cap.

## What students experience

A student clicks "Start Viva" and immediately gets the opening scenario and
a first question. They answer, the examiner asks a follow-up, and so on,
until the examiner decides it has enough to grade (or the hard cap is
reached). At that point the interview ends and grading begins
automatically, usually within a minute or two.

Students can restart their own viva, but only when they could start a new
session afterwards: the session has no answer yet, or they still have a
session left today under the limit above. Otherwise the Restart button is
not shown, so a student on an exam limit of 1 cannot throw away their only
session halfway through. Restarting closes the old attempt — it is never
deleted, and you can still open and read it. A closed attempt takes no more
answers and is not graded.

Every transcript is kept permanently, whether it's the student's current
attempt or an old, archived one.

## Alert flags — what to review

If the AI examiner notices a student trying to push it off its role —
asking it to reveal the rubric or the correct answer, pretending to be an
instructor, or asking it to grade itself on the spot — it stays in
character, declines politely, and quietly flags the turn. Today, a flag
never stops the interview by itself; the conversation continues, and the
flag is simply a note for you. Open the submission and read its turns to
see exactly what was said. This is where you'll notice patterns worth
discussing with a student, or worth tightening your briefing against.

## Regrading and retakes

If a grade looks wrong — the AI grader returned prose instead of a score, or
you think a stronger model would do better — open the session and use
**Re-run grading** on the Admin card, optionally with a different (usually
stronger) grading model. The student does not redo the interview. Three
things to know:

- **Nothing is lost.** Every grading run is kept in the **Grade history**
  table under the button, with its model, total and outcome. The current run
  is the one that counts; **Make current** on any earlier run puts that grade
  back.
- **Keep the higher grade** is ticked by default: if the new run scores
  lower, the student keeps their current grade and the run is filed as
  "lower". Untick it only when the old grade is wrong in kind, not merely
  different. A run that fails never removes an existing grade.
- **Whole classes** are regraded in one batch by your platform administrator
  (`viva:regrade`, optionally for one contest); it applies the same
  keep-the-higher rule to every session and can be reverted.

If you want to give a student a clean second attempt — for example after
a technical failure in the middle of an interview — use **Allow another
attempt** on the session's Admin card (or on the student's row of the
contest's **Viva check** page). It works on a session in any state, also
during a contest: the session is closed (an unfinished interview is not
graded, and takes no more answers), it stops counting toward the start
limit, and the student can start one more. The message after the click says
whether the student can actually start now: if another answered session of
theirs from today still counts, allow another attempt on that one too. The
old attempt is kept for your records, and every grant is logged.

## Scores: your best attempt always counts

A student's score for a viva problem is the **highest score across every
attempt they've made**, including ones that were archived. Retaking a viva
can only help a student's score, never hurt it — the same rule that already
applies to ordinary code submissions.

## Contests

Vivas work inside contests the same way ordinary problems do: include the
problem in the contest, and only enrolled students within the contest
window can start it (this is also how a "0 = contest-only" viva becomes
reachable at all). Two things are planned for a future update and are not
available yet: giving each contest its own separate retake budget, and
automatically cutting off answers the instant a contest window ends. Until
then, treat a contest-mode viva like any other contest problem, and use the
daily start limit (1, or 0) to allow one session per student during the
contest. The contest's **Viva check** page (contest page → Reports) lists
every student's sessions while the exam runs and flags anyone who took the
viva twice, a reply that failed, or a grade that does not add up.

## Operational notes

**Grading lag at the bell.** Grading happens after the interview ends, and
it takes real time — the AI grader has to read the whole transcript and
produce a score. Don't pull your final contest results the instant a window
closes. After the bell, click **Finish open vivas** on the contest page and
watch the status badge beside it: it shows how many sessions are still being
graded and updates itself every few seconds. Pull your tables once it reads
**All vivas graded**. If it shows grader errors, those sessions' grading
failed; open each one and use **Re-run grading** first.

**If you're developing or testing this locally:** the AI examiner and
grader only respond when the server is running in the deployment mode that
has real AI providers configured. If starting a viva locally gives you an
immediate "no provider configured" error, you're most likely running the
wrong server mode for this feature — switch to the mode used for the live
deployment before testing vivas.
