---
name: rust-ownership
description: Avoid needless clones, allocations and repeated work in Rust by borrowing in signatures, moving instead of copying, computing once per input and keeping lock scopes short. Use when fixing a borrow checker error, when writing function signatures, getters, loops over collections or code that locks shared state, and when reviewing code that adds `.clone()`, `.to_string()`, `.collect()` or a scan inside a loop.
---

# Ownership and allocation

Borrow what you read, move what you keep, and do each piece of work once per input. A `.clone()` that makes a borrow error go away usually hides a signature or a struct that asks for too much. Clones of small values and clones on cold paths stay; do not trade them for lifetimes or tricks.

## Before adding a clone

Take the first line that fits:

1. The value is not used afterwards: move it.
2. The callee only reads it: pass a borrow, and change the parameter to `&str`, `&[T]` or `&T` if it asks for more.
3. Only one field or element must be owned: filter first, then clone that field, not the whole element or collection.
4. A `&mut self` call conflicts with a borrow of one field: split the borrow.
5. The value is leaving a `&mut` place (drained, reset, replaced): `mem::take`, `mem::replace` or `Option::take`.
6. Read-only data is shared by several threads or owners: put it in an `Arc` once and clone the handle.
7. Anything else: keep the clone. That includes `Copy`-like, small and refcounted values, startup, configuration and error paths, and a clone that reads clearer than the borrow replacing it.

## Split the borrow or move the value out, do not clone the collection

```rust
// Avoid.
for item in self.items.clone() {
    self.index_item(&item);
}
for job in self.jobs.clone() {
    self.run(&job);
}
let batch = self.pending.clone();
self.pending.clear();

// Prefer.
for item in &self.items {
    self.index.add(item);
}
let jobs = std::mem::take(&mut self.jobs);
for job in &jobs {
    self.run(job);
}
self.jobs = jobs;
let batch = std::mem::take(&mut self.pending);
```

- The first conflict is between two fields that one `&mut self` method lumps together. Call the method of the field that changes, destructure (`let Self { items, index, .. } = self;`), or make the helper a free function over the fields it uses.
- When the helper needs most of `self`, move the collection out and write it back. The helper must not read that field meanwhile.
- `mem::take` leaves the default value behind, and an empty `Vec`, `String` or map does not allocate. `mem::replace` leaves the value you give it, and `Option::take` leaves `None`; prefer an `Option` field when a reader may run before the value is written back, so it sees "absent" and not an empty value.

## Borrow what you read, own what you keep

```rust
// Avoid.
impl Team {
    fn new(name: &str) -> Self { Self { name: name.to_string(), users: Vec::new() } }
    fn name(&self) -> String { self.name.clone() }
    fn user_names(&self) -> Vec<String> { self.users.iter().map(|u| u.name.clone()).collect() }
}
fn total(orders: &Vec<Order>) -> u64 { orders.iter().map(|o| o.total).sum() }

// Prefer.
impl Team {
    fn new(name: String) -> Self { Self { name, users: Vec::new() } }
    fn name(&self) -> &str { &self.name }
    fn user_names(&self) -> impl Iterator<Item = &str> { self.users.iter().map(|u| u.name.as_str()) }
}
fn total(orders: &[Order]) -> u64 { orders.iter().map(|o| o.total).sum() }
```

- A parameter that is only read is a borrowed view: `&str`, `&[T]`, `&Path`, `Option<&T>`, not `&String`, `&Vec<T>`, `&PathBuf`, `&Option<T>`, and not an owned `String` or `Vec<T>` the caller has to clone. Small `Copy` values go by value.
- A function that stores its argument takes it owned, so a caller that already has a `String` moves it in and no allocation hides inside.
- A getter returns `&str`, `&[T]`, `Option<&T>` or an iterator, and `Copy` fields by value. The caller clones when it needs to; the getter does not decide for every caller.

## Do not copy to compare, look up, count or share

