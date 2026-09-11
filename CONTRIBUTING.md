# Contributing to Keepling

Thank you for considering a contribution. Read `AGENTS.md` first — it is the repository's actual
coordination contract (monorepo layout, module boundaries, and the invariants every change must
preserve). This document does not restate it; it covers what contributing itself requires.

## Developer Certificate of Origin

Every contribution requires a **sign-off** under the
[Developer Certificate of Origin (DCO) 1.1](https://developercertificate.org/). Add
`Signed-off-by: Your Name <your.email@example.com>` to every commit message — `git commit -s`
does this automatically.

The sign-off is your assertion that you wrote the contribution, or otherwise have the right to
submit it under this project's licence. Apache-2.0 already grants this project the copyright and
patent rights it needs from a contribution once you make it; the DCO's job is narrower and more
important for a project this size: **provenance** — a plain statement that what you are
submitting is actually yours to submit.

**If an AI assistant wrote part of your contribution, sign off anyway.** The sign-off is your
assertion that you have the right to submit it, and that assertion is yours to make, not the
tool's. An assistant can produce code that resembles or reproduces licensed material it was
trained on or shown; you are the one certifying that what you are submitting is clear to submit,
exactly as if you had typed every line yourself.

This project does not use a Contributor License Agreement. A CLA would buy the maintainer the
right to unilaterally relicense your contribution later; under Apache-2.0 that right buys almost
nothing (a closed hosted service, App Store distribution, dual-licensing, and acquisition are all
already available without one), and its exercise elsewhere is exactly what has triggered some of
the best-known community forks of the last few years. The DCO is deliberately the smaller ask.

## Before you open a pull request

1. Read `AGENTS.md` for the coordination contract — which module owns what, and which boundaries
   a change must not cross.
2. Sign off every commit (`git commit -s`).
3. Fill in the pull request template, including the sign-off checkbox.
4. Expect review and iteration on a solo maintainer's schedule — see `SUPPORT.md` for what that
   means in practice.

## Reporting a security vulnerability

Do not open a public issue for a security vulnerability. Use the private reporting channel
described in `SECURITY.md`.

## Code of Conduct

This project follows the Contributor Covenant, with an enforcer named in `CODE_OF_CONDUCT.md`.
