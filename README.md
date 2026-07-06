# Tokengotchi 🐾

> A living AI agent companion that runs across your macOS menu bar — animated, gamified, and fully customisable.

## What it does

Your AI agent (Antigravity, OpenAI, Claude, Ollama) gets a **tiny pixel-art chibi pet** that lives in the menu bar. The pet reacts to everything your AI does:

| AI Event | Pet Animation |
|---|---|
| Idle | Slow walk, yawns, sits down |
| Thinking / typing | Paces, glows with an aura |
| Long task (>10s) | Runs fast, sweat drops |
| Task complete | Happy spin + confetti 🎉 |
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
  "base_color": "#8B5CF6",
  "eye_color": "#F59E0B",
  "personality": "mischievous",
  "accessories": ["antenna", "glasses"],
  "walk_speed": 1.8,
  "aura_color": "#06B6D4",
  "background_theme": "galaxy"
}
```

## Gamification

- **XP & Levels** — earn XP from every completed task (token count × streak multiplier)
- **Mood Meter** — pet mood rises with completions, falls with errors and inactivity
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
├── PetState (ObservableObject) — mood, XP, level, config
├── PetAnimationEngine (SKScene) — SpriteKit procedural chibi
├── GamificationCoordinator — XP, mood, tokens, streaks, achievements
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
