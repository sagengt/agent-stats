#!/bin/bash
# agentstats_statusline.sh
#
# AgentStats terminal status line script.
# Reads live usage data from the AgentStats app via UserDefaults shared storage
# and prints a compact, color-coded one-line summary suitable for tmux status-bar,
# iTerm2 badges, or any shell prompt.
#
# Usage:
#   agentstats_statusline.sh          # English output
#   agentstats_statusline.sh -ja      # Japanese output
#   agentstats_statusline.sh --no-color  # Plain text (no ANSI codes)
#
# Output format (English):
#   [Claude 42%] [Codex 87%!] [Z.ai 95%!!]
#
# Output format (Japanese):
#   [Claude 42%] [Codex 87%!] [Z.ai 95%!!]
#
# Color coding:
#   Green  (<70%): normal usage
#   Yellow (70-89%): warning threshold
#   Red    (90%+): danger threshold
#
# Requirements:
#   - AgentStats app must be running (or have run at least once)
#   - macOS 14+ with 'defaults' command available
#
# Note: The script reads from the AgentStats UserDefaults domain.
# Widget/export data is stored at key: agentstats.widgetExport
# Fallback: reads from agentstats.lastResults if widgetExport is absent.

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

BUNDLE_ID="com.agentstats.app"
DEFAULTS_KEY="agentstats.widgetExport"
FALLBACK_KEY="agentstats.lastResults"

# Parse arguments
LANGUAGE="en"
USE_COLOR=true

for arg in "$@"; do
    case "$arg" in
        -ja|--ja|--japanese) LANGUAGE="ja" ;;
        --no-color|-n)       USE_COLOR=false ;;
    esac
done

# ============================================================
# ANSI color helpers
# ============================================================

color_green="\033[0;32m"
color_yellow="\033[0;33m"
color_red="\033[0;31m"
color_reset="\033[0m"

color() {
    local code="$1"
    local text="$2"
    if $USE_COLOR; then
        printf "%b%s%b" "$code" "$text" "$color_reset"
    else
        printf "%s" "$text"
    fi
}

# ============================================================
# Read UserDefaults
# ============================================================

# Try to read the export blob from the app's defaults domain.
read_defaults() {
    local key="$1"
    defaults read "$BUNDLE_ID" "$key" 2>/dev/null || true
}

# ============================================================
# Parse JSON with plutil / python3 fallback
# ============================================================

# Extract a value from a plist/JSON blob using python3.
# Usage: json_value <json_string> <jq-style key path>
json_value() {
    local json="$1"
    local key="$2"
    python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    keys = sys.argv[2].split('.')
    val = data
    for k in keys:
        val = val[k]
    print(val)
except Exception:
    pass
" "$json" "$key" 2>/dev/null || true
}

# ============================================================
# Read usage data
# ============================================================

# AgentStats exports a JSON array under agentstats.widgetExport.
# Schema (best-effort — subject to app versioning):
# [
#   {
#     "service": "claude",
#     "label":   "Claude Code",
#     "windows": [
#       { "id": "5h", "label": "5 Hour", "usedPercentage": 0.42, "resetAt": "..." }
#     ]
#   },
#   ...
# ]
#
# If the key is absent (app never exported), we fall back to reading the
# raw agentstats.lastResults key, or print a placeholder.

RAW_DATA=$(read_defaults "$DEFAULTS_KEY")

if [[ -z "$RAW_DATA" ]]; then
    RAW_DATA=$(read_defaults "$FALLBACK_KEY")
fi

# ============================================================
# Format output
# ============================================================

format_pct() {
    local pct_float="$1"       # e.g. "0.42"
    local pct_int
    pct_int=$(python3 -c "print(int(float('$pct_float') * 100))" 2>/dev/null || echo "??")
    echo "$pct_int"
}

pct_color() {
    local pct_int="$1"
    if [[ "$pct_int" == "??" ]]; then
        echo ""
        return
    fi
    if (( pct_int >= 90 )); then
        echo "danger"
    elif (( pct_int >= 70 )); then
        echo "warning"
    else
        echo "ok"
    fi
}

suffix_for() {
    local level="$1"
    case "$level" in
        danger)  echo "!!" ;;
        warning) echo "!" ;;
        *)       echo "" ;;
    esac
}

build_output() {
    # If no data is available, show a brief placeholder.
    if [[ -z "$RAW_DATA" ]]; then
        if [[ "$LANGUAGE" == "ja" ]]; then
            color "$color_yellow" "[AgentStats: データなし]"
        else
            color "$color_yellow" "[AgentStats: no data]"
        fi
        echo
        return
    fi

    # Parse the JSON array with python3 and emit one token per service.
    python3 - "$RAW_DATA" "$LANGUAGE" "$USE_COLOR" <<'PYEOF'
import json, sys

raw     = sys.argv[1]
lang    = sys.argv[2]
color   = sys.argv[3] == "True"

ANSI = {
    "green":  "\033[0;32m",
    "yellow": "\033[0;33m",
    "red":    "\033[0;31m",
    "reset":  "\033[0m",
}

def colorize(text, level):
    if not color:
        return text
    c = {"ok": ANSI["green"], "warning": ANSI["yellow"], "danger": ANSI["red"]}.get(level, "")
    return f"{c}{text}{ANSI['reset']}"

def pct_level(pct):
    if pct >= 90: return "danger"
    if pct >= 70: return "warning"
    return "ok"

def suffix(level):
    return {"danger": "!!", "warning": "!"}.get(level, "")

try:
    entries = json.loads(raw)
except (json.JSONDecodeError, TypeError):
    msg = "データ解析エラー" if lang == "ja" else "parse error"
    print(f"[AgentStats: {msg}]")
    sys.exit(0)

parts = []
for entry in entries:
    service_label = entry.get("label") or entry.get("service", "?")
    windows = entry.get("windows", [])

    if not windows:
        # Token/activity type services — show if cost or count available.
        token = entry.get("tokenSummary") or {}
        cost = token.get("totalCostUSD")
        if cost is not None:
            cost_str = f"${cost:.2f}"
            parts.append(colorize(f"[{service_label} {cost_str}]", "ok"))
        continue

    # Show the highest-usage window for quota services.
    best = max(windows, key=lambda w: w.get("usedPercentage", 0))
    pct_float = best.get("usedPercentage", 0)
    pct_int   = int(pct_float * 100)
    level     = pct_level(pct_int)
    sfx       = suffix(level)
    tag       = f"[{service_label} {pct_int}%{sfx}]"
    parts.append(colorize(tag, level))

if parts:
    print(" ".join(parts))
else:
    msg = "サービスなし" if lang == "ja" else "no services"
    print(f"[AgentStats: {msg}]")
PYEOF
}

# ============================================================
# Entry point
# ============================================================

build_output
