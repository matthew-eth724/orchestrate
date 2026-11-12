---
name: orchestrate
description: "Plan with a strong model, execute through subagents on a cheap model, then review, spot flaws, and re-dispatch until the strong model approves. Use for /orchestrate, 'orchestrate this', or any implementation you want planned by a strong model but written by a cheap one."
---

# Orchestrate

A stronger **architect** model plans and reviews; cheaper **worker** models write the code. The architect is either the model this session already runs or a model chosen in setup. Neither model has a default: run `<agent-dir>/bin/orchestrate-setup.sh` once before the first use.

Two rules that keep this skill honest:

- **No self-execution.** The architect does not edit implementation files. Any task that changes files goes to a worker. Typing the implementation yourself defeats the point of the skill.
- **No approval without evidence.** You approve only after reading the real diff and seeing a verification command actually run. "Looks right" is not approval.

## Setup

1. **Read the request.** Restate the goal in one sentence and the done predicate ("done means X passes"). If the request is ambiguous in a way that changes the design, ask one question before planning.
2. **Resolve the models from configuration.** There is no general default for either model. Read `<agent-dir>/orchestrate.json` (`<agent-dir>` is `~/.pi/agent` unless `PI_CODING_AGENT_DIR` says otherwise). The skill does not run until both models are known.

   | Setting | Source |
   |---|---|
   | architect | value named in the request, else the `architect` key |
   | worker | value named in the request, else the `worker` key |
   | effort | value named in the request, else the `effort` key |

   - **If the file is missing, or either key is missing or empty:** stop before planning. Tell the user the orchestrate models are unconfigured and give them the command to fix it. Use whichever of these exists, in order:

     ```bash
     ~/.pi/agent/bin/orchestrate-setup.sh          # installed by scripts/install.sh
     scripts/setup.sh                              # from a clone of the skill repo
     ```

     Do not infer a worker from `pstack-models.md`, the session model, or anything else, and do not pick one yourself. One exception: if the request names both models explicitly, proceed and write them into `orchestrate.json` so the choice persists.
   - **architect = `session`**: you plan and review inline, on this session's model. Use your own `read`, `bash`, and diff tools.
   - **architect = a model slug**: planning and review run in subagents on that model, since this session's model is not the architect. Dispatch a planning subagent with `model` set to the architect slug; it returns the plan. Dispatch review the same way, giving it the plan path and the diff. **You relay and enforce the loop; you do not invent the plan.** If the architect subagent is unavailable, stop and report rather than falling back to planning yourself.
   - **worker**: pass as `model` on every dispatch. If the configured worker is `inherit-parent` or `auto`, that is a misconfiguration — stop and report, because the skill's premise is lost.
   - If a dispatch fails because a slug is invalid, read the error, pick the closest valid slug in the same provider, and report the substitution.
3. **Open a todolist.** Plan / Dispatch / Review / Fix / Approve, one entry each. Extend as rounds accumulate.
4. **Write the plan** to `.orchestrate/plan.md` in the working repo (gitignored or outside the diff), following [the plan template](references/plan.template.md).

## Phase 1 — Plan (architect only)

Produce a plan a stranger could execute without asking questions. It must name:

| Section | Content |
|---|---|
| Goal | One sentence, plus the done predicate |
| Constraints | Files that must not change, APIs that must stay stable, style rules |
| Steps | Ordered units, each small enough to land and verify alone |
| Touch list | Exact file paths each step creates or edits |
| Interfaces | Types, signatures, or schemas that steps share, written out |
| Verification | The exact command(s) that prove each step, and the expected result |
| Risks | What the cheap model will probably get wrong here, stated per step |

The **Risks** section is what makes cheap execution work. Name the specific mistakes you expect: off-by-one, ignored error paths, invented APIs, copied-from-nowhere helpers, forgotten call sites.

Do not dispatch until the plan has a verification command per step. If you cannot name one, plan the test first as its own step.

## Phase 2 — Dispatch (workers)

- One subagent per step or per independent group of steps. Parallel only when steps touch disjoint files and share no interface-in-flight.
- Call the `agent` tool with `subagent_type: "general-purpose"`, `model` set to the worker slug, `run_in_background: true` for parallel sets.
- Every brief stands alone. Do not write "as discussed above".
- The brief contains: goal, the plan file path, this step's scope, the interfaces it may use, files it may touch and files it may not, the verification command, and the required report format from `references/brief.template.md`.
- Tell the worker explicitly: **do not refactor outside your scope, do not add dependencies, do not invent APIs you have not read in this repo.**

## Phase 3 — Review (architect only)

Read the actual artifact, not the worker's summary:

1. `git diff` (or `git diff --stat` then the full diff) for every touched file.
2. Confirm the scope match: no stray files, no unrelated reformatting.
3. Re-read each hunk against the plan. Classify every defect:

| Class | Meaning | Action |
|---|---|---|
| `BLOCKER` | Wrong behavior, broken compile, breaks a stated constraint | Fix round |
| `SLOP` | Dead code, needless abstraction, invented helper, defensive junk | Fix round |
| `DRIFT` | Correct but not what the plan said | Fix round if the plan was right; amend the plan if the worker found a real problem |
| `NIT` | Style or wording | Fix round only if cheap |

4. Run the verification command **yourself**. Never trust a worker's claim that it passed.

Write the review as findings list in chat: file:line, class, one-line defect, and the required fix.

## Phase 4 — Fix

- Empty findings → Phase 5.
- Otherwise write a second-round brief to the **same** worker when its context still applies, or a fresh worker using `send_message` if it is cheaper to restate. Each fix brief names only the findings, the files, and the verification command.
- Cap at **3 rounds**. On the third failed round, stop dispatching and do one of:
  - **Narrow** the step to something the cheap model can land, plan the rest again, or
  - **Report blocked** with the exact findings you could not clear.

  Never approve a step that failed 3 rounds.

## Phase 5 — Approve

Approve a step only when all hold:

- Verification command run by you, output pasted or quoted.
- Diff read in full by you.
- Zero open `BLOCKER` or `SLOP` findings.
- Constraints from the plan intact.

State approval per step: `STEP 3 APPROVED — verify: <cmd> → <result>`.

After all steps: run the full verification once more on the combined diff, then give the final report:

- What changed, file by file.
- Verification transcript.
- Findings you cleared, per round.
- Anything you accepted knowing it was imperfect, and why.
- Model substitutions, gaps, or dropped workers.

## Models

Both models come from `<agent-dir>/orchestrate.json`, written by the setup script (`<agent-dir>/bin/orchestrate-setup.sh` once installed, or `scripts/setup.sh` from the repo). There is no built-in default: the skill refuses to run on a guess.

```json
{
  "architect": "session",
  "worker": "<provider/model-id>",
  "effort": "optional, low | medium | high"
}
```

- **architect**: required. `session` keeps planning and review on this session's model. A slug moves planning and review into subagents on that model, with this session acting only as the loop's enforcer.
- **worker**: required. The model that writes code. Keep it cheap; that is the point.

Workers are cheap and fast, so they get narrow briefs and short loops. If a step needs judgment the skill cannot delegate, the architect does it as a planning act (reading code, writing the interface, writing the test) and leaves only the mechanical work to workers.

## References

- [Plan template](references/plan.template.md)
- [Worker brief template](references/brief.template.md)
