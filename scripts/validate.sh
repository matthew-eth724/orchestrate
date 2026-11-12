#!/usr/bin/env bash
# Validate that the skill is well formed and installable.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
skill="$root/orchestrate"
fail=0

err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
ok()  { printf 'ok: %s\n' "$*"; }

# 1. SKILL.md exists with valid frontmatter.
[ -f "$skill/SKILL.md" ] || err "SKILL.md missing"
name=$(sed -n 's/^name: *//p' "$skill/SKILL.md" | head -1 | tr -d '"')
desc=$(sed -n 's/^description: *//p' "$skill/SKILL.md" | head -1)

[ "$name" = "orchestrate" ] || err "name must be 'orchestrate', got '$name'"
[ -n "$desc" ] || err "description missing"
[ "${#desc}" -le 1024 ] || err "description exceeds 1024 chars"
case "$name" in
  *[!a-z0-9-]*) err "name has invalid characters" ;;
  -*) err "name starts with a hyphen" ;;
  *-) err "name ends with a hyphen" ;;
  *--) err "name has consecutive hyphens" ;;
esac
[ "$fail" -eq 0 ] && ok "frontmatter"

# 2. Name matches directory name (portability across Agent Skills runtimes).
[ "$(basename "$skill")" = "orchestrate" ] || printf 'warn: repo dir is not named %s; harmless for Pi, required by some runtimes\n' "$name"

# 3. Every relative markdown link in SKILL.md resolves.
while read -r link; do
  [ -e "$skill/$link" ] || err "SKILL.md links to missing file: $link"
done < <(grep -o '](\([^)]*\.md\))' "$skill/SKILL.md" | sed 's/^](//; s/)$//')
[ "$fail" -eq 0 ] && ok "relative links resolve"

# 4. Referenced references exist.
for f in references/plan.template.md references/brief.template.md; do
  [ -f "$skill/$f" ] || err "missing $f"
done
[ "$fail" -eq 0 ] && ok "reference templates present"

# 5. Prompt template has a description and points at the skill.
grep -q '^description:' "$root/prompts/orchestrate.md" || err "prompt template lacks description"
grep -q 'orchestrate/SKILL.md' "$root/prompts/orchestrate.md" || err "prompt template does not load SKILL.md"
[ "$fail" -eq 0 ] && ok "prompt template"

# 6. Install into a throwaway HOME and prove the files land where Pi looks.
inst=$(mktemp -d)
HOME="$inst" "$root/scripts/install.sh" >/dev/null
for f in skills/orchestrate/SKILL.md skills/orchestrate/references/plan.template.md skills/orchestrate/references/brief.template.md prompts/orchestrate.md; do
  [ -f "$inst/.pi/agent/$f" ] || err "install did not create $f"
done
[ "$fail" -eq 0 ] && ok "clean install lands in \$HOME/.pi/agent"

# 7. Scripts parse, and setup.sh writes a config the skill can read.
for s in scripts/install.sh scripts/setup.sh scripts/validate.sh; do
  bash -n "$root/$s" || err "syntax error in $s"
done
if [ "$fail" -eq 0 ]; then ok "scripts parse"; fi

tmpc=$(mktemp -d)
trap 'rm -rf "$tmpc"' EXIT
AGENT_DIR="$tmpc" "$root/scripts/setup.sh" --architect session --worker nvidia/nemotron-3.5-super-vl-120b-a12b --effort high >/dev/null
python3 - "$tmpc/orchestrate.json" <<'PY' || err "setup.sh wrote an unreadable config"
import json, sys
c = json.load(open(sys.argv[1]))
assert c["architect"] == "session", c
assert c["worker"] == "nvidia/nemotron-3.5-super-vl-120b-a12b", c
assert c["effort"] == "high", c
PY
[ "$fail" -eq 0 ] && ok "setup.sh writes a valid config"

# 8. The skill documents the config file it depends on.
grep -q 'orchestrate.json' "$skill/SKILL.md" || err "SKILL.md does not read orchestrate.json"
[ "$fail" -eq 0 ] && ok "SKILL.md reads orchestrate.json"

exit "$fail"
