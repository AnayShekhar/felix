# Felix Mac

Menu bar app — install once, then just use it like any other Mac app.

## One-time install

From the repo root:

```bash
chmod +x mac/install.sh
./mac/install.sh
```

This builds Felix, installs it to **/Applications/Felix.app**, saves your repo path, and opens it.

After that you never need Xcode for the Mac side.

## Daily use

1. **Felix runs automatically** when you log in (toggle in the menu bar menu)
2. Or double-click **Felix** in Applications / Spotlight
3. Green dot in menu bar = backend running, phone can connect
4. Run the **iPhone app** from Xcode on your device (same WiFi)

No terminals. No ngrok.

## Menu bar

- **Open Dashboard** — live view in browser
- **Start at Login** — keep Felix running in the background
- **Restart Felix** — if something gets stuck
- **Quit Felix** — stop backend + dashboard

## First-time setup (once per machine)

```bash
cd backend && python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
cd ../web && npm install
```

Mac and iPhone must be on the **same WiFi**.
