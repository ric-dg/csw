# csw

**One `claude` across several Claude Code accounts.** See every account's 5-hour and
7-day limits at a glance, switch with one key, and keep going in the same
conversations, whichever account you're on.

```
$ csw ls
  ACCOUNT    5-HOUR          RESETS     7-DAY           RESETS     MODEL 7-DAY
* work       ###.......  26%  in 2h54m   #########.  86%  in 4h44m   Fable 0%      current
  personal   #.........   7%  in 3h04m   ..........   3%  Fri 04:00  Fable 3%
```

- **A single POSIX `sh` script.** Needs `jq` and `curl` or `wget` (optionally `fzf`);
  no Python, no Node, no daemon. Runs on laptops and servers alike: dash, bash,
  BusyBox ash.
- **Shared history, separate logins.** Every account can resume every conversation.
  Each login lives in exactly one place, so switching never copies tokens around.
- **Careful with your logins.** Expired logins are refreshed with Claude Code's own lock
  protocol and saved atomically. Tokens never go on a command line (visible in `ps`),
  and every file csw creates is private (`umask 077`).

> **Disclaimer.** csw is not affiliated with or endorsed by Anthropic. It reads the
> same usage endpoint as Claude Code's `/usage` and refreshes logins with Claude Code's
> public OAuth client. Both are **unofficial** and can change without notice; if they
> do, the limits view and refresh stop working until csw is updated, while switching
> keeps working. Using several accounts must comply with
> [Anthropic's terms](https://www.anthropic.com/legal) and, for work accounts, your
> organisation's policies. You are responsible for how you use it.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh
# or
wget -qO- https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh
```

The installer puts `csw` in `~/.local/bin` (no root). It downloads the latest release
over HTTPS and **refuses to install unless the SHA-256 checksum matches**. Re-run it to
update. Options: `--version X.Y.Z`, `--bin-dir DIR`, `--uninstall [--purge]`.

Prefer to read before running? Download `install.sh`, read it, then `sh install.sh`.
Or skip the installer entirely: csw is one file. Copy
[`csw`](csw) anywhere on your `PATH` and `chmod +x` it.

**Requirements:** Linux or WSL (Claude Code keeps logins in
`~/.claude/.credentials.json` there; on macOS they're in the Keychain, which csw
doesn't support). Also a POSIX `sh` with `local` (dash, bash, BusyBox ash, zsh,
mksh), [Claude Code](https://docs.claude.com/en/docs/claude-code/setup), `jq` ≥ 1.6,
and `curl` or `wget`. `fzf` is optional. Anything missing is reported with the install
command for your system.

## Use

```sh
csw add work          # create an account and sign in (repeat per account)
csw add personal
# make plain `claude` use the current account; the function starts Claude directly
# (no extra process) unless auto-switch is on:
eval "$(csw init sh)"        # in ~/.bashrc, ~/.shrc, ~/.zshrc
csw init fish | source       # in ~/.config/fish/config.fish
```

| Command | What it does |
|---|---|
| `csw` | Interactive picker with every account's limits (fzf; plain menu without it). **Enter** use · **Ctrl-O** use and start Claude · **Ctrl-B** best · **Ctrl-R** refresh |
| `csw ls` | Table of 5-hour / 7-day usage and reset times, plus per-model weekly limits (e.g. Fable) when an account has them |
| `csw watch [SEC]` | The same table, redrawn every SEC seconds (default 120) |
| `csw use NAME` | Make NAME the current account |
| `csw best` | Switch to the account with the most 5-hour room left |
| `csw run [ARGS]` | Start Claude Code with the current account (all ARGS pass through) |
| `csw auto [PCT\|off]` | When Claude starts on an account at ≥ PCT % 5-hour use, switch to the best one first |
| `csw add NAME` / `csw login NAME` | Add an account / sign in again |
| `csw rm NAME` | Forget an account (asks you to retype the name) |
| `csw relink` | Re-apply the shared-history links |
| `csw init sh\|fish` | Print the fast `claude` function for your shell |
| `csw doctor` | Check dependencies (and jq's version), accounts and file permissions |
| `csw version` / `csw help` | |

Hit a limit mid-conversation? Exit, run `csw best` (or let `csw auto` do it), then
`claude --continue`: the next account picks up the same conversation.

## How it works

```
~/.claude/                          shared: projects (conversations, memory), history,
                                    settings, skills, plugins, ...
~/.local/share/claude-accounts/
  work/      .credentials.json      its own login (mode 600, dir 700)
             .claude.json           its own account config
             projects -> ~/.claude/projects   (and the other shared items)
  personal/  ...
~/.local/state/claude-accounts/     current account, auto-switch threshold
~/.cache/claude-accounts/           usage readings (reused for 120 s)
```

- `csw run` sets `CLAUDE_CONFIG_DIR` to the current account's folder and `exec`s
  `claude`.
- **Usage:** `GET https://api.anthropic.com/api/oauth/usage` with the account's access
  token (`anthropic-beta: oauth-2025-04-20`). All accounts are fetched in parallel.
- **Refresh:** when a login is about to expire, csw takes the same directory locks
  Claude Code uses (`<config>/.oauth_refresh.lock`, then `<config>.lock`; stale after
  60 s). It re-reads the login, and if a running Claude refreshed it meanwhile, does
  nothing. Otherwise it exchanges the refresh token at
  `https://platform.claude.com/v1/oauth/token` and replaces the file atomically.
- **Tokens and argv:** curl gets headers and bodies from private files (`-H @file`),
  and GNU wget through a private `--config` file. BusyBox wget can only take headers
  in argv, so csw warns once when that is the only client available.

## Uninstall

```sh
sh install.sh --uninstall           # remove csw, keep its logins
sh install.sh --uninstall --purge   # also delete its accounts, logins and caches
```

Your conversations in `~/.claude` are never touched.

## Development

```sh
tests/run.sh                 # every scenario x {dash, bash, busybox ash} x {curl, GNU wget, BusyBox wget}
shellcheck csw install.sh tests/run.sh tests/fakes/*
```

The tests need no network and no real logins: `tests/fakes/` emulates curl, both
wgets, `claude`, and Anthropic's two endpoints. They cover refresh and token rotation,
stale and live locks, auto-switch, privacy (no token in argv, no readable files, no
leftover temp files), editing `csw` while it runs, and the installer (checksum
mismatch, update, uninstall).

**Upstream watch** (`.github/workflows/upstream.yml`, daily, no credentials):
1. **Endpoints.** `tests/upstream.sh` probes both endpoints. The usage path must
   answer 401 rather than 404 and must treat a bearer token as OAuth. The token
   endpoint must answer `invalid_grant` (not "client not found") for Claude Code's
   client id.
2. **Values.** It downloads the latest Claude Code Linux build from npm (checked
   against npm's integrity hash, never executed). `tools/upstream-values.py` reads
   the production OAuth settings out of it (`TOKEN_URL`, `CLIENT_ID`, usage path,
   beta header) and compares them with csw's.
3. **Outcome.** If only those values changed, the workflow patches csw
   (`tools/apply-upstream.sh`, strict character set), runs the full suite and
   **opens a pull request**. A human reviews it; nothing merges itself. Anything else
   opens an `upstream-drift` issue.

It can't see a change in the shape of a real usage reply, because that needs a login,
and CI never holds one.

**Supply chain:** workflow actions are pinned to commit SHAs (Dependabot updates them
weekly), and every workflow has least-privilege permissions. Releases carry a checksum
and a build provenance attestation:
`gh attestation verify csw --repo ric-dg/csw`.

Releases: bump `CSW_VERSION` in `csw`, add a `CHANGELOG.md` entry, and push a tag
`vX.Y.Z`. CI runs the tests and publishes `csw`, `csw.sha256` (with a provenance
attestation) and `install.sh`. See [CONTRIBUTING.md](CONTRIBUTING.md) and
[SECURITY.md](SECURITY.md).

## Prior art

- [claude-swap](https://github.com/realiti4/claude-swap) (Python): the full-featured
  original. csw's lock protocol and endpoints follow its documentation. csw differs by
  keeping one config folder per account instead of swapping one login file.
- The installer layout follows [rustup](https://github.com/rust-lang/rustup)'s and
  [zoxide](https://github.com/ajeetdsouza/zoxide)'s `install.sh`, adding checksum
  verification.

## License

[MIT](LICENSE)