```rust
// Avoid.
let known = roles.contains_key(&name.to_string());
let same = email.to_lowercase() == other.to_lowercase();
let paid = orders.iter().filter(|o| o.paid).collect::<Vec<_>>().len();
let worker = Worker { id, config: (*config).clone() };

// Prefer.
let known = roles.contains_key(name);
let same = email.eq_ignore_ascii_case(other);
let paid = orders.iter().filter(|o| o.paid).count();
let worker = Worker { id, config: Arc::clone(&config) };
```

- A `HashMap<String, _>` or `HashSet<String>` looks up by `&str`. `to_string`, `to_owned`, `format!` and `to_lowercase` each allocate. `eq_ignore_ascii_case` folds ASCII only; keep `to_lowercase` where Unicode case folding is required.
- Keep the iterator while the next step only iterates, counts, sums or tests (`count`, `sum`, `any`, `extend`). Collect when the result is reused, sorted or indexed, or when two phases must not interleave (spawn every thread, then join them).
- `(*config).clone()` copies the contents once per worker; `Arc::clone(&config)` bumps a count. The field becomes `Arc<Config>`, and payloads become `Arc<str>` or `Arc<[T]>` instead of a `String` or `Vec<T>` copied per reader.

## Compute once per input, look up by key

```rust
// Avoid.
fn is_number(s: &str) -> bool { Regex::new(r"^\d+$").unwrap().is_match(s) }
for id in &ids {
    notify(users.iter().find(|u| u.id == *id));
}

// Prefer.
static NUMBER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\d+$").unwrap());
fn is_number(s: &str) -> bool { NUMBER.is_match(s) }
let by_id: HashMap<UserId, &User> = users.iter().map(|u| (u.id, u)).collect();
for id in &ids {
    notify(by_id.get(id).copied());
}
```

- Parse, compile, sort and validate when the input changes (at load, in the constructor) and keep the result in a field or a `static LazyLock`. Do not redo it per call, per request or per item.
- `iter().find`, `position`, `any` and `Vec::contains` inside a loop are a nested scan. Build the map or `HashSet` once before the loop, or store the entities keyed by their identity in the first place.
- Use `BTreeMap` when iteration order reaches output. Keep the default hasher for keys a client controls.

## Reuse buffers and skip work nobody reads

```rust
// Avoid.
for order in orders {
    let mut line = String::new();
    render(order, &mut line);
    out.write_all(line.as_bytes())?;
}
let mut items: Vec<Item> = Vec::with_capacity(declared_len);
let text = format!("{state:?}");
debug!("state: {text}");

// Prefer.
let mut line = String::new();
for order in orders {
    line.clear();
    render(order, &mut line);
    out.write_all(line.as_bytes())?;
}
let mut items: Vec<Item> = Vec::with_capacity(declared_len.min(MAX_PREALLOC));
debug!(?state);
```

- A scratch buffer declared inside a loop allocates on every iteration. Declare it once and `clear()` it per item.
- Size a collection from a length you know. Cap a length that comes from input, or the input chooses how much memory to reserve. `collect` and `extend` size themselves.
- Do not format, clone or collect for a log line or a feature that may be off. Pass the value as a field; `tracing` formats it only when the level is enabled.

## Hold a lock only for the read or the write

```rust
// Avoid.
let n = state.lock().unwrap().clone().users.len();
let mut s = state.lock().unwrap();
for order in s.pending.drain(..) {
    submit(order)?;
}

// Prefer.
let n = state.lock().unwrap().users.len();
let pending = std::mem::take(&mut state.lock().unwrap().pending);
for order in pending {
    submit(order)?;
}
```

- Read the value you need under the guard. Do not clone the whole state out of the lock to read one field.
- Do I/O, formatting, sorting and calls into other components after the guard is dropped. Take or copy out only what that work needs, in one statement or a block.
- A guard created in the head of a `for`, `match`, `if let` or `while let` is held for the whole body. Bind the value with `let` first.

