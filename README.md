<div align="center">

# 🧠 NeuroFlow — Cognitive Interleaver & AI Subject Mentor

**A cross-platform cognitive workstation designed to replace passive, single-subject marathon grinding with dynamic subject interleaving, working-memory spill tracking, and AI-guided active recall.**

[![Flutter](https://img.shields.io/badge/Flutter-Cross--Platform-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![State Management](https://img.shields.io/badge/Riverpod-State_Management-00B4AB?logo=dart&logoColor=white)](https://riverpod.dev)
[![Local Storage](https://img.shields.io/badge/Hive-Local_NoSQL-FFCA28?logo=firebase&logoColor=black)](https://docs.hivedb.dev/)
[![Cloud Backend](https://img.shields.io/badge/Cloudflare_Workers-Edge_KV_&_AI_Proxy-F38020?logo=cloudflare&logoColor=white)](https://workers.cloudflare.com/)
[![AI Engine](https://img.shields.io/badge/Groq-LPU_Inference-F55036)](https://groq.com/)
[![CI Build](https://github.com/naman2365/NeuroFlow/actions/workflows/build.yml/badge.svg)](https://github.com/naman2365/NeuroFlow/actions/workflows/build.yml)
</div>

---

## ⚡ Why NeuroFlow?

Traditional Pomodoro timers treat every hour of study as identical. **NeuroFlow** is engineered around cognitive science principles for high-intensity exam preparation (JEE, SAT, and competitive programming):

1. **Cognitive Interleaving:** Alternating across distinct subjects (e.g., *Physics → Mathematics → Chemistry → Python / AI*) in 45–90 minute blocks forces the brain to continuously reload mental models, strengthening long-term retention.
2. **Auto-Regulated Block Durations:** After every session, you log a **Cognitive Fatigue Score (1–5)** and track **Working Memory Spills** (distractions). NeuroFlow dynamically scales your next study block (`45m`, `75m`, or `90m`) and recovery break (`15m` or `25m` NSDR) based on real-time strain.
3. **5-Word Breadcrumbs:** Before taking a break, you leave a 5-word note on where to pick up next (e.g., *"Completed Q14, start integration by parts"*), eliminating the 15-minute "what was I doing?" startup friction when returning to that subject.

---

## ✨ Key Features

* 🤖 **Groq-Powered Subject Mentor & Study Planner:**
  * Context-aware AI tutor that adapts to your active subject chip, student profile, recent fatigue scores, and latest 5-word breadcrumbs.
  * **One-Click Smart Actions:** *Plan Next 3 Blocks*, *Quiz Me on Selected Subject*, and *Resume My Breadcrumb*.
  * **Clean Unicode Math Engine:** Automatically converts raw LaTeX expressions into clean, readable mathematical notation (`½ mv² = mgR(1 − cos θ)`).
* 🔒 **First-Claim PIN-Protected Cloud Sync:**
  * Built on **Cloudflare Workers + KV Storage** for instant, zero-config cross-device sync between Windows PC and Android.
  * Users claim any username/Sync ID with a secret PIN on first sync; subsequent requests verify the PIN at the edge so logs stay private and isolated.
* 📌 **Always-On-Top Desktop Mini HUD:**
  * Collapses the full 1180×840 workstation into a frameless, pinned `330×195` floating HUD so you can keep your timer, memory-spill counter, and focus audio controls visible over PDFs, lecture videos, or IDEs.
* 🎧 **3-in-1 Focus Audio Hub:**
  * **Built-in Streamer:** Instant playback for *Lofi Focus Beats*, *Deep Ambient Drone*, *Synthwave Coding*, and *Classical Study*.
  * **Local Audio Loop:** Pick and loop any offline `.mp3`, `.wav`, or `.flac` track from your device.
  * **External Shortcuts:** Customizable 1-click launchers for your favorite Spotify and YouTube Music playlists.
* 📊 **Real-Time Cognitive Analytics:**
  * **14-Day Consistency Heatmap** tracking daily focus intensity.
  * **Subject Balance Distribution** bars to prevent neglecting weaker subjects.
  * **7-Block Fatigue Trend Bar Chart** powered by `fl_chart`.
* 💬 **Built-In Guide & Creator Feedback Inbox:**
  * Users can send bug reports and feature ideas straight to the cloud KV inbox, protected by a server-side Creator PIN.

---

## 🏗️ Tech Stack & Architecture

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Frontend UI** | Flutter (Material 3 Dark) | Responsive split-pane desktop workstation & mobile layout |
| **State Management** | `flutter_riverpod` | Reactive timer state, auto-regulated duration providers, and AI chat state |
| **Local Persistence** | `hive_flutter` | Offline-first NoSQL storage for study logs, custom subjects, and settings |
| **Edge Backend** | Cloudflare Workers | Serverless API proxy keeping `GROQ_API_KEY` and `CREATOR_PIN` 100% off-client |
| **Cloud Database** | Cloudflare KV (`SYNC_KV`) | Low-latency key-value storage for PIN-locked user logs and feedback inbox |
| **Desktop Windowing** | `window_manager` | Custom title bar, drag regions, and Always-On-Top Mini HUD mode |

---

## 🚀 Getting Started (Run from Source)

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x or higher)
* Visual Studio 2022 with *"Desktop development with C++"* (for Windows builds) or Android Studio (for Android APK builds)

### Installation

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/naman2365/NeuroFlow.git](https://github.com/naman2365/NeuroFlow.git)
   cd NeuroFlow