---
name: rust-domain-types
description: Model domain data in Rust with enums, newtypes and std types instead of bare strings, integers and bools. Use when defining structs, enums or function signatures, when parsing requests, config or other external input, and when reviewing code that passes ids, names, states or units around as `String`, `u64` or `bool`.
---

# Domain types

Give each domain value the weakest type that still rules out the mistakes it can cause. Parse external data once, where it enters, into enums and newtypes, and pass those types inward. Do not wrap values that guard nothing.

## Pick the form

Take the first line that fits:

1. A closed set of known values (status, kind, mode, action): an enum.
2. A meaning that std or a crate the project already depends on encodes: that type (`Duration`, `PathBuf`, `SocketAddr`, `NonZeroU32`, the project's URL, UUID or date type).
3. A value with a format or range rule that this code owns: a validated newtype.
4. An identifier that could be confused with an identifier of a different kind (a user id and a role id), or a value that keys a map: a newtype with a private field.
5. Only a readable name for a long type, or a field that mirrors an external schema: a type alias.
6. Anything else: keep the primitive. That includes free text, values only passed through to another API, plain numbers at a public API or FFI edge, and the one obvious value of a private helper.

Upgrade when the code changes:

- An alias becomes a newtype as soon as two aliases of the same primitive meet in one signature or map key. An alias is the same type, so `add(team, user)` still compiles.
- A newtype becomes validated as soon as this code checks that value anywhere.

## Branch on enums, not on string contents

```rust
// Avoid.
match order.status.as_str() {
    "SHIPPED" => notify(&order),
    _ => {}
}

// Prefer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum Status { Pending, Shipped, Cancelled }

match order.status {
    Status::Shipped => notify(&order),
    Status::Pending | Status::Cancelled => {}
}
```

- Convert the string into the enum once, where it enters (`#[derive(Deserialize)]`, `FromStr` or `TryFrom`).
- When a protocol you do not own may add values, add a last variant `#[serde(untagged)] Unknown(String)` on the side that must tolerate them, and in a published library mark the enum `#[non_exhaustive]`. Reject unknown values where they are an error.
- Match every variant of the enums you own. A `_ =>` arm silently accepts the next variant someone adds. Only enums from other crates marked `#[non_exhaustive]` need one.

## Give identifiers of different kinds their own types

```rust
// Avoid.
fn grant(user_id: &str, role_id: &str) {}

// Prefer.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct UserId(String);

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RoleId(String);

fn grant(user: &UserId, role: &RoleId) {}
```

- `grant(role, user)` compiles with strings and fails with newtypes. Typed map keys (`HashMap<UserId, Vec<RoleId>>`) get the same protection.
- Keep the field private and expose reads through `as_str()`, `AsRef<str>` and `Display`.
- For a newtype without a validity rule, `#[serde(transparent)]` keeps the wire format. Validated types use `try_from` instead; the two attributes do not combine.

## Put state-dependent data on enum variants

```rust
// Avoid.
struct Job {
    id: JobId,
    running: bool,
    finished: bool,
    exit_code: Option<i32>,
    error: Option<String>,
}

// Prefer.
struct Job {
    id: JobId,
    state: JobState,
}

enum JobState {
    Pending,
    Running { pid: u32 },
    Finished { exit_code: i32 },
    Failed(JobError),
}
```

- `Option` and `bool` fields that are set together, or only in some phase, are one enum. Fields that every state has stay on the struct.
- Independent on/off switches stay `bool`. Three domain states (auto, always, never) are a named enum; `Option<bool>` is fine when `None` only means "not given".

## Parse at the boundary, pass the parsed type inward

```rust
// Avoid.
fn invite(&self, email: &str) -> Result<(), Error> {
    if !is_valid_email(email) {
        return Err(Error::InvalidEmail);
    }
    self.mailer.send(email)
}

// Prefer.
fn invite(&self, email: &Email) -> Result<(), Error> {
    self.mailer.send(email)
}
```

- A check that returns `bool` throws away what it learned; a parser returns a value that carries it. The caller parses once (`Email::try_from(req.email)?`) and inner functions take the parsed type.
- Parse in one place: deserialize straight into domain types, or keep a loose wire struct and convert it in one mapping function. Never pass the wire struct inward.
- Further in, do not re-check what the parsed type guarantees. A deliberate second check at a trust boundary is fine.

## Validate in the constructor, with no way around it

```rust
// Avoid.
pub struct Username(pub String);
impl From<String> for Username { fn from(s: String) -> Self { Self(s) } }

// Prefer.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(try_from = "String")]
pub struct Username(String);

impl TryFrom<String> for Username {
    type Error = InvalidUsername;
    fn try_from(s: String) -> Result<Self, Self::Error> {
        if !(3..=32).contains(&s.len()) {
            return Err(InvalidUsername(s));
        }
        Ok(Self(s))
    }
}
```

- Expose reads (`as_str`, `AsRef`, `into_inner`) and route every construction through the check: no `pub` field, no infallible `From`, no `DerefMut`, no setter, no `Default` that yields an invalid value.
- A plain `#[derive(Deserialize)]` skips the constructor. Use `#[serde(try_from = "...")]`; its error type must implement `Display`.
- Never write a `From` that can fail or that silently clamps.

## Use the type that already exists

```rust
// Avoid.
struct Settings { timeout_ms: u64, data_dir: String }

// Prefer.
struct Settings { timeout: Duration, data_dir: PathBuf }
```

- A unit or format in a field name (`_ms`, `_secs`, `_at`, `_path`) is type information kept in the name.
- On wire and config structs keep the key and the unit, and convert in the mapping step: serde writes `Duration` as `{secs, nanos}`, and renaming a field changes the format. For dates use the project's date crate; `SystemTime` cannot parse RFC 3339.
- Represent "not set" with `Option` or a variant, never with `-1`, `0`, `""` or a default date. A default is fine when the spec says absence means that value.
- Deserialize known shapes into structs, not `serde_json::Value`, and do not model a record with known fields as `HashMap<String, String>`. `Value` fits schemaless or pass-through data; open maps such as tags and headers stay maps.

## Signatures and conversions

- Replace a `bool` argument that callers pass as a literal with an enum, or split the function when the flag selects between two bodies: `render(&doc, Toc::Include)`, not `render(&doc, true)`. A single `bool` that the function name explains (`set_visible(true)`) stays.
- Return a named struct, not a tuple of same-typed or boolean values.
- Prefer trait impls for conversions: `From` when total, `TryFrom` or `FromStr` when fallible, `Display` for text. Keep a named constructor when the types do not imply the meaning (`Duration::from_millis`).
- Model a known set of message or event kinds as an enum and `match` on it. `Box<dyn Any>` with downcasts, and branching on `TypeId`, are for open registries.

## Do not over-type

- Do not wrap free text, or values with no rule and no realistic mix-up. A newtype converted back to its primitive at every use (`.0`, `as_str()`, `into_inner()`) is a name, not safety.
- Do not enforce, in client code, constraints that only the server owns.
- Plain data may have public fields and no accessors. A type with an invariant has private fields and only the getters callers need, named after the field, without `get_` and without setter pairs. Do not mix `pub` and private fields on one type. Keep items private by default and use `pub(crate)` for internal sharing.
- When porting from another language, translate meaning, not spelling. Integer JSON numbers are `u64` or `i64`, not `f64`. JavaScript's `a || b` also replaces `""` and `0`, so `unwrap_or` alone changes behavior.

## Review checklist

Before finishing, verify in the diff:

- known values are compared as enum variants, not as strings;
- outside wire types, identifiers of different kinds are not the same primitive, and map keys are typed;
- types with a validity rule have no `pub` field, infallible `From` or plain `Deserialize`;
- `Option` and `bool` fields that change together are one enum;
- "not set" is `Option`, not `-1`, `0` or `""`;
- outside wire types, no field keeps its unit or format only in its name;
- data with a known shape is a struct, not `serde_json::Value` or `HashMap<String, String>`;
- no newtype is converted back to its primitive at every use.

These searches find candidates for the first, second, fifth and sixth items; read each hit before changing it:

```sh
rg -n 'match [^{;]*\.as_str\(\)|^\s*"[^"]*"\s*(\|\s*"[^"]*"\s*)*=>|[!=]= "[A-Za-z]|"\w+" [!=]='
rg -n '\b(\w+_)?(id|ids|name|key|url|email|code): (Option<|Vec<)?(String|&(.\w+ )?str)\b|Map<String,'
rg -n 'Option<bool>|unwrap_or\((-1|""|String::new\(\))\)'
rg -n '\w+_(ms|millis|secs|seconds|at|path|dir): (Option<)?(u\d+|i\d+|usize|f64|String|&str)\b'
```

No Clippy lint flags stringly typed fields. `clippy::fn_params_excessive_bools` and `clippy::struct_excessive_bools` (pedantic) fire only above three `bool`s unless `max-fn-params-bools` and `max-struct-bools` are lowered in `clippy.toml`. `clippy::partial_pub_fields` and `clippy::wildcard_enum_match_arm` (restriction) cover two of the items above.
