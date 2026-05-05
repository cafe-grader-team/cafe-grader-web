# Viva Exam

A **viva exam** is an oral-style programming exam conducted as a chat dialogue between the student and an LLM-driven interviewer. The student does not submit code; instead, an interactive interview is recorded as a transcript, and an LLM grader produces a final score and rubric from that transcript.

This document describes how a viva exam is structured, what an instructor must configure, and how the system turns that configuration into the prompts sent to the LLM.

---

# Authoring a Viva Problem

A viva exam is just a `Problem` with `compilation_type` set to `viva_exam`. From the student's point of view it appears in the problem list with a green **Start Viva** button (instead of the usual *New* / *Edit* code-submission button).

To author one, an instructor provides up to three pieces of content. Each piece plays a distinct role in the system prompt sent to the LLM.

| Source                    | Role in the prompt                       | Required? |
|---------------------------|------------------------------------------|-----------|
| `llm_prompt` tags         | Interviewer instructions (HOW & WHAT)    | Yes       |
| `problem.description`     | Scenario(s) to interview the student on  | Yes       |
| `viva_grounding` tags     | Reference material (mostly PDFs)         | Optional  |

## 1. `llm_prompt` tags — interviewer instructions

Tags whose `kind` is `llm_prompt` carry instructions about **how** the interviewer should behave and **what** topics or rubric points to cover. Their `params` text is concatenated and placed at the top of the LLM's system prompt.

Typical content for an `llm_prompt` tag:

- The interviewer persona and tone (strict, encouraging, Socratic, …).
- Topics to probe and the depth of follow-up expected.
- Rubric direction the grader should ultimately measure against.
- A selection rule when `problem.description` lists multiple scenarios — e.g. *"Pick exactly one scenario at random and base the entire interview on it."*
- A finishing condition — when the interviewer feels they have enough signal to grade.

Multiple `llm_prompt` tags may be attached to the same problem; their `params` are joined with blank lines.

## 2. `problem.description` — the scenario(s)

The problem's `description` field (markdown) is treated as the **scenario** for the viva. It can be a single scenario or a list of scenarios that the `llm_prompt` instructions tell the interviewer to choose from.

The description is **not** placed in the system prompt. It is sent as the **first user message** in the chat. The system prompt should instruct the interviewer that this first user message contains the scenario(s), to repeat the chosen scenario back to the student verbatim, and only then to begin the viva.

If `problem.description` is blank, the system synthesises a placeholder first user message (`(begin the interview)`) so the LLM still receives a valid conversation start. Authors are strongly encouraged to write a real scenario.

Markdown is sent as-is; the LLM understands headings, lists, code fences, and so on.

## 3. `viva_grounding` tags — optional reference material

Tags whose `kind` is `viva_grounding` carry reference material the interviewer should treat as authoritative — lecture notes, model solutions, the rubric in detail, supplementary readings. A grounding tag may have:

- `params` text (free-form notes), and/or
- one or more attached **PDF** files (preferred for longer reference material).

At interview time, the contents of all `viva_grounding` tags attached to the problem are joined and inserted into the system prompt under a `## Grounding Material` heading, after the `llm_prompt` instructions.

Grounding is optional. A problem with clear `llm_prompt` instructions and a self-contained `description` does not need any grounding tags at all.

---

# How the Prompt Is Assembled

Each turn of the viva (and the final grading call) builds a chat-completion request with this shape:

```
[
  { role: "system",    content: <SYSTEM PROMPT — see below> },
  { role: "user",      content: <problem.description>      },   ← always first; placeholder if blank
  { role: "assistant", content: <previous interviewer turn> },
  { role: "user",      content: <previous student answer>  },
  ...
]
```

The **system prompt** is composed of these sections, in order, separated by blank lines. Empty sections are omitted.

```
<llm_prompt tags joined>

## Grounding Material
<viva_grounding tags joined, including extracted PDF text>

The first user message contains the scenario or list of scenarios for this exam.
If multiple scenarios are listed, choose one (per any selection rule above; otherwise pick at random).
Repeat the chosen scenario back to the student verbatim, then begin the viva based on it.
[only included when problem.description is non-blank]

When you are satisfied you have enough signal to grade the student,
append exactly `[[VIVA_DONE]]` at the very end of your final message
to end the interview.
```

A few properties of this design worth noting:

- **The scenario is a user message, not a system rule.** This keeps "what to interview about" cleanly separated from "how to interview." It also lets `llm_prompt` instructions reference the user message naturally (*"the first user message will list the scenarios; pick one"*).
- **The DB role enum is `student`; on the wire we send `user`.** `VivaTurn` rows store `role: student` so the transcript view can render student bubbles, but every message handed to the LLM remaps `student → user` to conform to the OpenAI chat-completions role schema.
- **No interview state lives outside the database.** The transcript of `VivaTurn` rows is the source of truth; every LLM call is rebuilt from the system prompt + first-user(description) + the persisted turns. There is no hidden conversation state on the provider side.
- **The grader sees the same scenario as the interviewer.** The grading call sends three messages: a system prompt with rubric/grounding, a first user message containing the scenario, and a second user message containing the transcript. The grader's system prompt only describes this layout; it does not include the "repeat the scenario back" instruction (the grader does not converse).

---

# Lifecycle of a Viva Session

1. **Start.** The student clicks **Start Viva** on the problem list. A `Submission` is created (language `viva`, no source code), an interview transcript is initialised with a `system` marker turn, and an `assistant` placeholder turn is enqueued. The student is redirected to the viva session page.
2. **First turn.** The interviewer LLM runs with system prompt + `problem.description` as the first user message. It picks a scenario (per the `llm_prompt` selection rule), repeats it back to the student, and asks the first question. The placeholder turn is filled in with the response.
3. **Subsequent turns.** The student types an answer. A new student turn and a new assistant placeholder are written; the LLM runs again with the full transcript and updates the placeholder.
4. **Done sentinel.** When the interviewer feels it has enough signal, it appends `[[VIVA_DONE]]` at the end of its message. The system strips the sentinel, marks the submission as `evaluating`, and enqueues the grading job.
5. **Grading.** The grader LLM receives the same system prompt + scenario, plus the full transcript. It returns strict JSON of the form `{"total_points": 0–100, "narrative": "...", "rubric": {…}}`. The result is persisted as a `VivaGrade` and the submission is set to `done`.
6. **Re-grade (admin).** Admins can re-run the grader from the session page. Re-grading replaces the `VivaGrade` but does **not** start a new interview — the same transcript is graded again.

While a turn is in flight, the session page polls every few seconds and replaces the in-progress placeholder bubble with the response when it lands.

---

# Quick Authoring Checklist

- [ ] Create a `Problem` with `compilation_type: viva_exam`.
- [ ] Write a clear `description` (markdown). One scenario, or a numbered list of scenarios.
- [ ] Attach at least one `llm_prompt` tag describing interviewer behaviour, topics, rubric direction, and a selection rule if the description lists multiple scenarios.
- [ ] *(Optional)* Attach `viva_grounding` tags for reference material. Use PDF attachments for long content.
- [ ] Confirm a `Language` named `viva` is seeded — the system requires it to create viva submissions.
- [ ] Have a colleague run a viva end-to-end before exposing it to students, and read back the transcript and rubric to verify the interviewer is on-script.
