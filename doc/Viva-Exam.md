# Viva Exam

A **viva exam** is an oral-style programming exam conducted as a chat dialogue between the student and an LLM-driven interviewer. The student does not submit code; instead, an interactive interview is recorded as a transcript, and an LLM grader produces a final score and rubric from that transcript.

This document describes how a viva exam is structured, what an instructor must configure, how the system turns that configuration into the prompts sent to the LLM, and how the lifecycle handles failures.

---

# Authoring a Viva Problem

A viva exam is just a `Problem` with `compilation_type` set to `viva_exam`. From the student's point of view it appears in the problem list with a green **Start Viva** button (instead of the usual *New* / *Edit* code-submission button).

An author provides:

| Source | Role in the LLM call | Required? |
|---|---|---|
| **Statement PDF** (`problem.statement` ActiveStorage attachment) | First user message — the actual scenario, sent as a base64-encoded `image_url` content part | Strongly recommended; how the LLM actually sees the problem |
| `llm_prompt` tags | System message — interviewer instructions, persona, rubric. Same content is reused by the grader as the rubric source. | **Yes** — must include a `# Rubric` heading or the system refuses to start |
| `viva_grounding` tags | First user message — reference material the interviewer should treat as authoritative | Optional |
| `problem.description` | Supplementary text in the first user message (e.g. a short prose preface). The LLM relies on the PDF for the scenario itself. | Optional |

The system **validates the setup before starting a viva** (`Problem#viva_setup_errors`). Right now it only enforces one structural requirement: the `llm_prompt` content must contain a heading matching `^#+\s*Rubric` (case-insensitive). Failing this displays a clear flash on `/main/list` instead of starting a half-configured session.

## 1. `llm_prompt` tags — interviewer instructions AND grading rubric

Tags whose `kind` is `llm_prompt` carry the interviewer's instructions. Their `params` text is concatenated and placed at the top of the system message for **both** the interviewer turn job and the grader job.

A typical `llm_prompt` covers:

- **Persona and tone** — strict / encouraging / Socratic; required language (e.g. Thai or English).
- **Scaffolding behaviour** — what to do if the student struggles, how to step difficulty down.
- **Rules of engagement** — one question per response, no direct answers, anti-jailbreak guard, etc.
- **Knowledge grounding** — how to use the attached PDF, when to refer to grounding material.
- **A `# Rubric` section** *(required)* — what criteria the grader should score against. Because the grader prompt embeds this same `llm_prompt` content, the rubric you write here *is* what the grader sees. Without an explicit rubric, the grader has no rubric to score against and tends to refuse with prose, which fails the JSON-only contract.

Multiple `llm_prompt` tags may be attached to the same problem; their `params` are joined with blank lines.

There is no template substitution — the backend does not replace `{{TOPIC_NAME}}`, `{{MAX_TURNS}}`, etc. Literal `{{...}}` strings appear verbatim to the LLM. Write the actual values into the tag content.

## 2. Statement PDF — the scenario

Attach the problem statement as `problem.statement` (a regular ActiveStorage attachment, the same one downloaded via the `mdi(:description)` icon on `/main/list`). The system base64-encodes it into the first user message as an OpenAI-compatible `image_url` content part — every interview turn and the grade call re-sends the PDF so the LLM always has the canonical scenario in view.

For problems without a PDF, the `problem.description` text (if any) carries the scenario; if both are empty, the first user message becomes the placeholder string `(begin the interview)`, which works but gives the LLM nothing concrete to interview about.

## 3. `viva_grounding` tags — optional reference material

Tags whose `kind` is `viva_grounding` carry reference material the interviewer should treat as authoritative — lecture notes, model solutions, the rubric in detail, supplementary readings. The `grounding_payload` text of each tag is joined and inserted as an additional **text content part in the first user message** (under a `## Grounding Material` heading), *not* in the system message — so the interviewer reads it as "the case at hand" along with the scenario and PDF.

Grounding is optional. A problem with a clear PDF + clear `llm_prompt` instructions does not need grounding tags at all.

## 4. `problem.description` — optional supplement

The `description` field is free-form markdown. When the PDF is present, the description is supplementary (a short preface, hints, or a list of sub-scenarios to choose from). When the PDF is absent, the description becomes the scenario text.

---

# How the Prompt Is Assembled

The viva uses two distinct LLM calls per session: a **turn** call (per student exchange) and a **grade** call (once, after the interview ends). Each builds the same OpenAI-compatible chat-completion shape, but with different system prompts and message layouts.

## Per-turn (`Llm::VivaTurnAssist`)

The wire shape:

```
[
  { role: "system",
    content: "<llm_prompt tag content>

              <SECURITY_DIRECTIVE — platform-injected anti-jailbreak policy.
               Lists triggers (role spoofing, score/answer extraction,
               question laundering, out-of-band requests) and instructs the
               model to emit a user-visible banner plus `[[VIVA_ALERT]]`
               sentinel on detection.>

              When you are satisfied you have enough signal to grade
              the student, append exactly `[[VIVA_DONE]]` at the very
              end of your final message to end the interview."
  },
  { role: "user",
    content: [
      { type: "text", text: "<problem.description or '(begin the interview)'>" },
      { type: "text", text: "## Grounding Material\n\n<grounding tag content>" },  # if grounding exists
      { type: "image_url", image_url: "data:application/pdf;base64,..." }            # if PDF attached
    ]
  },
  { role: "assistant", content: "<prior turn 1>" },
  { role: "user",      content: "<prior turn 2>" },
  ...
]
```

A few properties of this design:

- **Two pieces of English text are backend-injected into the system prompt:** the `SECURITY_DIRECTIVE` (anti-jailbreak policy) and the `DONE_SENTINEL` directive. Everything else comes from the `llm_prompt` tag. Both are code contracts — `handle_response` parses for `[[VIVA_DONE]]` (transitions to grading) and `[[VIVA_ALERT]]` (jailbreak detected: sets `submissions.viva_terminated_at` and still transitions to grading on the partial transcript). Centralizing the security policy here (rather than asking each problem author to bake it into `llm_prompt`) keeps the sentinel string in lockstep with the parser and lets new attack patterns roll out platform-wide via a single edit.

- **Scenario, grounding, and PDF all live in the first user message** (as a multimodal content array). This keeps the system prompt purely about "how to interview" and the user message about "the case at hand." The arrangement mirrors how `Llm::CommentAssist` (the comment-on-submission flow) lays out PDF + managers + source code in its user message.

- **When the first user message has only the scenario text** (no PDF, no grounding), it degrades to a plain string for a simpler wire shape.

