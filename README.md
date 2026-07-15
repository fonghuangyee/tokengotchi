# Tokengotchi 🐾

> A living AI agent companion that runs across your macOS menu bar — animated, gamified, and fully customisable.

## What it does

Your AI agent (Antigravity, OpenAI, Claude, Ollama) gets a **tiny pixel-art chibi pet** that lives in the menu bar. The pet reacts to everything your AI does:

| AI Event | Pet Animation |
|---|---|
| Idle | Slow walk, yawns, sits down |
| Thinking / typing | Paces, glows with an aura |
| Long task (>10s) | Runs fast, sweat drops |
| Task complete | Happy spin 🎉 |
| Error | Trips, shakes head 😱 |
| Reaches screen edge | Grabs edge, scrambles back |
| App wake | Stretches and waves |
| Context limit | Slows down, eyes droop 😴 |

## Getting Started

### 1. Build the macOS App

Open in Xcode:
```bash
open /Users/fong/Documents/FHY/tokengotchi/Package.swift
```
Then **Product → Run** (`⌘R`).

### 2. Start the AGY Bridge

```bash
cd bridge
pip install fastapi uvicorn httpx google-antigravity
uvicorn tokengotchi_bridge:app --port 7432
```

### 3. Hook into your AGY Agent

```python
from tokengotchi_bridge import TokengotchiHook
from antigravity import LocalAgent

agent = LocalAgent(
    model="gemini-2.0-flash",
    hooks=[TokengotchiHook()]
)
```

The pet will now animate in real-time as your agent works!

## Pet Customisation

1. Open the popover (click the menu bar icon)
2. Go to **🎨 Customise** tab
3. Copy the system prompt
4. Paste it into any AI agent and let it design your pet
5. Paste the returned JSON back into the app
6. Your new pet appears instantly ✨

### Example AI-generated config
```json
{
  "name": "Nebula",
  "palette": {
    "base": "#8B5CF6",
    "accent": "#F59E0B"
  },
  "icon": {
    "svgs": [
      {
        "id": "nebula_icon_base",
        "svg": "<svg viewBox='0 0 100 100'><g id='body'><circle cx='50' cy='50' r='40' fill='var(--base)'/></g></svg>"
      }
    ],
    "states": [
      {
        "id": "idle",
        "animations": [
          {
            "id": "nebula_icon_idle",
            "name": "Icon Idle",
            "description": "Subtle breathing",
            "duration": 1.0,
            "tracks": [
              {
                "targetId": "body",
                "keyframes": [
                  { "time": 0.0, "sy": 1.0 },
                  { "time": 0.5, "sy": 1.05 },
                  { "time": 1.0, "sy": 1.0 }
                ]
              }
            ]
          }
        ]
      }
    ]
  },
  "pet": {
    "svgs": [
      {
        "id": "nebula_pet_base",
        "svg": "<svg viewBox='0 0 100 100'><g id='body'><circle cx='50' cy='50' r='40' fill='var(--base)'/></g></svg>"
      }
    ],
    "states": [
      {
        "id": "idle",
        "animations": [
          {
            "id": "nebula_pet_idle",
            "name": "Pet Idle",
            "description": "Breathing with ear twitch",
            "duration": 1.5,
            "tracks": [
              {
                "targetId": "body",
                "keyframes": [
                  { "time": 0.0, "sy": 1.0 },
                  { "time": 0.75, "sy": 1.1 },
                  { "time": 1.5, "sy": 1.0 }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
}
```

## Gamification

- **XP & Levels** — earn XP from every completed task (token count × streak multiplier)
- **Token Bank** — earn 1 coin per 100 tokens → spend in the cosmetics shop
- **Daily Streaks** — 3 days: 1.25×, 7 days: 1.5×, 30 days: 2× XP
- **Achievements** — 11 badges: First Steps, Centurion, Token Millionaire, Night Owl, and more
- **Cosmetic Shop** — wizard hat, crown, glasses, scarf, cape, headphones, antenna, halo, sunglasses

## Architecture

```
TokengotchiApp (NSApplication)
├── AppDelegate — wires all singletons
├── MenuBarPetController
│   ├── NSStatusItem — click target + state icon
│   ├── NSWindow overlay — full-width transparent, pet walks here
│   └── NSPopover — dashboard on click
├── PetState (ObservableObject) — mode, config, animation assignments
├── PetAnimationEngine (SKScene) — SpriteKit procedural chibi
├── GamificationCoordinator — XP, tokens, streaks, achievements
├── ProviderManager — routes between LLM providers
│   ├── AntigravityProvider — polls localhost:7432
│   ├── OpenAIProvider (stub)
│   ├── AnthropicProvider (stub)
│   └── OllamaProvider (stub)
└── bridge/tokengotchi_bridge.py — FastAPI server + AGY hooks
```

## LLM Providers

| Provider | Status | Config |
|---|---|---|
| Antigravity (AGY) | ✅ Active | Bridge at `localhost:7432` |
| OpenAI | 🔧 Stub | API key in Settings |
| Anthropic Claude | 🔧 Stub | API key in Settings |
| Ollama | 🔧 Stub | `localhost:11434` |
