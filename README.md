🛠 WinRepair-Toolkit v4.7
Diagnostic-first Windows repair engine with a fixed-coordinate TUI dashboard, live progress bars, and auto-resume across reboots. Three files. Run as Admin. Pick what to fix. Walk away.



📁 What's in This Repo
WinRepair-Toolkit/
    ├── WindowsRepair.ps1   The PowerShell repair engine (v4.7)
    ├── run.bat              One-click Admin launcher
    ├── Launch.html          Standalone preview demo for browser
    ├── README.md            This file
    ├── LICENSE              MIT
    └── .gitignore           Standard Windows / IDE ignores
    
Three files. No dashboard, no Node.js, no Python. Pure native Windows automation.



🆕 What's New in v4.7
Live visual progress bar — DISM and SFC scans now show a Unicode block-char progress bar with percentage in the status bar, color-coded by progress (yellow < 50%, cyan 50-89%, green 90%+)
Carriage-return parsing — DISM writes its percentages without newlines using \r, so v4.7 reads the buffer mid-stream to capture 14.3%, 62.3%, etc. in real time
Patience messages with elapsed time — every 2 minutes during long scans, with a special callout for the DISM 62.3% pause
Removed the abort key — was unreliable, caused process zombies. Engineers can use Task Manager if a scan needs to be killed
Phase 2 stays manual — diagnostic only does instant API/WMI checks, no auto-execution of DISM/SFC
🎯 The 3-Phase Workflow
Phase 1 → Pre-flight safeguard checks   (~10 seconds)
    Phase 2 → Diagnostic scan (instant)     (~5 seconds)
    Phase 3 → Engineer Action Menu (interactive loop)
    
The engineer is dropped into the menu and stays there until they choose [E] Exit. After every tool runs, the post-action menu appears — [M] Main Menu, [R] Reboot, [E] Record & Exit.




🎮 Action Menu Options
Key	Action
F	Full repair — All 12 tools in recommended order
Q	Quick repair — Only fix detected issues from Phase 2
D	Drivers only — Auto-launches Lenovo Vantage / System Update
A	Advanced mode — Pick individual tools by ID
R	Generate report — Export findings to file, no repairs
N	No action — Exit cleanly
🧰 The 12-Tool Catalog
ID	Tool	Reboot	Est. Time
01	Disk Cleanup	No	2-5 min
02	DISM CheckHealth	No	1 min
03	DISM ScanHealth	No	5-15 min
04	DISM RestoreHealth	No	10-30 min
05	SFC /verifyonly	No	5-10 min
06	SFC /scannow	Yes	10-20 min
07	DISM ComponentCleanup	No	3-10 min
08	CHKDSK /f /r /x	Yes	varies
09	TCP/IP Reset	Yes	1 min
10	Winsock Reset	Yes	1 min
11	Flush DNS Cache	No	<1 min
12	Perfmon Health Report	No	2 min
🚀 Running on a Client Machine
Prerequisites
Windows 10 or Windows 11
Administrator rights (script auto-requests via UAC)
Internet recommended (for DISM RestoreHealth + Lenovo driver lookup)
Steps
Transfer all 3 files to the client's machine via your remote tool (AnyDesk, TeamViewer, RDP)
Keep all files in the same folder
Double-click run.bat — UAC prompt will appear, click Yes
Watch Phase 1 and Phase 2 complete
Pick an action from the menu
Logs save automatically to C:\RepairLogs\
The PowerShell terminal that opens is the live view — you'll watch the entire process through your remote session in real-time.



🔄 Auto-Resume Across Reboots
When a tool needs a reboot (CHKDSK, SFC /scannow, network resets), the script:




Saves remaining queue to C:\RepairLogs\resume-state.json
Registers a Windows Scheduled Task (WinRepair-AutoResume) that runs on next login
Reboots automatically (or asks first based on your preference)
Picks up exactly where it left off after restart
Self-cleans the Scheduled Task when finished
🧱 No AI / No API Keys / No Vendor Dependencies
This is 100% deterministic automation — no AI, no machine learning, no language models. The only external calls are:



Lenovo PC Support API (pcsupport.lenovo.com) — public driver lookup, no key required
Microsoft Windows Update servers — same servers Windows Update uses natively
Windows Scheduled Tasks — IT-auditable, self-cleanup
Why corporate IT will approve this:

✅ No compliance review for AI usage
✅ No API keys or secrets to rotate
✅ Scheduled Task is visible and auditable
✅ Group Policy pre-checks fail-safe before any changes
✅ Full session logging to C:\RepairLogs\
📦 Version History
v4.7 — Live Progress Bar + Improved Reliability
Visual progress bar with Unicode block characters (████░░░░) in status bar
Mid-buffer carriage-return parsing for live DISM/SFC percentages
Removed unreliable abort key
Bumped patience message to call out DISM 62.3% pause
v4.6 — Real-Time Percentage Tracking
Character-by-character stdout reader for DISM/SFC progress
HTTP WebRequest internet check (replaced ICMP for corporate WiFi)
PowerShell 5.1 .Contains() compatibility fix
Smart-quote and em-dash sanitization
v4.0 — Fixed-Coordinate TUI Dashboard
Single-screen dashboard layout (no scrolling)
Tool grid with [OK]/[FAIL]/[RUN]/[SKIP] status cells
Failed-tool re-run selection list
ReCheck option after run
Interactive Phase 3 loop with M/R/E post-action menu
v3.5 — Advanced Mode + Auto-Resume
Engineer-controlled tool selection from 14-tool catalog
Auto-resume across reboots via Scheduled Task
Configurable auto-reboot preference
v3.0 — Diagnostic-First Refactor
3-phase workflow with engineer decision tree
Lenovo Vantage launcher
Removed React + FastAPI dashboard
v2.0 — Corporate-Friendly
Group Policy pre-checks
Lenovo driver version comparison
Patience messages every 2 minutes
v1.0 — Initial Release
Basic SFC and DISM support
👤 Author
Cody (Jefferz58) — IT Support Technician Built for Lenovo remote support workflows.

GitHub

📜 License
MIT License — free to use, modify, and distribute.
