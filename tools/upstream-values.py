#!/usr/bin/env python3
"""Read the values csw copies from Claude Code out of a Claude Code binary.

    python3 -I tools/upstream-values.py /path/to/claude

Prints KEY=VALUE lines (USAGE_URL, TOKEN_URL, CLIENT_ID, BETA) and exits 0, or
prints what it couldn't find and exits 1. The binary is memory-mapped and only
searched, never executed. CI tooling only (csw itself stays POSIX sh).

Claude Code bundles its OAuth settings as one object, e.g.
  {BASE_API_URL:"https://api.anthropic.com", ..., TOKEN_URL:"...", CLIENT_ID:"...", ...}
There can be other such objects (other environments), so the production one is the
object whose BASE_API_URL is https://api.anthropic.com. Exactly one distinct production
answer is required; anything ambiguous is reported, never guessed.
"""
import mmap
import re
import sys

PROD_API = b"https://api.anthropic.com"


def main(path: str) -> int:
    with open(path, "rb") as f, mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as m:
        found = {}
        blocks = []
        # Each settings object starts at its BASE_API_URL key. Read key:"value" pairs
        # from there until a key repeats (the next object has begun).
        for hit in re.finditer(rb'BASE_API_URL:"([^"]{1,200})"', m):
            if hit.group(1) != PROD_API:
                continue
            pairs, seen = {}, set()
            for k, v in re.findall(rb'([A-Z_]{3,40}):"([^"]{1,300})"', m[hit.start():hit.start() + 3000]):
                if k in seen:
                    break
                seen.add(k)
                pairs[k] = v
            if b"TOKEN_URL" in pairs and b"CLIENT_ID" in pairs:
                blocks.append(pairs)
        distinct = {(b[b"TOKEN_URL"], b[b"CLIENT_ID"]) for b in blocks}
        if len(distinct) == 1:
            token_url, client_id = distinct.pop()
            found["TOKEN_URL"] = token_url.decode()
            found["CLIENT_ID"] = client_id.decode()
        betas = sorted({b.decode() for b in re.findall(rb'"(oauth-\d{4}-\d{2}-\d{2})"', m)})
        paths = sorted({p.decode() for p in re.findall(rb'/api/oauth/[A-Za-z0-9_]*usage[A-Za-z0-9_]*', m)})
    problems = []
    if "CLIENT_ID" not in found:
        problems.append("expected exactly one production OAuth settings object "
                        "(BASE_API_URL=https://api.anthropic.com with TOKEN_URL and CLIENT_ID)")
    if len(betas) == 1:
        found["BETA"] = betas[0]
    else:
        problems.append(f"expected exactly one oauth-YYYY-MM-DD beta header, found {betas}")
    if len(paths) == 1:
        found["USAGE_URL"] = PROD_API.decode() + paths[0]
    else:
        problems.append(f"expected exactly one /api/oauth/*usage* path, found {paths}")
    if problems:
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        return 1
    for k in ("USAGE_URL", "TOKEN_URL", "CLIENT_ID", "BETA"):
        print(f"{k}={found[k]}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
