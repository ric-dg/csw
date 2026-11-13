#!/bin/sh
# csw test suite: no network and no real logins. Fake curl / GNU wget / BusyBox wget /
# claude emulate Anthropic's endpoints (tests/fakes/). Every scenario runs under each
# available shell (dash, bash, busybox ash) and each HTTP client.
#
#   tests/run.sh            all shells x all clients
#   SHELLS=dash tests/run.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CSW=$HERE/../csw
FAKES=$HERE/fakes
export FAKES
PASS=0 FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL [%s/%s] %s\n' "$SH" "$CLIENT" "$*"; }
check() { # check DESCRIPTION COMMAND...
	d=$1; shift
	if "$@" >/dev/null 2>&1; then ok; else bad "$d"; fi
}
has_text() { printf '%s' "$1" | grep -q -- "$2"; }
fails_text() { ! has_text "$@"; }

# a bin dir with real tools, minus any HTTP client (each run adds exactly one fake)
BASE=$(mktemp -d)
for t in sh dash bash date cat jq sed grep awk sort head cut tr mktemp mkdir rmdir rm mv cp chmod stat \
	kill ln basename dirname env sleep ls find touch wc printf readlink tail true sha256sum fish; do
	p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$BASE/$t"
done
ln -s "$FAKES/claude" "$BASE/claude"

creds() { # creds DIR ACCESS REFRESH EXPIRES_IN_S
	printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":%s,"scopes":["user:inference","user:profile"]}}\n' \
		"$2" "$3" "$((($(date +%s) + $4) * 1000))" >"$1/.credentials.json"
	chmod 600 "$1/.credentials.json"
}

