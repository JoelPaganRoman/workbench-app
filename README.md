<p align="right"><a href="README.es.md">🇪🇸 Español</a></p>

<p align="center">
  <img src="screenshots/logo.svg" alt="Workbench" width="480">
</p>

# Workbench

Workbench is a macOS desktop app that brings together **Google Docs, Sheets,
Slides, Gemini, and Drive** in a single tabbed window, instead of juggling
them as separate browser tabs.

## Screenshots

| Docs | Slides |
|---|---|
| ![Docs view](screenshots/docs-view.png) | ![Slides view](screenshots/slides-view.png) |

| Split view (Gemini + Docs) |
|---|
| ![Split view](screenshots/split-view.png) |

## What it does

- **5 apps in one window**: Docs, Sheets, Slides, Gemini, and Drive, each
  with its own tab (⌘1–⌘5 to jump between them).
- **Automatic routing**: open a file from Drive and the app detects whether
  it's a document, spreadsheet, or presentation, and opens it directly in
  the matching tab — you never leave the app.
- **Split screen**: two side-by-side panes, each with its own independent
  app selector ("Split" button or ⌘\\).
- Keeps your Google session between launches — no need to sign in every
  time.

## Installation

1. Go to the [**Releases**](../../releases) tab of this repository and
   download the latest `.zip` (`Workbench-mac.zip`).
2. Drag `Workbench.app` into your **Applications** folder.
3. The first time you open it, macOS will warn that it can't verify the
   developer. This is expected — follow these steps:
   - Try opening the app normally (double-click). You'll see the block
     warning.
   - Go to **System Settings → Privacy & Security**.
   - Scroll down to the Security section. You should see a message
     mentioning that "Workbench" was blocked, with an
     **Open Anyway** button.
   - Click it and confirm with your password or Touch ID.
   - Open the app once more and confirm with **Open** on the final dialog.
     From then on, the app opens normally without asking again.

### Why do I have to do this instead of just opening the app?

macOS only opens apps "without asking" if they've gone through Apple's
**notarization** process, which requires a paid **Apple Developer Program**
membership (99 USD/year) plus your own signing certificate. Workbench is a
small personal project, so instead of paying that fee, the app is signed
with an **ad-hoc signature** (free) during the automated build process on
GitHub Actions.

That ad-hoc signature is enough for macOS to trust that the file hasn't been
tampered with after being built, but it doesn't include identity
verification from a developer registered with Apple — which is why
Gatekeeper (macOS's security system) treats it as coming from an
"unidentified developer" and asks for manual confirmation the first time,
instead of blocking it outright as "damaged." It's a one-time step per
install, not something that repeats every time you open the app.
