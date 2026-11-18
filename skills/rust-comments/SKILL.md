---
name: rust-comments
description: Write Rust comments, doc comments, commit messages and pull request text that state reasons and contracts instead of restating code or narrating the edit. Use when adding or editing `//` comments, `///` docs, `SAFETY` comments or TODO markers, when committing or describing a pull request, and when reviewing a diff for comments that narrate, record history or contradict the code.
---

# Comments, commits and pull requests

Write a comment only for what the code cannot say: a reason, an invariant, a contract. Describe the code as it is now, in plain sentences, and leave the history to version control. Keep each commit to one purpose and the pull request text short.

## Comment the reason, not the code

```rust
// Avoid.
// Sort the items by id.
items.sort_by_key(|item| item.id);
// Then search for the wanted id.
let found = items.binary_search_by_key(&wanted, |item| item.id);

// Prefer.
// binary_search_by_key needs ascending ids.
items.sort_by_key(|item| item.id);
let found = items.binary_search_by_key(&wanted, |item| item.id);
```

- A comment earns its place with a reason, an invariant, an ordering requirement, a rejected alternative or a measured cost.
- Delete comments that restate the next line. If the code is unclear without one, rename or extract a function first.
- A comment that the code contradicts is worse than none. When an edit makes a comment false, fix or delete the comment in the same edit.

## Describe the code as it is, in plain sentences

```rust
// Avoid.
// ===== Step 2: Track seen users =====
// Changed to a HashSet instead of the old Vec, per review feedback.
// IMPORTANT: this MUST stay a set!!
let seen: HashSet<UserId> = users.iter().map(|user| user.id).collect();

// Prefer.
// A set, because membership is checked on every request.
let seen: HashSet<UserId> = users.iter().map(|user| user.id).collect();
```

- No change history, review conversation or work plan: "previously", "no longer", "now uses", "as requested", "per review", "phase 2". No claims that the code is idiomatic, safe or follows best practices.
- No banners, step numbers, capitals for emphasis, exclamation marks, em dashes, Unicode arrows, ellipsis characters, box drawing or emoji. Write ASCII sentences; a function that needs step comments wants splitting into named parts.
- The same holds for `///` and `//!` docs, commit messages and pull request text.

## Document the contract the signature cannot state

```rust
// Avoid.
/// Returns the timeout.
pub fn timeout(&self) -> Option<Duration> { self.timeout }

// Prefer.
/// Idle time after which the session is closed.
///
/// `None` never closes it.
pub fn timeout(&self) -> Option<Duration> { self.timeout }
```

- A public item gets one summary sentence, a blank line, then what the name and signature leave out: units, what `None` or an empty value means, guarantees, and when it fails (`# Errors`, `# Panics`).
- Document what callers can observe, not the internal storage or how the body works.
- A doc that rephrases the name says nothing. Rewrite it; a private item needs a doc only when it is not obvious.

## Name the action in debt markers, and do not ship stubs

```rust
// Avoid.
// TODO: handle this properly
// For now we just return an empty list.
fn search(&self, query: &str) -> Vec<Item> {
    Vec::new()
}

// Prefer.
// TODO(#412): search the archive once it has an index.
fn search(&self, query: &str) -> Result<Vec<Item>, Error> {
    Err(Error::Unsupported("search"))
}
```

- A marker names the action and where it is tracked, with the tag the project already uses (`TODO` or `FIXME`). Delete it when the work is done.
- "For now", "placeholder", "temporary" and "simplified" are debt markers written as prose. Do the work or write the marker.
- Implement it or do not add it. A `todo!()`, an `unimplemented!()` or a placeholder return (`Vec::new()`, `None`, `Ok(())`) in work presented as finished is a silent default. When a gap has to ship, return an explicit error and say so in the pull request text.

## Prove the obligation in SAFETY comments

```rust
// Avoid.
// SAFETY: the pointer is valid.
Some(unsafe { &*self.ptr.add(i) })

// Prefer.
if i >= self.len {
    return None;
}
// SAFETY: `i < self.len` was checked above, and `self.ptr` points to `self.len` initialized items.
Some(unsafe { &*self.ptr.add(i) })
```

- State each obligation of the unsafe operation and why it holds at this call site, naming the variables and the check that establishes it.
- "The pointer is valid", "the caller guarantees it" and "this is always in bounds" restate the obligation. They do not prove it.
- An `unsafe fn` lists what its caller must uphold in a `# Safety` doc section.

## Make each commit one purpose, and touch only its lines

