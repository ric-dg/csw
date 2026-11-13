# Changelog

All notable changes to csw. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-13

### Added
- Per-model weekly limits (the usage reply's `weekly_scoped` entries, e.g. "Fable 3%")
  in `csw ls`, `csw watch` and the picker, as a **MODEL 7-DAY** column. It appears
  only when some account has such a limit, and shows `-` for accounts without one.
  Model names come from the reply, so new models show up without a csw update.

## [0.1.0] - 2026-11-13

### Added
- `csw`: shared Claude Code across accounts. Usage table (`ls`, `watch`), fzf picker,
  `use`, `best`, `auto`, `run`, `add`, `login`, `rm`, `relink`, `version`.
- Login refresh using Claude Code's lock protocol, with atomic saves.
- HTTP via curl, GNU wget or BusyBox wget; tokens never in argv (except BusyBox, warned).
- `install.sh`: curl/wget installer with SHA-256 verification, update, uninstall.
- Test suite with fake clients and endpoints (dash, bash, BusyBox ash).
- `csw init sh|fish`: a `claude` shell function that starts Claude with no extra
  process when auto-switch is off (about 0.05 ms overhead, versus about 4 ms through
  `csw run`).
- `csw doctor`: checks dependencies (including jq's features), accounts and file
  permissions.
- `tests/upstream.sh` plus a daily workflow that checks, without credentials, that
  Anthropic's endpoints and Claude Code's constants are unchanged.
- The upstream workflow reads the new values out of Claude Code
  (`tools/upstream-values.py`), patches csw (`tools/apply-upstream.sh`), runs the full
  test suite and opens a pull request for review; anything else opens an issue.
- Release provenance attestations; commit-pinned actions with Dependabot;
  SECURITY.md, CONTRIBUTING.md, issue and PR templates, CODEOWNERS.

### Performance
- Fewer processes: account lookups use globals instead of `$(...)`; one `stat` and one
  `jq` cover all accounts; jq's clock replaces `date`; `/proc/<pid>/comm` is read with
  a builtin. `csw ls` and `csw best` are about 59 % faster; `csw run` about 19 %.
