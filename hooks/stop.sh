#!/bin/sh
# Symposium Stop hook: checks the Rust lines the session added and hands the findings back to the
# agent. A finding is reported once per session, and a session gets at most three reports.
dir=$(dirname "$0")
. "$dir/state.sh"
[ -n "$state" ] && [ -s "$state.base" ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
: >> "$state.seen"
: >> "$state.untracked"
: >> "$state.reports"
[ "$(wc -l < "$state.reports")" -lt 3 ] || exit 0
base=$(cat "$state.base")
[ "$base" != none ] || base=$(git hash-object -t tree /dev/null)
case "$base" in *[!0-9a-f]*) exit 0 ;; esac
diff_added() {
  git -c core.quotepath=off diff --no-color --no-ext-diff --no-textconv \
    --src-prefix=a/ --dst-prefix=b/ --inter-hunk-context=0 -U0 "$@"
}
findings=$(
  {
    diff_added --relative "$base" -- '*.rs'
    git -c core.quotepath=off ls-files --others --exclude-standard -- '*.rs' | while IFS= read -r path; do
      diff_added --no-index -- /dev/null "$path"
    done
  } 2>/dev/null | awk -v seen="$state.seen" -v skip="$state.untracked" -f "$dir/added-lines.awk"
)
[ -n "$findings" ] || exit 0
echo report >> "$state.reports"
{
  printf '%s\n' "just-right-rust check: findings in the Rust lines this session added."
  printf '%s\n' "$findings"
  printf '%s\n' "Fix each one in the lines you added, changing existing code just enough where that is what it takes. That the existing code does the same is not a reason to keep one. Keep a finding only when the rule does not apply to that line, and say why in one line. Then finish."
} >&2
exit 2
