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
# Strip quoting and surrounding whitespace; reject empty values, not just
# absent fields (an empty field passes a plain "does the key exist" check).
clean() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'; }
name=$(sed -n 's/^name://p' "$skill/SKILL.md" | head -1 | clean)
desc=$(sed -n 's/^description://p' "$skill/SKILL.md" | head -1 | clean)

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

# 7. Scripts parse.
for s in scripts/install.sh scripts/setup.sh scripts/validate.sh; do
  bash -n "$root/$s" || err "syntax error in $s"
done
[ "$fail" -eq 0 ] && ok "scripts parse"

# 8. setup.sh writes a config the skill can read, against a fixture catalog.
tmpc=$(mktemp -d)
trap 'rm -rf "$tmpc"' EXIT
mkdir -p "$tmpc/.pi/agent"
cp "$root/scripts/fixtures/models.json" "$tmpc/.pi/agent/models.json"
AGENT_DIR="$tmpc/.pi/agent" "$root/scripts/setup.sh" \
  --architect strong/strong-model --worker testvendor/cheap-model --effort high >/dev/null
python3 - "$tmpc/.pi/agent/orchestrate.json" <<'PY' || err "setup.sh wrote an unreadable config"
import json, sys
c = json.load(open(sys.argv[1]))
assert c["architect"] == "strong/strong-model", c
assert c["worker"] == "testvendor/cheap-model", c
assert c["effort"] == "high", c
PY
[ "$fail" -eq 0 ] && ok "setup.sh writes a valid config"

# 9. setup.sh refuses to invent models.
expect_fail() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then err "$label should have failed"; else ok "refuses: $label"; fi
}
expect_fail "no --architect" env AGENT_DIR="$tmpc/.pi/agent" "$root/scripts/setup.sh" --worker testvendor/cheap-model
expect_fail "unknown slug" env AGENT_DIR="$tmpc/.pi/agent" "$root/scripts/setup.sh" --architect strong/strong-model --worker nope/nothing
nocat="$tmpc/nocat/.pi/agent"
mkdir -p "$nocat"
expect_fail "missing models.json" env AGENT_DIR="$nocat" "$root/scripts/setup.sh" --list
expect_fail "empty input" sh -c "printf '\n\n\n' | AGENT_DIR=$tmpc/.pi/agent $root/scripts/setup.sh"

# 10. The vendored-id prefix is collapsed so slugs are usable.
AGENT_DIR="$tmpc/.pi/agent" "$root/scripts/setup.sh" --list | grep -Fxq "testvendor/vendored-model" \
  || err "model list does not collapse a vendored id prefix"
AGENT_DIR="$tmpc/.pi/agent" "$root/scripts/setup.sh" --list | grep -Fxq "testvendor/testvendor/vendored-model" \
  && err "model list still shows a doubled prefix"
[ "$fail" -eq 0 ] && ok "model list collapses vendored prefixes"

# 10b. Conform to the Agent Skills specification, using the spec skill's own
#      validator when it is installed. Never hard-require it.
agent_skills_validator="$HOME/.pi/agent/skills/agent-skills/scripts/validate-skill.sh"
if [ -x "$agent_skills_validator" ]; then
  if out=$("$agent_skills_validator" "$skill" 2>&1); then
    ok "agentskills.io validator: $(printf '%s\n' "$out" | tail -1)"
  else
    err "agentskills.io validator failed:
$out"
  fi
else
  printf 'skip: agentskills.io validator not installed\n'
fi

# 10c. Every path SKILL.md tells a reader to run must exist in at least one of
#      the places the skill can be read: a clone, or an install.
[ -e "$root/scripts/setup.sh" ] || err "SKILL.md tells readers to run scripts/setup.sh, which is missing from the repo"
[ -e "$root/scripts/install.sh" ] || err "install.sh missing"
[ "$fail" -eq 0 ] && ok "setup paths referenced by SKILL.md exist"

# 11. No general default anywhere in the shipped skill or scripts.
if grep -rEq '(worker|architect)[^=]*=\s*"?[a-zA-Z0-9_-]+/[a-zA-Z0-9._/-]+' "$root/scripts/setup.sh" \
   || grep -rEq 'default[_a-z]*worker|default[_a-z]*architect' "$root/scripts/setup.sh"; then
  err "a hard-coded default model remains in the setup script"
else
  ok "no hard-coded default model"
fi

# 12. The skill documents the config file it depends on and the no-default rule.
grep -q 'orchestrate.json' "$skill/SKILL.md" || err "SKILL.md does not read orchestrate.json"
grep -qi 'no built-in default' "$skill/SKILL.md" || err "SKILL.md does not state the no-default rule"
[ "$fail" -eq 0 ] && ok "SKILL.md documents config requirements"

exit "$fail"
