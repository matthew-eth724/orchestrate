<!-- Fill this in for every dispatch. No cross-references to earlier messages. -->

# Worker brief

**Goal of the whole change:** <one sentence>

**Read first:** `<path>/.orchestrate/plan.md` — sections Constraints, Step N, Shared interfaces.

## Your step

<Exact scope. What to build, and what is already built.>

## Files you may touch

- `path/a.ts`
- `path/b.ts`

## Files you must not touch

- <everything else, or name the tempting ones>

## Interfaces

Use only these declarations. Do not invent types, helpers, or imports that you have not read in this repo:

```ts
<copy from the plan>
```

## Verification

Run this before reporting:

```
<command>
```

Expected: <exact expected output or exit code>.

## Rules

- Do not refactor outside the file list above.
- Do not add dependencies.
- Do not add defensive code for states the caller cannot produce.
- If the plan is wrong about the repo, stop and report `BLOCKED` with what you found instead of improvising.

## Report format

```
RESULT: PASS | ISSUES | BLOCKED
FILES: <path>:<lines> for each change
VERIFY: <command> → <actual output, quoted>
DEVIATIONS: <where you departed from this brief, or "none">
NOTES: <anything the architect must know, or "none">
```

Do not claim PASS without pasting the verification output.
