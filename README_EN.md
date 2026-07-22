# Codex Inner IDE

[简体中文](README.md) | **English**

A local macOS extension that injects an `IDE` entry below `Files` in Codex and opens a native `NSPanel + WKWebView` Monaco Python IDE from its menu bar controller. It does not modify the ChatGPT/Codex app, ASAR, or signature.

> Preview: this project depends on unpublished and potentially unstable Codex Desktop CDP/UI interfaces. It is not an official OpenAI plugin and is not affiliated with or endorsed by OpenAI.

## Features

- Resizable native IDE window, centered on first launch with per-workspace frame restoration.
- Monaco editor, file tree, multiple tabs, versioned atomic saves, and external-change conflict handling.
- Python interpreter discovery, `.venv` creation, Run/Stop, Output, and Problems.
- Python execution through the bundled Codex `command/exec` with `workspaceWrite`, a single writable root, and network access disabled.
- `Add to chat` fills the bound Codex task composer; `More details` fills ChatGPT Quick Chat. Neither action sends automatically.
- Quick Chat first uses the official `⌘⌥N` shortcut, then a version-bound UI signal, and finally a clipboard fallback.

The preview does not include Side Chat, Review, an interactive terminal, Git UI, LSP, a debugger, notebooks, or AI autocomplete.

## Download

- [Codex Inner IDE v0.2.1 Preview](https://github.com/d8dzmf5mfn/codex-inner-ide/releases/tag/v0.2.1-preview)
- The current build supports Apple Silicon Macs running macOS 14 or newer.
- Download both the ZIP and `.sha256` file and verify the checksum before installing.

## Build and Run

Requirements:

- Apple Silicon Mac running macOS 14 or newer.
- A supported Codex Desktop version.
- Xcode Command Line Tools, Swift 6, Node.js 22, and npm.

```bash
./script/build_and_run.sh
```

Outputs:

- Installed and launched app: `~/Applications/Codex Inner IDE.app`
- Distribution archive: `dist/Codex Inner IDE-v0.2.1-macos-arm64.zip`
- Checksum file: `dist/Codex Inner IDE-v0.2.1-macos-arm64.zip.sha256`

Build the distribution archive without replacing the current installation:

```bash
./script/build_and_run.sh build-only
```

### Install the Preview Archive

1. Download the ZIP and matching `.sha256` file and verify the digest.
2. Extract the app and move it to `~/Applications` or `/Applications`.
3. This preview is ad-hoc signed and has not been signed with a Developer ID or notarized by Apple. macOS may block the first launch. Only if you trust the download source and the digest matches, right-click the app in Finder and choose **Open**, or build it from source.

When Codex Sidepanel and chat integration is enabled for the first time, the controller asks for confirmation before relaunching Codex and listens only on a random `127.0.0.1` CDP port. Choosing **Open IDE Only** keeps editing and Python execution available, but disables Sidepanel injection and chat handoff.

## Tests

```bash
npm --prefix codex-python-ide test -- --run
npm --prefix codex-python-ide run build

CLANG_MODULE_CACHE_PATH=/tmp/codex-inner-ide-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/codex-inner-ide-swift-cache \
swift test --scratch-path /tmp/codex-inner-ide-build
```

The Swift integration test calls `/Applications/ChatGPT.app/Contents/Resources/codex app-server` and verifies writes inside the workspace, rejection outside the workspace, and network denial.

## Compatibility

- Codex Desktop `26.715.70719` + `codex-cli 0.145.0-alpha.27`
- Codex Desktop `26.715.71837` + `codex-cli 0.145.0-alpha.30`
- Codex Desktop `26.715.72028` + `codex-cli 0.145.0-alpha.30`
- Codex Desktop `26.715.72359` + `codex-cli 0.145.0-alpha.30`

Unknown versions can still open the IDE from the menu bar, but Sidepanel injection and chat handoff are disabled by default. CDP selectors, Quick Chat UI, and the experimental App Server are not public stable Desktop APIs.

## Distribution Status

- `v0.2.1` is an Apple Silicon preview, not a notarized production release.
- The current build machine has no usable Apple Developer ID, so the Release ZIP retains an ad-hoc signature.
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled third-party components and licenses.