run_suite() { # run_suite SHELL CLIENT: runs in a subshell; prints its own counts
	SH=$1 CLIENT=$2 PASS=0 FAIL=0
	W=$(mktemp -d)
	mkdir -p "$W/bin" "$W/shared/projects" "$W/fake"
	case $CLIENT in
	curl) ln -s "$FAKES/curl" "$W/bin/curl" ;;
	gnu-wget) ln -s "$FAKES/wget-gnu" "$W/bin/wget" ;;
	busybox-wget) ln -s "$FAKES/wget-busybox" "$W/bin/wget" ;;
	esac
	export XDG_DATA_HOME="$W/data" XDG_STATE_HOME="$W/state" XDG_CACHE_HOME="$W/cache" \
		CSW_SHARED="$W/shared" CSW_TOKEN_URL=http://fake/token CSW_USAGE_URL=http://fake/usage \
		FAKE_STATE="$W/fake" PATH="$W/bin:$BASE" TMPDIR="$W"
	R=$W/data/claude-accounts
	c() { $SH "$CSW" "$@"; }
	# shellcheck disable=SC2329 # these helpers are called through check()
	# shellcheck disable=SC2329 # these helpers are called through check()
	fails() { ! c "$@"; }
	# shellcheck disable=SC2329
	# shellcheck disable=SC2329
	rm_wrong() { echo nope | c rm w; [ -d "$R/w" ]; }
	# shellcheck disable=SC2329
	# shellcheck disable=SC2329
	rm_right() { echo w | c rm w >/dev/null; [ ! -d "$R/w" ]; }

	# add: folders, privacy, shared links, first account becomes current
	for a in x y z w; do c add "$a" >/dev/null; done
	check "add creates private dirs" [ "$(stat -c %a "$R/x")" = 700 ]
	check "add links projects to the shared dir" [ "$(readlink "$R/y/projects")" = "$W/shared/projects" ]
	check "first account is current" [ "$(cat "$W/state/claude-accounts/current")" = x ]
	creds "$R/x" SECRET-old REFRESH-x -100 # expired: must be refreshed
	creds "$R/y" SECRET-busy REFRESH-y 3600
	creds "$R/z" SECRET-mid REFRESH-z 3600

	# ls: usage, refresh, rotation, privacy, no leaks
	out=$(c ls 2>"$W/err")
	check "ls shows refreshed x at 10%" has_text "$out" 'x .*10%'
	check "ls shows y at 92%" has_text "$out" 'y .*92%'
	check "ls shows z at 40%" has_text "$out" 'z .*40%'
	check "ls says w is not logged in" has_text "$out" 'w .*not logged in'
	check "ls shows the per-model column when an account has one" has_text "$out" 'MODEL 7-DAY'
	check "ls shows z's Fable weekly limit" has_text "$out" 'z .*Fable 7%'
	check "ls shows - for an account without per-model limits" has_text "$out" 'y .*33%.* - '
	check "ls footer names the time zone with its UTC offset" has_text "$out" 'times in .*(UTC[+-][0-9][0-9]:[0-9][0-9])'
	out=$(CSW_TTL=99999 c ls --utc 2>/dev/null)
	check "ls --utc shows the reset date and time in UTC" has_text "$out" 'x .*Jan 01 00:00 (.*Jan 05 00:00 ('
	check "ls --utc footer says UTC" has_text "$out" '^times in UTC'
	check "refresh saved the new access token" grep -q SECRET-fresh "$R/x/.credentials.json"
	check "refresh saved the rotated refresh token" grep -q REFRESH-rotated "$R/x/.credentials.json"
	check "refreshed login stays mode 600" [ "$(stat -c %a "$R/x/.credentials.json")" = 600 ]
	check "no lock left behind" [ ! -e "$R/x/.oauth_refresh.lock" ] && check "no legacy lock left" [ ! -e "$R/x.lock" ]
	check "no temp files left" [ -z "$(find "$W" -type f \( -name '.refresh.*' -o -name '.request.*' -o -name '.headers.*' -o -name 'csw.*' \))" ]
	check "all csw files private" [ -z "$(find "$W/data" "$W/state" "$W/cache" -type f -perm /077)" ]
	if [ "$CLIENT" = busybox-wget ]; then
		check "BusyBox wget warns about argv" grep -q 'BusyBox wget' "$W/err"
	else
		check "no token ever in argv" [ ! -s "$W/fake/leaks" ]
	fi

	# without any per-model limit the column is hidden (readings reused: no refetch)
	cp "$W/cache/claude-accounts/z.json" "$W/z.keep"
	jq 'del(.limits)' "$W/z.keep" >"$W/cache/claude-accounts/z.json"
	out=$(CSW_TTL=99999 c ls 2>/dev/null)
	check "per-model column hidden when no account has one" fails_text "$out" 'MODEL 7-DAY'
	mv "$W/z.keep" "$W/cache/claude-accounts/z.json"

	# best / use / auto / run
	check "best picks the emptiest account" has_text "$(c best)" 'now using x'
	c use y >/dev/null
	c auto 90 >/dev/null
	out=$(CSW_TTL=0 c run --flag 2>&1)
	check "auto-switch leaves y at 92%" has_text "$out" 'switching to x'
	check "run starts claude in the chosen account" has_text "$out" "dir=$R/x args=--flag"
	check "auto-switch remembers the new account" [ "$(cat "$W/state/claude-accounts/current")" = x ]
	c auto off >/dev/null
	check "auto off" [ ! -e "$W/state/claude-accounts/auto" ]

	# plain menu without a terminal / fzf
	check "plain menu switches" has_text "$(echo z | c 2>&1)" 'now using z'

	# errors and names
	check "unknown account rejected" fails use nope
	check "bad name rejected" fails add "a b"
	check "unknown command fails" fails frobnicate
	check "version" has_text "$(c version)" '^csw [0-9]'

	# rm: wrong confirmation cancels, right one removes
	check "rm cancelled by a wrong name" rm_wrong
	check "rm removes after confirmation" rm_right

	# missing tools are named with an install hint
	out=$(PATH="$W/bin" $SH "$CSW" ls 2>&1 || true)
	check "missing jq is reported with a hint" has_text "$out" 'missing:.*jq'

	if [ "$CLIENT" = curl ]; then
		# csw init: the fast path starts claude directly; with auto on it defers to csw
		c use x >/dev/null
		printf '#!/bin/sh\necho CSW-CALLED "$@"\n' >"$W/bin/csw"
		chmod +x "$W/bin/csw"
		c init sh >"$W/init.sh"
		# shellcheck disable=SC2016 # expanded by the inner shell, on purpose
		out=$($SH -c '. "$1"; shift; claude "$@"' _ "$W/init.sh" --hi)
		check "init sh: fast path starts claude directly" has_text "$out" "dir=$R/x args=--hi"
		c auto 90 >/dev/null
		# shellcheck disable=SC2016
		out=$($SH -c '. "$1"; claude --hi' _ "$W/init.sh")
		check "init sh: auto on defers to csw run" has_text "$out" 'CSW-CALLED run --hi'
		c auto off >/dev/null
		if command -v fish >/dev/null 2>&1; then
			c init fish >"$W/init.fish"
			out=$(fish --no-config -c "source $W/init.fish; claude --hi")
			check "init fish: fast path starts claude directly" has_text "$out" "dir=$R/x args=--hi"
		fi
		rm -f "$W/bin/csw"

		# stale lock from a crashed holder (2 minutes old) is taken over
		creds "$R/z" SECRET-mid REFRESH-z -100
		mkdir "$R/z/.oauth_refresh.lock"
		touch -d '-2 min' "$R/z/.oauth_refresh.lock"
		CSW_TTL=0 c ls >/dev/null
		check "stale lock taken over and login refreshed" grep -q SECRET-fresh "$R/z/.credentials.json"

		# live lock: "Claude Code" holds it, refreshes, releases; csw waits and skips its refresh
		creds "$R/z" SECRET-mid REFRESH-z -100
		before=$(cat "$W/fake/refreshes")
		mkdir "$R/z.lock"
		(sleep 2; creds "$R/z" SECRET-mid REFRESH-z 3600; rmdir "$R/z.lock") &
		CSW_TTL=0 c ls >/dev/null
		wait
		check "csw waits for a live lock and skips a refresh Claude already did" [ "$(cat "$W/fake/refreshes")" = "$before" ]

		# edit safety: the same file is rewritten in place (same inode, shifted bytes)
		# while a slow login waits, as an editor or update would do
		cp "$CSW" "$W/csw-copy"
		{ head -n 30 "$CSW"; i=0; while [ $i -lt 300 ]; do echo "# padding $i"; i=$((i + 1)); done; tail -n +31 "$CSW"; } >"$W/csw-mod"
		(sleep 1; cat "$W/csw-mod" >"$W/csw-copy") &
		out=$(FAKE_SLOW_LOGIN=2 $SH "$W/csw-copy" add v 2>&1)
		wait
		# shellcheck disable=SC2016 # $0 expands in the inner sh, on purpose
		# shellcheck disable=SC2016 # $0 expands in the inner sh, on purpose
		check "editing csw during a run does not break it" sh -c '! printf "%s" "$0" | grep -qi "syntax error"' "$out"
	fi
	rm -rf "$W"
	echo "COUNTS $PASS $FAIL"
}

