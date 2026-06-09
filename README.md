 Morrowind LLM Mod

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

### 2. Server & Client
Clone and run the [server/client repo](https://github.com/waterbobo24/Morrowind-llm-server-client):

```bash
git clone https://github.com/waterbobo24/Morrowind-llm-server-client.git
cd Morrowind-llm-server-client

You need two configuration files and two running processes:

Server configuration:

cp example/server-config.example.yaml .tmp/server-config.yaml
# Edit .tmp/server-config.yaml and add your LLM API key (OpenAI, Anthropic, or Gemini).
# Optional: add ElevenLabs key for cloud voice, enable Pocket TTS for offline voice.
# Optional: add Deepgram key for speech-to-text.

Client configuration:

cp example/client-config.example.yaml .tmp/client-config.yaml
# Edit .tmp/client-config.yaml (set server URL, input mode, push-to-talk key, etc.)

    Note: .tmp/ is gitignored so your API keys and local settings never leave your machine.

3. Run both processes

Terminal 1 — Start the Server:

dotnet run --project src/ZdoRpgAi.Server

Terminal 2 — Start the Client:

dotnet run --project src/ZdoRpgAi.Client.Console -- --config .tmp/client-config.yaml

    Tip — Run both in the background from one terminal:

    cd /path/to/Morrowind-llm-server-client
    nohup dotnet run --project src/ZdoRpgAi.Client.Console -- --config .tmp/client-config.yaml > /tmp/client.log 2>&1 &
    sleep 2

⚙️ Quick Start

    Start the Server (dotnet run --project src/ZdoRpgAi.Server).
    Start the Client (dotnet run --project src/ZdoRpgAi.Client.Console -- --config .tmp/client-config.yaml).
    Launch OpenMW with this mod enabled.
    Approach any NPC and talk (push-to-talk or text input via Zenity).



📸 Screenshot

In-game screenshot
📄 License

GNU General Public License v3.0
	
Original author	drzdo(opens in new tab)
Fork author	waterbobo24(opens in new tab)
"""	
with open("README.md", "w") as f:
