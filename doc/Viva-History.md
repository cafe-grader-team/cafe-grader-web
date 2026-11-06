# Viva — Change History

What we changed in the viva feature, why, and how it turned out. Newest first.
This is the *timeline*; design rationale lives in `doc/Viva-Exam.md` (Decision
Log), the problem-setter craft in `doc/wiki/viva-authoring-guide.md`.

**How to add an entry** (rule in `CLAUDE.md` → "Viva Live Docs"): any commit
that changes viva behavior, prompt text (conduct tags, briefings, kit files),
the model or provider behind turns or grading, or access/alert policy adds an
entry here *in the same commit*, shaped **Problem observed → Change →
Outcome / status**, with refs. When an entry supersedes an earlier one, mark
the old one `SUPERSEDED YYYY-MM-DD by …`; never delete. Rev numbers are local
hg revs of `~/cafe-grader/web` (master unless marked `chula_cp`); kit and
conduct edits cite `course-prep rev N` (the local `~/cafe-grader/course-prep`
repo, started 2026-09-02).

## Eras at a glance

| # | Era | Dates | Characterization |
|---|-----|-------|------------------|
| 7 | Audit & conduct split | 2026-08-29 → 09-02 | Grade-JSON schema check; full-transcript audit of the first live problem (182 sessions); conduct tag split into base + mode overlay; importer `conduct_tags:`; `course-prep` under hg; History + authoring guide seeded. |
| 6 | First student trial → fixes, bake-offs, 4.5.0 | 2026-08-23 → 08-28 | Grade default → gemini-3.1-pro; engaged-only daily limit + End button + narrowed alert triggers; English-only examiner; abandoned-session reaper; AI-gateway provider family; prompt hardening and the flip to gemini-3.7-flash (prod 08-27 22:47); kit grounding; markdown editor; release 4.5.0. |
| 5 | Kit + production launch | 2026-08-15 → 08-22 | Kit importer; completion caps raised after a real truncation; `practice-2569-1a` authored (conduct tag + 9 briefings); imported to prod 08-22; first student sessions that evening. |
| 4 | Deployment-readiness redesign | 2026-07-19 → 07-21 | `GroundingMaterial`; designs D1–D9; Phase 1 (`viva_prompt` column, `viva_conduct` tag kind, detect-only alerts, turn caps, practice/exam toggle) — then the same-week pivot that deleted the toggle for a per-problem daily start limit; authorization gates; docs wave. |
| 3 | Pilot content | 2026-06-10 | Five DS pilot scenarios under the old `llm_prompt`-tag scheme; no platform change. |
| 2 | Hardening sprint 1 | 2026-05-05 → 05-25 (released 4.4.0, 06-11) | `Llm::Request` hierarchy, error visibility, scenario-in-description, markdown rendering, setup validation, soft archive, model picker, stuck-turn recovery, first jailbreak directive, owner-only answering, PDF hidden. |
| 1 | Birth | 2026-04-19 → 05-04 | Feature lands in one commit: `viva_exam` type, `viva_turns`/`viva_grades`, abstract turn/grade services + Chula Genie wiring; prompts in `llm_prompt` tags; PDF is the scenario. |

## Lineages (the same story told per thread)

- **Prompt storage:** `llm_prompt` tag (04-19) → description added as scenario (05-05) → PDF declared the canonical scenario (05-08, 05-12) → `viva_prompt` column + `viva_conduct` tag, scenario = description, PDF = figures only (07-20/21) → conduct split into base + mode overlay (09-01).
- **Alerts and consequences:** none (04-19) → detect *and* terminate inside the prompt (05-20) → detect-only in prompt, backend decides — warn-then-terminate in exam, log in practice (07-21) → `exam_policy?` hardcoded false pending Phase B (07-21) → triggers narrowed and non-triggers listed after the first trial (08-25) → audit: false positives on listed non-triggers persist on gemini-2.5-flash, none on 3.7-flash (09-01).
- **Models actually running in prod:** turns gemini-2.5-flash via Genie (08-22 → 08-27 21:46) → gemini-3.7-flash via Chula AI Gateway (08-27 22:57 →). Grades: 2.5-flash → 3.1-pro (08-23 → 08-27) → 3.7-flash (08-27 →) → gemini-4-argon (chula_cp 2273, from its deploy; grounding extraction moves with it). The Claude-Sonnet turn default (chula_cp 2010) never ran in prod.
- **Pacing (Buggy Counter, completed sessions):** 2.5-flash median 10 student turns, 42% at the hard cap → 3.7-flash median 6, 3% at the cap, 55% inside the 6–9 target. Same prompt.
- **Retakes:** single attempt + admin archive (05-09) → practice self-restart 3/day, exam single attempt (07-20, lived one day) → per-problem daily limit, everyone restarts (07-21) → engaged sessions only count (08-25) → best-of-N recorded score confirmed as policy; audit shows it invites grinding (09-01) → DS Quiz 2 retakes under a leftover practice limit; one start rule (`Viva::StartPolicy`), limit 0 = one counted session in contest mode, Restart only when a new start is possible, staff "Allow another attempt" (10-07).
- **Still open / never built:** D7 authoring lint (the test-drive half shipped 09-23); red-team regression set; Phase B (per-contest retake budgets, governing-contest snapshot, window-end force-finish — its manual precursor, the contest page's "Finish open vivas" button, shipped 09-23); viva in problem export/import; persistent scenario panel; session wall clock; grade-JSON validation against rubric *weights* at grading time (detection on the contest's Viva check page shipped 10-07).

---

## Entries

### 2026-11-06 — What the viva measures (three hypotheses) and OpenAI models through Codex; nothing switched
**analysis, no code or config change** · course-prep `viva-talk-2026-11-06/viva-learning-analysis-2026-11-06.md` (with `viva-misreading-2026-11-06/`) and `model-eval/2026-11-06-codex-openai/`; every model result so far is tabled in course-prep `model-eval/README.md`
- **Problem observed:** for the 2026-11-06 Chula AI Gateway showcase talk: does the viva credit understanding that the coding problems miss, does practising vivas help, and what do misread or half-answered questions cost? And how would OpenAI's models (dae has Codex only, no API key) grade and examine?
- **Change:** none to the platform. Findings: a viva score predicts the next quiz's coding score beyond that quiz's own coding score in all three quiz pairs (+2.7 to +4.4 coding points per 10 viva points); a practice effect cannot be measured (9 in 10 students practised); in 191 of 394 exam vivas the examiner moved on without the unanswered part of a multi-part question, honest misreadings were 7, and only 3 sessions reached the hard cap. OpenAI, on 90 of the reader-graded exam sessions: gpt-6-astra +1.2 and gpt-6.1-sol +1.5 points above the reader grade (argon +4.8 on the same 90); as examiner neither put two questions in one message (argon 9 of 34), but both ended the session at only 1 of 6 closing points (3.7-flash 6 of 6).
- **Outcome / status:** no switch; neither OpenAI model is on the Gateway. The misreading policy is the backlog entry "Viva misreadings — three cases". From this entry on, studies live in course-prep, not in `doc/` (CLAUDE.md, "Viva & Assist Live Docs").

### 2026-11-03 — Practice and used exam vivas copied to cedt; old-style test vivas marked archived
**prompt text (course content, another host)** · no code change; prod data on cedt-grader 10.0.5.80 (vivas + tags) and comprog-grader 10.0.5.52 (tags only)
- **Problem observed:** cedt (CEDT's 2110328, the combined DS + Algo course) had no working viva: one old-style problem, `viva_basic`, whose prompt still sat in an `llm_prompt` tag (the scheme from before `problems.viva_prompt`), and no conduct tags. comprog had four hidden old-style test vivas of the same kind.
- **Change:** copied from 10.0.5.50's live database, not from the course-prep kits (the kits lag prod edits, e.g. the 2026-10-06 base-conduct text and problem 701's Quiz 2 changes). An export script dumped the rows, generated kits replayed them through `viva:import` with a dry run first, and the problems were created hidden. Copied: the nine practice vivas 693–701, plus only the exam vivas already used in an exam on 10.0.5.50 — 705 Cell Detection (d69_q1) and 721 split fix (d69_q3); 701 also ran in d69_q2. 720 `d69_v1_split_own_code` was never used, so it was NOT copied. **Rule (dae 2026-11-03): an exam viva leaves 10.0.5.50 only after it has been used there** (in a contest, with student submissions); the export script refuses an exam viva that fails that check. The three conduct tags went to both hosts byte-identical (comprog gets them unattached, as a reference). The old-style vivas were kept but marked: full name prefixed `[ARCHIVED – delete soon]`, their prompt tags renamed `ARCHIVED-delete-soon-*`.
- **Outcome / status:** on cedt, all 11 problems match 10.0.5.50's scenario and briefing text, conduct links and grounding, with no `viva_setup_errors`; all are hidden until dae makes them visible. cedt's archived `viva_basic` is still visible to students. Next: example vivas for comprog's Python course (not started; dae approves the scope first).

### 2026-10-31 — Buggy Counter briefing: a broken `upper_bound` precondition is undefined behaviour, not "unspecified"
**prompt text (course content)** · course-prep rev 36 (`data-structures/viva/practice-2569-1a/01-buggy-counter.briefing.md`, kit `README.md`); prod: problem 693's `viva_prompt` only
- **Problem observed:** in the 2026-10-31 blind read (next entry) a reader noted that the briefing calls the result of searching an unsorted range "unspecified" and says it "will not crash", in the model answer, plan step 4 and the `precondition_reasoning` criterion. Standard C++ makes a violated library precondition undefined behaviour, so a student who answers "undefined behaviour" is right — and one examiner reply (gemma-4-31b) told such a student it is not undefined behaviour.
- **Change:** all three places now say undefined behaviour, describe the practical effect (an iterator inside the range, a count right or wrong by luck, no out-of-range read), accept "undefined behaviour", "unspecified" and "a wrong result" equally, and tell the examiner never to call undefined behaviour wrong. The "it still works" probe is unchanged.
- **Outcome / status:** live on prod 2026-10-31 ~21:40: dae copied the file to `~/viva-kits/practice-2569-1a/` on 10.0.5.50 and set problem 693's `viva_prompt` from it with one `bin/rails runner` `update!` (checked: the stored text equals the file). The kit must not be re-imported as a whole: its `_conduct.md` predates the 2026-10-06 base-conduct text that quiz-2569-3 carries (a full import would shrink the shared `DS-viva-conduct-2569` from 6,138 to 6,004 characters), and problem 701 was changed for Quiz 2 since the kit was written. Update only problem 693's `viva_prompt` from the file; the dry run's only change for 693 is `viva_prompt`.

### 2026-10-31 — Department LiteLLM models tested for viva: deepseek-v4.1-flash is the only candidate; nothing switched
**analysis, no code or config change** · study `doc/dept-model-viva-test-2026-10-30.md`, data in course-prep `dept-litellm-viva-2026-10-30/`; design `docs/superpowers/specs/2026-10-30-multiple-ai-gateways-design.md` §4.10
- **Problem observed:** the department's LiteLLM (`http://10.0.5.92:4000`) serves qwen3.5 and gemma-4-31b (free to run) and glm-5.3 and deepseek-v4.1-flash (Huawei, paid). Could any of them run viva grading or replies?
- **Change:** offline test on the 2026-10-29 sessions and reply points. Grading (316 sessions with a reader grade): deepseek +5.3 above the readers (argon +5.6, 3.7-flash +14.5), gemma +3.7 but scattered, glm +5.8 but 17 failed calls and two minutes per grade, qwen +10.2. Replies: deepseek as fast as 3.7-flash (median 3.4 s, opening 5 s); gemma 10 s alone and 33 s with 30 at once; glm 33 s; qwen broke 4 of 40 (three empty, one looping). Blind read: deepseek and gemma level with 3.7-flash on most faults, but both answered in Thai on 693 (4 of 40 each, 3.7-flash 0) and deepseek gave running verdicts in 11 of 40 (3.7-flash 4). Huawei refused 9 of 30 simultaneous deepseek replies (4 requests per second); Quiz 3's peak would have hit that limit about twice, and the grader does not retry a 429. dae raised the department LiteLLM's retries (4, at least 1 s apart): 28 of 30 then got through.
- **Outcome / status:** no switch. Before deepseek could take a viva role: the grader-side 429 retry (design §4.10) for the remainder, and a fix for its Thai replies and running verdicts. The read also found the Buggy Counter briefing error above.

### 2026-10-29 — Viva grading and grounding extraction move to gemini-4-argon; replies stay on 3.7-flash
**model change (deployment config)** · chula_cp 2273 (`config/llm.yml`); study `doc/gateway-model-test-2026-10-29.md`, data and report in course-prep `gateway-argon-2026-10-29/`
- **Problem observed:** the AI grade ran 14–18 points above an independent reading in the 2026-10-18 audit and about 10 above in Quiz 3, and the exam overlay's narrative rule was broken in most Quiz 3 narratives (backlog "Exam viva grading"). On 2026-10-29 the Gateway began serving `gemini-4-argon` and `gemini-3.8-flash`.
- **Change:** offline test of both against 3.7-flash on today's prompts (US$19.48 of gateway credit). Grading, over the 316 exam sessions that have a reader grade: argon +5.6 points above the readers (Q1 +2.7, Q2 +9.0, Q3 +3.0), 3.8-flash +10.8, 3.7-flash +14.5; same rank order (0.96–0.97); argon steadiest across three runs (typical change 1 point) and fastest (5.6 s, US$0.017 per grade); on Quiz 3 argon's narratives named `mLess` in 4 of 30 sessions against 22 for 3.7-flash. Extraction: argon copied 97–100% of the slides' code on four of five decks. Examiner replies (40 points from real sessions, read blind): argon is better on the audit faults — accepts unchecked work 2 times in 40 against 6–7, ends with a plan step open 1 against 4–6, explains after a failure 0 against 1–3, gives the answer away 1 against 3–4 — but narrows the search more often (13 against 5–7), bundles questions, takes 20 s for an opening against 9 s, altered the scenario code in one of 13 openings with code, and its two runs of 30 simultaneous replies disagreed (slowest 37 s, then 9 s). dae 2026-10-29: `viva_grade` and `grounding_extract` → gemini-4-argon; `viva_turn` stays on gemini-3.7-flash; argon added to the roster, so the admin Re-run grading picker offers it.
- **Outcome / status:** committed and pushed (chula_cp 2273); live from the cp-grader deploy. Grades of this semester's remaining quizzes will be stricter than Quizzes 1–3 were (dae accepted). Before argon may take the examiner replies: a simultaneous-load test at exam hours and a decision on the altered-code risk (backlog). Quiz 2's +9 remains.

### 2026-10-28 — DS Quiz 3 post-exam: the viva shared the quiz with its own coding problem (an experiment); AI grade about 10 points high; the `std::greater` re-ask rarely works
**analysis + docs, no code or prompt change** · course-prep `data-structures/viva/quiz-2569-3-postexam-2026-10-28/` (`report.html`, `tools/`, `regrade-sample/`); authoring guide §8b, §9, §10; `doc/backlog.md` (Exam viva grading, rule-break notice wording); kit `quiz-2569-3/README.md`; local prod copy refreshed 2026-10-28 22:34
- **Problem observed:** contest 47 `d69_q3` (2026-10-21) ran viva C `d69_v1_split_fix` (problem 721) in the same quiz as the coding problem it was built on, `d69_q3a_heap_split` (724), with the split score = the higher of the two — a deliberate experiment (dae 2026-10-28); the kit had recommended C alone, and A was never used. Running: 129 sessions, 109 answered and graded, no retakes, no failed replies or grades; examiner and grader gemini-3.7-flash; a provider slowdown 10:22–10:32 made 31 replies wait 45–145 s; "Finish open vivas" was not clicked, so the 24-hour reaper graded 15 answered sessions the next day; openings correct in all 129 (exam wording, full scenario, Thai translation). **The experiment:** 49 of 116 students submitted the scenario's buggy code to 724 — none before opening the viva, 23 before answering any question; 9 of them reached 100 on 724. Under the higher-of-two rule the viva decided the split score for 69 students and 724 for 78; 14 students' split score rests on 724 code taken from the scenario after opening the viva; the 41 who never answered the viva averaged about 89 on 724 against 37 for those who did. **Grading:** a blind sample of 30 sessions (two reader agents with the 2026-10-18 reader instructions; 5 of the 30 also graded blind in-session, agreeing with the readers within 8 points) gives AI 44.6 against 34.7: +9.8 on average, never lower, more than 10 higher in 11 of 30, ranked almost the same (rank agreement 0.95); the gap grows with the score (+5 in the bottom third, +11 middle, +14 top). Main causes: credit for examples that are not valid heaps (13 of 30 right-result and 11 of 30 wrong-result examples; the examiner never checked heap validity) and for untraced claims; 65 of 109 narratives name `mLess` and 51 describe the re-check bug, against the exam overlay. Examiner: accepted untraced examples in 17 of 30 sampled sessions, explained after a failure in 6, gave the briefing's own witness array in 6 of all 109. **The problem itself:** the rung-5 `std::greater` re-ask rarely brings out bug 2 — most students asked it answered "1, 3", reading "less than `value` in the queue's own order" as plain numeric order; in the sample, 10 of 30 found the comparator bug unprompted and 2 after the re-ask.
- **Change:** authoring guide — §8b a gate line to decide the pairing of a viva with a same-task coding problem on purpose (dae 2026-10-28: a check, not a hard rule), §9 the post-exam overlap check, §10 a pitfall row; reusable check `tools/scenario_overlap.rb` (finds 48 of the 49 with default settings); kit README records what ran; skill `course-viva-prep` points to the check. Backlog: the rule-break notice says "In practice mode" during exams; narrative leaks added to "Exam viva grading".
- **Outcome / status:** open for dae — the 724 scores of the students who used the scenario code (recommended: leave as is; the rule was announced and the quiz showed the code); before any reuse of 721, a plan rung that checks heap validity of every example and a clearer `std::greater` re-ask; the exam grading fix (backlog) now has a third measured exam, and the gap is largest for the highest grades.

### 2026-10-19 — DS Quiz 3 `split()` vivas: three authored, A and C imported to prod (hidden); first exam overlay on prod
**prompt text (course content) + production operation** · course-prep rev 34 (kit `data-structures/viva/quiz-2569-3/`, verification code `data-structures/drafts/pq-split/`); prod 10.0.5.50 `viva:import` of an A+C-only copy in `~/viva-kits/quiz-2569-3`
- **Problem observed:** dae wanted one Quiz 3 problem (`CP::priority_queue::split`) to have both a coding and a viva part. The first idea — student does either, the higher score counts — was rejected after discussion: the parts measure different abilities (implementing vs explaining), the viva grade is the noisier and more generous one (2026-10-18 audit: +14–18), and a viva's questions teach the code.
- **Change:** three vivas, a contest uses at most one. **A** `d69_v1_split_own_code` "Explain your split()": the student pastes the `split()` they submitted and is interviewed on their own code; score 70% coding + 30% viva; the coding score counts only submissions made before the student's first viva message (enforced after the exam by a read-only check). **B** `d69_v1_split_method` "How would you split?" (standalone design viva) and **C** `d69_v1_split_fix` "Fix this split()" (standalone debug viva, two bugs: the freed slot is never re-checked; `<` instead of `mLess`) — B and C reveal the method, so never with the coding problem. Hidden `mLess` check in all three without naming it. First kit built under the 2026-10-18 rules: a cold read of every scenario by a fresh agent (fixed: sorted and subtree-shaped examples, unclear submit/attempt wording, backtick fences — the backtick key switches language on Thai Windows —, list items that named weak spots or gave away the method's shape), all traces verified by running the code, caps inside each criterion, the exam overlay. Prod import (dae: A and C only): created tag `DS-viva-conduct-2569-exam` (the first exam overlay on prod) and the two problems, `available=false`, start limit 1; base tag `DS-viva-conduct-2569` unchanged (the kit carries an exact copy of prod's 2026-10-06 text). B is not on prod.
- **Outcome / status:** test-drives pending — A with four student codes (`testdrive/`), C with two. Decision rule: A with the coding problem if its test-drives pass, else C alone. Open for dae: the "lower priority than `value`" wording proposed by both cold reads (not applied). *(2026-10-28: what ran instead was C in the same quiz as the coding problem, scored as the higher of the two — see the 2026-10-28 entry.)*

### 2026-10-18 — Full audit of both exam vivas: the AI grade runs 14–18 points high; authoring lessons and an exam gate
**analysis + docs, no code or prompt change** · report and data in course-prep `data-structures/viva/exam-audit-2026-10-18/` (`report.html`, 13 batch findings, tools); authoring guide §3, §4b, §4c, §8, new §8b, §9, §10, §12; backlog "Contest checklist" items and "Exam viva grading" entry
- **Problem observed:** every exam session with a student answer was read in full — 143 of problem 705 Cell Detection (Quiz 1, contest 43) and 143 of problem 701 Rule of Three (Quiz 2, contest 46) — by 13 Claude reader agents, each writing its own grade from the transcript *before* opening the AI grade. The AI grade (gemini-3.7-flash) was higher by a mean of 14.3 (705) and 17.8 (701) points, more than 10 points higher in 208 of 282 graded sessions, never lower; but it ranked students almost the same way (Spearman 0.94 / 0.90). Causes, in sessions: no hint discount (51 / 69), credit for examiner-supplied content (42 / 61), credit for unreached criteria (41 / 11), unexplained or pasted code credited (13 / 39) — all conventions already in the base conduct since 09-02. The viva agrees with the coding problems as much as two coding problems agree (rank correlation 0.33–0.47 vs 0.30–0.40; Q1 viva vs Q2 viva 0.42 = Q1 coding vs Q2 coding). 705: 59% never reached a working design; queue delays in 109 sessions; the scenario's own example type (`map<pair<int,int>, bool>`) was the commonest wrong opening. (Corrected 2026-10-18: the readers also reported that no 705 opening carried the Thai translation the conduct requires — not a failure: that rule was added to the prod base tag only on 2026-10-06 22:49, in the web form, after Quiz 1 and with no History entry; it was in force for Quiz 2.) 701: the examiner said "practice" in 143/143; the rule's name sat in the scenario subtitle; task 6's word "safe" sent students to `CP::vector`'s `mCap`; the naming rung was always last and bundled, and the examiner closed after the first reply (named by 53 of 128 asked); 12 students pasted runtime output of the viva's code; no sign of copying between students (repeated text = deck 09 slides and the two retakers' own first answers). Eight of the failure kinds were already rules in the authoring guide (09-02); six staff test-drives of 701 had not caught its wording problems.
- **Change:** authoring guide — scenario checks (nothing in the text answers a criterion; only acceptable examples; one reading per task word; the artifact exercises what is asked; no mode words; unpublished source for exams), plan rules (one question per rung, nothing essential last, written re-ask, the prepared-answer case, timing, compiler-proof questions), rubric rule (repeat the conventions as caps per criterion), the cold read and rule-break count in the pilot, a new pre-exam gate (§8b), the post-exam independent-grade sample and "close the loop" (§9), ten pitfall rows. Backlog: concrete items for the contest checklist; an exam-grading entry (stronger model or two passes, tested on this audit's 286 transcripts). Skill `course-viva-prep` updated to match (not under version control).
- **Outcome / status:** dae 2026-10-18: the automatic pre-exam checks and the exam-grading fix stay in the backlog (not scheduled). Still open for dae: spot-check the ten largest gaps (report appendix); whether to leave the published quiz scores (recommended: order is right, fix the grader before the next exam); which problem-text fixes to apply to 701/705 before any reuse; what students may use during an exam viva (slides, compiler).

### 2026-10-08 — The viva failsafe and reaper had not run since 2026-09-17; timed-out message names the real wait
**platform (scheduling) + behavior (message text)** · rev 2258 (master); `doc/decisions.md` 2026-10-08
- **Problem observed:** while checking the nightly job cleanup, found that no scheduled task had run on any of the nine deployed web hosts since the 2026-09-17 deploy: rev 2137's worker split served only `viva` and `default`, and Solid Queue queues every `command:` task in `solid_queue_recurring`. For viva that meant `viva_turn_failsafe` (fails an examiner reply that never arrives) and `viva_session_reaper` (finishes sessions idle 24 h) were off through DS Quiz 2. Read-only counts on 2026-10-08 found no effect: no examiner turn stuck "thinking" on any host, and on cp-grader 11 idle sessions waiting for the reaper (10 greeting-only, 1 with one answer). Reading the failsafe also showed that `llm_started_at` is saved only with the reply, so the "started more than 10 min ago" rule of rev 2142 never fires: every stuck reply is failed by the 20-minute rule, while the message said "no response after 10 minutes".
- **Change:** the second Solid Queue worker serves every queue (`"*"`), so the scheduled tasks run again; the ~9,550 unrun requests per host were discarded by hand on 2026-10-08 (dae's decision) so the catch-up happens once, at each task's normal time. The timed-out message names the wait that applied ("no response after 20 minutes" for a reply that never started).
- **Outcome / status:** on master for 4.7.3, not yet deployed. After deploy, the first reaper run on cp-grader grades the one answered session (Cell Detection, started 2026-09-29) and archives the ten greeting-only ones. Open: record `llm_started_at` when the call begins if the 10-minute rule for a running call is still wanted.

### 2026-10-07 — DS Quiz 2: students retook the viva; one start rule, staff grants, and a Viva check page
**access policy + behavior + staff UI** · revs 2238–2240, 2242, 2244, final-review fixes 2247–2249 (master); spec `docs/superpowers/specs/2026-10-07-viva-retakes-and-viva-check-design.md`; plan `docs/superpowers/plans/2026-10-07-viva-retakes-and-viva-check.md`
- **Problem observed:** in DS Quiz 2 (contest 46 `d69_q2`, viva = problem 701, 148 sessions by 146 students) proctors saw students take the viva twice. Problem 701 came from the practice kit with start limit 5, so the page offered Restart and End and allowed five sessions; two students finished, restarted and retook (80 → 94, 74 → 83 — the contest score is the best session) before a TA set the limit to 1 at 09:49:59. Quiz 1 had started on the same value. The scenario still said "practice viva", repeated in 147 of 148 greetings. Reading the code found three traps: limit 0 meant *unlimited* retakes during a contest; under limit 1 the admin "Archive & allow retake" gave no retake (archived sessions still count); and under limit 1 a student who pressed Restart mid-interview archived an ungraded session nothing would grade, and could not start again. Staff had no place to see any of it during the exam.
- **Change:** `Viva::StartPolicy` is the one start rule used by Start, Restart and the session page; limit 0 now allows one counted session in contest mode; Restart is offered only when the student could start again. **Allow another attempt** (staff who can edit the problem; works in contest mode) archives a session at any status, stops it counting toward the start limit and writes a `viva_retake_grant` audit row — on the session page's Admin card (replacing Archive & allow retake) and on each student row of the new **Viva check** page (contest → Reports), which refreshes every 30 s during the contest and flags Retook, Waiting for reply, Reply failed, Grading failed, Left unfinished, Grade doesn't add up and Rubric unreadable (needs action, counted in an "N to check" badge on the contest page) plus No answer yet, Short but high, Ended early and Rule-break flag. dae decided against a hard single-attempt rule in code: the start limit stays the control, 1 for an exam.
- **Outcome / status:** on master, not yet deployed; the two Quiz 2 retakers are graded on their first attempt in the gradebook (dae, 2026-10-07; the platform still shows the best session). Open: the pre-exam contest checklist that would warn about a practice limit or "practice" wording (`doc/backlog.md`). Final-review fixes (rev 2247): a closed (archived) session refuses answers and retries and is never sent to grading, even by an examiner reply in flight that ends the interview — before, a granted open session still took answers beside the new session the grant had freed; the grant message says what the student can actually do now (read from `Viva::StartPolicy` after the grant); Viva check lists the contest's students only (staff sessions left out); contest-mode tests for limit 0 and for a contest editor's grant. Rev 2249: a grant that frees no start is shown as a warning (toast or alert), not a green notice; a `[[VIVA_DONE]]` reply moves a session to grading only if it is still open (`submitted`), so a late reply after an End click cannot queue a second grade job (possible when the stale-turn sweeper had failed the turn and the student pressed End before the original reply landed); the owner's button reads "Restart viva", since it also shows during exams.

### 2026-09-24 — Contest page shows how many vivas are still being graded
**behavior (staff UI)** · rev 2201 (master); backlog entry raised 2026-09-23 → Resolved
- **Problem observed:** reports bucket a viva by its start, so grades land after the bell, and staff had no signal on the contest page that the score table was final; the rule was to watch the queue page by hand.
- **Change:** a status badge next to **Finish open vivas** — "Grading: N in progress", "N grader errors", or "All vivas graded" — over the same in-window, enrolled, non-archived sessions (`Contest#viva_grading_counts`), refreshed every 10 s through a turbo frame while anything is grading. Regrades of graded sessions are not counted.
- **Outcome / status:** on master, not yet deployed; checked in a headless browser against the local copy of `d69_q1` (the badge flipped from "Grading: 1 in progress" to "All vivas graded" 9 s after the grade landed).

### 2026-09-23 — Grade history: every grader run is kept; Re-run and batch regrade decide under never-lower
**platform code** · revs 2183–2192, review fixes 2195–2197 (master); spec `docs/superpowers/specs/2026-09-23-viva-grade-history-design.md`; closes the gap recorded in the 2026-09-09 entry; backlog "Viva grade history" → Resolved
- **Problem observed:** `viva_grades` held one row per submission (unique index) and the admin Re-run button destroyed it, so the 2026-09-09 Cell Detection regrade of 157 sessions needed an external before-image, a hand-written max(old, new) step and a verify pass; a failed re-run left the student with no grade at all; `rubric_version` was never written, so nothing recorded which briefing graded a session and a batch could not tell a stale grade from a fresh one.
- **Change:** one `viva_grades` row per grader run; the row with `superseded_at IS NULL` is the current grade (`Submission#viva_grade`), the rest are history labelled `replaced` / `lower` / `error` / `reverted`, with `superseded_by_id`, `requested_by_id`, `batch_id`, `error`. A run is written non-current and decided under the row lock: no valid grade → adopt; higher, or never-lower off → adopt; lower under never-lower → kept as `lower`. Failed runs are stored as `error` and never take a grade away. `rubric_version` = SHA-256 of conduct tags + briefing + grounding text on every run. Re-run gains "Keep the higher grade" (default on) and refuses an open interview; the Admin card lists the history with **Make current** (audited on the problem). `bin/rails viva:regrade PROBLEM= [CONTEST=] [MODEL=] [ALL=1] [REPLACE=1] [LIMIT=] [APPLY=1]` (stale grades only by default, one audit row per batch), `viva:regrade_status` and `viva:regrade_revert` replace the course-prep toolkit. Reports still key on `submitted_at`: a regrade never moves a session out of its contest (`doc/viva-visibility.md`, rewritten from caveat to rule). Review fixes (2195–2197): a session with any valid run under the current rubric — a `lower` one included — counts as up to date, so rerunning a batch cannot draw extra never-lower tickets; batch runs are queued at Solid Queue priority 10, behind live turns, and the report prints the open-session count; a migration files legacy failed rows (current, no points) as `error`; failure checks run under the row lock; `viva:regrade_status` gains a `replaced` outcome.
- **Outcome / status:** on master, not yet deployed. Existing rows are current and stale (`rubric_version NULL`), so the first batch on a problem targets everything, as the 2026-09-09 run did. Open: an in-flight grading count on the contest page (backlog).

### 2026-09-23 — Test-drive sessions: authors sit their own viva outside limits and reports
**behavior + access policy** · revs 2167–2173 (master); spec `docs/superpowers/specs/2026-09-23-viva-test-drive-design.md`; D7 (2026-07-20 readiness spec) half done
- **Problem observed:** the only real check of an LLM examiner is to sit the viva, but an author's trial session was a real submission — on the stat page, in every report and the AI-usage figures, burning a daily start (editors, not admins) and sitting among student transcripts. Authors polluted the data or tested less than they should. Listed in `doc/Viva-Exam.md` Known Gaps since 2026-07-21.
- **Change:** `submissions.test_drive`; `Submission.regular` now excludes test-drives as well as near-miss shadows, so every student-facing list, quota and report drops them in one change (hand-written shadow checks in the cheat report, `ProblemStat` and `AiUsageReport` gained the same condition). `POST /problems/:id/viva/test_drive` (editors of the problem's group, admins) shares session creation with the student start but skips the daily limit, the contest-only rule and the one-active-session guard; restart opens a fresh test-drive at once; End is allowed on contest-only vivas. `can_view_submission?` denies test-drives to peers even under transcript sharing. UI: header **Test-drive** button and a Test-drives list on the problem edit page; the admin problem index offers Test-drive on viva rows instead of the former staff Start Viva; badge + "unlimited restarts" line on the session page; badges on the viva alerts and stuck-turns pages. Restart takes the row lock like End (2171), so a double click cannot open two test-drives.
- **Outcome / status:** shipped on master, not yet deployed. The preflight-lint half of D7 stays open (`doc/Viva-Exam.md` Known Gaps). Phase B must keep test-drives on the practice alert branch (recorded there).

### 2026-09-23 — "Finish open vivas": one click closes every open session of a contest
**behavior + policy** · rev 2161 (master); backlog "Contest stop does not finish open viva sessions" → Resolved
- **Problem observed:** at the 2026-09-09 quiz bell, 65 of 151 answered sessions were still open (no End, no `[[VIVA_DONE]]`, under the hard cap) and were finalised by 62 manual Re-run clicks over 36 minutes; otherwise the 24 h reaper would have graded them the next day. Decision 2026-09-17 (dae): a batch button, not a contest-stop trigger.
- **Change:** `Contest#finish_open_vivas!` runs over the contest's open viva sessions — enrolled users, contest problems, inside the window with per-user offset/extra time, the same rules as `Contest#submissions` — and the button on `contests/show` (contest editors and admins; shown only when the contest has a viva problem; confirm names the current count) toasts the three counts: sent to grading, archived, skipped. The two branches now live in one place, `Submission#finalize_open_viva!` (answered → closing system turn `(session closed by contest staff — grading begins)` + :evaluating + grade job with the default model; greeting-only → `(… — archived)` + `viva_archived_at`), shared with `reap_abandoned_vivas!`. Both run under the same row lock as `#answer`/`#finish` and re-check inside it, so a student's answer landing at the same instant is serialised, not doubled; a session with a reply in flight is skipped, not force-closed. Audit row `finish_open_vivas` on the contest with the counts.
- **Outcome / status:** shipped on master, not yet deployed. The manual precursor of Phase B's window-end force-finish (`doc/Viva-Exam.md`), which stays open; so does the missing session wall clock.

### 2026-09-12 — Quiz 1 post-exam analysis: queue saturation, seven lost vivas, dry second-opinion pilot
**analysis only, no code change** · `doc/exam-postmortem-2026-09-09-d69_q1.md`; working files in course-prep `data-structures/viva/quiz-2569-1-postmortem-2026-09-12/`
- **Problem observed:** the single 3-thread Solid Queue worker served viva turns, grades and assists together; from 10:19 turn wait rose from 4–6 s to p95 358 s / max 461 s. Seven active students opened the viva, waited 92–454 s for the greeting and never answered (viva 0). 65 of 151 sessions were still open at 11:20 and were finalised by 62 manual Re-run clicks. No failed turns. Daily limit 5 → 1 changed by hand at 09:38 and held; no contest-level retake limit exists.
- **Change:** SHIPPED on master (revs 2134–2143): dedicated `viva` queue+worker so assist traffic can't starve interviews (2137); per-call timing columns `llm_started_at`/`llm_latency_ms` splitting queue wait from provider time (2135–2136); the stale-turn sweeper now distinguishes queued from running so a backlog no longer shows a false timeout (2142); the contest AI-usage report (2140–2141); header 500 fix (2139); admin-only site-mode switch (2141). Worker defaults resized to 3+3 threads so they fit the stock pool of 5 (2146) — deploy needs no host env change; per-host tuning via VIVA_JOB_THREADS/JOB_THREADS + RAILS_MAX_THREADS in the host's queue env file. Merged to chula_cp, pushed; deployed with chula_cp 2158 — verified live on cp-grader 2026-09-21 and ise-grader 2026-09-22 (`hg id` on the hosts); other hosts unverified.
- **Outcome / status:** dry second-opinion pilot (claude-opus-4-5, 30 sessions, USD 2.03, nothing written): opus ≈ 11 points stricter than gemini-3.7-flash, 25 down / 4 up. Decision on a full pass is open (postmortem §Decisions).

### 2026-09-09 — Quiz 1 "Cell Detection": lenient briefing v2 + whole-cohort regrade under a never-lower rule
**prompt text + production operation** · course-prep revs 15–19 (`data-structures/viva/quiz-2569-1/` kit, `data-structures/viva/regrade-cell-detection-2026-09-09/` images, tooling, run); prod problem 705 `d69_v1_cell_detection`, contest `d69_q1` (165 students, 157 graded)
- **Problem observed:** the quiz briefing named one design (per-row / per-column `vector<set<int>>`); students who proposed the equivalent two-`set<pair<int,int>>` design were marked down under `container_selection_and_memory`. Cohort mean 39.0/100. The briefing existed only in prod's DB (typed in the web form, CRLF line endings) — nothing in course-prep, and the audit log stores briefing text as `[redacted]`.
- **Change:** (1) before-image of every grade row, submission field and the briefing (CSV + JSON + mysqldump REPLACE image; server `~/regrade-cell-detection-2026-09-09/` and course-prep rev 15) and the problem hidden as a curtain (`available=false`, audit 816). (2) Briefing v2 accepts Option 2 (two global pair sets, row-first + column-first): new model-answer block, one cross-cutting question, interview-plan step 4, criterion wording; weights and the conduct-tag grading conventions unchanged. Applied through the new one-problem kit `quiz-2569-1` (`viva:import`, dry run said UPDATE) at 23:39. (3) All 157 graded submissions (4 archived attempts included) regraded **in place** through the production Solid Queue worker, same grader (gemini-3.7-flash via Chula AI Gateway): 7 minutes, USD 1.62, 0 grader errors. (4) Rule: a student keeps whichever **whole** grade record (points + breakdown + narrative) scores higher — 59 old records written back; final state verified column-identical against the final image. Tooling `tools/regrade_tool.rb` (snapshot / regrade / status / finalize / restore / verify / apply_briefing / report) and `tools/delta_report.py`, rehearsed first on a local prod copy (failure path with real 403s, simulated success path, revert identical, briefing apply/revert audited).
- **Outcome / status:** the rubric change itself moved almost nothing — pure regrade mean 39.30 vs 39.04; `container_selection_and_memory` +0.5/20 on average (64 up, 27 down), every other criterion flat. **Rerun noise dominated:** on identical transcripts the new grade differed from the old by SD 4.2 points with swings to ±11 (e.g. 74 → 63, 31 → 42) — far above the ±2 assumed from the 08-27 bake-off. Under the never-lower rule the final mean is 40.77 (+1.73), 73 students up, none down, +271 points total. Problem left hidden pending dae's review of `run/report.html`; unhide = `available=true`. Revert at any time: `regrade_tool.rb restore 705 run/before --briefing` then `verify`. Lessons → authoring guide pitfalls (name every acceptable design; one grade carries roughly ±10 of uncertainty). Gaps found → backlog: `viva:import` left **no audit row** for the `viva_prompt` update; the app has no grade history (the per-submission Re-run button destroys the row).

### 2026-09-06 — Answer and End take a row lock (no double grade job on a double-click)
**platform code** · rev 2114; `app/controllers/viva_sessions_controller.rb`, `test/integration/viva_sessions_controller_test.rb` (+3)
- **Problem observed:** noted in the 2026-07-21 Phase 1 review and parked in `doc/backlog.md`: the hard-cap branch of `#answer` and all of `#finish` read the session state, wrote the closing system turn, flipped the status to `evaluating` and queued `Llm::VivaGradeAssistJob` with no lock. Two POSTs within milliseconds of each other (a double-click on Send or End, a second tab, a browser retry) both saw the pre-cap state and both force-finished: two closing turns in the transcript, two grade jobs for one interview. Below the cap the same gap could record two student turns and two assist jobs. The grade is recomputed from the transcript, so the cost was one wasted LLM grading call and a duplicated closing line — never a grade change.
- **Change:** both actions now run their check-and-transition inside `@submission.with_lock` (the pattern `VivaTurn#assign_sequence_if_blank` already used). `lock!` reloads the row, so the second request sees `evaluating` (or the first request's processing placeholder) and is refused with the existing "grading in progress" / "waiting for the previous response" message. The shared step is `#force_finish!`; jobs are enqueued after the lock block has committed. Three regression tests play the first-committed request through a one-shot hook on `lock!`.
- **Outcome / status:** in master rev 2114, not yet merged to chula_cp or deployed. Residual, recorded in the backlog's Resolved ledger: `#retry_turn` and `#restart` stay lock-free — a double-click on Retry can run one turn's LLM call twice (the second result overwrites the first), and Restart can archive a session just as an answer lands. Neither touches grading.

### 2026-09-02 — Transcript renders `<` and `>` literally (C++ templates no longer vanish)
**platform code** · rev 2078; `app/helpers/application_helper.rb`, `app/views/viva_sessions/_turn.html.haml`, `test/helpers/application_helper_test.rb` (new), `test/integration/viva_sessions_controller_test.rb` (+2)
- **Problem observed:** students typing `vector<int> v;` saw `vector v;` in their own history and panicked — the stored turn was intact. Student, system and error turns went through Rails `simple_format`, whose default sanitizer strips unknown tags (`a<b && c>d` even became a bold element); interviewer turns went through Redcarpet `filter_html`, which drops raw tags the same way (`vector<vector<int>>` → `vector>`, only backticked code survived).
- **Change:** `simple_format_escaped` — escape, then paragraphs and `<br>` — for the three plain-text roles; `safe_markdown` switches `filter_html` → `escape_html`, so raw HTML in an interviewer turn shows as text rather than disappearing (autolinks and code spans unchanged). The markdown editor preview shares the helper and now shows `<int>` too.
- **Outcome / status:** in master rev 2078, not yet merged to chula_cp or deployed. Regression tests cover every role, including an `<img onerror>` / `<script>` probe in both the student and the interviewer path (rendered as text, no element created).

### 2026-09-02 — Viva guides published to the upstream wiki
**docs/tooling** · wiki commit `1f9501f` (cafe-grader-team/cafe-grader-web.wiki); rev 2072 (link targets)
- **Problem observed:** the instructor and student guides had been drafts in `doc/wiki/` since 2026-07-21 and never reached the wiki; the new authoring guide needed a home problem setters can find.
- **Change:** pages `Viva-Instructor-Guide`, `Viva-Authoring-Guide`, `Viva-Student-Guide` (verbatim copies of `doc/wiki/*.md`), plus a "Viva exams" section on `Home`. Cross-links in the sources now use the wiki page names so the copies stay verbatim.
- **Outcome / status:** live. Re-sync rule: when a `doc/wiki/*.md` changes, re-copy it to the wiki page of the same title (dae pushes; see the `cafe-grader-wiki-publishing` memory).

### 2026-09-02 — `course-prep` becomes a local hg repo; wiki procedure recorded
**docs/tooling** · `hg -R ~/cafe-grader/course-prep log` revs 0–1; memory `cafe-grader-wiki-publishing`
- **Problem observed:** conduct and briefing text had no version trail — it lived only in prod's DB and in README prose. How the upstream wiki gets published was not written down anywhere (found while planning these docs).
- **Change:** `hg init` on `course-prep` (no remote, ever — it holds exam papers and model answers); rev 0 baseline, rev 1 the conduct split. Memory note: the `cafe-grader-team` wiki holds verbatim copies of `web/doc/*.md`, pushed by hand; `doc/wiki/` viva guides are unpublished drafts.
- **Outcome / status:** live.

### 2026-09-02 — Kit importer accepts a `conduct_tags:` list
**platform code** · rev 2071; `app/services/viva/kit_importer.rb`, `test/services/viva/kit_importer_test.rb` (+3 tests)
- **Problem observed:** the manifest took one `conduct_tag:`; the base + overlay design needs two tags per problem.
- **Change:** `conduct_tags:` list (legacy single form still accepted; both merged); each tag upserted by name and linked add-only to every kit problem; the same name twice fails the import; the UPDATE report names the linked tag. Header comment documents suffix naming and name-order concatenation.
- **Outcome / status:** live — rev 2071, merged to chula_cp (2073/2075), deployed to 10.0.5.50 on 2026-09-02 by replaying the pipeline's remote steps over ssh (no GitLab token here; the 8 other hosts still need the pipeline). 10/10 importer tests; the prod dry run printed the two `CONDUCT` lines before `APPLY`. Older importers ignore the key silently.

### 2026-09-01 — Conduct split: base profile + practice/exam overlays; Buggy Counter witness carve-out
**prompt text (course content) + policy** · course-prep rev 1; `_conduct.md` (base, tag `DS-viva-conduct-2569`, 4,859 → 6,004 chars), `_conduct.practice.md` (`DS-viva-conduct-2569-practice`), `_conduct.exam.md` (staged for a future exam kit, not imported), `01-buggy-counter.briefing.md`, `manifest.yml`; review page `~/Documents/reports/viva-conduct-split-2026-09-01.html`
- **Problem observed:** one tag mixed mode-invariant rules with practice-only scaffolding, so it could serve neither a leak-tolerant practice nor a strict exam. dae's position: leaks are fine in practice, not in exams; leading questions corrupt scores in both.
- **Change:** *Base* gains: never put the answer inside a question; ask for the student's own working; examiner-supplied content is not evidence; unreached criterion = 0; criterion ≤ weight; probe examples in English (the Thai examples were being imitated); don't end while a criterion rests on an unverified claim; no answer summary in the close; "never reveal" reworded to "while the point is still being assessed". *Practice overlay*: one hint per topic; a sanctioned one-sentence, no-code explanation after a rung is settled; concrete narrative. *Exam overlay*: one restatement, no content hints, no teaching, topic-only narrative. Each overlay ends with a precedence line. Buggy Counter briefing: never supply a concrete witness even in practice — witnesses are what retakers paste verbatim.
- **Outcome / status:** **live on prod since 2026-09-02 ~20:50** — chula_cp 2075 deployed to 10.0.5.50, kit re-imported (`APPLY=1`; base tag 4,860 → 6,004 chars, practice tag created, overlay linked to all 9 problems, Buggy Counter briefing updated; setup errors none; 2 sessions in progress picked up the new conduct on their next turn). Exam overlay still staged, not attached anywhere.

### 2026-09-01 — Full-transcript audit of problem 693 "The Buggy Counter"
**docs/tooling (analysis)** · report `~/Documents/reports/viva-audit-buggy-counter-2026-09-01.html` + findings tarball; memory `viva-buggy-counter-audit`
- **Data:** 182 sessions, 101 students, 2,372 turns, 117 grades (08-22 → 09-01). 54 zero-turn peeks (30%); 116 graded; one `grader_error` never re-run (937805). All 128 transcripts with content close-read against briefing, conduct, security directive and grading conventions.
- **Findings:** (1) *Compliance is a model property.* The 2.5-flash era broke English-only in 44 sessions, revealed its running assessment in ~53, escalated hints in 22, and hit the hard cap in 42% of completions; the 3.7-flash era is clean on all of those but skips demanding witness traces and sometimes ends early on thin evidence. (2) *No leak under direct attack* — 20+ jailbreaks (prompt extraction, TA role-spoof, "friend said the examiner confirmed…", a grading-pipeline injection) all deflected in both eras. Real leak channels: the examiner teaching the answer after a failed rung (108 instances in 63 sessions, both models), leading yes/no questions containing the answer, grade narratives spelling out the fix (25/117), abandon-and-retry oracle farming. (3) *Scoring* ≈73/116 plausible, ~36 over, ~6 under; untraced witnesses credited; precondition over-credit; phantom credit for unreached rungs; 2/117 rubrics exceeded their weights; gemini-3.1-pro unanimously the best-calibrated grader; external-LLM pastes scored 98–100 undetected. (4) *Alerts*: 56 turns / 21 sessions, 0 terminations (practice mode — correct); ≥14 false positives on explicitly listed non-triggers (all 2.5-flash era); under exam two-strike two honest students would have been terminated. Heavy retake grinding (one student 10 sessions); two account-sharing suspects.
- **Outcome / status:** drove the conduct split. Open recommendations: stronger grader default (3.1-pro or better), grade-JSON validation against weights, re-grade 937805, paste/burst heuristics as review flags (never auto-penalize), session wall clock, alert regression set from the 56 practice alerts before exam mode, retake scoring policy.

### 2026-08-29 — Grade JSON schema check + one re-ask before `grader_error`
**platform code** · rev 2043 (chula_cp merge 2054)
- **Problem observed:** the extractor took the first balanced `{…}`; a grader reply that slipped into the interviewer role could land as `points: nil` with status *done* — a silent zero (prod 937805, 08-23).
- **Change:** `grade_schema_error` (numeric `total_points` 0..100, non-empty rubric); re-ask once (not on `finish_reason=length`); second failure → `grader_error` with the raw response preserved.
- **Outcome / status:** live in code; deployment to prod after chula_cp 2038 unconfirmed. Does **not** check criteria against weights — the audit's two over-weight rubrics would have passed (open item).

### 2026-08-28 — Viva grade display: compact marker, badge on the main list
**platform code (UI)** · revs 2036–2038; `bin/rails viva:clean_grader_comments`
- **Problem observed:** the 300–450-char narrative was copied into `grader_comment` and rendered as a paragraph in the main list's verdict cell.
- **Change:** marker `viva` / `viva:terminated`, badge linking to the viva page, "Interview in progress" / "Grader error" states. 4.5.0 head moved to include it.
- **Outcome / status:** live; prod runs chula_cp 2038 (4.5.0) from 08-29.

### 2026-08-28 — Kit importer carries grounding; DS grounding text; markdown editor; two-column edit page; release 4.5.0
**platform code + prompt text (grounding) + docs** · revs 2027 (`grounding:` manifest section), 2030 (Ace editor + server preview), 2031 (edit page), 2033 (release); kit `_grounding-stl-usage-01-07.md` (≈5k tokens re-sent every turn; no `CP::`, examiner never uses O-notation) attached to problems #01–#08
- **Outcome / status:** live. Prod grounding record pre-created so the import matches by title.

### 2026-08-27 — Bake-off → prompt hardening; viva services flipped to Chula AI Gateway gemini-3.7-flash
**prompt text (backend directives) + model/provider** · rev 2024 (hardening, master), 2025 (config flip, chula_cp); report `~/cafe-grader/bakeoff-2026-08-27/`; deployed to prod 22:47
- **Problem observed:** with wire-role labels, Claude models slid into the interviewer role and kept interviewing instead of grading (21/24 gateway calls; 2.5-flash showed the same on 08-23); one model announced "the interview has ended" without `[[VIVA_DONE]]`, stranding the session; two models wrote LaTeX that `safe_markdown` renders raw. Bake-off: 3.7-flash 4.0 s/turn vs Sonnet 10.7 s, zero leaks for both, 12/12 grade compliance under the hardened prompt, ±2 rerun noise, ~5 points kinder than 3.1-pro.
- **Change:** grading transcript labeled `INTERVIEWER:`/`STUDENT:` with an "END OF TRANSCRIPT — output ONLY the grade JSON" re-anchor (Claude 3/24 → 16/16 compliant); `[[VIVA_DONE]]` made binding; no-LaTeX format directive. Config: viva turn, viva grade, grounding extract → gateway, all gemini-3.7-flash.
- **Outcome / status:** live. Audit 09-01: hard-cap hits 42% → 3%, English-only violations 44 → 0, praise/running-assessment violations gone. Residual on 3.7-flash: skipped trace demands, occasional leading questions, early endings on thin evidence — addressed in the 09-01 conduct split.

### 2026-08-26 — Hosted AI-gateway provider family (master) + Chula AI Gateway wiring (chula_cp)
**model/provider** · revs 2018–2019 (master), 2020 (chula_cp `ai_gateway:` block); placement rule `doc/decisions.md` 2026-07-30
- **Problem observed:** OIT's LiteLLM proxy with static bearer keys replaces the Genie token dance; Anthropic models reject PDFs sent as `image_url`.
- **Change:** `Llm::AiGatewayTransport` + per-role subclasses (assist, viva turn, viva grade, grounding extract, repair); PDFs as OpenAI `file` blocks; cost from `x-litellm-response-cost`. Viva services stayed on Genie until the bake-off.
- **Outcome / status:** live.

### 2026-08-26 — Abandoned-session reaper
**platform code** · rev 2016; `config/recurring.yml` `viva_session_reaper` (hourly, production)
- **Problem observed:** grading fired only on sentinel, hard cap, or the End button; tab-closers sat in `submitted` forever (trial: ~17 with progress, ~27 greeting-only).
- **Change:** `Submission.reap_abandoned_vivas!` grades sessions idle 24 h+ with ≥1 student answer and archives greeting-only peeks.
- **Outcome / status:** live; audit: 54 peeks archived ungraded as designed, 1 session reaped-and-graded.

### 2026-08-25 — Conduct: examiner writes English only; students any language; kit names `d69_v1_<slug>`
**prompt text (course content)** · kit `_conduct.md` §Language (verified identical to prod tag on 08-29)
- **Problem observed:** the original Thai-speaking-examiner policy caused per-session language chaos once the deployed tag's headline was flipped to English by hand.
- **Change:** examiner English-only (one-line Thai orientation allowed in the opener); students Thai/English/mixed, never commented on; translation requests → simpler-English restatement, never flagged; narrative in the student's language. Kit and prod problem names converged so the importer matches by name.
- **Outcome / status:** live — but **gemini-2.5-flash ignored it** (362 Thai non-opening messages in 44 sessions through 08-27); 3.7-flash complied fully. Recorded in `Viva-Exam.md` §2 as "interview language is a conduct concern".

### 2026-08-25 — Grading model independent of how the interview ended
**platform code** · rev 2011
- **Problem observed:** on 08-24, 14 hard-capped sessions were graded by the grade default and 11 sentinel-ended ones by the *turn* model — two graders in one cohort.
- **Change:** both end paths leave model selection to the grade service; only the admin re-run picker passes a model.
- **Outcome / status:** live.

### 2026-08-24 — First student trial (70 sessions) → flow fixes and narrowed alert triggers
**platform code + policy + prompt text (security directive)** · rev 2014
- **Problem observed:** 39% of starts were greeting-only peeks, each burning a daily slot (often a misclick); ~17 sessions with real progress parked in `submitted`; 28 alerts were mostly benign redirects drowning the real signal.
- **Change:** daily limit counts *engaged* sessions only (≥1 student turn); "End interview & get graded" button (practice only); `SECURITY_DIRECTIVE` trigger 4 narrowed to credit negotiation, with explicit non-triggers (off-topic, frustration, breaks, skip/stop requests, translation requests).
- **Outcome / status:** live. Audit 09-01: peeks 30% and free; ≥14 false positives still fired on listed non-triggers in 2.5-flash sessions.

### 2026-08-24 — Turn default → Claude-Sonnet (chula_cp)
**model/provider** · chula_cp rev 2010
- **Problem observed:** replaying three real turns through five relay models: 2.5-flash and 3-flash gave sub-answers away, Haiku lectured, Sonnet never leaked and matched the student's Thai; 3–10 s/turn at ~USD 0.025 (flash 0.002). Also removes the 2.5-flash retirement deadline (~2026-10-16).
- **Change:** `VivaTurnGenieAssist` default Claude-Sonnet.
- **Outcome / status:** **never ran in prod** — the audit shows 2.5-flash until 08-27 21:46 and 3.7-flash from 22:57; rev 2025 replaced it before deployment. SUPERSEDED 2026-08-27.

### 2026-08-23 — Grade default → gemini-3.1-pro (chula_cp)
**model/provider** · chula_cp rev 2008; comparison scripts on the grader host
- **Problem observed:** over 12 graded sessions, fresh 2.5-flash reruns scattered ±10 points (stdev 7); it credited interviewer scaffolding as student knowledge (937769) and reproducibly role-played the interview instead of grading → nil-score grade (937805).
- **Change:** `VivaGradeGenieAssist` default gemini-3.1-pro.
- **Outcome / status:** in effect 08-23 → 08-27 (18 prod grades); SUPERSEDED 2026-08-27 by the gateway flip to 3.7-flash. The 09-01 audit again found 3.1-pro the best-calibrated grader — reinstating it is an open recommendation.

### 2026-08-22 — Kit imported to production; first student sessions
**deployment (content)** · prod 10.0.5.50 @ chula_cp 2006; kit at `~/viva-kits/practice-2569-1a`; problems 693–701
- **Outcome / status:** Buggy Counter made available the same day; first session 16:20.

### 2026-08-22 — Submit authorization: one gate, viva start included
**platform code + policy** · revs 1996–2001; `doc/decisions.md` 2026-08-22
- **Problem observed:** viva start used `problems_for_action(:submit)` directly; editors couldn't test-start hidden vivas; the manage page's Submit button bounced viva rows.
- **Change:** `User#can_submit_to_problem?` gates web, API, viva start, UI and the model validation; disabled membership grants no role; manage page offers Start/View Viva.
- **Outcome / status:** live.

### 2026-08-15 — Kit `practice-2569-1a` authored; first conduct tag; pilot findings
**prompt text (course content)** · `course-prep/data-structures/viva/practice-2569-1a/` (`_conduct.md`, 9 scenario/briefing pairs, `manifest.yml`); self-runs on local dev
- **Problem observed (pilot):** with "in full and verbatim" alone the examiner dropped the "Come prepared to" list; a student who needed one pushback was regraded 94 → 100.
- **Change:** conduct tag `DS-viva-conduct-2569` (Thai-speaking examiner at this point); grading conventions including **correct-after-hint = partial credit**; the opening rule names the task list explicitly; per-problem caps (Buggy Counter 8/12); daily limit 5.
- **Outcome / status:** live content; conduct SUPERSEDED 2026-08-25 (language) and 2026-09-01 (split).

### 2026-08-15 — Kit importer; completion caps raised
**docs/tooling + platform code** · revs 1989 (`bin/rails viva:import DIR=… [APPLY=1]`), 1990 (grade 2048 → 8192, turn 2048 → 4096 tokens), 1991 (doc refresh)
- **Problem observed:** nine problems to author by hand; gemini-2.5-flash spent 1,963–3,301 reasoning tokens before the JSON → `finish_reason=length` → `grader_error` on a 13-turn self-run.
- **Change:** idempotent, report-first importer (problems by name, conduct tag by name, `available` on create only); caps raised.
- **Outcome / status:** live.

### 2026-07-30 — LLM provider placement rule
**policy (engineering)** · `doc/decisions.md` 2026-07-30; rev 1924
- **Change:** generic providers (self-host, gateways) live on master, dormant until configured; Chula-only integrations (Genie) on chula_cp; config and secrets are per deployment. Near-miss grading explicitly excludes viva submissions.
- **Outcome / status:** live; governed the 08-26 gateway family.

### 2026-07-21 — Grounding PDF → text extraction (D4)
**platform code + model/provider** · revs 1919–1920 (master), 1922 (Genie wiring, chula_cp)
- **Change:** abstract extraction service + job + draft-review UI; at send time a material's body text replaces its PDF parts.
- **Outcome / status:** live (CHANGELOG 4.5.0). *`Viva-Exam.md` Known Gaps listed this as unbuilt until 2026-09-02 — stale text, corrected.*

### 2026-07-21 — Alert-review admin page
**platform code** · rev 1917
- **Change:** Graders → Viva alerts lists flagged sessions with the triggering utterance — the calibration instrument D3 asked for.
- **Outcome / status:** live. The red-team regression set remains unbuilt. *Known Gaps text was stale about this too — corrected 2026-09-02.*

### 2026-07-21 — Docs wave
**docs/tooling** · revs 1914–1916; `doc/viva-visibility.md`; `doc/wiki/instructor-viva-guide.md`, `doc/wiki/student-viva-guide.md`
- **Outcome / status:** the two wiki guides sat unpublished until 2026-09-02 (upstream wiki had 8 pages, none about viva) — see that day's entry.

### 2026-07-21 — Audit-guard batch for viva submissions
**platform code (security/robustness)** · revs 1907, 1909
- **Change:** API description endpoint gated (the description *is* the hidden scenario); bulk dataset rejudge skips viva; graders backlog excludes viva; stale `:evaluating` → `grader_error` + monitoring.
- **Outcome / status:** live.

### 2026-07-21 — Context-based policy replaces the practice/exam mode (Phase A)
**policy + platform code** · revs 1905 (spec), 1911–1912; `docs/superpowers/specs/2026-07-21-viva-context-policy-design.md`
- **Problem observed (dae's insight):** the mode toggle was a binary encoding of a numeric idea — how many starts, in what context; a forgotten toggle inside a real exam permits restarts; `contest_mode?` is server-global so wrapper contests are infeasible.
- **Change:** every viva is practice; per-problem `viva_daily_limit` (nil → site default 3; N per day; 0 = contest-only); self-restart for everyone; `exam_policy?` hardcoded false with the warn-then-terminate branch kept dormant for Phase B. Phase B planned: per-contest retake budgets, governing-contest snapshot, mandatory window-end force-finish.
- **Outcome / status:** Phase A live; **Phase B not shipped**. SUPERSEDES D1/D2 of 07-20.

### 2026-07-21 — Show/refresh authorization; archived attempts owner/staff-only
**platform code + policy (security)** · rev 1903
- **Problem observed:** `#show`/`#refresh` had no authorization beyond login — any student could read any transcript by guessing ids.
- **Change:** reuse `User#can_view_submission?` plus one viva branch (`return false if viva_archived_at`).
- **Outcome / status:** live.

### 2026-07-21 — Daily start limit in `GraderConfiguration`; smoke-test UX fixes; endpoint guards
**platform code** · revs 1898–1901
- **Change:** `viva.practice_daily_start_limit` (default 3); archive redirect/relabel; editor guard; form layout; nil-guards on evaluations/download/compiler_msg for viva submissions.

### 2026-07-21 — Grader inoculation against embedded operational instructions
**prompt text (grader system prompt)** · rev 1897
- **Problem observed:** a legacy briefing migrated from an `llm_prompt` tag carried its own `----- ALERT -----` rule; the grader obeyed it over the JSON contract → `grader_error`.
- **Change:** the grading prompt explicitly ignores interview-conduct, security and alert instructions found in author content.
- **Outcome / status:** live — the only defence until the D7 lint exists. Lesson carried into both guides: authors write content, never operational rules.

### 2026-07-20/21 — Phase 1 ships: `viva_prompt` + `viva_conduct` (D6), detect-only alerts (D3), turn caps (D8), mode toggle (D1/D2), authoring UI (D5)
**platform code + prompt assembly + policy** · revs 1878–1896; `doc/decisions.md` 2026-07-20 "ownership follows cardinality"
- **Change:** `problems.viva_prompt` (audited, redacted) holds rubric and model answers; `Tag#kind :viva_conduct` shared persona, concatenated in name order, `public` forced false; assembly order conduct → `viva_prompt` → `SECURITY_DIRECTIVE` → pacing → done-sentinel; `viva:migrate_prompt_tags`; `SECURITY_DIRECTIVE` becomes detect-only with backend `apply_alert_policy` (practice: log + notice; exam: warn then terminate); `viva_soft_cap`/`viva_hard_cap`; `viva_mode` enum; scenario relabel, Examiner-briefing field, Conduct-profile select. Deviation from spec: hiding LLM tags from the generic picker silently stripped `llm_prompt` tags on save → only `viva_conduct` hidden (rev 1888).
- **Outcome / status:** D6/D3/D8 live; D1/D2 SUPERSEDED the next day.

### 2026-07-20 — Deployment-readiness design (D1–D9)
**policy / design** · revs 1876–1877; `docs/superpowers/specs/2026-07-20-viva-deployment-readiness-design.md`
- **Problem observed:** an August practice month and a ~October graded exam with 100–200 concurrent students; single-attempt-until-admin-archive collides with practice on day one; jailbreak FP/FN rates unmeasured; rules text embedded in PDFs; mislabeled description field.
- **Change (design):** D1 practice/exam mode; D2 retakes; D3 detect-in-prompt / decide-in-backend + alert-review page + red-team set; D4 PDF → text; D5 scenario = description, PDF = figures; D6 `viva_prompt` column + `viva_conduct` tag; D7 lint + test-drive; D8 turn caps; D9 measurement/ops.
- **Outcome / status:** D4, D5, D6, D8 and the D3 alert page shipped; D1, D2 and D3's *selector* SUPERSEDED 07-21 by context policy; D7, the red-team set and D9's load test remain unbuilt.

### 2026-07-19 — `GroundingMaterial` model replaces `viva_grounding` tags
**platform code** · revs 1860–1875; `docs/superpowers/specs/2026-07-19-viva-grounding-materials-design.md`
- **Problem observed:** grounding tags had no working authoring UI and overloaded `Tag`; discovered in planning: uploaded files were *never* text-extracted — file grounding had always contributed empty text.
- **Change:** dedicated `GroundingMaterial` (title, body, files, estimated tokens) with an admin library and a viva-only attach select; files delivered as base64 PDF parts; tag kind retired after backfill.
- **Outcome / status:** live.

### 2026-06-11 — Release 4.4.0 backfills the hardening sprint
**docs/tooling** · rev 1754; CHANGELOG 4.4.0 Security "Viva exam hardening (revs 1722–1736)".

### 2026-06-10 — Pilot content kit (`course-prep`, `llm_prompt` scheme)
**prompt text (course content)** · `course-prep/data-structures/viva/pilot-midterm/` (kept for provenance)
- **Change:** five DS pilot scenarios for the old tag scheme; `course-prep/` deliberately outside the code repo so exam material never reaches the GitHub mirror.
- **Outcome / status:** SUPERSEDED 2026-08-15 by kit `practice-2569-1a`.

### 2026-05-25 — Viva-irrelevant form fields hidden
**platform code (UI)** · rev 1736 — Stimulus toggle hides permitted_lang / submission_filename / view_testcase for viva; `view_submission` kept (peer transcript visibility). Edit page redesigned again 08-28.

### 2026-05-21 — Problem PDF hidden from students on viva problems
**platform code + policy** · revs 1733, 1735
- **Problem observed:** the PDF was the interviewer's brief; revealing it defeats the interview.
- **Change:** `Problem#pdf_visible_to_student? = !viva_exam?`, `User#can_view_problem_pdf?`; web and API gates; no PDF link on the main list.
- **Outcome / status:** live; API description endpoint got the same gate 07-21.

### 2026-05-21 — Stuck assistant turns recover; `fail_stale!` sweeper; Retry button
**platform code** · revs 1732, 1739
- **Problem observed:** sessions parked forever on "Interviewer is thinking…"; recurring-task additions never took effect because solid_queue was not restarted on deploy.
- **Change:** non-retryable errors → `on_retries_exhausted`; `VivaTurn.fail_stale!` (10-min threshold, 5-min recurring task); owner-or-admin Retry; graders page "Background Workers" card + stuck-turns list; deploy pipeline restarts solid_queue.
- **Outcome / status:** live.

### 2026-05-20/21 — Answering restricted to the owner
**platform code + policy** · revs 1727–1730
- **Problem observed:** admins could post into a student's viva, corrupting transcript ownership.
- **Change:** owner-only `#answer`; non-owners see "Viewing as observer".
- **Outcome / status:** live.

### 2026-05-20 — First jailbreak directive: detect *and* terminate (v1)
**prompt text (backend-injected) + platform code + policy** · revs 1722–1728; migration `add_viva_terminated_at_to_submissions`
- **Problem observed:** no defence against role spoofing, answer extraction or question laundering.
- **Change:** `SECURITY_DIRECTIVE` injected into the system prompt; on detection the model prints a banner + `[[VIVA_ALERT]]`; backend sets `viva_terminated_at` and grades the partial transcript with a termination note.
- **Outcome / status:** SUPERSEDED 2026-07-21 by detect-only + backend strike policy (the model no longer decides consequences).

### 2026-05-17 — `viva` Language seeded by migration; name locked
**platform code** · revs 1697–1698 — existing installs get the sentinel language without a manual seed; unique index + immutability.

### 2026-05-12 — `Viva-Exam.md` rewritten to match the implementation; Decision Log born
**docs/tooling** · revs 1695–1696 — PDF as canonical scenario (later reversed), `llm_prompt` with `# Rubric`, grounding in the user message, Failure Modes. Rewritten again 07-21 and 08-15.

### 2026-05-11 — Retry-exhaustion marking; response-shape validation; Genie token failure
**platform code** · revs 1692–1694
- **Problem observed:** eternal spinner when all retries failed; an empty assistant turn accepted as `:ok`; Genie "no token" returned nil → confusing `NoMethodError`.
- **Change:** `on_retries_exhausted` per job; raise on blank content; Genie raises on token failure.

### 2026-05-09 — Soft archive (`viva_archived_at`) instead of delete
**platform code + policy** · revs 1686–1688; Decision Log "Soft archive instead of delete"
- **Problem observed:** letting a student retake required destroying a submission (cascades to turns, grade, comments — irreversible).
- **Change:** nullable `viva_archived_at`; main list ignores archived; start refuses while an active viva exists; admin `archive_viva` on terminal states.
- **Outcome / status:** live; extended to self-service restart 07-21.

### 2026-05-08 — Re-run grading with a model override; Genie roster
**platform code + model/provider** · revs 1682 (master), 1683 (chula_cp `KNOWN_MODELS`)
- **Problem observed:** a grade stuck on gemini-2.5-flash refusing JSON-only output.
- **Change:** admin picker passes `model:` to the grade job; gemini-2.5-pro recommended for strict JSON.
- **Outcome / status:** live; the picker is the only explicit-model caller after rev 2011.

### 2026-05-08 — `:evaluating` treated as terminal; state-driven view; admin and debug cards
**platform code (UI)** · revs 1672–1681
- **Problem observed:** after `[[VIVA_DONE]]` the answer form stayed open (turn job vs grader race, double cost); `grader_error` rendered as an empty card.
- **Change:** `#answer` rejects late answers; view dispatches on `submission.status`; Admin card (Re-run grading), Debug card (raw responses, next-payload previews).

### 2026-05-08 — Problem setup validation before start (`viva_setup_errors`)
**platform code** · revs 1668–1671
- **Problem observed:** half-broken sessions when the prompt lacked a Rubric section.
- **Change:** `Problem#viva_setup_errors`; `#start` refuses with a flash. (Same day, description-field checks were dropped on the belief that the PDF carries the scenario — reversed by D5 on 07-20.)
- **Outcome / status:** live; the `# Rubric` check now runs against `viva_prompt`.

### 2026-05-08 — Grader raw response persisted; tolerant JSON extraction
**platform code** · revs 1666–1667
- **Problem observed:** "no JSON object found" raised and the raw body was discarded — nothing to inspect.
- **Change:** raw saved before parsing; balanced-brace extractor tolerating fences and prose.
- **Outcome / status:** live; the "first balanced object" behaviour later allowed silent zeros → rev 2043.

### 2026-05-07/08 — Session UI: markdown rendering, info card, scroll preservation
**platform code (UI)** · revs 1658–1665, 1687–1689
- **Problem observed:** students saw literal `**stars**`; polling replaced the chat container and jumped to the top every 3 s.
- **Change:** `safe_markdown` (Redcarpet, HTML filtered) for LLM output; innerHTML swap with scroll restore.
- **Outcome / status:** live. `safe_markdown`'s lack of LaTeX later motivated the no-LaTeX directive (08-27).

### 2026-05-07 — Grounding moves to the user message; backend stops injecting scenario prose
**prompt assembly** · rev 1656
- **Problem observed:** the system message mixed persona with "the case"; an auto-appended scenario paragraph pushed English prompt engineering into Ruby.
- **Change:** grounding text → first user message with scenario and PDF; scenario paragraph removed; the done-sentinel directive becomes the single backend-owned English text. The grader keeps grounding in system (its rubric source).
- **Outcome / status:** live.

### 2026-05-07 — Same-role message consolidation; prompt required; PDF sent to the LLM
**platform code / prompt assembly** · revs 1650–1653
- **Problem observed:** consecutive `user` messages degrade Gemini/OpenAI and Anthropic refuses them; a viva with no prompt tag silently ran with only the done-sentinel instruction; the LLM never saw the PDF.
- **Change:** `consolidate_role_runs`; assembly raises without a prompt; PDF as an `image_url` part in the first user message (for gateway providers SUPERSEDED 08-26 by OpenAI `file` blocks).

### 2026-05-07 — `Llm::Request` hierarchy; viva error handling tightened
**platform code** · revs 1634–1648; `doc/llm-refactor-handoff-2026-05-07.md`
- **Problem observed:** retry/error contract ad hoc; grade JSON failures swallowed (job "succeeded"); one regression crashed every LLM job → eternal spinner; `viva_turn_service`/`viva_grade_service` sat outside the YAML anchor so `config_for(:llm)` never loaded them and the abstract base raised.
- **Change:** retryable vs deterministic errors (`ResponseError`); viva services raise on no-JSON so Solid Queue records the failure; config keys moved inside the anchor; console `Llm::Request.preview` for prompt-assembly debugging.

### 2026-05-05 — Scenario sent as the first user message; wire-role fix; first `Viva-Exam.md`
**docs/tooling + platform code** · revs 1623–1630
- **Problem observed:** authors could say *how* to interview (tag) but not *what* to interview about; `role: "student"` was sent literally on the wire.
- **Change:** `problem.description` sent as the first user message on every turn and grader call; student → user remap; grader becomes system + user(scenario) + user(transcript).
- **Outcome / status:** live; description made the primary scenario channel by D5 (07-20).

### 2026-05-04 — Viva start route bug; Re-grade moved to Turbo Stream
**platform code** · revs 1605–1606, 1611
- **Problem observed:** `set_problem` read `params[:problem_id]` on a member route passing `:id` — every start 404'd; Re-grade used `remote: true` + `.js.haml`.
- **Change:** read `params[:id]`; integration tests; `button_to` + Turbo + shared toast, GET → POST.

### 2026-04-19 — Chula Genie wiring (chula_cp)
**model/provider** · chula_cp revs 1590–1591
- **Change:** `VivaTurnGenieAssist` / `VivaGradeGenieAssist` POST through Genie's OpenAI-compatible endpoint; default model gemini-2.5-flash.
- **Outcome / status:** SUPERSEDED 2026-08-27 by the Chula AI Gateway flip.

### 2026-04-19 — Viva exam feature lands
**platform code** · revs 1587–1588
- **Problem observed:** no oral-exam alternative to code submission.
- **Change:** `compilation_type: viva_exam`; `viva_turns` (one row per turn, sequence assigned under a row lock) and `viva_grades`; provider-agnostic `Llm::VivaTurnAssist` / `Llm::VivaGradeAssist` (OpenAI-compatible shape, concrete provider via `config/llm.yml`); sentinel `Language("viva")`; `VivaSessionsController` start/show/answer/refresh with a polling Stimulus controller; the interview ends when the model emits `[[VIVA_DONE]]`.
- **Outcome / status:** core architecture unchanged since. Prompt storage in `llm_prompt` tags SUPERSEDED 07-21 (D6); `viva_grounding` tag kind SUPERSEDED 07-19 (`GroundingMaterial`).
