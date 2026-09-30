# Contributing

This kit is meant to be taken and adapted. Fork it, bend it to your project, and if you improve
something that would help everyone, propose it back.

## How a change gets in

1. **Fork** the repository and make your change on a branch in your fork.
2. **Run the gates** before you open a pull request — they are the CI:
   ```bash
   bash scripts/run-all-gates.sh
   bash scripts/selftest.sh
   ```
   A pull request with a red gate will not be merged. If you add a gate or a hook, ship its
   known-answer test with it (see any `scripts/*-test.sh`) and show it failing on the thing it catches.
3. **Open a pull request** against `master`. Say what the change fixes or adds, and **why** — this kit
   records the reason behind every rule, and a change without one is hard to review.
4. The maintainer reviews every pull request (`.github/CODEOWNERS`). `master` is protected: nothing
   merges without an approved pull request, and history is never force-pushed.

## What makes a good contribution

- **A control, not a sentence.** A rule nobody checks is a hope; prefer a gate or a hook with a test.
- **Generic.** Keep project names, vendors and personal details out; configuration belongs in
  `harness.conf` (document new options in `harness.conf.example`).
- **No outside service required.** Anything that calls an external API must be optional and fall
  back cleanly when the key is absent (see "Second-opinion reviewers" in the README).
- **Portable shell.** Scripts run on macOS bash 3.2 and on Linux: no heredoc nested inside `$( )`,
  no Python inside `python3 -c '…'` (both are explained where they bite).

## Never include

- Secrets of any kind — keys, tokens, passwords, `.env` contents. GitHub secret scanning with push
  protection is on for this repository and will block a push that contains one.
- Personal details — real names, email addresses, phone numbers, home-folder paths. Use
  placeholders such as `user@example.com`; the maintainer checks every pull request for them.

## License

Apache License 2.0 — see `LICENSE`. By contributing you agree your contribution is released under the
same license (section 5 of the license).
