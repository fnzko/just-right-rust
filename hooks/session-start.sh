#!/bin/sh
# Symposium SessionStart hook: gives the agent the Rust rules and records the working tree as it is
# now, so the Stop hook can tell which lines the session added.
dir=$(dirname "$0")
. "$dir/state.sh"
if [ -n "$state" ] && [ ! -e "$state.base" ]; then
  find "$root" -type f -mtime +7 -exec rm -f {} + 2>/dev/null
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    base=$(git -c user.name=hook -c user.email=hook@localhost stash create 2>/dev/null)
    [ -n "$base" ] || base=$(git rev-parse --verify -q HEAD 2>/dev/null)
    [ -n "$base" ] || base=$(git hash-object -t tree /dev/null)
    git -c core.quotepath=off ls-files --others --exclude-standard -- '*.rs' > "$state.untracked" 2>/dev/null
  else
    base=none
  fi
  (set -C; printf '%s\n' "$base" > "$state.base") 2>/dev/null
fi
printf '{"SessionStart":{"additionalContext":"'
awk 'front < 2 && /^---$/ { front++; next } front == 2' "$dir/../skills/rust-rules/SKILL.md" \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' \
  | awk '{ printf "%s\\n", $0 }'
printf '"}}\n'
