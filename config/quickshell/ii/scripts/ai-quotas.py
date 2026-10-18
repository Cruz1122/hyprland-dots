#!/usr/bin/env python3
"""Quota service entry point; GUI credentials travel only over private stdin."""
from ai_quotas.main import main

if __name__ == "__main__":
    raise SystemExit(main())
