# Zdo RPG AI

**Voice- and text-driven AI NPCs for OpenMW.**  
This mod connects Morrowind to a local LLM server, giving every NPC persistent memory, dynamic personality, and contextual awareness.

> **Fork Notice:** This is a community fork of [drzdo's zdo-rpg-ai-openmw-mod](https://github.com/drzdo/zdo-rpg-ai-openmw-mod), with additional features for deeper immersion.  
> Original work © [drzdo](https://github.com/drzdo) (GPLv3).

---

## ⚠️ Work in Progress — Experimental

**This fork is under active development and is not yet stable.**  
The enhancements listed below are **experimental** and **subject to change or removal** without notice. Expect bugs, breaking changes, and force-pushes to `main`. Use at your own risk, and please report issues if you try it out.

---

## 🤖 AI Disclosure

**Portions of this fork — including code, documentation, and design decisions — were created or significantly modified with assistance from large language models (e.g., Claude, ChatGPT).**  
All generated content has been reviewed, tested, and curated by a human maintainer, but errors or oversights may remain. The original upstream project was human-authored by drzdo.

---

## ✨ Features

### Core (Original)
- Natural language conversations with any NPC via LLM (OpenAI, Anthropic, Google Gemini)
- Persistent NPC memory across sessions (powered by ChromaDB vector database)
- Voice output via **ElevenLabs**
- Speech-to-text via **Deepgram** (optional)

### Enhancements (This Fork — Experimental)

| Feature | Description |
|---|---|
| **Player Persona Injection** | NPCs know your backstory, stats, reputation, and current location |
| **Game-Time Awareness** | NPCs reference the in-universe Tamrielic date and time via `openmw_aux.calendar` |
| **Equipment Tracking** | NPCs recognize what you and others are wearing or wielding |
| **Equip Responses** | NPCs react when you change gear in front of them |
| **Item Transactions** | Trade, buy, sell, and gift items through natural dialogue (`transfer_item` action) |
| **Periodic NPC Refresh** | Background context updates prevent NPCs from going stale |
| **Save Stability** | Fixes for context persistence across save/load cycles |
| **Local TTS Support** | Speech can be generated offline via Pocket TTS |

---

## 💻 Platform Notes

| Platform | Status | Notes |
|---|---|---|
| **Linux** | ✅ Primary target | Developed and tested on Linux. Zenity text dialogs work out of the box. |
| **Windows** | ⚠️ Untested | Server (.NET) is cross-platform. Mod text input requires Zenity or script modifications. Voice-only mode should work. |
| **macOS** | ⚠️ Untested | Server (.NET) is cross-platform. Mod text input uses Zenity (not native); `osascript` or voice-only may be needed. |

> **Text Input:** This mod uses **Zenity** to display text entry dialogs *outside* the game window. An in-game text box is not currently implemented. If Zenity is unavailable, text input falls back to voice-only mode (if Deepgram is configured) or fails gracefully.

---

## 📋 Requirements

- **OpenMW** with Lua scripting enabled
- **Zenity** (Linux) — for text input dialogs. Usually pre-installed on GNOME/GTK desktops.
- **[Morrowind LLM Server Client](https://github.com/waterbobo24/Morrowind-llm-server-client)** — The .NET backend that proxies game events to your LLM API

---

## 🚀 Installation

### 1. Mod (this repo)
Install using an OpenMW mod manager (e.g., **Amethyst Mod Manager**) or extract manually to your `mods/` folder.

Key paths:
- `scripts/` — Core Lua logic
- `Sound/` — Cached voice lines
- `l10n/` — Localization strings
- `zdorpgai.omwscripts` — Main OpenMW script entrypoint

### 2. Server
Clone and run the [server](https://github.com/waterbobo24/Morrowind-llm-server-client):

```bash
git clone https://github.com/waterbobo24/Morrowind-llm-server-client.git
cd Morrowind-llm-server-client
# See server README for `dotnet run` instructions

The server requires API credentials:

    Copy the example config:

    cp example/server-config.example.yaml .tmp/server-config.yaml

    Edit .tmp/server-config.yaml and add your LLM API key (OpenAI, Anthropic, or Gemini).
    Optional: add ElevenLabs key for cloud NPC voice output, or enable Pocket TTS for offline voice.
    Optional: add Deepgram key for speech-to-text.

    Note: .tmp/server-config.yaml is gitignored so your keys never leave your machine.

⚙️ Quick Start

    Start the server (dotnet run in the server src/ZdoRpgAi.Server project).
    Launch OpenMW with this mod enabled.
    Approach any NPC and talk (push-to-talk or text input depending on your client config).

📸 Screenshot

In-game screenshot
📄 License

GNU General Public License v3.0
	
Original author	drzdo(opens in new tab)
Fork author	waterbobo24(opens in new tab)
"""	
with open("README.md", "w") as f:
