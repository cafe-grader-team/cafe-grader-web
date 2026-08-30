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
normal coding problem. Two fields matter most.

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

Every viva has a "how many times per day can a student start this" setting.

- Leave it **blank** to use the site default (a small number, typically 3
  per day).
- Set a specific **number** to allow that many fresh starts per day.
- Set it to **0** to make the viva contest-only — students can only start it
  during an active contest window, never as free practice.

Restarting a viva always uses up part of that day's budget, even for a
session the student later throws away. This stops a student from grinding
through unlimited attempts by discarding every one that goes badly.

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

Students can restart their own viva between sessions at any time.
Restarting archives the old attempt — it is never deleted, and you can
still open and read it — and immediately frees up a new attempt, subject to
the daily limit above.

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

If a grade looks wrong — for example the AI grader returned prose instead
of a proper score, or you think a stronger model would do better — you can
re-run grading on the same transcript without asking the student to redo
the interview, optionally picking a different (usually stronger) grading
model.

If you want to give a student a clean second attempt, use "Archive and
allow retake." The old attempt is kept for your records but no longer
counts as the current one, and the student's Start Viva button reappears
(still subject to their daily limit).

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
daily-start-limit setting if you need to restrict attempts during a
contest.

## Operational notes

**Grading lag at the bell.** Grading happens after the interview ends, and
it takes real time — the AI grader has to read the whole transcript and
produce a score. Don't pull your final contest results the instant a window
closes. Check the grading-queue page first and wait until no viva jobs are
still running, then pull your tables.

**If you're developing or testing this locally:** the AI examiner and
grader only respond when the server is running in the deployment mode that
has real AI providers configured. If starting a viva locally gives you an
immediate "no provider configured" error, you're most likely running the
wrong server mode for this feature — switch to the mode used for the live
deployment before testing vivas.
