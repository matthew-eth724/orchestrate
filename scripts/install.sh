#!/usr/bin/env bash
# Install the orchestrate skill, its /orchestrate prompt template, and its setup
# script. Usage: scripts/install.sh [agent-dir]   (default: $HOME/.pi/agent)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
agent_dir="${1:-$HOME/.pi/agent}"

skill_dir="$agent_dir/skills/orchestrate"
prompt_dir="$agent_dir/prompts"
bin_dir="$agent_dir/bin"

mkdir -p "$skill_dir/references" "$prompt_dir" "$bin_dir"

cp "$root/SKILL.md" "$skill_dir/SKILL.md"
cp "$root/references/plan.template.md" "$skill_dir/references/plan.template.md"
cp "$root/references/brief.template.md" "$skill_dir/references/brief.template.md"
cp "$root/prompts/orchestrate.md" "$prompt_dir/orchestrate.md"

# setup.sh derives the agent dir from its own location, so install it at a path
# the user keeps. It is also usable straight from the clone.
install -m 0755 "$root/scripts/setup.sh" "$bin_dir/orchestrate-setup.sh"

printf 'installed skill  -> %s\n' "$skill_dir"
printf 'installed prompt -> %s\n' "$prompt_dir/orchestrate.md"
printf 'installed setup  -> %s\n' "$bin_dir/orchestrate-setup.sh"
printf '\nNext:\n  1) %s\n  2) /reload in a running Pi session\n  3) /orchestrate <task>\n' "$bin_dir/orchestrate-setup.sh"
