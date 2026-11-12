#!/usr/bin/env bash
# Configure the default architect and worker models for the orchestrate skill.
#
#   orchestrate-setup.sh                      interactive picker
#   orchestrate-setup.sh --list               list available models
#   orchestrate-setup.sh --architect M --worker M [--effort L]
#   orchestrate-setup.sh --show
#   orchestrate-setup.sh --reset
#
# Writes $AGENT_DIR/orchestrate.json, which the skill reads at the start of every
# run. AGENT_DIR defaults to $HOME/.pi/agent.
set -euo pipefail

agent_dir="${AGENT_DIR:-${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}}"
config="$agent_dir/orchestrate.json"
models_json="$agent_dir/models.json"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Print provider/model pairs from the Pi models.json. There is no built-in
# fallback list: an unreadable catalog is an error, not a guess.
list_models() {
  local from_file=""
  if [ -r "$models_json" ] && command -v python3 >/dev/null 2>&1; then
      from_file="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for prov, v in d.get("providers", {}).items():
    for m in v.get("models", []):
        mid = m["id"]
        # Some catalogs store the vendor inside the id (nvidia/nemotron-...),
        # which would compose to provider/vendor/model. Collapse the repeat.
        if mid.startswith(prov + "/"):
            mid = mid[len(prov) + 1:]
        print(prov + "/" + mid)
' "$models_json" 2>/dev/null || true)"
  fi
  [ -n "$from_file" ] || die "cannot read models from $models_json — is Pi configured?"
  printf '%s\n' "$from_file"
}

# Fail when a slug is neither 'session' nor present in the model catalog.
check_registered() {
  local slug="$1"
  [ "$slug" = "session" ] && return 0
  if list_models | grep -Fxq "$slug"; then
    return 0
  fi
  die "unknown model '$slug' — run --list to see available models"
}

show() {
  if [ ! -f "$config" ]; then
    printf 'not configured — run scripts/setup.sh\n'
    return 0
  fi
  printf 'config:         %s\n' "$config"
  python3 -c '
import json, sys
c = json.load(open(sys.argv[1]))
for k in ("architect", "worker", "effort"):
    if k in c:
        print("%-15s %s" % (k + ":", c[k]))
' "$config"
}

write_config() {
  local architect="$1" worker="$2" effort="${3:-}"
  mkdir -p "$agent_dir"
  python3 -c '
import json, sys
path, architect, worker, effort = sys.argv[1:5]
cfg = {"architect": architect, "worker": worker}
if effort:
    cfg["effort"] = effort
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
' "$config" "$architect" "$worker" "$effort"
  printf 'wrote %s\n\n' "$config"
  show
}

# Numbered picker. Prints the chosen slug to stdout; prompt goes to stderr.
pick_model() {
  local prompt="$1" items=() m i=1 sel
  while IFS= read -r m; do
    [ -n "$m" ] && items+=("$m")
  done < <(list_models)
  [ "${#items[@]}" -gt 0 ] || die "no models found in $models_json"
  printf '\n' >&2
  for m in "${items[@]}"; do
    printf '  %2d) %s\n' "$i" "$m" >&2
    i=$((i + 1))
  done
  printf '%s: ' "$prompt" >&2
  read -r sel
  [ -n "$sel" ] || die "no choice made"
  case "$sel" in
    *[!0-9]*)
      # Not a number: treat the input as a literal model slug.
      printf '%s' "$sel"
      ;;
    *)
      if [ "$sel" -lt 1 ] || [ "$sel" -gt "${#items[@]}" ]; then
        die "choice $sel out of range 1..${#items[@]}"
      fi
      printf '%s' "${items[$((sel - 1))]}"
      ;;
  esac
}

prompt_architect() {
  local choice
  printf 'Architect model (plans, reviews, approves).\n' >&2
  printf '  1) session — the model this session already runs\n' >&2
  printf '  2) a specific model — planning runs in a subagent on that model\n' >&2
  printf 'Choice: ' >&2
  read -r choice
  [ -n "$choice" ] || die "no choice made"
  case "$choice" in
    1|session) printf 'session' ;;
    2|pick)     printf '%s' "$(pick_model 'Architect model')" ;;
    *)          printf '%s' "$choice" ;;
  esac
}

interactive() {
  printf '\n=== orchestrate setup ===\n'
  printf 'config: %s\n\n' "$config"

  local architect worker effort
  architect="$(prompt_architect)"
  printf '\n'
  worker="$(pick_model 'Worker model (writes the code)')"
  printf '\n'
  printf 'Worker reasoning effort — low, medium, high, or blank to inherit: '
  read -r effort
  case "$effort" in
    low|medium|high) ;;
    *) effort="" ;;
  esac

  [ -n "$worker" ] || die "worker model is required"
  printf '\n'
  check_registered "$architect"
  check_registered "$worker"
  write_config "$architect" "$worker" "$effort"
  printf '\nNext: /reload in a running Pi session, then /orchestrate <task>\n'
}

architect=""
worker=""
effort=""

case "${1:---interactive}" in
  --list) list_models ;;
  --show) show ;;
  --reset)
    rm -f "$config"
    printf 'removed %s\n' "$config"
    ;;
  --interactive) interactive ;;
  --architect|--worker|--effort)
    while [ $# -gt 0 ]; do
      case "$1" in
        --architect) architect="${2:-}"; shift 2 ;;
        --worker)    worker="${2:-}"; shift 2 ;;
        --effort)    effort="${2:-}"; shift 2 ;;
        *) die "unknown argument: $1" ;;
      esac
    done
    [ -n "$worker" ] || die "--worker is required"
    [ -n "$architect" ] || die "--architect is required (use 'session' to plan on this session's model)"
    check_registered "$architect"
    check_registered "$worker"
    write_config "$architect" "$worker" "$effort"
    ;;
  -h|--help)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) die "unknown argument: $1 (see --help)" ;;
esac
