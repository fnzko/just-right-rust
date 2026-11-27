#!/bin/sh
# Checks the hooks against small throwaway repositories. Usage: sh hooks/test.sh [shell]
SH="${1:-sh}"; H=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export XDG_STATE_HOME="$T/state"
failed=0
start() { (cd "$1" && printf '{"SessionStart":{"session_id":"%s","cwd":"x"}}' "$2" | $SH "$H/session-start.sh" >/dev/null); }
stop() { (cd "$1" && printf '{"Stop":{"session_id":"%s","cwd":"x"}}' "$2" | $SH "$H/stop.sh" 2>"$T/err"; echo $? >"$T/code"); }
repo() { mkdir -p "$1/src" && (cd "$1" && git init -q && printf 'pub fn a() {}\n' > src/lib.rs && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm start); }
expect() { code=$(cat "$T/code"); hits=$(grep -c "$3" "$T/err"); if [ "$code" = "$1" ] && [ "$hits" = "$2" ]; then echo "ok   $4"; else failed=1; echo "FAIL $4 (exit $code want $1, hits $hits want $2)"; sed 's/^/     /' "$T/err" | head -6; fi; }

repo "$T/a"; start "$T/a" A; printf 'pub fn p(t: &str) -> u16 { t.parse().expect("n") }\n' >> "$T/a/src/lib.rs"
stop "$T/a" A; expect 2 1 "panic on failure" "A clean repo: new expect reported"
stop "$T/a" A; expect 0 0 "panic on failure" "A second stop is silent"

repo "$T/b"; printf 'pub fn old() { None::<u8>.unwrap(); }\n' >> "$T/b/src/lib.rs"; printf 'fn u() { None::<u8>.unwrap(); }\n' > "$T/b/src/untracked.rs"
start "$T/b" B; stop "$T/b" B; expect 0 0 "panic" "B dirty tree at start: nothing reported"
printf 'pub fn fresh() { None::<u8>.expect("x"); }\n' >> "$T/b/src/lib.rs"; printf 'fn more() { None::<u8>.unwrap(); }\n' >> "$T/b/src/untracked.rs"
stop "$T/b" B; expect 2 1 "panic on failure" "B only the line added after start is reported"
expect 2 1 "fresh" "B it is the new line"

mkdir -p "$T/c/src"; (cd "$T/c" && git init -q); start "$T/c" C; printf 'pub fn p() { None::<u8>.unwrap(); }\n' > "$T/c/src/lib.rs"
stop "$T/c" C; expect 2 1 "panic on failure" "C repository with no commits"

mkdir -p "$T/d/src"; start "$T/d" D; stop "$T/d" D; expect 0 0 "panic" "D no repository: silent"
(cd "$T/d" && git init -q); printf 'pub fn p() { None::<u8>.unwrap(); }\n' > "$T/d/src/lib.rs"
stop "$T/d" D; expect 2 1 "panic on failure" "D repository created during the session"

repo "$T/e"; start "$T/e" E; mkdir -p "$T/e/tests"
printf 'pub fn ok() {}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() { let v = Some(1).unwrap(); assert!(Some(v).is_some()); }\n}\n' >> "$T/e/src/lib.rs"
printf '#[test]\nfn t() { let v: u8 = "1".parse().unwrap(); assert_eq!(v, 1); }\n' > "$T/e/tests/it.rs"
stop "$T/e" E; expect 2 0 "panic on failure" "E unwrap in test scopes is not a panic finding"
expect 2 1 "weak assertion" "E a weak assertion in a unit test is reported"

repo "$T/f"; start "$T/f" F; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'pub fn f%s() { None::<u8>.expect("%s"); }\n' $i $i; done >> "$T/f/src/lib.rs"
stop "$T/f" F; expect 2 10 "panic on failure" "F ten listed"; expect 2 1 "and 2 more" "F the rest is counted"
stop "$T/f" F; expect 0 0 "panic" "F second stop is silent"

repo "$T/g"; start "$T/g" G; for i in 1 2 3; do printf 'pub fn g%s() { None::<u8>.expect("%s"); }\n' $i $i >> "$T/g/src/lib.rs"; stop "$T/g" G; done
printf 'pub fn g4() { None::<u8>.expect("4"); }\n' >> "$T/g/src/lib.rs"; stop "$T/g" G; expect 0 0 "panic" "G a session gets at most three reports"

repo "$T/h"; start "$T/h" H; printf 'pub fn p() { None::<u8>.unwrap(); }\n' > "$T/h/src/café.rs"; (cd "$T/h" && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm more)
stop "$T/h" H; expect 2 1 "src/café.rs:1" "H committed file with an accent in its name"

repo "$T/i"; (cd "$T/i" && git config diff.noprefix true && git config color.ui always && git config diff.mnemonicPrefix true); start "$T/i" I; printf 'pub fn p() { None::<u8>.unwrap(); }\n' >> "$T/i/src/lib.rs"
stop "$T/i" I; expect 2 1 "src/lib.rs:2" "I unusual git diff configuration"

repo "$T/j"; (cd "$T/j" && printf '{"SessionStart":{"session_id":null,"cwd":"x"}}' | $SH "$H/session-start.sh" > "$T/err"); echo 0 > "$T/code"; expect 0 1 '^{"SessionStart":{"additionalContext":"\\n# Rust rules' "J null session still gets the rules"
(cd "$T/j" && printf '{"Stop":{"session_id":null,"cwd":"x"}}' | $SH "$H/stop.sh" 2>"$T/err"; echo $? >"$T/code"); expect 0 0 "panic" "J null session: stop is silent"

repo "$T/k"; start "$T/k" K; printf 'pub fn a2() -> Result<HashMap<u8, String>, MyError> { todo() }\npub fn b2() -> Result<(), String> { Ok(()) }\npub fn w(x: u8) -> u64 { x as u64 }\n' >> "$T/k/src/lib.rs"
stop "$T/k" K; expect 2 1 "untyped error" "K only the String error is an untyped error"

Q="$T/q\"uote"; repo "$Q"; start "$Q" Q; printf 'pub fn p() { None::<u8>.unwrap(); }\n' >> "$Q/src/lib.rs"
stop "$Q" Q; expect 2 1 "panic on failure" "L directory name with a quote"
exit $failed
