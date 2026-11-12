# Contributing

Thanks for helping. csw is deliberately small: one POSIX `sh` file, no runtime beyond
`jq` and `curl`/`wget`.

## Before you open a PR

```sh
shellcheck csw install.sh tests/*.sh tests/fakes/* tools/*.sh
tests/run.sh          # needs dash and bash; busybox and fish are used if present
```

Both must pass; CI runs the same commands, plus BusyBox ash.

## Code conventions

- POSIX `sh` plus `local`, which every supported shell has. No bashisms: CI runs dash
  and BusyBox ash.
- Mind the forks: every `$(...)` and external command costs about 1 ms on slow
  machines. Hot paths (`run`, `ls`, `best`) set globals instead of echoing, use
  builtins, and batch `jq`/`stat` across accounts.
- Never put a token in argv. Pass it through a private file (see `http()`).
- Anything that touches a login file takes Claude Code's locks (see `refresh()`).
- New behaviour needs a test in `tests/run.sh`. The fakes in `tests/fakes/` emulate
  curl, both wgets, `claude` and Anthropic's endpoints, so no network is needed.
- User-facing changes go in `CHANGELOG.md` under *Unreleased*.

## Upstream changes

`tests/upstream.sh` runs daily in CI. When Claude Code changes a value csw copies, a bot
PR updates it. Please check it with a real account (`csw ls`) before merging.
