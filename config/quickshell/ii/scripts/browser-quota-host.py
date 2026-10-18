#!/usr/bin/python3
"""Native Messaging entry point; no network listener and no exported credentials."""
from ai_quotas.browser_link import native_main

if __name__ == "__main__":
    raise SystemExit(native_main())
