#!/usr/bin/env python3
"""Official Claude Code statusline input; only sanitized quota windows are retained."""
from ai_quotas.claude_statusline import capture

if __name__ == "__main__":
    raise SystemExit(capture())
