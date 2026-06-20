# 🛠 WinRepair-Toolkit

**A diagnostic-first Windows repair engine for remote IT support — fixed-coordinate TUI dashboard, live progress bars, and auto-resume across reboots.**

Three files. Run as Admin. Pick what to fix. Walk away.

![Version](https://img.shields.io/badge/version-4.7-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)
![Dependencies](https://img.shields.io/badge/dependencies-none-success)

---

## Table of Contents

- [What's New in v4.7](#-whats-new-in-v47)
- [Repo Contents](#-repo-contents)
- [The 3-Phase Workflow](#-the-3-phase-workflow)
- [Action Menu](#-action-menu)
- [The 12-Tool Catalog](#-the-12-tool-catalog)
- [Running on a Client Machine](#-running-on-a-client-machine)
- [Auto-Resume Across Reboots](#-auto-resume-across-reboots)
- [No AI / No API Keys / No Vendor Dependencies](#-no-ai--no-api-keys--no-vendor-dependencies)
- [Version History](#-version-history)
- [Author](#-author)
- [License](#-license)

---

## 🆕 What's New in v4.7

- **Live visual progress bar** — DISM and SFC scans show a Unicode block-character progress bar with live percentage, color-coded by completion (yellow `<50%`, cyan `50–89%`, green `90%+`)
- **Carriage-return parsing** — DISM writes its percentage updates with `\r` instead of newlines; v4.7 reads the buffer mid-stream to capture live values (`14.3%`, `62.3%`, etc.)
- **Patience messages with elapsed time** — surfaced every 2 minutes during long scans, with a dedicated callout for the well-known DISM 62.3% pause
- **Abort key removed** — the old kill-switch was unreliable and caused process zombies; use Task Manager if a scan needs to be terminated
- **Phase 2 stays manual** — diagnostics are limited to instant API/WMI checks; DISM/SFC never auto-execute

---

## 📁 Repo Contents

```
WinRepair-Toolkit/
├── WindowsRepair.ps1   # The PowerShell repair engine (v4.7)
├── run.bat             # One-click Admin launcher
├── Launch.html         # Standalone browser preview/demo
├── README.md           # This file
├── LICENSE             # MIT
└── .gitignore          # Standard Windows / IDE ignores
```

No dashboard, no Node.js, no Python. Pure native Windows automation.

---

## 🎯 The 3-Phase Workflow

| Phase | Description | Duration |
|---|---|---|
| **1** | Pre-flight safeguard checks | ~10 sec |
| **2** | Diagnostic scan | ~5 sec |
| **3** | Engineer Action Menu (interactive loop) | Until exit |

The engineer is dropped into the menu and stays there until choosing **[E] Exit**. After every tool runs, a post-action menu appears: **[M]** Main Menu, **[R]** Reboot, **[E]** Record & Exit.

---

## 🎮 Action Menu

| Key | Action | Description |
|---|---|---|
| `F` | Full repair | All 12 tools, run in recommended order |
| `Q` | Quick repair | Only the issues flagged in Phase 2 |
| `D` | Drivers only | Auto-launches Lenovo Vantage / System Update |
| `A` | Advanced mode | Pick individual tools by ID |
| `R` | Generate report | Exports findings to file — no repairs run |
| `N` | No action | Exit cleanly |

---

## 🧰 The 12-Tool Catalog

| ID | Tool | Reboot Required | Est. Time |
|---|---|---|---|
| 01 | Disk Cleanup | No | 2–5 min |
| 02 | DISM CheckHealth | No | 1 min |
| 03 | DISM ScanHealth | No | 5–15 min |
| 04 | DISM RestoreHealth | No | 10–30 min |
| 05 | SFC /verifyonly | No | 5–10 min |
| 06 | SFC /scannow | Yes | 10–20 min |
| 07 | DISM ComponentCleanup | No | 3–10 min |
| 08 | CHKDSK /f /r /x | Yes | Varies |
| 09 | TCP/IP Reset | Yes | 1 min |
| 10 | Winsock Reset | Yes | 1 min |
| 11 | Flush DNS Cache | No | <1 min |
| 12 | Perfmon Health Report | No | 2 min |

---

## 🚀 Running on a Client Machine

### Prerequisites

- Windows 10 or Windows 11
- Administrator rights (script auto-requests via UAC)
- Internet connection recommended (for DISM RestoreHealth + Lenovo driver lookup)

### Steps

1. Transfer all 3 files to the client machine via your remote tool (AnyDesk, TeamViewer, RDP)
2. Keep all files in the same folder
3. Double-click `run.bat` — accept the UAC prompt
4. Watch Phase 1 and Phase 2 complete automatically
5. Pick an action from the menu
6. Logs save automatically to `C:\RepairLogs\`

The PowerShell terminal that opens **is** the live view — you'll watch the entire process through your remote session in real time.

---

## 🔄 Auto-Resume Across Reboots

When a tool requires a reboot (CHKDSK, SFC /scannow, network resets), the script:

1. Saves the remaining queue to `C:\RepairLogs\resume-state.json`
2. Registers a Windows Scheduled Task (`WinRepair-AutoResume`) that runs on next login
3. Reboots automatically (or prompts first, based on your preference)
4. Picks up exactly where it left off after restart
5. Self-cleans the Scheduled Task when finished

---

## 🧱 No AI / No API Keys / No Vendor Dependencies

This is 100% deterministic automation — no AI, no machine learning, no language models. The only external calls are:

- **Lenovo PC Support API** (`pcsupport.lenovo.com`) — public driver lookup, no key required
- **Microsoft Windows Update servers** — the same servers Windows Update uses natively
- **Windows Scheduled Tasks** — IT-auditable, self-cleaning

**Why corporate IT will approve this:**

- ✅ No compliance review for AI usage
- ✅ No API keys or secrets to rotate
- ✅ Scheduled Task is visible and auditable
- ✅ Group Policy pre-checks fail-safe before any changes are made
- ✅ Full session logging to `C:\RepairLogs\`

---

## 📦 Version History

<details>
<summary><strong>v4.7 — Live Progress Bar + Improved Reliability</strong></summary>

- Visual progress bar with Unicode block characters (`████░░░░`) in the status bar
- Mid-buffer carriage-return parsing for live DISM/SFC percentages
- Removed the unreliable abort key
- Patience message now calls out the DISM 62.3% pause specifically

</details>

<details>
<summary><strong>v4.6 — Real-Time Percentage Tracking</strong></summary>

- Character-by-character stdout reader for DISM/SFC progress
- HTTP WebRequest internet check (replaced ICMP for corporate Wi-Fi)
- PowerShell 5.1 `.Contains()` compatibility fix
- Smart-quote and em-dash sanitization

</details>

<details>
<summary><strong>v4.0 — Fixed-Coordinate TUI Dashboard</strong></summary>

- Single-screen dashboard layout (no scrolling)
- Tool grid with `[OK]` / `[FAIL]` / `[RUN]` / `[SKIP]` status cells
- Failed-tool re-run selection list
- ReCheck option after run
- Interactive Phase 3 loop with M/R/E post-action menu

</details>

<details>
<summary><strong>v3.5 — Advanced Mode + Auto-Resume</strong></summary>

- Engineer-controlled tool selection from a 14-tool catalog
- Auto-resume across reboots via Scheduled Task
- Configurable auto-reboot preference

</details>

<details>
<summary><strong>v3.0 — Diagnostic-First Refactor</strong></summary>

- 3-phase workflow with engineer decision tree
- Lenovo Vantage launcher
- Removed the React + FastAPI dashboard

</details>

<details>
<summary><strong>v2.0 — Corporate-Friendly</strong></summary>

- Group Policy pre-checks
- Lenovo driver version comparison
- Patience messages every 2 minutes

</details>

<details>
<summary><strong>v1.0 — Initial Release</strong></summary>

- Basic SFC and DISM support

</details>

---

## 👤 Author

**Cody** ([@Jefferz58](https://github.com/Jefferz58)) — Technical Support Engineer 

Built for Lenovo remote support workflows.

## 📜 License

[MIT License](LICENSE) — free to use, modify, and distribute.