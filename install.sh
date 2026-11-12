#!/bin/sh
# shellcheck shell=dash
#
# csw installer: puts the csw script in ~/.local/bin. No root needed.
#
#   curl -fsSL https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh
#   wget -qO-  https://raw.githubusercontent.com/ric-dg/csw/main/install.sh | sh
#
#   sh install.sh [--version X.Y.Z] [--bin-dir DIR] [--from FILE] [--uninstall [--purge]]
#
#   --version X.Y.Z   install that release (default: the latest)
#   --bin-dir DIR     where to put csw (default: ~/.local/bin)
#   --from FILE       install a local copy instead of downloading (development)
#   --uninstall       remove csw; --purge also deletes its accounts, logins and caches
#
# Re-running updates. Downloads the release's csw and csw.sha256 over HTTPS (TLS 1.2+)
# and refuses to install unless the SHA-256 matches. Everything runs from main on the
# last line, so a download cut off half-way can't run half a script.
set -eu

REPO=${CSW_REPO:-ric-dg/csw}
TMP_DIR= # global: the EXIT trap runs after main's locals are gone

say() { printf 'csw-install: %s\n' "$*"; }
err() { printf 'csw-install: error: %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

download() { # download URL FILE
	if has curl; then
		curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
	elif case $(wget --version 2>/dev/null) in *'GNU Wget'*) true ;; *) false ;; esac then
		wget -q --https-only --secure-protocol=TLSv1_2 -O "$2" "$1"
	elif has wget; then
		wget -q -O "$2" "$1" # BusyBox wget: no TLS-version flag
	else
		err "needs curl or wget"
	fi
}

sha256() { # print the SHA-256 of a file
	if has sha256sum; then sha256sum "$1" | cut -d ' ' -f 1
	elif has shasum; then shasum -a 256 "$1" | cut -d ' ' -f 1
	elif has openssl; then openssl dgst -sha256 "$1" | sed 's/.*= *//'
	else err "needs sha256sum, shasum or openssl to verify the download"; fi
}

check_deps() { # report (don't fail on) what csw needs at run time
	local missing='' c
	for c in jq claude; do has "$c" || missing="$missing $c"; done
	has curl || has wget || missing="$missing curl"
	[ -z "$missing" ] || say "csw also needs:$missing (it will tell you how to install them)"
	has fzf || say "optional: install fzf for the interactive picker"
}

path_hint() {
	case :$PATH: in
	*:"$1":*) ;;
	*)
		say "$1 is not on your PATH. Add it:"
		say "  sh/bash/dash: echo 'export PATH=\"$1:\$PATH\"' >> ~/.profile"
		say "  fish:         fish_add_path $1"
		;;
	esac
}

uninstall() { # uninstall BIN_DIR PURGE
	local data=${XDG_DATA_HOME:-$HOME/.local/share}/claude-accounts
	local state=${XDG_STATE_HOME:-$HOME/.local/state}/claude-accounts
	local cache=${XDG_CACHE_HOME:-$HOME/.cache}/claude-accounts
	rm -f "$1/csw"
	say "removed $1/csw"
	if [ "$2" = 1 ]; then
		rm -rf "$data" "$state" "$cache"
		say "deleted csw's accounts and logins ($data), state and cache"
		say "your conversations in ~/.claude were not touched"
	else
		say "kept csw's accounts and logins in $data (delete with --uninstall --purge)"
	fi
}

main() {
	local version='' bin_dir="$HOME/.local/bin" from='' do_uninstall=0 purge=0 tmp url got want
	trap 'rm -rf "${TMP_DIR:-}"' EXIT
	trap 'exit 130' INT TERM
	while [ $# -gt 0 ]; do
		case $1 in
		--version) version=${2:?--version needs a value}; shift ;;
		--version=*) version=${1#*=} ;;
		--bin-dir) bin_dir=${2:?--bin-dir needs a value}; shift ;;
		--bin-dir=*) bin_dir=${1#*=} ;;
		--from) from=${2:?--from needs a file}; shift ;;
		--from=*) from=${1#*=} ;;
		--uninstall) do_uninstall=1 ;;
		--purge) purge=1 ;;
		-h | --help) sed -n '4,/^set -eu/p' "$0" 2>/dev/null | sed '$d; s/^# \{0,1\}//'; return 0 ;;
		*) err "unknown option: $1 (see --help)" ;;
		esac
		shift
	done

	if [ "$do_uninstall" = 1 ]; then
		uninstall "$bin_dir" "$purge"
		return 0
	fi

	TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/csw-install.XXXXXX")
	tmp=$TMP_DIR

	if [ -n "$from" ]; then
		[ -f "$from" ] || err "no such file: $from"
		cp "$from" "$tmp/csw"
		say "installing local file $from"
	else
		if [ -n "$version" ]; then
			url=https://github.com/$REPO/releases/download/v${version#v}
		else
			url=https://github.com/$REPO/releases/latest/download
		fi
		say "downloading $url/csw"
		download "$url/csw" "$tmp/csw" || err "download failed: $url/csw"
		download "$url/csw.sha256" "$tmp/csw.sha256" || err "download failed: $url/csw.sha256"
		want=$(cut -d ' ' -f 1 "$tmp/csw.sha256")
		got=$(sha256 "$tmp/csw")
		[ -n "$want" ] && [ "$got" = "$want" ] || err "checksum mismatch (expected $want, got $got); not installing"
		say "checksum OK ($got)"
	fi

	head -n 1 "$tmp/csw" | grep -q '^#!/bin/sh' || err "downloaded file is not the csw script"
	sh -n "$tmp/csw" || err "downloaded file has a syntax error; not installing"

	mkdir -p "$bin_dir"
	# copy next to the target, then rename: an update never leaves a half-written csw
	cp "$tmp/csw" "$bin_dir/.csw.new"
	chmod 755 "$bin_dir/.csw.new"
	mv "$bin_dir/.csw.new" "$bin_dir/csw"
	say "installed $("$bin_dir/csw" version) to $bin_dir/csw"
	path_hint "$bin_dir"
	check_deps
	say "next: csw add NAME (sign in), then: csw help"
}

{ main "$@" || exit 1; } && exit 0
