# 🔒 Security Policy

## 📦 Supported Versions

Security updates and edge-backend patches are actively maintained for the latest release of **NeuroFlow**:

| Version | Supported          | Platforms |
| ------- | ------------------ | --------- |
| 1.0.x   | :white_check_mark: | Windows (x64), Android |
| < 1.0   | :x:                | N/A |

---

## 🛡️ Security Architecture Overview

**NeuroFlow** is engineered with an offline-first, zero-client-secret architecture to protect user study data and API credentials:

1. **Zero Hardcoded Client Secrets:** 
   * No AI provider keys (`GROQ_API_KEY`) or administrative credentials (`CREATOR_PIN`) are bundled inside the Flutter source code, Android `.apk`, or Windows `.exe` binaries.
   * All AI Mentor requests are routed through a serverless **Cloudflare Worker Edge Proxy** where secrets remain isolated in encrypted server-side environment bindings.
2. **Local-First Data Privacy (Hive NoSQL):**
   * By default, all study logs, fatigue scores, memory spills, and 5-word breadcrumbs are stored strictly locally on the user's device via `hive_flutter`.
3. **First-Claim PIN-Locked Cloud Sync:**
   * Cross-device synchronization via **Cloudflare KV** is strictly opt-in.
   * When a user claims a `Sync ID`, it is cryptographically bound to their chosen `Secret PIN` on the first sync. Subsequent read/write requests without the matching PIN are rejected at the Cloudflare edge (`HTTP 403 Forbidden`).
4. **Optional Custom API Keys:**
   * If a user chooses to supply a personal `gsk_...` Groq API key in the profile settings, it is stored solely inside their local device's `settings_box` and transmitted exclusively over `HTTPS` (`TLS 1.3`) to `api.groq.com`.

---

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability within the Flutter client, the PIN-sync verification logic, or the Cloudflare Worker proxy routes, **please do not open a public GitHub issue.**

Instead, please report it privately using one of the following channels:

1. **GitHub Private Vulnerability Reporting:** Navigate to the [**Security**](https://github.com/naman2365/NeuroFlow/security) tab of this repository and click **"Report a vulnerability"**.
2. **Direct Email:** Send a detailed report to **[mohantypratyush37@gmail.com](mailto:mohantypratyush37@gmail.com)** with the subject line `[SECURITY] NeuroFlow Vulnerability Report`.

### What to Include in Your Report:
* A clear description of the vulnerability and its potential impact.
* Step-by-step instructions or a proof-of-concept (PoC) to reproduce the issue.
* Affected platform(s) (`Windows`, `Android`, or `Cloudflare Worker Backend`).

### Response Timeline:
* **Acknowledgment:** Within **48 hours** of submission.
* **Triage & Fix Deployment:** Critical edge/worker fixes are typically patched and deployed within **24–72 hours** without requiring a client binary update.
