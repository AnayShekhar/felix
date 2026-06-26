# Deploying Felix to Railway

1. Push repo to GitHub
2. Go to railway.app, sign up free
3. New Project → Deploy from GitHub
4. Select felix repo
5. Set root directory to: backend
6. Add environment variables:
   GROQ_API_KEY = your key
   GROQ_MODEL = meta-llama/llama-4-scout-17b-16e-instruct
7. Copy the generated Railway URL
8. Replace RAILWAY_URL_HERE in:
   - ios/FelixApp/FelixApp/ContentView.swift
   - macos-app/Felix/Felix/AppEnvironment.swift
9. Rebuild iOS app and install on phone
10. Rebuild Mac app and run on Mac
11. Never use ngrok again

To verify: curl https://your-url/health
Should return: {"status":"ok"}
