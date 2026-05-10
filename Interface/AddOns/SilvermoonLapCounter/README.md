Silvermoon Lap Counter
======================

A World of Warcraft addon that tracks your laps around the Sanctum of Light in Silvermoon City (Midnight).

Race through four checkpoints, beat your best time, and compare your results across all your characters.

## How It Works

The route passes through four checkpoint zones arranged around the Sanctum of Light in Silvermoon City:

```
┌───────────────────────────────────┐
│                                   │
│            North ●                │
│              ╱      ╲             │
│            ╱          ╲           │
│          ╱  Sanctum of  ╲         │
│  West ●       Light       ● East  │
│          ╲              ╱         │
│            ╲          ╱           │
│              ╲      ╱             │
│            South ●                │
│                                   │
└───────────────────────────────────┘
```

Ride through all four checkpoints in any order to complete a lap. The timer starts when you hit the first checkpoint. Checkpoints light up green in the tracker as you pass through them.

## Features

- **Automatic tracking** — the UI appears when you enter Silvermoon and hides when you leave
- **Lap timer** — tracks your last and best lap time per character
- **Checkpoint indicators** — N / E / S / W dots show your progress through the current lap
- **Leaderboard** — click the button to compare laps and best times across all your characters, displayed in class colors
- **Sounds** — different sounds for checkpoints, lap completion, and new best times (toggle with `/slc sound`)
- **Movable frame** — drag the tracker anywhere on screen, position is saved
- **Guild announce** — optionally post new best times and lap milestones (100, 1k, 10k, 100k) to guild chat (off by default, toggle with `/slc guild`)
- **Quiet by default** — only new best times are shown in chat

## Slash Commands

| Command | Description |
|---------|-------------|
| `/slc` | Show available commands |
| `/slc show` | Show the tracker (works anywhere) |
| `/slc hide` | Hide the tracker (works anywhere) |
| `/slc reset` | Reset laps and times for the current character |
| `/slc status` | Print status and all character stats to chat |
| `/slc guild` | Toggle guild announce for new best times on/off |
| `/slc sound` | Toggle sounds on/off |
| `/slc chat` | Chat: best times only (default) |
| `/slc chat all` | Chat: checkpoints + all lap times |
| `/slc chat off` | Chat: no output at all |

## Installation

1. Download or clone this repository
2. Copy the `SilvermoonLapCounter` folder into your WoW AddOns directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Restart WoW or type `/reload`

## Requirements

- World of Warcraft: The War Within / Midnight (Retail)
- Interface version: 12.0.1+
