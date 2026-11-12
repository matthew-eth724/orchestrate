# orchestrate

Plan on the strong model you are already talking to. Write the code on a cheap one. Let the strong model review and fix until it approves.

An orchestrator skill for [Pi](https://github.com/badlogic/pi-mono). The session model acts as architect: it plans, dispatches narrow briefs to subagents on a cheap model, reads the real diff, classifies defects, and re-dispatches until either the code is clean or it admits it is blocked.

## Install

```bash
git clone https://github.com/matthew-eth724/orchestrate.git
orchestrate/scripts/install.sh
```

Pass an explicit agent dir if yours is not `~/.pi/agent`:

```bash
orchestrate/scripts/install.sh /path/to/agent-dir
```

Then `/reload` in a running Pi session. The installer also drops `orchestrate-setup.sh` in `<agent-dir>/bin/` so you can re-run the model picker later.

Pick your models (or jump to [Setup](#setup-choose-your-models)):

```bash
~/.pi/agent/bin/orchestrate-setup.sh
```

Two entry points after install:

| Command | Source |
|---|---|
| `/orchestrate <task>` | prompt template |
| `/skill:orchestrate <task>` | skill command |

## Setup: choose your models

Run the setup wizard after installing:

```bash
~/.pi/agent/bin/orchestrate-setup.sh
```

It asks two questions:

1. **Architect** — the model that plans, reviews, and approves.
   `session` (default) uses the model your Pi session already runs, so planning and review stay inline with no extra tokens. Picking a specific model moves planning and review into subagents on that model.
2. **Worker** — the model that writes the code.

Then it asks for an optional worker reasoning effort (`low`, `medium`, `high`, or blank to inherit).

Wizard output lands in `<agent-dir>/orchestrate.json`:

```json
{
  "architect": "session",
  "worker": "nvidia/nemotron-3.5-super-vl-120b-a12b",
  "effort": "high"
}
```

`<agent-dir>` is `~/.pi/agent` unless `PI_CODING_AGENT_DIR` is set. If the file is missing, the skill uses its built-in defaults and says so once.

### Non-interactive

```bash
orchestrate-setup.sh --list                              # show models
orchestrate-setup.sh --show                              # current config
orchestrate-setup.sh --architect session \
                     --worker nvidia/z-ai/glm-5.3-flash  # set both
orchestrate-setup.sh --reset                             # back to defaults
```

Model choices resolve in this order: the request itself ("orchestrate with fable as architect") → `orchestrate.json` → an `orchestrate workers` line in `pstack-models.md` for the worker → built-in defaults.

## The loop

| Phase | Actor | Output |
|---|---|---|
| Plan | architect | ordered steps, exact touch list, shared interfaces written out, one verification command per step, and the specific mistakes a cheap model is expected to make in each step |
| Dispatch | workers | code, plus `PASS` / `ISSUES` / `BLOCKED` with pasted verification output |
| Review | architect | reads the diff, classifies findings |
| Fix | workers | findings-only re-dispatch, same worker where its context still applies |
| Approve | architect | per-step approval, then one final verification on the combined diff |

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
orchestrate/SKILL.md                     the loop
orchestrate/references/plan.template.md  plan scaffold, written to .orchestrate/plan.md
orchestrate/references/brief.template.md worker brief + required report format
prompts/orchestrate.md                   bare /orchestrate command
scripts/setup.sh                         model picker, writes orchestrate.json
scripts/install.sh                       copies skill, prompt, and setup script into an agent dir
scripts/validate.sh                      frontmatter, links, clean install, setup round-trip
```

`orchestrate/` is a self-contained Agent Skills directory, so it can also be dropped into any runtime that reads `skills/` without the install script.

Plan files land in `.orchestrate/` inside the target repo. Add that directory to `.gitignore`.

## Limitations

- Designed for Pi. With `architect: session` there is no architect dispatch at all; with an architect slug, the session relays planning and review through subagents.
- Cheap models still need narrow steps. If a step needs judgment the architect cannot delegate, it does that part itself and leaves the mechanical rest to workers.
- Parallel dispatch is only safe for steps that touch disjoint files and share no interface in flight. The skill says so; it does not enforce it.
