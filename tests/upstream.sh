#!/bin/sh
# Upstream drift check: are the unofficial things csw relies on still there?
# Run daily by .github/workflows/upstream.yml; safe to run by hand. Needs curl, jq, tar.
#
#  1. Endpoints, probed WITHOUT credentials (two tiny requests):
#     - the usage endpoint must exist (401 without credentials; a moved or removed
#       endpoint answers 404) and treat a made-up bearer token as an invalid OAuth token;
#     - the token endpoint must reject a made-up refresh token with `invalid_grant`
#       for Claude Code's client id (a revoked client id answers "Client ... not found").
#  2. The latest Claude Code release (linux-x64 build from npm, integrity-checked, never
#     executed): tools/upstream-values.py reads the URLs, client id and beta header out
#     of it and compares them with csw's; the lock, credential and usage field names
#     must still be there. With UPSTREAM_ENV=FILE, changed values are written to FILE.
#
# Exit: 0 all good; 1 needs a human; 3 only values changed (patchable, PR-able).
#
# What it can't see: a change in the *shape* of a real usage reply. That needs a real
# login, and CI must never hold one.
set -eu

CSW=$(cd "$(dirname "$0")/.." && pwd)/csw
const() { sed -n "s/^$1=\${[A-Z_]*:-\(.*\)}\$/\1/p; s/^$1=\([^ \$]*\)\( .*\)\{0,1\}\$/\1/p" "$CSW" | head -n 1; }
USAGE_URL=$(const USAGE_URL)
TOKEN_URL=$(const TOKEN_URL)
CLIENT_ID=$(const CLIENT_ID)
BETA=$(const BETA)
FAIL=0
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

ok() { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; FAIL=1; }

for v in USAGE_URL TOKEN_URL CLIENT_ID BETA; do
	eval "[ -n \"\$$v\" ]" || { echo "could not read $v from csw"; exit 2; }
done

# --- 1. endpoints ----------------------------------------------------------------
# Without credentials an existing path answers 401 and an unknown one 404. With a
# token, auth runs before routing (a renamed path would also answer 401), so it takes
# two probes: no token proves the path exists, a made-up token proves OAuth is accepted.
code=$(curl -sS -m 20 -A csw-upstream-check -o "$T/u0" -w '%{http_code}' -H "anthropic-beta: $BETA" "$USAGE_URL") || code=000
if [ "$code" = 401 ]; then
	ok "usage endpoint exists (401 without credentials, not 404): $USAGE_URL"
else
	bad "usage endpoint moved or changed: HTTP $code $(head -c 200 "$T/u0" 2>/dev/null) ($USAGE_URL)"
fi
code=$(curl -sS -m 20 -A csw-upstream-check -o "$T/u" -w '%{http_code}' \
	-H "anthropic-beta: $BETA" -H 'Authorization: Bearer sk-ant-oat01-csw-upstream-check' "$USAGE_URL") || code=000
if [ "$code" = 401 ] && jq -e '.error.type == "authentication_error" and (.error.message | test("oauth"; "i"))' "$T/u" >/dev/null 2>&1; then
	ok "usage endpoint accepts OAuth tokens (rejects a made-up one as an invalid OAuth token)"
else
	bad "usage endpoint no longer treats bearer tokens as OAuth: HTTP $code $(head -c 200 "$T/u" 2>/dev/null)"
fi

code=$(curl -sS -m 20 -A csw-upstream-check -o "$T/t" -w '%{http_code}' -H 'Content-Type: application/json' \
	-d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"csw-upstream-check\",\"client_id\":\"$CLIENT_ID\"}" "$TOKEN_URL") || code=000
if [ "$code" = 400 ] && jq -e '.error == "invalid_grant"' "$T/t" >/dev/null 2>&1; then
	ok "token endpoint answers and the client id is accepted (invalid_grant for a made-up token)"
elif grep -q 'not found' "$T/t" 2>/dev/null; then
	bad "Claude Code's OAuth client id is no longer accepted: $(head -c 200 "$T/t")"
else
	bad "token endpoint changed: HTTP $code $(head -c 200 "$T/t" 2>/dev/null) ($TOKEN_URL)"
fi

# --- 2. the latest Claude Code: same values? -----------------------------------------
meta=$(curl -fsS -m 30 https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/latest) ||
	{ bad "could not read Claude Code's npm metadata"; exit 1; }
ver=$(printf '%s' "$meta" | jq -r .version)
url=$(printf '%s' "$meta" | jq -r .dist.tarball)
integrity=$(printf '%s' "$meta" | jq -r .dist.integrity) # sha512-<base64>
curl -fsS -m 600 -o "$T/cc.tgz" "$url" || { bad "could not download Claude Code $ver"; exit 1; }
got="sha512-$(openssl dgst -sha512 -binary "$T/cc.tgz" | openssl base64 -A)"
[ "$got" = "$integrity" ] || { bad "Claude Code $ver tarball failed its npm integrity check"; exit 1; }
mkdir "$T/cc"
tar -xzf "$T/cc.tgz" -C "$T/cc"
bin=$(find "$T/cc" -type f -size +10M | head -n 1)
[ -n "$bin" ] || { bad "no binary found in Claude Code $ver"; exit 1; }

# the values csw copies, read out of Claude Code itself
if python3 -I "$(dirname "$0")/../tools/upstream-values.py" "$bin" >"$T/values" 2>"$T/values.err"; then
	CHANGED=0
	: >"$T/changed"
	while IFS='=' read -r k v; do
		cur=""
		eval "cur=\$$k"
		if [ "$v" = "$cur" ]; then
			ok "Claude Code $ver: $k unchanged"
		else
			printf 'CHANGED  Claude Code %s: %s %s -> %s\n' "$ver" "$k" "$cur" "$v"
			echo "$k=$v" >>"$T/changed"
			CHANGED=1
		fi
	done <"$T/values"
	if [ "$CHANGED" = 1 ] && [ -n "${UPSTREAM_ENV-}" ]; then cp "$T/changed" "$UPSTREAM_ENV"; fi
else
	bad "could not read csw's values from Claude Code $ver: $(cat "$T/values.err")"
fi

# names csw reads from credential files and usage replies
missing=''
for s in .oauth_refresh.lock claudeAiOauth accessToken refreshToken expiresAt five_hour seven_day utilization resets_at; do
	grep -a -q -F -- "$s" "$bin" || missing="$missing $s"
done
if [ -z "$missing" ]; then
	ok "Claude Code $ver still uses the lock, credential and usage field names csw relies on"
else
	bad "Claude Code $ver no longer contains:$missing"
fi

# 0 = all good; 1 = something needs a human; 3 = only values changed (patchable: see
# tools/apply-upstream.sh and the upstream workflow, which opens a PR)
[ "$FAIL" = 0 ] || exit 1
[ "${CHANGED:-0}" = 0 ] || exit 3
exit 0
