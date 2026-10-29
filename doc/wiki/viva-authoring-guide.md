# Authoring Guide: Writing a Viva

This guide is for the person who *writes* a viva — the scenario the student
reads, the private briefing the AI examiner follows, and the rubric the AI
grader applies. It is about craft: what makes an interview that actually
measures understanding, and the mistakes we have watched examiners and
graders make on real student sessions.

Companion pages: the [Instructor Guide](Viva-Instructor-Guide) covers
*operating* a viva (fields, limits, alerts, regrading, contests) and the
[Student Guide](Viva-Student-Guide) is what students are told; the
platform reference `doc/Viva-Exam.md` in the repository covers *how the
prompt is assembled* and the session lifecycle. This page assumes neither.

A live document. Each section that came from a lesson says so; the change
log of the viva feature itself is `doc/Viva-History.md`.

---

## 1. What a viva is good for

A viva is a chat interview about a small artifact — a code fragment, a data
structure choice, a design sketch — graded from the transcript. It measures
*whether the student can explain, trace, predict and critique*. It does not
measure whether they can produce working code; you have ordinary problems
for that.

Three shapes work well, in increasing length:

| Shape | Typical rungs | Student turns | Example |
|---|---|---|---|
| **Debug / concept** | trace → witness → bug → precondition → cost | 6–9 | "This four-line fragment is sometimes wrong. Why?" |
| **Container choice** | requirement → choice → justify → cross-question | 8–12 | "Which container for X? Now the requirement changes." |
| **Design** | operations → structure → invariant → worked example → cost | 10–15 | "Design the bookkeeping for a prepaid card." |

Roughly three quarters of paper-exam questions do **not** convert: anything
that needs a compiler, a long derivation, a drawing, or a single numeric
answer. A good viva candidate has one small artifact, is answerable in
words and short fragments, has at least one *trap* (a plausible wrong
diagnosis), and has small examples a student can trace by hand.

---

## 2. The pieces you write, and who sees them

| Piece | Where it lives | Who sees it |
|---|---|---|
| **Scenario** | the problem's Description field | the **student**, delivered by the examiner's opening message (the viva page shows no statement) |
| **Examiner briefing** | the problem's *Examiner briefing* field (`viva_prompt`) | examiner and grader LLMs only — model answer, interview plan, `# Rubric` |
| **Conduct profile** | a shared tag, attached to many problems | examiner and grader — the course's house rules, split into a base and a mode overlay (§5) |
| **Grounding material** | a shared library, attached per problem | examiner and grader — reference text they must treat as authoritative |

