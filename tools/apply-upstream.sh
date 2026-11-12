#!/bin/sh
# apply-upstream.sh FILE: write KEY=VALUE lines from tools/upstream-values.py into the
# constants at the top of csw (USAGE_URL, TOKEN_URL, CLIENT_ID, BETA). Values are
# checked against a strict character set first, so nothing odd from a binary can
# reach the script. Used by .github/workflows/upstream.yml before it opens a PR.
set -eu
CSW=$(cd "$(dirname "$0")/.." && pwd)/csw
[ -r "${1-}" ] || { echo "usage: $0 KEY=VALUE-file" >&2; exit 2; }
while IFS='=' read -r key value; do
	case $value in '' | *[!A-Za-z0-9:/._-]*) echo "refusing unsafe value for $key: $value" >&2; exit 1 ;; esac
	case $key in
	USAGE_URL | TOKEN_URL)
		sed -i "s|^$key=\${CSW_$key:-[^}]*}|$key=\${CSW_$key:-$value}|" "$CSW" ;;
	CLIENT_ID | BETA)
		sed -i "s|^$key=[A-Za-z0-9:/._-]*|$key=$value|" "$CSW" ;;
	*) echo "unknown key: $key" >&2; exit 1 ;;
	esac
	grep -q "^$key=.*$value" "$CSW" || { echo "could not update $key" >&2; exit 1; }
	echo "updated $key=$value"
done <"$1"
