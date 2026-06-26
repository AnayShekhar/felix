The backend is deployed on Railway (Linux) which 
cannot run osascript, pmset, or any macOS commands.
We need to split the architecture:

1. Railway backend handles:
   - Receiving input from iOS
   - LLM planning via Groq
   - WebSocket broadcasting
   - Memory and history storage

2. A new local Mac agent handles:
   - Receiving tool execution instructions 
     from Railway via WebSocket
   - Running all osascript/shell tools locally
   - Sending results back to Railway
   - Railway then broadcasts results to iOS

Create backend/mac_agent.py:
- Connects to Railway backend via WebSocket
  as a special "mac" client
- Listens for a new event type "execute_on_mac"
  containing { action_id, tool, args }
- Executes the tool locally using the existing
  tools.py functions
- Sends result back to Railway via WebSocket
  as "mac_result" event with { action_id, result }

Update backend/engine.py:
- Instead of executing tools directly, broadcast
  "execute_on_mac" event and wait up to 30 seconds
  for a "mac_result" event back
- If no Mac agent is connected, return a helpful
  error: "Mac agent not connected. Run mac_agent.py
  on your Mac."

Update backend/routes.py:
- Add GET /mac/status endpoint returning whether
  a Mac agent is currently connected

Update Mac dashboard (macos-app):
- On launch, automatically start mac_agent.py
  as a subprocess or bundle the agent logic
  directly into the Mac app
- Show connection status in the menu bar popover:
  "Mac Agent: Connected" or "Mac Agent: Offline"

Create a simple launch script run_mac_agent.sh:
  #!/bin/bash
  cd "$(dirname "$0")/backend"
  ./venv/bin/python mac_agent.py

This means:
- Railway = brain (cloud, always on)
- mac_agent.py = hands (local, runs on Mac)
- iOS app = eyes and ears (mobile input)