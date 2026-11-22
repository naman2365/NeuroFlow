<div align="center">

# 🧠 NeuroFlow — Cognitive Interleaver & AI Subject Mentor

**A cross-platform cognitive workstation designed to replace passive, single-subject marathon grinding with dynamic subject interleaving, working-memory spill tracking, and AI-guided active recall.**

![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?logo=flutter&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-State%20Management-00BFA5)
![Hive](https://img.shields.io/badge/Hive-Local%20NoSQL-FBC02D?logo=hive&logoColor=black)
![Cloudflare Workers](https://img.shields.io/badge/Cloudflare%20Workers-Edge%20KV%20%26%20AI%20Proxy-F38020?logo=cloudflareworkers&logoColor=white)
![Groq](https://img.shields.io/badge/Groq-LPU%20Inference-E53935)
![Release](https://img.shields.io/badge/Release-v1.2.0%20Windows%20%7C%20v1.1.0%20Android-00BFA5)
[![NeuroFlow CI & Release Builder](https://github.com/naman2365/NeuroFlow/actions/workflows/build.yml/badge.svg)](https://github.com/naman2365/NeuroFlow/actions/workflows/build.yml)

</div>

---

## ⚡ Why NeuroFlow?

Traditional Pomodoro timers treat every hour of study as identical. **NeuroFlow** is engineered around cognitive science principles for high-intensity exam preparation (JEE, SAT, and competitive programming):

1. **Cognitive Interleaving:** Alternating across distinct subjects (e.g., *Physics → Mathematics → Chemistry → Python / AI*) in 45–90 minute blocks forces the brain to continuously reload mental models, strengthening long-term retention.
2. **Auto-Regulated Block Durations:** After every session, you log a **Cognitive Fatigue Score (1–5)** and track **Working Memory Spills** (distractions). NeuroFlow dynamically scales your next study block (`45m`, `75m`, or `90m`) and recovery break (`15m` or `25m` NSDR) based on real-time strain.
3. **5-Word Breadcrumbs:** Before taking a break, you leave a 5-word note on where to pick up next (e.g., *"Completed Q14, start integration by parts"*), eliminating the 15-minute "what was I doing?" startup friction when returning to that subject.

---

## ✨ Key Features

- 🤖 **Groq-Powered Subject Mentor & Study Planner:**
  - Context-aware AI tutor that adapts to your active subject chip, student profile, recent fatigue scores, and latest 5-word breadcrumbs.
  - **One-Click Smart Actions:** *Plan Next 3 Blocks*, *Quiz Me on Selected Subject*, and *Resume My Breadcrumb*.
  - **Clean Unicode Math Engine:** Automatically converts raw LaTeX expressions into clean, readable mathematical notation (`θ`, `π`, `Δ`, `√`, `½`, `x²`, `→`).
- 🛡️ **Strict Focus Shield & Smart Study Whitelist *(New in v1.2.0 — Windows)*:**
  - **Continuous 30-Second Grace Buffer:** Tracks active focus throughout your study block—including when pinned in the Mini-HUD so the shield cannot be bypassed. Leaving to a distraction for over 30s plays a Windows alert chime, logs `+1 Memory Spill`, and keeps ticking live in a red `SPILL • 30s` warning state.
  - **Native Win32 Window-Title Inspection (`dart:ffi`):** Reads active window titles via `user32.dll` with zero browser extensions. Automatically pauses the shield (`STUDY OK`) on study platforms (Physics Wallah, Khan Academy, NCERT, VS Code, GitHub, Notion, PDFs) and subject-relevant YouTube lectures while catching YouTube Shorts, gaming, and social media.
  - **Custom Keyword Whitelist:** Add your own allowed study platforms or apps in-app, persisted locally in Hive.
- 🪟 **Windows 11 Fluent Mini-HUD *(Upgraded in v1.2.0)*:**
  - Always-on-top compact companion featuring native Windows 11 rounded corners and Acrylic/Mica backdrop via `dwmapi.dll` FFI.
  - Includes a live shield badge (`STUDY OK` / `30s` / `SPILL • 30s`), edge-to-edge session progress bar, quick music controls, and subtle vertical motion-blur timer transitions.
- 🎵 **Audio Hub 2.0 & Native `libmpv` Engine *(v1.1.0 + v1.2.0)*:**
  - Powered by native **`media_kit` (`libmpv` FFI)** on Windows for rock-solid local audio playlists (`.mp3`, `.wav`, `.m4a`, `.flac`, `.ogg`, `.aac`), track scrubbing, 10s skip, loop-one/auto-next, and volume control.
  - Customizable one-tap external shortcuts for **Spotify** and **YouTube Music**.
- ☁️ **PIN-Protected Cloud Sync & Creator Inbox *(v1.1.0)*:**
  - Mirror study logs across Windows and Android using a unique Username + Secret PIN backed by Cloudflare Workers Edge KV.
  - Built-in **Help & Feedback** hub with direct cloud submission and a PIN-protected Creator Inbox.
- 📊 **Cognitive Analytics Dashboard:**
  - Real-time KPI cards (**Total Focus**, **Avg Strain**, **Total Spills**), **14-Day Consistency Heatmap**, **Subject Balance** breakdown, and a **7-Block Fatigue Trend** chart.

---

## 🚀 Release Highlights

### `v1.2.0` — Windows Desktop Edition *(Latest)*
> Distributed via **Inno Setup** (`NeuroFlow-Setup-v1.2.0.exe`). Android users should continue using **`v1.1.0`** ahead of the ground-up Android UI overhaul in **`v2.0.0`**.
- Added **Strict Focus Shield** with a 30s grace buffer, continuous Mini-HUD tracking, and native `user32.dll` study-site & YouTube lecture whitelisting.
- Redesigned the **Mini-HUD** with native Windows 11 DWM rounded corners, Fluent controls, edge progress bar, and subtle motion-blur timer transitions.
- Migrated Windows audio playback to native **`media_kit` (`libmpv`)** for reliable local playlists and seeking.
- Fixed the `flutter_windows.dll` accessibility crash via `ExcludeSemantics` and resolved Riverpod initialization assertions.

### `v1.1.0` — Audio Hub 2.0, Groq Mentor & Android Release
- Launched **Audio Hub 2.0** with local playlist queueing, transport controls, and Spotify/YT Music shortcuts.
- Added **Groq AI Subject Mentor** with Unicode math formatting and breadcrumb-aware study planning.
- Introduced **PIN-Protected Cloudflare Cloud Sync**, in-app feedback submission, and the **Android APK** build.

---

## 📦 Download & Installation

- **Windows (`v1.2.0`):** Download and run **`NeuroFlow-Setup-v1.2.0.exe`** from the [Releases](https://github.com/naman2365/NeuroFlow/releases) page.
- **Android (`v1.1.0`):** Download the **`v1.1.0`** `.apk` from [Releases](https://github.com/naman2365/NeuroFlow/releases) and connect using your Cloud Sync Username + PIN.

---

## 🛠️ Build from Source

```bash
git clone [https://github.com/naman2365/NeuroFlow.git](https://github.com/naman2365/NeuroFlow.git)
cd NeuroFlow
flutter pub get

# Run on Windows
flutter run -d windows

# Build Windows Release (for Inno Setup)
flutter build windows --release
```

---

## 🗺️ Roadmap (`v2.0.0`)

- **Windows & Android UI Overhaul:** Ground-up visual redesign across both desktop and mobile for a cleaner, more cohesive workstation experience.
- **Android Native Focus Shield:** Background app and study-content detection via `UsageStatsManager` and `AccessibilityService`.
- **macOS & Linux Desktop Support:** Native builds expanding NeuroFlow to macOS and Linux alongside Windows.
