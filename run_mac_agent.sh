#!/bin/bash
# Launch the Lumis Mac agent — the local "hands" that run macOS tools the
# Railway backend can't. Uses the backend venv so tools.py imports resolve.
cd "$(dirname "$0")/backend"
exec ./venv/bin/python mac_agent.py