## Do not over-apply

- Keep a clone that is cheap, cold or clearer than the alternative. Do not thread lifetimes through structs to avoid one; own the data.
- Keep `&str` in a constructor when almost every caller only holds a borrow. `impl Into<String>` and `impl AsRef<str>` belong at published library entry points, not in internal code.
- A linear scan over a handful of items is fine and often faster than a map. Startup code, cold administrative paths and tests may recompute, and `format!` is fine for one-off strings, argument parsing and error messages.
- Do not add `Arc` without real sharing, and do not call `with_capacity` without a known size.
- Removing an accidental allocation or a rescan inside a loop needs no benchmark. A non-obvious optimization (`#[inline(always)]`, a custom hasher, a small-vector crate, interning, a hand-rolled loop) lands only with the benchmark that justifies it.

## Review checklist

Before finishing, verify in the diff:

- no `.clone()` was added only to make a borrow error go away, and no collection is cloned to iterate over it or cloned and then cleared;
- parameters that are only read are borrowed views, arguments that are stored are taken owned, and getters return borrows or iterators;
- no `String` is allocated to compare or look up, and no `Vec` is collected only to iterate, count or test;
- nothing is parsed, compiled, sorted or scanned per call or per item that could be done once;
- no buffer is created per iteration, no capacity comes straight from input, and nothing is formatted for a log line that may be off;
- no whole state is cloned out of a lock, and no guard is held during I/O or other slow work.

These searches find candidates for each item, in the same order; read each hit before changing it:

```sh
rg -n 'for \w+ in &?self\.\w+\.clone\(\)|\(\*+\w+(\.\w+)*\)\.clone\(\)'; rg -nU '\.clone\(\);\s*\n\s*self\.\w+(\.clear\(\)| = None)'
rg -n 'fn \w+\(&self[^)]*\) -> (String|Vec<)|fn [^{]*: &(String|Vec<|PathBuf|Option<)'
rg -n '\.(get|contains_key|remove)\(&[^)]*(to_string|to_owned)\(\)|to_lowercase\(\) [!=]=|collect::<Vec<[^;]*>>\(\)\.(len|iter|is_empty)\('
rg -n 'Regex::new\(|serde_json::from_(str|value)\('; rg -nU '(for|while)\b[^{;]*\{[^{}]*\.(contains|iter\(\)\.(find|position|any))\('
rg -nU '(for|while|loop)\b[^{;]*\{\s*let (mut )?\w+(: [^=]+)? = (Vec|String|HashMap|HashSet)::(new|with_capacity)\(|let \w+ = format!\([^;]*;\s*\n\s*(tracing::|log::)?(trace|debug|info)!'
rg -n '\.(lock|read|write)\(\)[^;]*\.clone\(\)|let (mut )?\w+ = [^;]*\.(lock|read|write)\(\)(\.unwrap\(\)|\.expect\([^)]*\))?;'
```

Clippy backs part of this. On by default: `clippy::ptr_arg` (`&Vec<T>` and `&String` parameters), `clippy::map_entry` (`contains_key` followed by `insert`; use `entry`), `clippy::large_enum_variant` (box a rare large variant) and `clippy::await_holding_lock` (a guard held across `.await`). To enable: `clippy::needless_pass_by_value` (pedantic; flags `T` taken where `&T` is enough, not a `&str` that is always turned into a `String`), `clippy::needless_collect` (nursery; only a local `collect` followed by `len` or another pass, not a method that returns a `Vec`), `clippy::or_fun_call` (nursery; `unwrap_or(load())` runs `load` even when it is not needed, write `unwrap_or_else(load)`), `clippy::format_push_string` (pedantic; `push_str(&format!(..))`, use `write!`) and `clippy::inline_always` (pedantic). No lint flags a clone added to pass the borrow checker, a getter that clones, a scan inside a loop or slow work under a guard.
