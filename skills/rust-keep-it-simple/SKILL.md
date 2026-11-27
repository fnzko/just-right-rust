---
name: rust-keep-it-simple
description: Keep Rust code simple by adding no abstraction, state, helper, dependency or compatibility code the change does not need, and by writing branches, loops and iterator chains in their direct form. Use when adding a feature, trait, generic, helper, field or dependency, when changing or copying an existing function, when writing `if`, `match`, loops or iterator chains, and when reviewing a diff for unused code, duplicated logic, shims and debugging leftovers.
---

# Keep it simple

Write the least code that does what the change needs. Change what exists before adding beside it, make each decision once, and delete what the change makes unnecessary. For control flow use the direct form: bind instead of test, one `match` per decision, adapters for pure transforms and loops for effects.

## Add nothing the change does not use

```rust
// Avoid.
trait Cleanup {
    fn run(&self, dir: &Path) -> io::Result<()>;
}
struct DefaultCleanup;
impl Cleanup for DefaultCleanup {
    fn run(&self, dir: &Path) -> io::Result<()> { fs::remove_dir_all(dir) }
}

// Prefer.
fn cleanup(dir: &Path) -> io::Result<()> { fs::remove_dir_all(dir) }
```

- A trait needs a second implementation that exists today, a generic a second instantiation. A three-field struct needs no builder or factory.
- Ship no function, field, parameter, variant, option, feature flag or trait method without its caller in the same change.
- Add no flag, cache, persisted field, thread or timer for what existing state already answers: `is_empty: bool` stored next to `items: Vec<Item>` is the method `self.items.is_empty()`.

## Change the existing function, do not add a twin

```rust
// Avoid.
fn load_config(path: &Path) -> io::Result<Config> {
    parse(&fs::read_to_string(path)?)
}
fn load_config_with_env(path: &Path, env: &Env) -> io::Result<Config> {
    Ok(parse(&fs::read_to_string(path)?)?.overridden_by(env))
}

// Prefer.
fn load_config(path: &Path, env: &Env) -> io::Result<Config> {
    Ok(parse(&fs::read_to_string(path)?)?.overridden_by(env))
}
```

- Update the callers. A `_v2`, `_new`, `_with_x` or `_ext` copy drifts from the original; a diff that adds many lines and deletes none usually contains one.
- Before writing a helper, type or test harness, search the workspace, std and the crates the project already depends on. A hand-written recursive `read_dir` in a project that has `walkdir` is a duplicate.
- When nothing depends on the old shape, delete it: no `#[deprecated]` alias, second `pub use` path, retired variant or migration module.
- Add a crate only for a concrete need, with `cargo add` and only the features the code uses (`features = ["rt", "sync"]`, not `"full"`), and not for what std has (`LazyLock`).

## Make each decision once, in the type that owns it

```rust
// Avoid.
impl Order {
    fn ships_free(&self) -> bool { self.total >= 5000 }
    fn shipping_cost(&self) -> u32 { if self.total > 5000 { 0 } else { 499 } }
}

// Prefer.
impl Order {
    fn shipping_cost(&self) -> u32 { if self.total >= FREE_SHIPPING_FROM { 0 } else { 499 } }
    fn ships_free(&self) -> bool { self.shipping_cost() == 0 }
}
```

- Two functions that must agree will drift; the two above already disagree at 5000. Define one by the other.
- Do not write "keep in sync" comments or hold a second copy of data that lives elsewhere. A cached derived value needs one place that invalidates it.
- Shared code does not ask which implementation it holds (`if writer.name() == "csv"`). Add a trait method with a default body, or a method on the enum, and let each implementation answer.

## Extract a helper only when it removes duplication or names a concept

```rust
// Avoid.
fn format_greeting_for_user(user: &User) -> String { format!("hello {}", user.name) }

fn greet(user: &User) { send(&format_greeting_for_user(user)); }

// Prefer.
fn greet(user: &User) { send(&format!("hello {}", user.name)); }
```