installer_tests() { # runs once, in a subshell, with a fake GitHub release
	SH=installer CLIENT=$1 PASS=0 FAIL=0
	W=$(mktemp -d)
	mkdir -p "$W/bin" "$W/release" "$W/home"
	cp "$CSW" "$W/release/csw"
	(cd "$W/release" && sha256sum csw >csw.sha256)
	# fake curl that serves the release folder for github.com/test/csw/releases/...
	cat >"$W/bin/curl" <<'FAKE'
#!/bin/sh
out= url=
while [ $# -gt 0 ]; do case $1 in -o) shift; out=$1 ;; -*) ;; --proto) shift ;; *) url=$1 ;; esac; shift; done
case $url in https://github.com/test/csw/releases/*/download/*|https://github.com/test/csw/releases/download/*/*) ;; *) exit 22 ;; esac
cp "$RELEASE/${url##*/}" "$out"
FAKE
	chmod +x "$W/bin/curl"
	mkdir -p "$W/tmp"
	export TMPDIR="$W/tmp" HOME="$W/home" PATH="$W/bin:$BASE" RELEASE="$W/release" CSW_REPO=test/csw \
		XDG_DATA_HOME="$W/home/data" XDG_STATE_HOME="$W/home/state" XDG_CACHE_HOME="$W/home/cache"
	B=$W/home/.local/bin
	i() { sh "$HERE/../install.sh" "$@"; }

	out=$(i --from "$CSW" 2>&1)
	check "installer: local install" [ -x "$B/csw" ]
	check "installer: warns when bin dir is not on PATH" has_text "$out" 'not on your PATH'
	out=$(i 2>&1)
	check "installer: release download verifies checksum" has_text "$out" 'checksum OK'
	check "installer: installed copy runs" has_text "$("$B/csw" version)" '^csw '
	check "installer: no temp file left in bin dir" [ ! -e "$B/.csw.new" ]
	echo '# tampered' >>"$W/release/csw"
	out=$(i 2>&1 || true)
	check "installer: refuses a tampered download" has_text "$out" 'checksum mismatch'
	check "installer: keeps the old copy on mismatch" sh -n "$B/csw"
	mkdir -p "$XDG_DATA_HOME/claude-accounts/a"
	i --uninstall >/dev/null
	check "installer: uninstall removes csw" [ ! -e "$B/csw" ]
	check "installer: uninstall keeps logins by default" [ -d "$XDG_DATA_HOME/claude-accounts/a" ]
	i --from "$CSW" >/dev/null && i --uninstall --purge >/dev/null
	check "installer: --purge deletes csw data" [ ! -e "$XDG_DATA_HOME/claude-accounts" ]
	check "installer: temp dirs cleaned up" [ -z "$(ls -A "$W/tmp")" ]
	# shellcheck disable=SC2016
	# shellcheck disable=SC2016
	check "installer: unknown option fails" sh -c '! sh "$0" --bogus' "$HERE/../install.sh"
	rm -rf "$W"
	echo "COUNTS $PASS $FAIL"
}

SHELLS=${SHELLS:-}
if [ -z "$SHELLS" ]; then
	for s in dash bash; do command -v $s >/dev/null 2>&1 && SHELLS="$SHELLS $s"; done
	command -v busybox >/dev/null 2>&1 && SHELLS="$SHELLS busybox-ash"
fi
for s in $SHELLS; do
	# absolute path: some tests run csw with a PATH that has no shells on it
	if [ "$s" = busybox-ash ]; then sh_cmd="$(command -v busybox) ash"; else sh_cmd=$(command -v "$s"); fi
	for client in curl gnu-wget busybox-wget; do
		out=$( (run_suite "$sh_cmd" "$client") 2>&1)
		counts=$(printf '%s\n' "$out" | sed -n 's/^COUNTS //p')
		PASS=$((PASS + ${counts%% *})) FAIL=$((FAIL + ${counts##* }))
		if [ "${counts##* }" = 0 ]; then
			printf '  ok   [%s/%s] %s checks\n' "$s" "$client" "${counts%% *}"
		else
			printf '%s\n' "$out" | grep '^  FAIL'
		fi
	done
done
out=$( (installer_tests curl) 2>&1)
counts=$(printf '%s\n' "$out" | sed -n 's/^COUNTS //p')
PASS=$((PASS + ${counts%% *})) FAIL=$((FAIL + ${counts##* }))
if [ "${counts##* }" = 0 ]; then printf '  ok   [installer] %s checks\n' "${counts%% *}"; else printf '%s\n' "$out" | grep '^  FAIL'; fi

rm -rf "$BASE"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