Everything you write in the briefing or a conduct tag is read by **both**
the interviewer and the grader. Write content — model answers, plan,
rubric, tone. Never write operational rules ("if the student says X, print
Y", output formats, alert banners): the platform injects those itself and
keeps them in lockstep with the code that parses them; yours will compete
with them and can break grading. (This is not hypothetical — see the
Instructor Guide.)

---

## 3. Step 1 — Choose and shape the scenario

**Start from something real.** Old paper exams are the best source: the
question has already been vetted, and the marking scheme tells you what the
rubric should reward. Reskin the domain if the paper is still in
circulation.

**Pass the checklist:**

- One artifact, small enough to quote in a chat bubble (≤ ~10 lines of code
  or ≤ ~6 rules).
- Answerable in words and short fragments; no compiler needed.
- Has a **trap**: a wrong diagnosis a reasonable student will offer, that
  the examiner can probe with one question.
- Has **witnesses**: tiny inputs (5 elements, 3 operations) the student can
  trace by hand and the examiner can verify by hand.
- Gradable from the transcript alone: you can name 4–6 rubric criteria now.

**Then check what the text gives away or invites** (all from our first
exam audit, §10):

- **Nothing in the text is an answer.** No topic line, deck number or
  technique name that a rubric item asks the student to produce. An exam
  scenario whose subtitle named the rule its last question asked for turned
  that criterion into a reading test. Topic and source notes belong in the
  briefing or the kit README, never in the scenario.
- **Every example is one you would accept.** Students copy example types
  and values word for word. A scenario that offered a wrong design as an
  "e.g." made it the most common opening answer.
- **Every task word has one reading.** Read each item as a student who has
  just studied the course's own classes: words like "safe" or "blocks", or
  anything that sounds like a course class, pull answers toward the course
  material instead of the artifact. Name the thing you are asking for
  ("which special member function", "how many heap-allocated arrays").
- **The artifact exercises everything you ask about.** If an item asks
  what a function does or why it is needed, the code must call it;
  otherwise only students who already know the answer can trace it.
- **No mode words.** The scenario never says "practice" or "exam". The
  conduct overlay says which it is (§5), so one scenario serves both.
- **For an exam, a source nobody can have seen.** A scenario adapted from a
  published past paper is not unseen, however well reskinned.

**Write the "Come prepared to" list.** The scenario ends with a numbered
list of what the student will be asked. It is the *public face of your
rubric*: each item should map to a criterion. Students who prepare against
it are doing exactly what you want; the interview's job is to check the
preparation is theirs (§7). Expect some students to arrive with a written
answer to the whole list and paste it as their first message; the plan
must still verify it one rung at a time (§4b).

Keep it compact. The student cannot see the scenario anywhere else — the
examiner reproduces it verbatim in the opening message, and a long scenario
makes a long first bubble.

### Worked example — "The Distinct Counter" (illustrative, not deployed)

> A classmate wrote this to count how many *distinct* values a
> `std::vector<int> V` contains:
>
> ```cpp
> auto it = unique(V.begin(), V.end());
> cout << it - V.begin() << endl;
> ```
>
> It compiles, and for many inputs it prints the right number — but for
> some inputs it does not.
>
> Come prepared to: (1) explain what `unique` does and what `it - V.begin()`
> counts; (2) give a 5-element `V` for which it prints the correct count and
> another for which it prints a wrong one, with the printed and true values;
> (3) state the bug precisely and give the minimal fix; (4) say what `V`
> looks like *after* the call; (5) compare the cost of the fixed version
> with using a `set`.

Every item maps to a rung and a criterion. There is a trap (students say
"`unique` needs a sorted range", which is true of the *intent* but not of
the function's contract — it removes *adjacent* duplicates on any range).
Witnesses are 5 elements. Nothing needs a compiler.

---

## 4. Step 2 — Write the examiner briefing

The briefing has three parts, in this order. Keep the headings; the
platform validates that a heading starting with `Rubric` exists.

### 4a. Model answer — "for your judgment only, never reveal"

Write the answer *you* would give, then verify every claim by hand. The
examiner will trust this text over the student, so a wrong model answer
grades every student wrong.

- State the precise rule, not just the bug: *"the fragment is correct
  exactly when every group of equal values is already contiguous; otherwise
  it over-counts."* A rule lets the examiner judge witnesses it has never
  seen.
- Give **verified** witnesses for both sides, traced: *`{1,1,2,2,3}` → prints
  3, true 3 ✔; `{1,2,1,2,3}` → no adjacent equals, prints 5, true 3 ✔.*
- Name the trap and the correct reply to it: *"unique needs a sorted range"
  → ask "what does unique promise on an unsorted range? try `{1,2,1}`."*
- List acceptable alternatives (`sort` then `unique`; `set<int>(V.begin(),
  V.end()).size()`; a loop with a `set`), and the bonus points (the tail of
  `V` after `unique` holds unspecified values; `V.size()` is unchanged, so a
  student who thinks `V` shrank has misunderstood the erase–remove idiom).
- Say which student claims are *fine* and which reveal a misconception, so
  the examiner knows when to probe and when to move on.

### 4b. Interview plan — numbered rungs, gates, traps, scaffolding

```
1. What does line 1 do and what does line 2 print? Gate: the student must
   say "adjacent" (or an equivalent) before moving on.
2. Correct 5-element witness, then a wrong one. For each: what is the
   printed value, what is the true count, walk me through the elements.
   Verify the trace yourself.
3. State the bug in one sentence and the minimal fix. Trap: "the range is
   not sorted" → "what does unique promise on an unsorted range?"
4. What does V look like after the call? Probe for "size unchanged, tail
   unspecified", not "V is now the distinct values".
5. Cost: sort+unique vs set vs unordered_set. When is each preferable?

Scaffolding: if the student cannot find a wrong witness, ask "put two equal
values apart from each other" — one hint only. If they cannot explain
line 2, ask what `unique` returns on {1,1,2} and where that iterator points.
```

Rules that came from real sessions:

- **Number the rungs and mark gates.** The examiner follows them in order
  and a gate stops it skipping ahead when a student volunteers a later
  answer.
- **Pre-write the probe for each trap** in the examiner's language. Left to
  itself, an LLM examiner tends to *state the correction* ("not quite — the
  range is sorted, the problem is…") instead of asking the question that
  makes the student find it.
- **Pre-write the one hint per rung**, and make it a *question*, not a fact.
- **Say what to do when a rung is out of reach**: spend remaining turns
  hardening earlier rungs, so the grade rests on evidence rather than on
  criteria the interview never reached.
- **Demand the working, not the claim.** "Walk me through it" for every
  witness. Untraced witnesses are the single most over-credited thing in
  our audit (§8).
- **Aim for a turn count** and write it into the plan ("aim for 6–9 student
  turns"). The platform's soft cap is advisory; the plan is what the
  examiner actually paces by.
- **One question per rung, one criterion per question.** A bundled rung
  ("which function is missing, what is the rule called, when does a class
  need none?") gets one answer; the examiner then moves on or closes, and
  the other parts score 0. In our exam audit a bundled last rung was the
  main reason a criterion scored 0 for a quarter of the cohort.
- **Nothing that must be asked goes last.** The last rung is the one lost
  to slow replies, late starts, early endings and the clock. Put a rung
  that carries its own criterion before the open discussion rung, or give
  the last rung a small weight.
- **Write the re-ask for the rung most likely to miss.** "One neutral hint
  per rung" in the conduct was not enough: the examiner closed after the
  first wrong answer instead of using it. Write the exact second question
  into the plan.
- **Plan for the prepared answer.** If the first message answers the whole
  task list, treat it as a set of claims: still take the rungs in order
  and ask for the working at each before moving on. Left alone, the
  examiner accepted such essays, skipped the middle rungs and closed after
  four answers.
- **Size the plan to the time students actually give it.** In a contest
  with coding problems, students first answered the viva 15–20 minutes
  after opening it (median) and left 15–45-minute gaps between answers.
- **If students can compile, ask what a compiler cannot tell them.** "What
  happens at line 3?" is answered by running the code (students pasted the
  runtime error); "why is that worse than the leak?" is not.

### 4c. Rubric

```
# Rubric

Weights sum to 100. Apply the course grading conventions.

- fragment_semantics (20): explains that unique removes adjacent
  duplicates and what the iterator difference counts.
- witnesses (25): a correct 5-element correct case AND a correct 5-element
  failing case, each with the printed value and the true count, traced.
  A witness with the wrong printed or true value caps this criterion at
  12; only one of the two witnesses caps it at 12.
- bug_and_fix (20): pinpoints that equal values must be adjacent (a
  contract mismatch, not a "sort is missing" error) and gives a correct
  fix. Diagnosing it as "unique requires a sorted range" caps this at 8.
- post_state (15): V.size() unchanged; elements past `it` are unspecified;
  the erase–remove idiom if they want the vector trimmed.
- cost_critique (20): sort+unique O(n log n) in place vs set O(n log n)
  with allocations vs unordered_set O(n) expected; a correct statement of
  when each is preferable earns the last few points.
```

- **Keys** are `snake_case` identifiers; the grader returns them verbatim in
  its JSON, and the admin page shows them. Four to six criteria is the
  sweet spot.
- **Weights sum to 100** and each criterion scores at most its weight. Say
  so; an LLM grader that is told "0–100" will happily score every criterion
  out of 100.
- **Caps for critical failures** are the most reliable lever you have
  ("caps this criterion at 8"). Graders apply them consistently; they apply
  vague instructions ("penalize heavily") inconsistently.
- **Repeat the grading conventions inside each criterion, as caps.** The
  conduct's conventions (§5: hinted answer = partial, examiner-supplied
  content is not evidence, unreached = 0) were in force for both of our
  exams, and the grader ignored them in roughly half the sessions — its
  grades came out 14–18 points above an independent grading. Write them
  where the grader cannot miss them: *"If the student reached this only
  after a hint, cap at 12. If the examiner stated the consequence first,
  cap at 8. Code the student did not explain caps this at 10. Not asked =
  0."*
- **Say what earns the last few points** — otherwise the grader gives full
  marks for a partial answer.
- Every criterion should be reachable by the interview plan; a criterion
  the plan never reaches scores 0 (and must — see §5).

### 4d. Per-problem carve-outs

The conduct profile (§5) sets course-wide rules; the briefing may *narrow*
them for this problem. Example: in practice mode our conduct lets the
examiner state a key point in one sentence after a rung is settled — but a
briefing whose witnesses are exactly what a retaker would paste verbatim
adds: *"never supply a concrete witness at any point; say at most which
values would need to be apart."* The briefing sits after the conduct in the
prompt, so it wins on specifics.

---

## 5. Step 3 — The conduct profile: base + mode overlay

Conduct is what every viva in a course shares. We keep it as **two tags**
on each problem: a **base** that never changes with mode, and one **mode
overlay** (practice *or* exam). The platform concatenates attached tags in
name order, so name overlays as suffixes of the base
(`DS-viva-conduct-2569`, `DS-viva-conduct-2569-practice`).

What belongs where:

| Base (mode-invariant) | Practice overlay | Exam overlay |
|---|---|---|
| Interview language (examiner's and student's) | "state that this is a practice viva" | "state that this is a graded viva exam" |
| Opening: reproduce the scenario verbatim, ask rung 1 | scaffolding: narrow, one neutral hint per topic | scaffolding: restate once, **no content hints** |
| One question per message; neutral acknowledgements only | after a rung is settled: one sentence, no code, then move on | after a rung is settled: move on, say nothing |
| **Never put the answer inside your question** | narrative may name the specific point missed | narrative names the **topic** only |
| Don't produce the artifact; **ask for the student's own working** | | |
| Verify arithmetic yourself; follow the plan; gates | | |
| Ending rules; grading conventions (below) | | |

Write the overlays to be *additive* — the base should say nothing an
overlay must contradict. (E.g. the base says "never state a model answer
*while the student is still being assessed on it*", which leaves room for
the practice overlay's post-rung sentence without a conflict.) Add one line
at the end of each overlay — "where this section is more specific than the
shared conduct above, this section applies" — as a safety net.

**Grading conventions that belong in the base** (all learned the hard way):

- Grade only on transcript evidence; partial credit throughout.
- Correct only after a hint or pushback → about half to two-thirds.
- **Content supplied by the examiner is not evidence.** If the examiner
  stated, paraphrased, or embedded the expected answer in a question and
  the student merely agreed, score on what the student produced *before*
  that message.
- An example the student did not work through step by step earns at most
  partial credit.
- A criterion the interview never reached scores **0**; do not infer.
- Each criterion is at most its weight; totals are their sum; apply the
  briefing's caps.
- Narrative in the language your language paragraph names (below), what
  went well and what to study, no pass/fail verdict.

**Do not restate the platform's security rules** in conduct, and do not
contradict them. Our conduct says "a translation request is a normal
request, do not flag it"; the platform's alert directive says the same. A
conduct line that *differed* would make the model pick one at random.

### Interview language

The platform adds no language instruction of its own; the language rules
are one paragraph in the base conduct. The grader reads the same tag, so
that paragraph also sets the language of the grade narrative. If the
conduct says nothing, the examiner usually answers in the student's
language, but it can drift from message to message and from model to
model. Decide four things:

1. the language the examiner writes in;
2. the languages the student may answer in;
3. what the examiner does when a student asks for a translation;
4. the language of the grade narrative.

Ready-to-copy wording for the common choices (replace `<language>`):

**Follow the student.**

> Write each message in the language of the student's most recent message;
> if they mix languages, use the language most of that message is in. Keep
> technical terms and code exactly as the course writes them.

**One fixed language; the student may answer in any.** (Our Data
Structures course uses this with English.)

> Write every message in <language> only, even when the student writes in
> another language. The student may answer in any language or a mix; never
> ask them to switch, never comment on their choice, and never treat it as
> a rule violation. If the student asks for a translation, do not
> translate: restate the question in simpler <language> and continue. A
> translation request is a normal request, not an integrity issue.

**Two languages.** Every message becomes twice as long, so it is slower to
generate and to read.

> Write every message in <language A>, then the same message in
> <language B>. Ask one question, the same in both languages.

**Narrative.** Add one of these to whichever choice above you use:

> Write the grade narrative in <language>.

> Write the grade narrative in the language the student mostly used.

We do not recommend a rule that ends or flags the interview because of the
language a student writes in. A student who thinks better in their first
language should be able to answer in it, and a language flag would compete
with the platform's alert rules (see the paragraph above).

Whichever you choose:

- **Put probe examples in the language the examiner writes in.** Our first
  conduct said "examiner writes English only" and then gave Thai probe
  phrasings as examples — one model imitated the examples and ran a third
  of its interviews in Thai.
- **Pilot it (§8) and check it in the audit (§9) after any model change.**
  A language rule is an instruction to the model, not a switch, and models
  differ in how well they follow it: under the same English-only rule, one
  model wrote Thai in 44 sessions and the next model in none.

---

## 6. Step 4 — Grounding (optional)

Use grounding for reference material the examiner must treat as
authoritative *and* cannot be expected to know: the course's own container
classes, "we do not use O-notation before week 8", a model solution PDF.
It is re-sent on every turn, so keep it short and attach it only to the
problems that need it. A clear scenario plus a clear briefing usually needs
none.

---

## 7. Step 5 — Caps and limits

- **Soft cap** ≈ number of rungs + 2 (a 5-rung debug viva: 7–8). The
  examiner is told to wrap up around it.
- **Hard cap** ≈ soft cap + 4. It is a cutoff, not a target; sessions that
  hit it usually did so by burning turns on scaffolding, and a plan whose
  last rungs were never reached zeroes those criteria.
- **Daily start limit** (the *start limit*): blank for the site default, a
  number for this problem, `0` for contest-only. Peeks (opened, never
  answered) are free; only sessions with at least one student answer count,
  and a session stops counting when staff use **Allow another attempt**.
  **For an exam, use `1`** — one counted session; staff can allow a second
  one by hand after an infrastructure failure. `0` also means one counted
  session during a contest, and none outside it. The two differ in one
  button: under `1` the student can press **End interview & get graded**;
  under `0` it is hidden, so nobody ends early to lock in a score before the
  harder questions. A practice value (3, 5) left on an exam viva lets
  students finish, restart and retake, and the best session counts. The
  count is per day, not per contest: practice sessions earlier the same day
  count, so keep an exam viva hidden until the exam.

---

## 8. Step 6 — Pilot before students see it

**Sit it yourself first — twice.** The problem edit page has a **Test-drive**
button (viva problems only, editors and admins; the admin problem index offers
it too). It opens a real interview with the real examiner and grader, but the
session is flagged as a test-drive: it does not appear in any report or score
table, its cost is not counted as student spend, it does not use up your daily
starts, and it can be restarted without limit. Take one test-drive as a strong
student and one as a weak student who gives the trap answer and needs the
hint. Then read each transcript, the grade narrative and the rubric JSON on
the admin page. Your test-drives are listed under **Test-drives** in the Viva
Exam card of the edit page. Check:

- [ ] The opening reproduces the scenario verbatim, including the "Come
      prepared to" list, and asks rung 1.
- [ ] One question per message; the plan is followed in order; the gate held
      when you volunteered a later answer.
- [ ] The trap probe was *asked*, not stated. You were asked to trace your
      witnesses; a wrong trace was caught.
- [ ] You received at most one hint per rung, and it was a question.
- [ ] The interview ended around the soft cap with a neutral close — no
      score, no summary of answers.
- [ ] The grade JSON has exactly your rubric keys, each ≤ its weight, total
      = sum; the hint you needed shows as a discount and is named in the
      narrative.
- [ ] The narrative is in your language and does not spell out the answer
      (exam) / names the specific point (practice), as your mode intends.

If the grader returned prose instead of JSON, or the keys don't match, the
briefing's `# Rubric` block is the first thing to inspect.

**Then a cold read — by someone who does not know the answer.** You and
your TAs cannot see what the text invites, because you read it with the
model answer in your head: one exam viva had six staff test-drives, and
students still hit three wording problems on the day (an answer printed
in the subtitle, a task word read two ways, a question about code that
never ran). Give the scenario alone — no briefing — to a reader who has
not seen it: a student from a past cohort, or a fresh AI chat told to
answer as a typical student of the course who has the course slides but
not the briefing. Note every copied example, misread word and answer
found in the text, and fix the scenario before anyone sits it.

**Check the rules, not just the answers.** Count, in your two test-drives,
how often the examiner asked two things in one message, put the answer in
its question, or explained after you failed; and whether the grader cut
your hinted answers and gave 0 for rungs never asked. What the models do
in two test-drives they do in most exam sessions — if a rule breaks here,
change the rung, the cap or the model; another sentence in the conduct
will not hold (§9).

---

## 8b. Before an exam — the gate

Run this the day before, for every viva in the exam, even one that has
run as practice for weeks. Each line is something that went wrong in a
real exam.

- [ ] Scenario: no "practice"/"exam" wording, no topic line or term that
      answers a criterion, no example you would not accept (§3).
- [ ] Conduct: base + the **exam** overlay attached (the import dry run
      prints both CONDUCT lines); no practice overlay.
- [ ] Start limit `1` (or `0`); problem hidden until the exam; no sessions
      today (§7).
- [ ] Source: not a published paper.
- [ ] Materials: decided whether slides and a compiler are allowed, and the
      plan asks what they cannot answer (§4b).
- [ ] Grader: the exam grading model chosen, and run on your weak-student
      test-drive; the hinted rungs came out discounted.
- [ ] Cold read done since the last scenario edit (§8).
- [ ] Every open item from the last audit fixed, or accepted in writing.
- [ ] Pairing with coding problems decided on purpose: if the exam also has
      a coding problem on the task the viva is about, write down how the
      two scores combine, and assume students will use the viva's scenario
      on the coding problem — it is on their screen. This is a decision,
      not a ban; §9 checks what happened.
- [ ] Post-exam audit planned (§9).

---

## 9. Step 7 — After launch: the audit loop

Transcripts are the feedback channel for your briefing. Once a week, or
after every ~50 sessions, read:

- **Alerted sessions** (admin list): are the flags real attacks, or
  translation requests and "can we skip this?" (both non-triggers)? A false
  positive under exam policy terminates an honest student.
- **Sessions at the hard cap**: what burned the turns — scaffolding, a
  student stalling, the examiner tracing for the student?
- **Very short high scores** (≤ 3 student turns, ≥ 90): almost always a
  pasted omnibus answer that the examiner accepted without re-verifying.
- **Narratives**: do they leak the answer? Retakers read them.
- **Grader calibration**: pick five transcripts and re-grade them yourself
  against the rubric; disagreements of more than ~10 points point at a
  rubric line, a missing cap, or a grader model to change.
- **After every exam, an independent-grade sample.** Grade about 30
  sessions yourself (or with a careful reader) *before* looking at the AI
  grade, then compare: the mean gap, how many differ by more than 10, and
  why. In our first exam audit (286 sessions, two problems) the AI grade was
  14–18 points higher in every score band and never lower — yet it ranked
  students almost the same way (rank agreement 0.90–0.94). A generous but
  well-ordered grader is fixable; you only learn which kind you have by
  looking.
- **After an exam that paired the viva with a coding problem on the same
  task, the overlap.** Compare the distinctive lines of the scenario's code
  with that problem's submissions, split by whether each was made before or
  after the student opened the viva; also compare who took the viva with
  their coding scores. In our first such exam (a "fix this code" viva next to
  the coding problem it was built on, scored as the higher of the two), 49
  of 116 students submitted the scenario's buggy code to the coding problem
  — none before opening the viva, 23 before answering any question — and
  most students who already had full marks on the coding problem never
  answered the viva.

**Close the loop.** Every finding becomes a rule in this guide, a line in
the gate (§8b), or a backlog item — and the next audit checks whether it
held. Eight of the failures in our first exam audit were already rules
here, written a week before the first exam; writing them down had not
stopped them, because the models ignored them and nothing checked.

Split every statistic by **examiner model**: in our first audit the
proportion of sessions hitting the hard cap went from 42% to 3% across a
model change with the *same* prompt. Compliance is largely a model
property; fix the model before you fix the prompt.

Then decide which layer the fix belongs to: briefing (this problem's trap,
hint, witnesses), conduct (every problem in the course), or platform (a
code change — file it in the repo's backlog).

### After you change a briefing: regrade, never lower

A briefing or conduct edit changes what the grader reads, so sessions graded
before it were graded under a different rubric. Regrade them in one batch
rather than one Re-run at a time, and let the platform keep the higher grade:

1. Apply the new briefing (kit import or the edit form).
2. Dry run: `bin/rails viva:regrade PROBLEM=<name>` lists how many sessions
   are stale under the new rubric and an estimated cost. Add
   `CONTEST=<name>` to touch one exam cohort only, `LIMIT=5` to rehearse.
3. Apply: the same command with `APPLY=1`; when the queue is empty,
   `bin/rails viva:regrade_status BATCH=<id>`. Read the old / new / final
   means and the *down* count before announcing anything.

Two rules the platform enforces for you: a student keeps whichever **whole**
grade record scores higher (points, breakdown and narrative together), and
nothing is deleted — every run stays in the session's grade history, and
`viva:regrade_revert BATCH=<id>` puts a batch back. Expect noise: the same
transcript regraded by the same model moved by SD 4 points in our first
cohort regrade, so a small rubric edit plus a plain regrade would lower some
students by luck; that is what never-lower is for. Use `REPLACE=1` only when
the old grades are wrong in kind (a hijacked grader, a broken rubric), not
merely different.

---

## 10. Pitfalls catalogue

Every row is something we observed on real student sessions
(2110211 Data Structures: practice vivas, Aug–Sep 2026, 182 sessions; three
exam vivas, Sep–Oct 2026, 395 sessions).

| Symptom in the transcript | Cause | Fix (layer) |
|---|---|---|
| Examiner writes in the student's language although told not to | Weaker model imitating Thai probe *examples* in the conduct | Examples in the examiner's language (conduct); stronger model |
| "Excellent! Exactly right!" after every answer | Model's default register; running assessment revealed | "Neutral acknowledgements only — no praise, no 'correct', no 'not quite' while a rung is open" (conduct) |
| Examiner states the fix after the student fails, then asks the next question | No rule about what happens *after* a rung is settled | Base: never state a model answer while it's being assessed; overlay decides post-rung behaviour (conduct) |
| "So the fix is X, right?" → "yes" → full marks | Leading yes/no question | "Never put the answer inside your question" (conduct) + "examiner-supplied content is not evidence" (grading) |
| Witnesses accepted untraced; omnibus first message scores 100 in 2 turns | Examiner skips the trace demand; grader credits claims | "Ask for the student's own working" (conduct); "untraced example = partial at most" (grading); pilot with a pasted answer |
| Sessions hit the hard cap with rungs 4–5 never asked | Scaffolding burn; examiner tracing for the student | Pre-written single hints; "if out of reach, harden earlier rungs" (briefing); model change |
| Interview ends at turn 4 with thin evidence | Stronger model over-corrects on pacing | "Do not end while a criterion rests on an unverified claim" (conduct) |
| Grade narrative spells out the fix; retakers score 30 → 92 in 20 minutes | Narrative written as feedback, read as an answer key | Exam overlay: topic only. Practice: your call — we keep it, with per-problem carve-outs for witnesses |
| Criterion scored 8/20 for a topic never discussed | Grader infers | "Unreached criterion = 0" (grading) |
| Rubric JSON has every criterion out of 100, total 94 | Grader followed a "0–100" schema hint | "Each criterion at most its weight" (grading); the platform validates weights |
| Translation request / "what does viva mean?" / "skip this?" flagged as jailbreak | Weaker model over-triggering | Do not duplicate or contradict the security directive in conduct; stronger model; review flags before enabling exam policy |
| Perfect LaTeX-formatted essay 81 seconds after "I have no idea what upper_bound is" | External LLM paste | Not a prompt problem: environmental control for exams; for practice, treat scores as formative |
| Student abandons the moment the examiner corrects them, restarts, scores 94 | Every adaptive interview is an oracle | Exam: single attempt. Practice: accept, or rotate scenario parameters between attempts |
| Examiner announces "the interview is over" but the session never ends | Model omitted the end-of-interview token | Platform issue; report it — a stronger model fixed it |
| A correct but *different* design scores low on the container criterion (Quiz 1, 2026-09-09) | Briefing named one design; the grader treated the equivalent alternative as wrong | Name **every** acceptable design in the model answers and in the criterion text; if found after the exam, regrade under a never-lower rule (briefing + operation) |
| Same transcript regraded: 74 → 63, 31 → 42; SD 4 points over 157 sessions | Grader rerun noise (gemini-3.7-flash), not the rubric | Treat one grade as ±10; never "fix" a cohort with a small rubric edit and a plain regrade — keep the higher record (policy); consider averaging two grading passes for exams |
| Rubric wording or a probe only turns out to be confusing once real students hit it | Viva published without anyone sitting it | Take two test-drives first — strong and weak student — via the edit page's Test-drive button; read both narratives (authoring) |
| Grades need redoing after a briefing fix, but a plain re-run would lower some students | Re-run replaces; rerun noise is about ±10 per grade | Batch `viva:regrade` (never-lower by default, stale sessions only); read `viva:regrade_status` before announcing (operation) |
| Students retake the exam viva and the better score counts (Quiz 2, 2026-10-07: 80 → 94, 74 → 83); the examiner greets everyone with "practice viva" | A practice viva reused for an exam kept its practice start limit (5) and its scenario's "practice viva" line | Before the exam: start limit `1` (or `0`), scenario and conduct overlay switched to exam wording; during it, the contest's **Viva check** page flags *Retook* live (operation) |
| Many students open with exactly the wrong design the scenario gave as an "e.g." (exam, 2026-09-09) | An example in the task text that is itself a wrong answer | Only examples you would accept, or neutral ones; cold read (scenario) |
| The name a criterion asks for is printed in the scenario's subtitle (exam, 2026-10-07) | Topic/deck metadata left in the student-facing text | Topic and source lines go in the briefing or README (scenario) |
| Asked what else a class needs "to be safe", students list features of the course's own container class | A task word with two readings, one pointing at course material | Name the thing asked for; cold read by someone without the briefing (scenario) |
| The last criterion scores 0 for a quarter of the cohort | Bundled last rung; examiner closes after the first reply and never re-asks | One question per rung; not last; the re-ask written into the plan (briefing) |
| First message answers the whole task list; the examiner closes after four answers | The "Come prepared to" list invites an essay; the examiner treats it as verified | Plan: a prepared answer is a set of claims — rungs still in order, working at each (briefing) |
| Students paste the runtime error ("double free detected") as their answer | A compiler is open during the exam for the coding problems | Ask what the compiler cannot answer, or decide compiler access before the exam (briefing + operation) |
| Pasted course-slide code, unexplained, gets 22–25 of 25 on the fix criterion | Grader credits code as understanding | "Code the student did not explain caps this at N" in the criterion (rubric) |
| AI grade 14–18 points above an independent grading in every score band, never below, on two exams | Grader ignores the conduct's conventions (hint discount, examiner content, unreached = 0) | Repeat the conventions as caps in each criterion; test the grader on a weak test-drive; independent-grade sample after every exam (rubric + operation) |
| Six staff test-drives passed, yet students hit three wording problems on the day | Every test-driver already knew the answer | Cold read by someone who has not seen the briefing (authoring) |
| Rules written a week before the exam broken in most sessions (leading questions, explaining after a failure, two questions per message) | Prompt rules are requests; the models ignore some, and nothing checked | Count rule breaks in the test-drives; change the rung, cap or model; the gate (§8b) and the post-exam audit check that the rule held (operation) |
| Students submit the viva scenario's code to a coding problem of the same exam (exam, 2026-10-21: 49 of 116) | The scenario shows most of the coding problem's answer, and both are open at once | Decide the pairing and how the scores combine before the exam; check the overlap afterwards (§8b, §9) (operation) |

---

## 11. Bulk authoring with a kit

For a course, keep scenarios, briefings, conduct and grounding as markdown
files in a kit directory with a `manifest.yml`, and import with
`bin/rails viva:import DIR=<kit>` (report only) then `APPLY=1`. The import
is idempotent by problem name, conduct-tag name and grounding title;
`available` is applied on create only; links are add-only. Conduct is a
list — one base plus one overlay:

```yaml
conduct_tags:
  - {name: DS-viva-conduct-2569,          file: _conduct.md}
  - {name: DS-viva-conduct-2569-practice, file: _conduct.practice.md}
```

Two operational notes: the kit is *data* — the deployment pipeline ships
code, and a kit reaches a server's database only when you copy it there
and run the import on that host. And the dry run should list every conduct
tag you expect before you `APPLY`; an importer older than the list form
skips the block silently.

---

## 12. Checklist

- [ ] Scenario: one artifact, a trap, hand-traceable witnesses, a "Come
      prepared to" list that maps to the rubric; nothing in it answers a
      criterion, every example acceptable, every task word one reading, no
      mode words.
- [ ] Briefing: verified model answer with the precise rule; numbered rungs
      with gates, one question each, nothing essential last, pre-written
      trap probes, single hints and the re-ask; a plan for the prepared
      answer; `# Rubric` with snake_case keys, weights summing to 100, caps
      (the grading conventions repeated as caps), "last few points".
- [ ] Cold read by someone who has not seen the briefing.
- [ ] Per-problem carve-outs where the conduct's mode overlay is too
      generous for this problem.
- [ ] Conduct: base + one mode overlay attached; overlays additive; a
      language paragraph (examiner, student, translation, narrative) with
      probe examples in the examiner's language; grading conventions in
      the base.
- [ ] Caps sized to the plan; start limit chosen (`1`, or `0`, for an exam);
      grounding only if needed.
- [ ] Reusing a practice viva for an exam: start limit, scenario wording
      ("practice viva") and conduct overlay all switched to the exam versions.
- [ ] Piloted twice (strong, weak); transcript and rubric JSON read; rule
      breaks counted (examiner and grader).
- [ ] For an exam: the gate (§8b) run the day before.
- [ ] First audit scheduled after ~50 sessions; statistics split by model;
      after an exam, an independent-grade sample; every finding closed into
      this guide, the gate or the backlog.
- [ ] After any briefing change on a live problem: `viva:regrade` dry run,
      then `APPLY=1`, then read the status report.
