# Security policy

csw handles Claude Code login tokens, so security reports are welcome and taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting:
**Security → Report a vulnerability** on this repository. You'll get an answer within a
few days. Please include the csw version (`csw version`), your shell and OS, and steps
to reproduce.

## What csw promises

- Login tokens never appear on a command line, where `ps` would show them to other
  users. The exception is BusyBox wget, which can only take headers there; csw warns
  when it has to use it.
- Every file csw creates is private (`umask 077`; logins are mode 600 in 700 folders).
- Logins are written atomically and refreshed under Claude Code's own lock protocol.
- Releases ship a SHA-256 checksum (checked by `install.sh`) and a build provenance
  attestation: `gh attestation verify csw --repo ric-dg/csw`.

## Scope

csw talks only to Anthropic's endpoints (see README) and runs only `claude`, `jq`, `curl`
or `wget`, `fzf` and standard POSIX tools. Problems in Claude Code itself should go to
Anthropic.