- Inline a forwarder with one caller whose name only restates its body.
- Split a function or a file when it mixes concerns (parse, authorize, apply, render), not to reach a line count. After the split the top function reads as one line per concern.
- Name items for their domain meaning: `decode_frame(bytes)`, not `process(data)`; no `Manager`, `Helper`, `Util` or numeric suffixes. Keep std verbs with their std meaning: `get` borrows, `take` removes, `into_` consumes, `is_` answers yes or no.

## Bind the value instead of checking and then unwrapping

```rust
// Avoid.
if users.get(&id).is_some() {
    notify(users.get(&id).unwrap());
}

// Prefer.
if let Some(user) = users.get(&id) {
    notify(user);
}
```

- Use `if let`, `let ... else`, `match` or `?` so the check returns the value. A separate check and `unwrap` drift apart under edits and look the key up twice.
- The same holds for validate-then-parse (`if is_valid(s) { parse(s).unwrap() }`): call the parser and bind its result.
- Handle the short and failing cases first (`let Some(user) = find(id) else { return };`, `?`) and keep the main path unindented.

## Express one decision as one `match`

```rust
// Avoid.
let retry = status == 429 || status == 503;
if retry && attempts < MAX_ATTEMPTS {
    again()
} else if retry {
    give_up()
} else {
    done()
}

// Prefer.
match status {
    429 | 503 if attempts < MAX_ATTEMPTS => again(),
    429 | 503 => give_up(),
    _ => done(),
}
```

- Use guards and grouped arms instead of a flag variable followed by a second `if`.
- `if let` is right when exactly one variant matters.
- Let `if` and `match` produce the value (`let limit = if premium { 100 } else { 10 };`) instead of declaring a variable and assigning it in each branch.

## Use adapters for pure transforms and loops for effects

```rust
// Avoid.
let mut emails = Vec::new();
for user in &users {
    if let Some(email) = &user.email {
        emails.push(email.clone());
    }
}
items.iter().for_each(|item| send(item).unwrap());

// Prefer.
let emails: Vec<String> = users.iter().filter_map(|user| user.email.clone()).collect();
for item in &items {
    send(item)?;
}
```

- A push loop, a `found` flag or a running total is `filter_map` and `collect`, `any`, `find` or `position`, `sum` or `max_by_key`. Parse a list with `collect::<Result<Vec<_>, _>>()?`, and append to an existing collection with `extend`.
- Write a plain `for` when the body has side effects, mutates more than one local, or leaves early with `return`, `break` or `?`, and when the chain would need multi-line closures or more than about four adapters. Never use `map` for a side effect.
- Iterate over elements (`for item in &items`, `enumerate`, `zip`, `windows`), not over `0..items.len()`.
- Adapters are lazy. Keep the `collect` that separates two phases: `jobs.iter().map(spawn).for_each(join)` joins each thread before the next one starts, so collect the handles first and join them in a second loop.

## Signatures and bindings

- Return a value, a `Result` or a named struct instead of filling `&mut` parameters and flags: `fn parse(input: &str) -> Result<Vec<Token>, ParseError>`, not `fn parse(input: &str, out: &mut Vec<Token>, failed: &mut bool)`.
- Shadow a binding when its representation changes, so the old value cannot be used by mistake: `let port = env::var("PORT")?; let port: u16 = port.parse()?;`, not `port_str` and `port_num`.

## Leave no scaffolding behind

```rust
// Avoid.
#[allow(dead_code)]
fn old_total(items: &[Item]) -> u64 { items.iter().map(|item| item.price).sum() }

fn total(items: &[Item]) -> u64 {
    dbg!(items.len());
    items.iter().map(|item| item.price * item.quantity).sum()
}

// Prefer.
fn total(items: &[Item]) -> u64 {
    items.iter().map(|item| item.price * item.quantity).sum()
}
```

- Before finishing, delete `dbg!`, stray `println!` and `eprintln!`, commented-out code and `if false` switches. A line worth keeping goes through the project's logger.
- Fix or delete the code a warning points at. Do not hide new code behind `#[allow(...)]` or an underscore prefix.
- When a lint is wrong, use `#[expect(lint, reason = "...")]` on the narrowest item; it warns once it stops being needed.

