# Support

Keepling is a personal, open-source project maintained by one person, in his spare time, for his
own daily use. This document states plainly what that does and does not include.

## What is not promised

- **No response-time commitment** for issues, pull requests, or discussions. They may be answered
  in an hour or not for months.
- **No paid support, consulting, or service levels.** This is out of scope entirely, not merely
  unavailable — there is no tier or arrangement under which it exists.
- **No help operating your own deployment.** Self-hosting Keepling means you own its operation:
  its database, its reverse proxy, its backups, its upgrades.
- **No feature requests by default.** Opening one is welcome, but it does not create an obligation
  to build it.
- **No commitment to accept any given pull request**, however well-intentioned or well-written.

## The counterweight

Because Keepling is licensed under the Apache License 2.0, none of the above can strand you.
**The licence is the support guarantee.** You do not need permission to run it, modify it, fork
it, or keep using an old version forever. Nothing above closes any of those doors.

## If the project goes quiet

- If development stops, the project `README.md` will say so, and the repository will be archived.
- **Six months of no commits and no maintainer replies means treat the project as unmaintained,
  whether or not an explicit notice ever appears.** Waiting for an announcement that may never
  come is not a reasonable expectation to place on a solo maintainer, so this document sets the
  bound instead.
- **Your data comes with you.** The export path (`apps/server/lib/keepling/application/export.ex`,
  verified independently by `tooling/verify-export-reader.mjs`) is tested, and produces a plain,
  independently readable bundle — not a proprietary format that locks you to this one project's
  continued existence.
- **Forking is pre-blessed.** Apache-2.0 already grants everything a fork needs. The one thing it
  does not grant is the Keepling name itself — a fork should rename itself rather than represent
  itself as this project.

## Where to actually get help

- Read `AGENTS.md` for how this project's own coordination works, and `CONTRIBUTING.md` before
  opening a pull request.
- Use GitHub Issues and Discussions for bug reports and questions. They are read; they are simply
  not answered on any guaranteed timeline.
- For a security vulnerability specifically, use `SECURITY.md`'s private reporting channel, not a
  public issue.