```text
Avoid: one commit.
fix order total, refactor item lookup, rename helpers, bump deps

Prefer: one purpose each, and every commit builds and passes the tests.
refactor: move item lookup into Order (no behavior change)
fix: count a discounted item once in the order total
```

- Refactors, moves and renames go in their own commits, apart from behavior changes. The test goes in or before the commit that makes it pass. Rebase onto the base branch instead of merging it in.
- Touch only the lines the change needs: no drive-by reformatting, renames, rewording of nearby comments or restyling of working code. `Cargo.lock` changes only together with a manifest change.

## Write pull request text short, in your own words

```text
Avoid.
This PR introduces a comprehensive and robust solution that significantly
improves order handling. Key changes:
- Updated order.rs with the new total logic
- Added tests

Prefer.
Discounted items were counted twice in the order total. Each item is now
counted once, and the new test covers an order with two discounts.
```

- Say what was wrong or wanted, what the change does and why it is correct. A few sentences cover most changes.
- No selling adjectives, no bullet per touched file, no pasted test logs, no headings around three sentences.
- The text matches the diff. Update it when the code changes, and describe nothing the diff does not do.
- Commit messages and review replies follow the same rules. Disclose LLM use where the project asks for it.

## Match the project and the pinned version

- Match the surrounding code in naming, import grouping, error style, module layout, item order, comment density, marker tags and commit subject style, even where another form is slightly better. A deliberate convention change goes in its own pull request.
- Before calling a dependency's API, or describing it in a comment, check it at the version in `Cargo.lock` (`rg -A1 'name = "toml"' Cargo.lock`), then read docs.rs for that version or the source under `~/.cargo/registry/src`. Do not guess again from the compile error.

## Do not over-apply

- Do not delete or shorten a comment that records a reason, an invariant, a workaround or a rejected alternative, however long it is. Removing it is a regression. When unsure, keep it.
- Leave existing comments alone unless your change makes them false. Rewording them is an off-topic diff. Comment density is the project's choice: do not add comments to reach a quota, and do not strip them to look terse.
- A marker that points forward (`FIXME(#412): ...`) and a note on why the obvious alternative was rejected are not history.
- Signal words (`NB:`, `Subtle:`, `SAFETY:`), acronyms in capitals and short worked examples are fine. One non-ASCII character in a string literal or a fixture is not the target.
- `todo!()` is fine in a local draft that is not presented as finished, and an explicit "unsupported" error with a tracking issue is honest.
- A large pull request is acceptable when each commit can be reviewed on its own. Cleanup is welcome as a separate pull request.

## Review checklist

Before finishing, verify in the diff:

- every added comment states a reason, an invariant or a contract, and none restates the line below it;
- no comment or doc mentions what the code used to do, the review or the plan, and none is made false by the change;
- added comments, docs and messages are plain ASCII, with no banners, step numbers or capitals for emphasis;
- public items say what the signature cannot, and no doc only rephrases the name;
- every `TODO` or `FIXME` names an action and an issue, and nothing is stubbed;
- every `SAFETY` comment names the check that makes the block sound;
- each commit has one purpose, `git diff` and `git diff -w` show the same lines, and the pull request text matches the diff.

These searches find candidates for every item but the last; read each hit before changing it:

```sh
rg -n '^\s*//\s*(Step \d|Create|Initialize|Set|Get|Loop|Iterate|Check|Return|Call|Handle|Parse|Convert|Now|First|Then|Finally)\b|//\s*[=\-#*]{4,}'
rg -ni '//.*\b(previously|no longer|used to|now uses|we now|as requested|per (the )?review|as discussed|best practices|phase \d)\b'
rg -nP '//.*\b(?!TODO\b|FIXME\b|SAFETY\b)[A-Z]{4,}\b|[^\x00-\x7F]' --type rust
rg -n '///\s*(Gets?|Returns?|Sets?|Creates?) (the |a |an )?\w+\.?\s*$'
rg -nPi '//\s*(TODO|FIXME|XXX)\b(?!\(#\d+\))|\bfor now\b|placeholder|not yet implemented|todo!\(|unimplemented!\('
rg -n 'SAFETY:.*(is valid|caller guarantees|always|never null)'
```

No Clippy lint reads what a comment says. `clippy::undocumented_unsafe_blocks` (restriction) requires a `SAFETY` comment on every `unsafe` block, not that it proves anything. `clippy::missing_errors_doc` and `clippy::missing_panics_doc` (pedantic, noisy) ask for the `# Errors` and `# Panics` sections, not for docs that say something. Commits and pull request text have no lint.
