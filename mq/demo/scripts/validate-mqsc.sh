#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# MQSC Policy & Syntax Validator (runs in CI on PRs — no MQ binaries required)
# =============================================================================

MQSC_FILE="${1:-mq/demo/myqmgr.mqsc}"

if [[ ! -f "$MQSC_FILE" ]]; then
  echo "ERROR: MQSC file not found: $MQSC_FILE" >&2
  exit 1
fi

if [[ ! -s "$MQSC_FILE" ]]; then
  echo "ERROR: MQSC file is empty: $MQSC_FILE" >&2
  exit 1
fi

echo "Validating MQSC file: $MQSC_FILE"

python3 - "$MQSC_FILE" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
raw_lines = path.read_text(encoding="utf-8").splitlines()

errors = []
warnings = []
statements = []

# Join MQSC continuation lines (+ or -) and strip comments (* in column 1)
buf = []
start_line = None
allow_destructive = False

for idx, line in enumerate(raw_lines, start=1):
    stripped = line.strip()
    if not stripped:
        continue
    if line.startswith("*"):
        if "ALLOW-DESTRUCTIVE" in line.upper():
            allow_destructive = True
        continue

    if start_line is None:
        start_line = idx

    if stripped.endswith("+"):
        buf.append(stripped[:-1].rstrip())
    elif stripped.endswith("-"):
        buf.append(stripped[:-1])
    else:
        buf.append(stripped)
        statements.append((start_line, " ".join(buf), allow_destructive))
        buf = []
        start_line = None
        allow_destructive = False

if buf:
    errors.append(f"Line {start_line}: Unterminated MQSC continuation ('+' or '-') at end of file.")

if not statements:
    errors.append("No MQSC statements found in file.")

VALID_VERBS = {
    "DEFINE", "DEF",
    "ALTER", "ALT",
    "SET",
    "REFRESH",
    "START",
    "STOP",
    "DISPLAY", "DIS",
    "DELETE", "DEL",
    "CLEAR",
    "END",
}

for line_no, stmt, destructive_ok in statements:
    upper = stmt.upper()
    verb = upper.split()[0]

    # 1. Valid MQSC verb
    if verb not in VALID_VERBS:
        errors.append(f"Line {line_no}: Unknown or unsupported MQSC verb '{verb}': {stmt}")
        continue

    # 2. Balanced parentheses and single quotes
    if stmt.count("(") != stmt.count(")"):
        errors.append(f"Line {line_no}: Unbalanced parentheses in statement: {stmt}")
    if stmt.count("'") % 2 != 0:
        errors.append(f"Line {line_no}: Unbalanced single quotes in statement: {stmt}")

    # 3. Security guardrails
    if re.search(r"\bCHLAUTH\s*\(\s*DISABLED\s*\)", upper):
        errors.append(f"Line {line_no}: Security policy violation — disabling CHLAUTH is prohibited.")
    if re.search(r"\bCONNAUTH\s*\(\s*'?\s*'?\s*\)", upper):
        errors.append(f"Line {line_no}: Security policy violation — clearing CONNAUTH is prohibited.")

    # 4. Destructive statement guardrail
    if verb in {"DELETE", "DEL", "CLEAR"} and not destructive_ok:
        errors.append(
            f"Line {line_no}: Destructive command '{verb}' blocked in declarative MQSC "
            f"(add '* ALLOW-DESTRUCTIVE' comment above statement if intentional)."
        )

    # 5. Idempotency guardrail: DEFINE must include REPLACE
    if verb in {"DEFINE", "DEF"}:
        if not re.search(r"\bREPLACE\b", upper):
            errors.append(
                f"Line {line_no}: DEFINE statement must include REPLACE for idempotent GitOps runs: {stmt}"
            )

    # 6. Native HA durability guardrail: QLOCAL queues must set DEFPSIST(YES)
    if re.match(r"^(DEFINE|DEF)\s+QLOCAL\b", upper):
        if not re.search(r"\bDEFPSIST\s*\(\s*YES\s*\)", upper):
            errors.append(
                f"Line {line_no}: Native HA policy requires DEFPSIST(YES) on QLOCAL queues "
                f"so messages are replicated across failover: {stmt}"
            )

print(f"Checked {len(statements)} MQSC statement(s).")
for w in warnings:
    print(f"WARNING: {w}")

if errors:
    print("\nValidation FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print("Validation PASSED: All syntax, idempotency, durability, and security checks succeeded.")
PY