- **Consecutive same-role messages are consolidated** via `Llm::Request#consolidate_role_runs`. This matters when (a) the scenario user message is followed directly by a student-answer user message (the LLM doesn't see two consecutive `user` roles), and (b) when error-recovery has produced multiple student answers without successful assistant turns in between (Anthropic Claude rejects consecutive same-role messages outright; OpenAI/Gemini handle them less well than alternating turns).

- **The DB role enum is `student`; on the wire we send `user`.** `VivaTurn` rows store `role: student` so the transcript view can render student bubbles, but every message handed to the LLM remaps `student → user` to conform to the chat-completions role schema. System turns are filtered out entirely; processing/error turns are also filtered (the LLM doesn't see the placeholder it's about to fill, nor the failed turns).

- **No interview state lives outside the database.** The transcript of `VivaTurn` rows is the source of truth; every LLM call is rebuilt from the system prompt + first user message + the persisted prior turns. There is no hidden conversation state on the provider side.

## Grading (`Llm::VivaGradeAssist`)

The grader has a different system prompt (strict-JSON rubric grader) but reuses the same `llm_prompt` content as its rubric source:

```
[
  { role: "system",
    content: "You are a strict but fair grader for an oral programming exam.
              The user message contains the scenario (at the top), followed
              by the interview transcript (below).
              Respond ONLY with valid JSON matching this schema:
              { total_points: 0–100, narrative: '...', rubric: { criterion: score, ... } }
              Use the rubric and grounding context below as authoritative:
              <llm_prompt tag content>
              <viva_grounding tag content>"
  },
  { role: "user",
    content: [
      { type: "text", text: "<problem.description or '(no scenario provided)'>" },
      { type: "image_url", image_url: "data:application/pdf;base64,..." },  # if PDF attached
      "Transcript:\n\nASSISTANT: <turn 1>\n\nUSER: <turn 2>\n\n..."
    ]
  }
]
```

(`consolidate_role_runs` merges the scenario + transcript into one user message when both are strings; when the PDF is attached the user content is an array.)

Key differences from the turn call:

- **The rubric/grounding lives in the system prompt** (not the user message). For the grader's role, rubric IS the rules — system-level material.
- **No `[[VIVA_DONE]]` directive** — the grader doesn't have an end condition; it produces JSON and exits.
- **Strict-JSON contract** — the grader must respond with parseable JSON matching the schema, no markdown fences, no prose. `Llm::Request::ResponseError` is raised when this is violated, and `viva_grade.llm_response_raw` is preserved for admin inspection.

---

# Lifecycle of a Viva Session

1. **Start.** The student clicks **Start Viva** on `/main/list`.
   - `Problem#viva_setup_errors` runs. If the `llm_prompt` tag has no `# Rubric` section, redirects to `/main/list` with a flash alert listing what's missing. No submission is created.
   - Defensive check: if the user already has an active (non-archived) viva for this problem, refuses. Stops a stale tab or direct POST from creating a parallel session.
   - Otherwise: creates a `Submission` (language `viva`, no source code), an opening `system` marker turn (`"(interview start)"`), and an `assistant` placeholder turn (`status: processing`). Enqueues `Llm::VivaTurnAssistJob`. Redirects to the viva session page.

2. **First turn.** The interviewer LLM runs with system prompt + first user message (scenario text + grounding text + PDF). Replies with the scenario echoed back and the first question. The placeholder turn is updated with the response (sentinel stripped if present, status `:ok`). The session page polls every 3 seconds and renders the new assistant message via the `safe_markdown` helper (Redcarpet with HTML filtering, so prompt-injection-via-HTML can't execute).

3. **Subsequent turns.** The student types an answer. A new student turn (`status: ok`) and a new assistant placeholder (`status: processing`) are written; the job is enqueued. The LLM runs with the full transcript and updates the placeholder.

4. **Done sentinel.** When the interviewer judges it has enough signal, it appends `[[VIVA_DONE]]` at the end of its response. The backend strips the sentinel before displaying the message, marks the submission as `:evaluating`, and enqueues `Llm::VivaGradeAssistJob`. The session UI hides the answer form, shows an "Interview ended. Grading in progress…" alert, and keeps polling.

4a. **Alert sentinel (jailbreak termination).** When the interviewer detects a jailbreak attempt under the SECURITY_DIRECTIVE policy, it emits a short user-visible banner ("⚠️ Jailbreaking attempt detected…") followed by `[[VIVA_ALERT]]`. The backend strips the sentinel, sets `submissions.viva_terminated_at = Time.current`, marks the submission `:evaluating`, and enqueues the same `Llm::VivaGradeAssistJob` so the partial transcript is still scored. (`done` is treated as true whenever ALERT is true — alert implies end-of-interview.) The student sees the banner as the model's final message; from the UI's perspective the session has ended normally.

5. **Grading.** The grader LLM receives its system prompt + the scenario + transcript. It returns strict JSON. The result is persisted as a `VivaGrade` (with `total_points`, `narrative`, `rubric`, `llm_response_raw`, cost), and the submission is set to `:done`. When `viva_terminated_at` is set, `VivaGradeAssist#grading_system_prompt` prepends a termination note instructing the grader to score academic content prior to termination normally (no extra rubric penalty for the termination — that's an instructor policy decision) but to explicitly call out the termination and flagged-for-review status in the student-facing `narrative`.

6. **Polling stops** once the submission status is terminal (`:done` or `:grader_error`) and there are no more `:processing` turns.

While a turn is in flight, the polling refresh swaps the chat area's inner content without disturbing the page's outer scroll anchor — the student's reading position is preserved.

---

# Failure Modes and Recovery

The error-handling contract aims for: **every failure produces a clear in-line error to the student AND a diagnostic record for the admin.** Most paths reach both surfaces; a small set still need a stuck-turn watchdog (deferred).

| Failure | Student sees | Admin sees | Recovery |
|---|---|---|---|
| Missing `# Rubric` in `llm_prompt` | Flash alert on `/main/list` listing what's missing; no submission created | (no failure recorded) | Author updates the tag, retries Start Viva |
| Provider raises immediately (`NotImplementedError` on master — no concrete service configured) | Red error frame on the placeholder turn, content `LLM error: NotImplementedError: ... must implement #execute_call` | `Llm::VivaTurnAssistJob` in `/grader_processes/queues` with class, message, expandable backtrace | Configure `viva_turn_service` (and `viva_grade_service`) in `config/llm.yml`; restart worker |
| Provider auth failure (e.g. Genie token fetch returns nil) | Red error frame with `LLM error: Could not obtain authentication token for ChulaGenie` | Same FailedExecution record | Fix credentials / TokenManager, archive viva, retry |
| Transient network errors (`Faraday::TimeoutError`, `Faraday::ConnectionFailed`, `ActiveRecord::Deadlocked`, `ActiveRecord::ConnectionTimeoutError`) | Spinner persists while retrying (the no-flicker design); after retries exhausted, red error frame with `LLM error (retries exhausted): <class>: <message>` | FailedExecution recorded after final retry | Restart worker / fix the underlying issue and re-trigger from admin |
| HTTP 4xx/5xx from the provider | Red error frame with the Faraday error | Same FailedExecution | Inspect Debug card's raw response if non-empty |
| LLM returns prose for the grade (no JSON) | Red "Grader error" alert with `Llm::Request::ResponseError: no JSON object found in grader response` | Same; **`viva_grade.llm_response_raw` is preserved** so admin can see the actual prose Gemini/etc. returned | Click **Re-run grading** (model picker on the Admin card) to retry, optionally upgrading to a stricter model like `gemini-2.5-pro` |
| LLM returns empty `choices` or missing `content` (turn) | Red error frame with `ResponseError: Empty or missing choices[0].message.content` | FailedExecution | Re-trigger a new turn (student submits another answer) |
| Worker process killed mid-call | Placeholder turn stays `:processing`; eternal spinner | Solid Queue eventually marks job released after `claim_after` timeout, no FailedExecution | Manual: update the stuck turn's status via console; or archive viva |

## Admin actions on the viva session page

The right-side cards (visible to users with `can_edit_problem?` permission on the problem — i.e., admins and group_editors):

- **Re-run grading** *(form with model picker)* — destroys the current `viva_grade` record, sets submission back to `:evaluating`, enqueues `Llm::VivaGradeAssistJob` with the chosen model (default = the service class's `DEFAULT_MODEL`). Useful when the grader returned prose or low-quality output; upgrading from `gemini-2.5-flash` to `gemini-2.5-pro` is the most common move.
- **Archive viva** *(soft archive)* — sets `submission.viva_archived_at = Time.current`. Transcript, grade, cost, and raw response are all preserved; only the submission's role as the canonical attempt is given up. The student's Start Viva button reappears on `/main/list`. Available only when the submission status is `:done` or `:grader_error` (refuses to archive an in-progress interview).
- **Debug card** — collapsible sections showing:
  - Last grader run summary (model, cost, when).
  - The grader's raw response body (the full HTTP response, not just the content).
  - **Grader request payload preview** — the JSON that *would be* sent on the next grader call, reconstructed from current state via `Llm::Request.preview`. PDFs in the payload are redacted to `<application/pdf base64, ~XKB redacted>` for readability.
  - **Turn request payload preview** — same for the next interviewer call.
  - **Per-turn responses** — every assistant turn's `llm_response_raw`, model, cost, token counts.

The archived state is also surfaced in the **student-visible** Viva Info card (an "archived" badge on the Status row + an "Archived X ago" note), so a student opening their archived viva understands why their grade no longer counts and why Start Viva is available again.

---

# Authoring Checklist

- [ ] Create a `Problem` with `compilation_type: viva_exam`.
- [ ] **Attach the problem statement as a PDF** (`problem.statement` ActiveStorage attachment). This is what the LLM actually sees as the scenario.
- [ ] Attach at least one `llm_prompt` tag with:
  - [ ] Interviewer persona / tone / language requirements.
  - [ ] **A `# Rubric` section** (validated; required) — the same rubric drives the grader.
  - [ ] Rules of engagement (one question per response, no direct answers, anti-jailbreak, etc.).
  - [ ] No `{{...}}` template literals — write the actual values.
- [ ] *(Optional)* Attach `viva_grounding` tags for additional reference material.
- [ ] *(Optional)* Add `problem.description` markdown if you want supplementary text (sub-scenarios, hints) outside the PDF.
- [ ] Confirm a `Language` named `viva` is seeded — the system requires it to create viva submissions.
- [ ] Confirm `viva_turn_service` and `viva_grade_service` are configured in `config/llm.yml` for the deployment (on chula_cp they're `Llm::VivaTurnGenieAssist` / `Llm::VivaGradeGenieAssist`; on master they're blank, intentionally — the abstract bases raise `NotImplementedError` to signal "no provider configured for this deployment").
- [ ] Have a colleague (or yourself, as an editor) run a viva end-to-end before exposing it to students. Read the transcript and the rubric breakdown. If the grader returned prose, escalate to `gemini-2.5-pro` via the Re-run grading model picker.

# Decision Log (why some things are the way they are)

- **Scenario in PDF, not description.** Originally we considered the description-as-scenario approach, but real problem statements are usually written as PDFs (with diagrams, code blocks, formatting). Forcing instructors to re-type or markdown-ify the PDF would be redundant. The Genie-relayed Gemini API accepts PDFs as `image_url` content parts, and they're attended-to properly.
- **One `llm_prompt`, two consumers.** The interviewer and grader use the same `llm_prompt` tag content — the interviewer reads it as "how to behave," the grader reads it as "what rubric to score against." Splitting into separate `interviewer_prompt` / `grader_rubric` tag kinds was considered but adds complexity for marginal benefit; instructors think of "how to interview and what to score" as one thing.
- **Backend doesn't template `{{...}}`.** Considered, rejected — adds substitution complexity for fields (max-turns, target-difficulty, topic) that the backend doesn't enforce anyway. If you want hard caps on turn count, that's a separate feature.
- **Grounding in user message, not system.** Switched from system to user on 2026-05-08 to match the interviewer's mental model: rubric is "rules" (system), scenario + PDF + grounding is "the case" (user). The grader keeps grounding in system because the grader's grounding IS its rubric source.
- **Soft archive instead of delete.** Discussed at length on 2026-05-09. Destroying a submission cascades to viva_turns, viva_grade, comments, evaluations — irreversible and lossy. Soft archive (`viva_archived_at` timestamp) preserves the audit trail and admin can un-archive via Rails console.
