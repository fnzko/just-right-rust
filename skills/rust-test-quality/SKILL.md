---
name: rust-test-quality
description: Write Rust tests that fail when the code is wrong, with exact assertions, expected values that do not come from the code under test, and cases that do not depend on timing or on each other. Use when writing or changing `#[test]` functions, test modules, files under `tests/` or test helpers, when adding a regression test for a fix, and when reviewing tests that assert only `is_ok()`, non-emptiness or a substring.
---

# Test quality

A test is worth keeping only if it fails when the behavior is wrong. Assert exact results, take the expected values from outside the code under test, and keep every case independent of timing, the machine and the other cases.

## Assert the exact result

```rust
// Avoid.
assert!(!list_users(&store).is_empty());
assert!(find_user(&store, "carol").is_err());

// Prefer.
let names: Vec<_> = list_users(&store).into_iter().map(|u| u.name).collect();
assert_eq!(names, ["alice", "bob"]);
assert_eq!(find_user(&store, "carol"), Err(FindError::NotFound));
```

- `is_ok()`, `is_some()`, `!is_empty()`, `len() > 0` and "it did not panic" pass for almost every wrong answer. Compare the whole value and the exact error variant. Compare a collection whole, in a known order, not by its length and one element.
- Every test asserts something. A body without an assertion only checks that the code does not panic.

## Do not let an assertion pass on a fallback

```rust
// Avoid.
let config = load_config(&path).unwrap_or_default();
assert_eq!(config.retries, 3);
if let Ok(user) = find_user(&store, "alice") {
    assert_eq!(user.age, 30);
}

// Prefer.
let config = load_config(&path).unwrap();
assert_eq!(config.retries, 5);
let user = find_user(&store, "alice").unwrap();
assert_eq!(user.age, 30);
```

- `unwrap_or`, `unwrap_or_default` and `.ok()` turn a failure into a value the assertion may accept: `Config::default().retries` is 3, so the first test passes with no file at all. Choose inputs whose expected value differs from the default.
- An assertion inside `if let`, a `match` arm or a `for` over the result does not run when the value is missing or the collection is empty. Unwrap first, and assert the length before a loop.
- Use `unwrap()` in test bodies: the panic already names the line. `expect("create_user should succeed")` adds nothing. Write `expect` only when the message says what the location cannot.

## Take expected values from the spec, not from the code

```rust
// Avoid.
let expected: u64 = order.items.iter().map(|i| i.price_cents * i.quantity).sum();
assert_eq!(order.total_cents(), expected);

// Prefer.
let order = Order { items: vec![item(250, 2), item(750, 1)] };
assert_eq!(order.total_cents(), 1250);
```

- An expectation computed by the function under test, or by a copy of its logic, passes for every bug the two share. Write the literal, taken from the spec, a published test vector or a recording of the real system.
- For a bug fix, write the test first and run it against the unfixed code. A regression test that never failed says nothing about the fix. When the fix is already written, undo it locally and rerun the new test. A pure refactor needs no new test; the existing ones stay green, unchanged.

## Compare whole values, not one field of an untyped tree

```rust
// Avoid.
let json: serde_json::Value = serde_json::from_str(&body).unwrap();
assert_eq!(json["name"], "alice");
assert!(body.contains("age"));

// Prefer.
let user: User = serde_json::from_str(&body).unwrap();
assert_eq!(user, User { name: "alice".into(), age: 30 });
```

- Parse the output into its type and compare with `assert_eq!`, so a field the code drops or gets wrong fails the test. Derive `Debug` and `PartialEq` on the type for this.
- A substring matches in the wrong field too, and an index into `Value` checks one leaf and nothing around it.
- Where the output is the product (rendered text, CLI output, generated code), use the snapshot tool the project already has (`insta`, `expect-test`). Regenerate snapshots with the tool and read every changed line; never hand-edit or bulk-accept them. Redact ids, timestamps and ports first.

## Keep tests deterministic and isolated

```rust
// Avoid.
unsafe { env::set_var("APP_DATA_DIR", "/tmp/app-test") };
let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
let server = Server::start(listener, Config::from_env());
thread::sleep(Duration::from_millis(500));

// Prefer.
let dir = tempfile::tempdir().unwrap();
let config = Config { data_dir: dir.path().to_path_buf(), retries: 5 };
let listener = TcpListener::bind("127.0.0.1:0").unwrap();
let addr = listener.local_addr().unwrap();
let server = Server::start(listener, config);
server.ready().recv_timeout(Duration::from_secs(5)).unwrap();
```

- Tests in one binary run on parallel threads in no fixed order, so a fixed port, a fixed path, the process environment and a `static` are shared by all of them. Bind port 0 and read the address back, write under a temp dir, and pass settings as values. Each test creates the state it reads.
- A fixed sleep is too short on a loaded machine and wasted time on a fast one. Wait for the event (a channel, a `JoinHandle`, a readiness future) with a timeout that only a failure reaches. Under Tokio, pause the clock and advance it.
- No expected value depends on `SystemTime::now()`, `Instant::now()`, random values or generated ids. Inject them, as in the next section.

## Test the real code through a fake, not through a test-only branch

