# Just Right Rust

Just Right Rust is an opinionated collection of Rust recommendations packaged
as a [Symposium](https://github.com/symposium-dev/symposium) plugin.

The plugin currently provides:

- guidance for async Rust built on Tokio, actors, and cancellation-safe
  concurrency;
- `rust-rules`, a short entry skill with the rules for types, errors,
  ownership, simplicity, comments and tests, and how they apply when changing
  existing code;
- a guide with examples for each of those six areas (`rust-domain-types`,
  `rust-error-discipline`, `rust-ownership`, `rust-keep-it-simple`,
  `rust-comments`, `rust-test-quality`);
- two hooks, as shell scripts that need `sh` and `git`: at session start the
  agent is given the rules, and when it finishes, the Rust lines it added are
  searched for a few of them and the findings handed back. The second one runs
  on the agents that have a stop event (Claude Code, Codex CLI, Antigravity);
- Google's unsafe Rust review skill;
- a skill that has the agent run the project's tests before calling a change
  done.

## License

Licensed under either of Apache License, Version 2.0 or MIT license at your
option.
