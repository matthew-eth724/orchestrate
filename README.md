# orchestrate

Plan on the strong model you are already talking to. Write the code on a cheap one. Let the strong model review and fix until it approves.

An orchestrator skill for [Pi](https://github.com/badlogic/pi-mono). The session model acts as architect: it plans, dispatches narrow briefs to subagents on a cheap model, reads the real diff, classifies defects, and re-dispatches until either the code is clean or it admits it is blocked.

## Install

```bash
git clone https://github.com/matthew-eth724/orchestrate-skill.git
orchestrate-skill/scripts/install.sh
```

Pass an explicit agent dir if yours is not `~/.pi/agent`:

```bash
orchestrate-skill/scripts/install.sh /path/to/agent-dir
```

Then `/reload` in a running Pi session.

Two entry points after install:

| Command | Source |
|---|---|
| `/orchestrate <task>` | prompt template |
| `/skill:orchestrate <task>` | skill command |

## Configure the worker model

Default worker is `nvidia/nemotron-3.5-super-vl-120b-a12b`. Override it by adding one line to `~/.pi/agent/pstack-models.md`:

```
orchestrate workers: <provider/model-id>
```

If the line is missing, the skill uses its default. `inherit-parent` is accepted but defeats the point: workers then run on the architect model.

## The loop

| Phase | Actor | Output |
|---|---|---|
| Plan | session model | ordered steps, exact touch list, shared interfaces written out, one verification command per step, and the specific mistakes a cheap model is expected to make in each step |
| Dispatch | workers | code, plus `PASS` / `ISSUES` / `BLOCKED` with pasted verification output |
| Review | session model | reads the diff, classifies findings |
| Fix | workers | findings-only re-dispatch, same worker where its context still applies |
| Approve | session model | per-step approval, then one final verification on the combined diff |

Findings are classified so fixes stay targeted:

- `BLOCKER` — wrong behavior, broken build, violated constraint
- `SLOP` — dead code, invented helper, needless abstraction, defensive junk
- `DRIFT` — correct but not what the plan said
- `NIT` — style

Two rules are non-negotiable in the skill:

1. **No self-execution.** The architect does not edit implementation files. Planning acts (reading code, writing an interface, writing a test) are allowed; mechanical edits go to a worker.
2. **No approval without evidence.** The architect reruns the verification command itself. A worker's claim of `PASS` is not evidence.

## Why it works with a cheap executor

The cost of a cheap model is guessing. The plan removes the guessing:

- every step names the exact files it may touch
- shared interfaces are copied into the plan verbatim, so workers cannot invent types or helpers
- every step carries a verification command, so a wrong answer fails loudly instead of quietly
- each step lists the mistakes expected of a cheap model, which the architect checks for by name

Fixes are capped at three rounds per step. After that the architect must narrow the step or report blocked. A step that fails three rounds is never approved.

## Layout

```
orchestrate/SKILL.md                    the loop
orchestrate/references/plan.template.md plan scaffold, written to .orchestrate/plan.md
orchestrate/references/brief.template.md worker brief + required report format
prompts/orchestrate.md                  bare /orchestrate command
scripts/install.sh                      copies skill + prompt into an agent dir
scripts/validate.sh                     checks frontmatter, links, and a clean install
```

`orchestrate/` is a self-contained Agent Skills directory, so it can also be dropped into any runtime that reads `skills/` without the install script.

Plan files land in `.orchestrate/` inside the target repo. Add that directory to `.gitignore`.

## Limitations

- Designed for Pi. The session model is the architect by construction: the skill never passes a `model` to its own work, only to worker dispatches.
- Cheap models still need narrow steps. If a step needs judgment the architect cannot delegate, it does that part itself and leaves the mechanical rest to workers.
- Parallel dispatch is only safe for steps that touch disjoint files and share no interface in flight. The skill says so; it does not enforce it.
