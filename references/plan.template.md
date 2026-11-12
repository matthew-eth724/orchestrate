<!-- Copy to .orchestrate/plan.md in the target repo. Keep it out of the diff. -->

# Plan: <goal in one sentence>

**Done when:** <the done predicate — a command and its expected result>

## Constraints

- Must not change: <files, APIs, interfaces>
- Must stay stable: <behavior callers rely on>
- Style: <rules the repo enforces>

## Steps

### Step 1 — <name>

- **Scope:** <what this step does, one paragraph>
- **Touches:** `path/a.ts` (edit), `path/b.ts` (new)
- **Interfaces used:** <signature or type, written out in full>
- **Verify:** `<command>` → <expected result>
- **Risks for a cheap model:** <specific mistakes you expect>
- **Dispatch to:** <worker>

### Step 2 — <name>

...

## Shared interfaces

```ts
// Copy the exact declarations here; workers must not invent these.
```

## Out of scope

- <things a worker might be tempted to do, and must not>
