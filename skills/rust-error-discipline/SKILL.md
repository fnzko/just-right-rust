---
name: rust-error-discipline
description: Handle Rust failures without hiding them. No silent defaults or discarded `Result`s, panics only for bugs, context added once when an error crosses a layer, and typed errors that keep the cause. Use when writing or reviewing code that handles `Result` or `Option`, adds a fallback, parses input, does I/O, casts or adds numbers that come from input, or reaches for `unwrap`, `expect`, `unwrap_or_default`, `let _ =` or `catch_unwind`.
---

# Error discipline

Every failure is something a caller can act on, a case the spec gives a value to, or a bug. Propagate the first, default the second, and panic on the third with a message that names the broken assumption. Never turn a failure into a plausible value, and never report it twice.

## Pick the response

Take the first line that fits:

1. A user, a file, the network or the environment can cause it: return `Result` and propagate with `?`.
2. The spec says absence means a value (an optional header, an optional key): use that default.
3. Only a bug in this code explains it: change the type so the state cannot exist, or panic with a message that names the invariant.
4. No caller can act on it (best-effort cleanup, a receiver that is gone): handle it here, once, and log it or say why it cannot matter.

## Propagate failures instead of substituting a default

```rust
// Avoid.
let config = load_config(&path).unwrap_or_default();
let limit: u32 = raw.parse().unwrap_or(0);
let items: Vec<Item> = lines.iter().filter_map(|l| l.parse().ok()).collect();

// Prefer.
let config = load_config(&path)?;
let limit: u32 = raw.parse()?;
let items: Vec<Item> = lines.iter().map(|l| l.parse()).collect::<Result<_, _>>()?;
```

- A default makes a broken file look like an empty one. `unwrap_or_default()`, `.ok().unwrap_or(..)`, `filter_map(Result::ok)` and `Err(_) => Vec::new()` are the same shape.
- When the spec defines the default, apply it to the `Option` after the error was propagated: `find_limit(&config)?.unwrap_or(DEFAULT_LIMIT)`.
- A fallback from an optimization to the slow path is fine; log it at debug level.
- In a batch of untrusted items, skip the bad ones and report each. Do not drop them silently and do not fail the whole batch.

## Handle or propagate every `Result`

```rust
// Avoid.
let _ = fs::remove_file(&tmp);
fs::remove_file(&tmp).ok();

// Prefer.
if let Err(e) = fs::remove_file(&tmp) {
    warn!("removing {}: {e}", tmp.display());
}
```

- Propagate when the caller can act on it; log when it cannot. Do not end a function with an unconditional `Ok(())` after ignoring the failures of its steps.
- `let _ =` stays for calls that are best-effort by design, with a comment giving the reason: `let _ = tx.send(item);` when the receiver may be gone, or a write to an infallible writer.

## Return `Result` for input, panic only for bugs

```rust
// Avoid.
let age: u8 = input.parse().unwrap();
let user = users.get(&id).unwrap();
let order = panic::catch_unwind(|| parse_order(text)).map_err(|_| Error::Syntax)?;

// Prefer.
let age: u8 = input.parse()?;
let user = users.get(&id).expect("ids are only handed out after insert");
let order = parse_order(text)?;
```

- Anything input can trigger returns `Result`. That includes indexing and slicing input: `text.get(..4)`, not `&text[..4]`. Replacing `unwrap` with `expect` on input is still a panic.
- Panic when a bug is the only explanation. The message says why the value must be there, not `"failed to get user"`. Finished code has no bare `unreachable!()`, `todo!()` or `unimplemented!()`.
- `catch_unwind` is not error handling: make the callee return `Result`. It belongs only at a thread, task or FFI boundary, where the caught panic is logged as a bug.

## Check numbers that come from input

```rust
// Avoid.
let len = data.len() as u32;
let end = offset + len;

// Prefer.
let len = u32::try_from(data.len())?;
let end = offset.checked_add(len).ok_or(Error::Overflow)?;
```

- `as` truncates and wraps without a trace; `try_from` returns an error.
- Cap the sizes, counts and recursion depth that input controls before allocating or recursing.
- Use `wrapping_*` or `saturating_*` when that is the intended policy. Arithmetic that can only overflow through a bug stays plain.

## Add context when an error crosses a layer, and report it once

```rust
// Avoid.
let text = fs::read_to_string(&path).map_err(|e| {
    error!("load failed: {e}");
    e
})?;

// Prefer.
let text = fs::read_to_string(&path)
    .with_context(|| format!("reading {}", path.display()))?;
```

- Context names what was attempted and on what (path, key, id, line): `"reading config.toml"`, not `"failed to read"` or `"error"`.
- An error is either handled (logged, retried, turned into a response) or returned, never both. The top level reports it once, with its chain.
- Do not pass a label into a function only so it can print its own errors. Return the `Result` and let the caller add the context.

## Give callers a typed error that keeps the cause

