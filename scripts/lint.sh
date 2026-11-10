#!/usr/bin/env bash
# Lokální lint: syntaxe shellu, shellcheck (error) a Python bytecode.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

status=0

while IFS= read -r -d '' f; do
    bash -n "$f" || status=1
done < <(git ls-files -z '*.sh')

if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r -d '' f; do
        shellcheck --severity=error "$f" || status=1
    done < <(git ls-files -z '*.sh')
else
    echo "shellcheck není nainstalovaný – přeskakuji."
    echo "  macOS: brew install shellcheck"
    echo "  Debian: sudo apt install shellcheck"
fi

if command -v python3 >/dev/null 2>&1; then
    python3 -m compileall -q . >/dev/null || status=1
fi

exit "$status"
