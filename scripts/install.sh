#!/usr/bin/env bash
# Install the orchestrate skill and its /orchestrate prompt template.
# Usage: scripts/install.sh [agent-dir]   (default: $HOME/.pi/agent)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
agent_dir="${1:-$HOME/.pi/agent}"

skill_dir="$agent_dir/skills/orchestrate"
prompt_dir="$agent_dir/prompts"

mkdir -p "$skill_dir/references" "$prompt_dir"

cp "$root/orchestrate/SKILL.md" "$skill_dir/SKILL.md"
cp "$root/orchestrate/references/plan.template.md" "$skill_dir/references/plan.template.md"
cp "$root/orchestrate/references/brief.template.md" "$skill_dir/references/brief.template.md"
cp "$root/prompts/orchestrate.md" "$prompt_dir/orchestrate.md"

printf 'installed skill  -> %s\n' "$skill_dir"
printf 'installed prompt -> %s\n' "$prompt_dir/orchestrate.md"
printf '\nRun /reload in a running Pi session, then /orchestrate <task>.\n'
