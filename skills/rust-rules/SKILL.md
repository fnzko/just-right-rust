---
name: rust-rules
description: Write, change or refactor Rust code. Use first, before writing or editing any Rust source in this project, whatever the task is (a new crate, a feature, a bug fix, a cleanup). It holds the Rust rules to follow.
---

# Rust rules

Follow these rules in all Rust code you write or change.

## When you work on existing code

The code already here may not follow these rules. How far they reach depends on the request.

When the request is to clean up, refactor or review code, the rules apply to all the code in the requested scope. Go through each section below, find where the code breaks it, and fix what you find.

When the request is to add a feature or fix a bug:

- Every line you add follows the rules, even where the code next to it does not.
- When existing code forces new code to break a rule, change the existing code just enough for the new code to follow it. Small changes like that are part of the task.
- Do not go further: no rewrite of functions the change does not need to touch, and no migration of existing code to the rules.
- Rules that only hold crate-wide apply to the data this change introduces. Do not retype existing data.

## Types

- known values are compared as enum variants, not as strings;
- outside wire types, identifiers of different kinds are not the same primitive, and map keys are typed;
- types with a validity rule have no `pub` field, infallible `From` or plain `Deserialize`;
- `Option` and `bool` fields that change together are one enum;
- "not set" is `Option`, not `-1`, `0` or `""`;
- outside wire types, no field keeps its unit or format only in its name;
- data with a known shape is a struct, not `serde_json::Value` or `HashMap<String, String>`;
- no newtype is converted back to its primitive at every use.

## Errors

- no failure becomes a default, an empty collection or `None` unless the spec defines that value;
- no `Result` is dropped with `let _ =`, `.ok();` or an unconditional `Ok`, except commented best-effort calls;
- nothing that input can trigger panics: no `unwrap`, `expect`, index or slice on input;
- every `expect` and `unreachable!` names the invariant, and no `todo!()` or `unimplemented!()` remains;
- `catch_unwind` appears only at a thread, task or FFI boundary;
- sizes and offsets that come from input use `try_from` and checked arithmetic;
- an error that crosses a layer says what was attempted, and is logged or returned, not both;
- no error type is `String`, `&'static str` or `()`, and no library function returns `anyhow::Result`;
- no `Option`, `Result` or branch exists for a state that cannot occur.

## Ownership

- no `.clone()` was added only to make a borrow error go away, and no collection is cloned to iterate over it or cloned and then cleared;
- parameters that are only read are borrowed views, arguments that are stored are taken owned, and getters return borrows or iterators;
- no `String` is allocated to compare or look up, and no `Vec` is collected only to iterate, count or test;
- nothing is parsed, compiled, sorted or scanned per call or per item that could be done once;
- no buffer is created per iteration, no capacity comes straight from input, and nothing is formatted for a log line that may be off;
- no whole state is cloned out of a lock, and no guard is held during I/O or other slow work.

## Simplicity

- every new function, field, parameter, variant and trait method has a caller;
- every new trait has two implementations, and no new state repeats what existing state answers;
- no function has a suffixed twin, and no helper repeats one from the workspace, std or a dependency;
- no decision is computed in two places, and shared code does not branch on a concrete implementation;
- nothing exists only for an old shape that has no users;
- no value is checked and then unwrapped, and no flag variable feeds a second `if`;
- push, flag and accumulator loops are adapters, and chains with effects, `?` or early exits are loops;
- no `dbg!`, stray print, commented-out code or new `#[allow]` remains;
- every new dependency has a named need and only the features in use.

## Comments and commits

- every added comment states a reason, an invariant or a contract, and none restates the line below it;
- no comment or doc mentions what the code used to do, the review or the plan, and none is made false by the change;
- added comments, docs and messages are plain ASCII, with no banners, step numbers or capitals for emphasis;
- public items say what the signature cannot, and no doc only rephrases the name;
- every `TODO` or `FIXME` names an action and an issue, and nothing is stubbed;
- every `SAFETY` comment names the check that makes the block sound;
- each commit has one purpose, `git diff` and `git diff -w` show the same lines, and the pull request text matches the diff.

## Tests

- every test asserts a value, a count or an error variant, not only `is_ok()`, emptiness or a substring;
- no assertion sits behind `if let`, `unwrap_or`, `unwrap_or_default` or a loop that may not run;
- no expected value is computed by the code under test, and each regression test was seen failing without the fix;
- structured output is compared as a whole typed value or a reviewed snapshot;
- no fixed sleep, port or path, environment change, wall clock or random value decides a result;
- production code has no test-only branch;
- test names describe the scenario, and the inputs of one behavior share one table;
- no new helper repeats an existing one or hides the assertions.

## Longer guides

Each section above has a guide with examples and the cases where the rule does not apply: `rust-domain-types`, `rust-error-discipline`, `rust-ownership`, `rust-keep-it-simple`, `rust-comments` and `rust-test-quality`. Load the one for a section when a rule there needs more than its one line.