## Do not over-simplify

- Keep a trait with a real second implementation, including a test fake the project uses. `with_x` builder methods that set one option are not twins.
- Keep the old function, format or column for a release when real users or stored data depend on it.
- Keep a single-use helper that names a concept or lets its body use `?` and `return`. A long linear function with one concern is fine, and so is one special case inline until a second appears.
- Do not add a dependency to save a few lines, and do not hand-write tricky parsing that a well-known crate already does.
- Keep a loop when the chain would change behavior: `any` and `find` stop early and skip effects the loop ran, `zip` stops at the shorter input where indexing would have panicked, and `collect::<Result<_, _>>()` keeps only the first error. Keep the index when it reaches neighbors or the loop changes the collection.
- Keep a `match` on a `Result` when a site recovers from the error or maps it to a different variant, and `if`/`else` when both branches carry similar weight.
- Keep `&mut` output for a caller-owned buffer reused across a hot loop, and `#[allow]` on generated, macro and cfg-dependent code.
- Apply these rules to the code the change touches. Do not rewrite working code elsewhere to match them.

## Review checklist

Before finishing, verify in the diff:

- every new function, field, parameter, variant and trait method has a caller;
- every new trait has two implementations, and no new state repeats what existing state answers;
- no function has a suffixed twin, and no helper repeats one from the workspace, std or a dependency;
- no decision is computed in two places, and shared code does not branch on a concrete implementation;
- nothing exists only for an old shape that has no users;
- no value is checked and then unwrapped, and no flag variable feeds a second `if`;
- push, flag and accumulator loops are adapters, and chains with effects, `?` or early exits are loops;
- no `dbg!`, stray print, commented-out code or new `#[allow]` remains;
- every new dependency has a named need and only the features in use.

These searches find candidates for the second to eighth items, and for vague names, unshadowed conversions and output parameters; read each hit before changing it:

```sh
rg -n '^\s*(pub(\(\w+\))? )?trait \w+|struct \w+(Impl|Factory|Builder)\b'
rg -n 'fn \w+_(v2|new|with_\w+|ext|alt)\(|(?i:\b(legacy|retired|compat|migrat\w*)\b|keep (this )?in sync)'
rg -n 'if [^{]*\.is_(some|ok)\(\) \{|let mut \w+ = (Vec::new\(\)|false|0);|for \w+ in 0\.\.\w+\.len\(\)'
rg -n '#!?\[allow\(|dbg!\(|^\s*e?println!\(|^\s*//\s*(let|fn|pub|use|if|for|match|return|impl|struct)\b.*[;{]\s*$'
rg -n '(struct|enum|trait|mod) \w*(Manager|Service|Helper|Util|Utils|Wrapper)\b|fn \w+[0-9]\(|let (mut )?\w+_(str|opt|raw|parsed)\b'
rg -n 'fn \w+\([^)]*: &mut (Vec|String|bool|Option)'
```

Clippy's default groups already flag a `match` that only propagates an error, nested `if`s that collapse, declare-then-assign, a hand-written `clamp`, `map` called for a side effect, a redundant cast and index loops (`clippy::question_mark`, `collapsible_if`, `needless_late_init`, `manual_clamp`, `option_map_unit_fn`, `unnecessary_cast`, `needless_range_loop`). Enable `clippy::manual_let_else`, `needless_for_each` and `non_std_lazy_statics` (pedantic) and `clippy::allow_attributes`, `allow_attributes_without_reason` and `dbg_macro` (restriction), plus `print_stdout` (restriction) in libraries. Two lints cover only part of a rule: `clippy::unnecessary_unwrap` fires only when the same variable is checked and unwrapped, and rustc `dead_code` skips `pub` items. Leave `clippy::single_call_fn`, `shadow_reuse` (restriction) and `too_many_lines` (pedantic) off: they flag helpers that name a concept, the shadowing above and length instead of mixed concerns.