```rust
// Avoid.
pub fn expired(&self) -> Vec<String> {
    if cfg!(test) { return Vec::new(); }
    self.expired_at(SystemTime::now())
}

// Prefer.
let clock = FakeClock::at(SystemTime::UNIX_EPOCH);
let mut sessions = Sessions::new(clock.clone(), Duration::from_secs(60));
sessions.open("s1");
clock.advance(Duration::from_secs(61));
assert_eq!(sessions.expired(), ["s1"]);
```

- Production code does not know it is under test: no `cfg!(test)` branch, no `#[cfg(test)] impl` that replaces behavior, no special case for inputs named `test-...`.
- Take the first that works: the real component, an in-memory fake behind the same trait, a mock. Mock only what a test cannot run, such as an external network service. A fake that ships in the crate goes behind a `test-util` feature.

## One behavior per test, many inputs as one table

```rust
// Avoid.
#[test] fn test_status_1() { assert_eq!("pending".parse::<Status>().unwrap(), Status::Pending); }
#[test] fn test_status_2() { assert_eq!("shipped".parse::<Status>().unwrap(), Status::Shipped); }

// Prefer.
#[test]
fn parses_known_statuses() {
    for (input, want) in [("pending", Status::Pending), ("shipped", Status::Shipped)] {
        assert_eq!(input.parse::<Status>(), Ok(want), "input {input:?}");
    }
}
```

- Name the test after the scenario and its outcome (`get_after_eviction_returns_none`), not `test_cache_1`, `it_works` or `test_basic`.
- A test that inserts, reads, evicts and clears reports one failure for four causes. Split it by behavior.
- One behavior over many inputs is one loop over a table, with the input in every assertion message. Near-copies of a test function add count, not coverage.

## Define helpers once, keep the assertions in the test

```rust
// Avoid.
fn check_created(resp: &Response) {
    assert_eq!(resp.status, 201);
    assert!(!resp.body.is_empty());
}
check_created(&resp);

// Prefer.
mod common;

#[test]
fn creates_user() {
    let resp = common::app().post("/users", r#"{"name":"alice","age":30}"#);
    assert_eq!(resp.status, 201);
    assert_eq!(resp.json::<User>(), User { name: "alice".into(), age: 30 });
}
```

- Before writing a setup helper, search the test tree for one that exists. Integration tests share code through `tests/common/mod.rs`; a `tests/common.rs` would be compiled as a test binary of its own.
- Setup, builders and clients are shared. The action and the assertions stay in the test body, so reading the test shows what it checks.
- An assertion helper checks the one thing its name states and is marked `#[track_caller]`, so a failure points at the calling test.

## Do not over-apply

- Assert the key fragment of human prose such as an error message, not its full text. `contains` is the right check there.
- A multi-step end-to-end scenario is a good test when its name says so. Do not split it, and do not force tests with different bodies into one table or macro.
- A few repeated setup lines that keep a test readable on its own are fine. Do not extract a helper for them.
- Do not build a trait and a fake for something the test can run for real, such as a temp dir or a local socket.
- A sleep is fine when the timer itself is under test or the clock is paused. Comparing against a simpler reference implementation in a property test is a valid oracle.

## Review checklist

Before finishing, verify in the diff:

- every test asserts a value, a count or an error variant, not only `is_ok()`, emptiness or a substring;
- no assertion sits behind `if let`, `unwrap_or`, `unwrap_or_default` or a loop that may not run;
- no expected value is computed by the code under test, and each regression test was seen failing without the fix;
- structured output is compared as a whole typed value or a reviewed snapshot;
- no fixed sleep, port or path, environment change, wall clock or random value decides a result;
- production code has no test-only branch;
- test names describe the scenario, and the inputs of one behavior share one table;
- no new helper repeats an existing one or hides the assertions.

These searches find candidates for the first, second, fifth, sixth and seventh items, and for `expect` messages that add nothing. Run the fourth over production code and the others over test code; read each hit before changing it:

```sh
rg -n 'assert!\(\s*!?[^;]*\.is_(ok|err|some|none|empty)\(\)\s*[,)]|assert!\([^;]*\.len\(\)\s*(>|>=|!=)\s*[01]\b|assert!\([^;]*\.contains\('
rg -n 'unwrap_or(_default|_else)?\(|if let (Ok|Some)\(|\.expect\("[^"]*should (succeed|work)'
rg -n '\bsleep\s*\(|(127\.0\.0\.1|localhost):[1-9][0-9]{1,4}\b|env::(set_var|remove_var)|(SystemTime|Instant)::now|thread_rng|Uuid::new_v4'
rg -nU 'cfg!\(test\)|#\[cfg\(test\)\]\s*impl |is_test|TEST_MODE|"test[-_]'
rg -n 'fn \w*(_works|_success|_basic|_happy_path|_[0-9]+)\s*\('
```

No lint in Clippy's default groups checks what a test asserts, where its expected values come from or whether it is deterministic. When `clippy::unwrap_used` (restriction) is enabled, set `allow-unwrap-in-tests = true` in `clippy.toml` so test code is exempt; nothing flags an `expect` message that adds nothing.
