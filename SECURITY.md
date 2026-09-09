# Security policy

## Reporting a vulnerability

Please report security issues through GitHub's private vulnerability reporting:
**[Report a vulnerability](https://github.com/akatekhanh/sweep/security/advisories/new)**
(Security → Advisories → Report a vulnerability). That keeps the report private
until a fix ships.

If you can't use GitHub, email <akatekhanh0212@gmail.com> with "Sweep security"
in the subject.

This is a one-maintainer project. Expect an acknowledgement within a week; a fix
timeline depends on severity. There is no bounty.

## What counts as a vulnerability here

Sweep deletes things, so the interesting bugs are about *deleting the wrong
thing* or *deleting more than the user agreed to*:

- A path outside a declared scan target ending up in scan results — anything
  that would let a crafted filename, symlink, or directory name escape the
  category's roots.
- An item being removed **permanently** when the UI said it goes to the Trash
  (or vice versa: the report claiming something is restorable when it isn't).
- Command injection through the Docker integration. Sweep shells out to the
  `docker` binary; a container, image, or volume name should never be able to
  turn into extra arguments or shell syntax.
- Anything that makes the pre-selected set include an item the user didn't
  choose — the app's core promise is that only Safe *and* recoverable items
  arrive pre-ticked.
- Escalation: Sweep runs unprivileged and should never need `sudo`. A path that
  makes it modify files outside the user's home (other than the OS trash) is a
  bug.

## Not vulnerabilities

- Cleaning something you selected. The risk levels and the per-category
  "what happens after cleaning" text are there to be read.
- Categories showing nothing because macOS denied access (see Full Disk Access
  in the README) — that's the sandbox working.
- The app being unsigned, so Gatekeeper warns on first launch. That's expected
  for this project; the README explains it.
