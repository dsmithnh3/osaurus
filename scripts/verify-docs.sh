#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared by CI (.github/workflows/docs-integrity.yml) and lefthook pre-push.
# Pin Node markdown-link-check major via npx; config: .markdown-link-check.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="$ROOT/.markdown-link-check.json"
MARKDOWN_LINK_CHECK_VERSION="${MARKDOWN_LINK_CHECK_VERSION:-3.14.2}"

run_mlc() {
  npx --yes "markdown-link-check@${MARKDOWN_LINK_CHECK_VERSION}" -q -c "$CONFIG" "$1"
}

echo "verify-docs: checking Markdown links under docs/ ..." >&2
# Omit superpowers plans/specs: tables use ../*.md hints for humans; markdown-link-check
# resolves them like HTTP and returns 400 (see docs/superpowers/specs/2026-04-11-doc-integrity-automation-design.md).
while IFS= read -r -d '' f; do
  run_mlc "$f"
done < <(
  find docs \
    -type f -name '*.md' \
    ! -path 'docs/superpowers/plans/*' \
    ! -path 'docs/superpowers/specs/*' \
    -print0
)

if [[ -f AGENTS.md ]]; then
  echo "verify-docs: checking AGENTS.md ..." >&2
  run_mlc AGENTS.md
fi

echo "verify-docs: checking cited paths (DEVELOPER_MAP, agent-stubs) ..." >&2
python3 "$ROOT/scripts/verify-doc-paths.py"

echo "verify-docs: OK" >&2
