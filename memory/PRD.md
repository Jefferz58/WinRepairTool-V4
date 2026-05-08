# WinRepair-Toolkit — Static Landing Page

## Problem Statement
Rebuild the WinRepair-Toolkit hosting site as a pure static landing page. No backend, no React, no Node, no Python, no API, no DB, no AI. Just one self-contained `index.html` that:
1. Renders the README as styled documentation (dark theme, #0a0a0f bg, #22d3ee cyan, monospace).
2. Provides 3 download buttons (relative paths) for the toolkit files.
3. Embeds `Launch.html` as a live iframe preview.

The 3 toolkit files (`WindowsRepair.ps1`, `run.bat`, `Launch.html`) must be byte-for-byte identical to the source ZIP.

## Architecture
Pure static. Engineer drops 4 files (`index.html` + the 3 toolkit files) in a single folder, opens `index.html` in a browser, done. No server. Relative-path downloads via `<a download>`.

## Final Deliverable — `/app/dist/`
```
/app/dist/
├── index.html          22 KB — self-contained dark-themed landing page
├── WindowsRepair.ps1   30 KB — byte-for-byte unchanged (md5 8be010ae766991e01979ffb47caffc02)
├── run.bat              1 KB — byte-for-byte unchanged (md5 dd74810c7cc1f068016f020e42111880)
└── Launch.html         13 KB — byte-for-byte unchanged (md5 85fb21f3e7c3d0fc3f5a32606166bd11)
```

## What's Implemented (2026-05-08)
- Self-contained `index.html` with zero external script/CSS dependencies (only the GitHub badge img inherited from the README).
- README.md pre-rendered to HTML at build time (Python `markdown` lib) and inlined — no client-side markdown parser needed.
- Dark-theme styling: `#0a0a0f` bg, `#22d3ee` cyan accents, `#4ade80` green secondary, JetBrains Mono / Cascadia Code stack for code, Inter / system-ui for body.
- Top status bar (winrepair-toolkit · v4.7 · stable · Win 10/11 · MIT) and hero card with cyan tagchip + 3 download buttons, all carrying `data-testid` hooks.
- **SHA-256 hash under each download button** (full 64-char hash, monospace, muted `#6b7280`) plus a "Verify in PowerShell" code snippet showing the 3 `Get-FileHash` commands with green `PS>` prompts and cyan command text. Hashes verified to match actual file contents:
  - WindowsRepair.ps1 → `2093573a9bd2703b38c34d3d1e06c8a7f1be0b887c55e4574ee80f7670e571ba`
  - run.bat           → `e33e7758e82155695449b382630f2c0c63db365b24141695d7c57549101ae6d5`
  - Launch.html       → `82080e73d1de8bce2854cc50e7c75a9ae27d0b24bae9b0ef4779f459f82932b1`
- README rendered as documentation card: H2 in cyan (`#` prefix), H3 in green (`##` prefix), tables with cyan header row + hover rows, code blocks with cyan→green gradient left border, blockquote with cyan accent.
- Live preview section with macOS-style frame bar (3 lights, faux URL, "open in new tab" link) embedding `Launch.html` via lazy-loaded iframe.
- Mobile breakpoint at 720px (collapses topbar, scales hero, reduces padding).
- Verified end-to-end: all 3 download links serve correct MIME types (`application/octet-stream` for ps1, `application/x-msdownload` for bat, `text/html` for Launch.html), md5 hashes match source ZIP byte-for-byte.

## Preview Hosting Note
For dev preview only, the 4 files were also copied to `/app/frontend/public/` so they're served by the existing CRA dev server at the preview URL. The React entry point (`src/index.js`) was made a no-op so no bundle CSS/JS bleeds into the static page. **The preview is just a hosting convenience — the actual deliverable in `/app/dist/` has zero references to React, bundle.js, Tailwind, or any CDN.**

## Backlog / Next Items
- (Optional) If the user wants a one-click ZIP download, add a pre-built `WinRepair-Toolkit.zip` next to `index.html` and add a 4th button. Skipped per latest user instruction (pure static, 3 buttons only).
- (Optional) If user wants offline-first, replace the GitHub badge `<img src="https://img.shields.io/...">` in the rendered README with an inline SVG or remove it.

## Future / Enhancement Ideas
- Add a "Verify SHA-256" line under each download button so engineers can confirm the binary matches what corporate IT approved (helpful for compliance reviews of the toolkit).

## Personas
- **Lenovo IT support engineer** running remote sessions (AnyDesk / TeamViewer / RDP). Lands on the page, reads what v4.7 does, downloads the 3 files, transfers them to the client machine, double-clicks `run.bat`.
- **Corporate IT reviewer** auditing the toolkit before approving for fleet use. Reads the "No AI / No API Keys / No Vendor Dependencies" section, sees the 12-tool catalog, can preview the TUI flow via the embedded `Launch.html` without running anything.