```rust
// Avoid.
fn read(path: &Path) -> Result<String, String> {
    fs::read_to_string(path).map_err(|e| e.to_string())
}

// Prefer.
#[derive(Debug, thiserror::Error)]
#[error("reading {}", .path.display())]
struct ReadError { path: PathBuf, source: io::Error }

fn read(path: &Path) -> Result<String, ReadError> {
    fs::read_to_string(path).map_err(|source| ReadError { path: path.into(), source })
}
```

- Across modules an error is never `String`, `&'static str` or `()`, and `map_err(|_| ...)` never drops the cause: keep it in `source`.
- Libraries expose typed errors that callers can match on; binaries use `anyhow` with context; `anyhow::Error` stays out of a library's public API. The `error-handling-basics`, `application-errors` and `library-errors` skills cover both crates.
- Show the cause through `source()` or in `Display`, never both. Messages are lowercase, without trailing punctuation.

## Remove the impossible state instead of handling it

```rust
// Avoid.
struct App { config: Option<Config> }

fn port(&self) -> Result<u16, Error> {
    let config = self.config.as_ref().ok_or(Error::NotConfigured)?;
    Ok(config.port)
}

// Prefer.
struct App { config: Config }

fn port(&self) -> u16 {
    self.config.port
}
```

- Do not add an `Option`, an error variant or an `else` branch for a condition that the types or the callers rule out. A function that cannot fail does not return `Result`.
- A branch that needs `unreachable!` means the representation should change.
- A cheap `debug_assert!` documents an invariant without a runtime branch.

## Do not over-apply

- "No `unwrap`" never means "use a default". Replacing a panic with `unwrap_or_default()` trades a loud bug for a wrong answer; use `?`, or `expect` with the invariant.
- Do not invent error variants for states that only a bug can reach. Panic there.
- A bare `unwrap()` is fine in tests, on a poisoned `Mutex::lock()`, and when the check that guards it is on the adjacent line.
- Do not add context at every `?` inside one layer, and do not wrap an error in words it already says.
- Do not build an error enum that no caller matches on. In a binary, `anyhow` with context is enough.
- A deliberate second check at a trust boundary is not defensive code. Keep it.

## Review checklist

Before finishing, verify in the diff:

- no failure becomes a default, an empty collection or `None` unless the spec defines that value;
- no `Result` is dropped with `let _ =`, `.ok();` or an unconditional `Ok`, except commented best-effort calls;
- nothing that input can trigger panics: no `unwrap`, `expect`, index or slice on input;
- every `expect` and `unreachable!` names the invariant, and no `todo!()` or `unimplemented!()` remains;
- `catch_unwind` appears only at a thread, task or FFI boundary;
- sizes and offsets that come from input use `try_from` and checked arithmetic;
- an error that crosses a layer says what was attempted, and is logged or returned, not both;
- no error type is `String`, `&'static str` or `()`, and no library function returns `anyhow::Result`;
- no `Option`, `Result` or branch exists for a state that cannot occur.

These searches find candidates for every item except the third and the sixth, which the lints below cover; read each hit before changing it:

```sh
rg -n '\.unwrap_or_default\(\)|\.ok\(\)\s*\.unwrap_or|\.unwrap_or\((0|""|false|String::new\(\))\)|filter_map\((\s*Result::ok|.*\.ok\(\)\))|Err\(_\)\s*=>\s*(Vec::new|None|Default::default|String::new)'
rg -n '^\s*let _ = |\.ok\(\);'
rg -n 'expect\("(failed|error|unable)|unreachable!\(\)|todo!\(|unimplemented!\(|catch_unwind|resume_unwind'
rg -nU '(error|warn)!\([^;]*\);\s*\n\s*return Err'
rg -n 'Result<[^;{}]*,\s*(String|&.static\s+str|\(\))\s*>|map_err\(\|\w+\|\s*\w+\.to_string\(\)\)|pub (async )?fn [^{;]*-> anyhow::Result|Box<dyn (std::error::)?Error'
rg -ni 'should (not|never) happen|just in case|else \{\s*unreachable!'
```

No Clippy lint flags a silent default, a doubled report or `catch_unwind`. `clippy::let_underscore_must_use` and `clippy::unused_result_ok` (restriction) flag discarded results; rustc's `unused_must_use` only covers the bare call. `clippy::unwrap_used` (restriction), with `allow-unwrap-in-tests = true` in `clippy.toml`, flags every `unwrap`, but its fix is `expect`, which on input is still a panic, and it does not read the message. `clippy::cast_possible_truncation` and `clippy::cast_possible_wrap` (pedantic) flag lossy `as` casts; `clippy::arithmetic_side_effects` (restriction) flags every integer `+`, so keep it for code that parses input. `clippy::map_err_ignore` (restriction) flags `map_err(|_| ...)` and `clippy::result_unit_err` (style, on by default) flags a public `Result<_, ()>`; neither flags an error turned into a `String`.
