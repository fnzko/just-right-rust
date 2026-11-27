# Sourced by the hooks. Reads the event from stdin and sets `state` to the path prefix of this
# session's files, or leaves it empty when the event has no session id or the user has no home.
# The files live under the user's own state directory, never in a shared temporary directory.
state=
session=$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
if [ -n "$session" ] && [ -n "${HOME:-}" ]; then
  root="${XDG_STATE_HOME:-$HOME/.local/state}/just-right-rust"
  if (umask 077 && mkdir -p "$root") 2>/dev/null; then
    state="$root/$(printf '%s\n%s\n' "$session" "$(pwd -P)" | cksum | tr ' ' '-')"
  fi
fi
