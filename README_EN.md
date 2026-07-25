# Codex Inner IDE

[简体中文](README.md) | **English**

A local macOS extension that injects an `IDE` entry below `Files` in Codex and opens a real multi-language Monaco IDE in the Codex built-in Browser first. A failed handshake or unsupported compatibility profile falls back to the native `NSPanel + WKWebView`. It does not modify the ChatGPT/Codex app, ASAR, signature, or private IPC.

> Preview: this project depends on unpublished and potentially unstable Codex Desktop CDP/UI interfaces. It is not an official OpenAI plugin and is not affiliated with or endorsed by OpenAI.

## Features

- Browser-first IDE on a random `127.0.0.1` port with a per-process token, authenticated RPC and event streams, Origin checks, a 16 MiB request limit, and a restrictive CSP.
- The native window remains available as a fallback. Pin is available only in native mode.
- Monaco, multiple tabs, versioned atomic saves, conflict handling, file filtering, hierarchy guides, and a collapsible sidebar.
- Local execution for Python, Java, JavaScript, and TypeScript; previews for HTML, CSS, and Markdown; JSON validation; no fake Run action for plain text.
- Runtime discovery uses only system and Workspace tools. Missing environments show copy-only commands or official download pages plus `Recheck`; nothing is installed automatically.
- Java and TypeScript build products are isolated in per-Workspace application caches.
- Local language-aware completion combines current-file symbols, Workspace symbols, language catalogs, and user snippets. Tab accepts a suggestion; five rows are visible before scrolling.
- Recent Workspace switching with independent editor, tree, panel, and sidebar state restoration.
- `More details` fills ChatGPT Quick Chat without sending automatically.
- Quick Chat first uses the official `⌘⌥N` shortcut, then a version-bound UI signal, and finally a clipboard fallback.
- The `Codex Inner Edit` plugin generates an isolated read-only proposal for the active Python selection or file. `Enter` changes only the Monaco buffer, `Esc` rejects it, and `⌘S` writes it to disk.
- Auto / Light / Dark themes; Auto follows the live macOS appearance.

The preview does not include Side Chat, Review, an interactive terminal, Git UI, LSP, a debugger, notebooks, Maven/Gradle, or AI autocomplete.

## Download

- The latest public preview is [`v0.4.4-preview`](https://github.com/d8dzmf5mfn/codex-inner-ide/releases/tag/v0.4.4-preview).
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
- Distribution archive: `dist/Codex.Inner.IDE-v0.4.4-preview-macos-arm64.zip`
- Checksum file: `dist/Codex.Inner.IDE-v0.4.4-preview-macos-arm64.zip.sha256`
- Plugin archive: `dist/codex-inner-edit-v0.1.0.zip`

Build the distribution archive without replacing the current installation:

```bash
./script/build_and_run.sh build-only
```

### Install the Preview Archive

1. Download the ZIP and matching `.sha256` file and verify the digest.
2. Extract the app and move it to `~/Applications` or `/Applications`.
3. This preview is ad-hoc signed and has not been signed with a Developer ID or notarized by Apple. macOS may block the first launch. Only if you trust the download source and the digest matches, right-click the app in Finder and choose **Open**, or build it from source.

When Codex Sidepanel and chat integration is enabled for the first time, the controller asks for confirmation before relaunching Codex and listens only on a random `127.0.0.1` CDP port. Choosing **Open IDE Only** keeps the native IDE available, but disables Sidepanel injection and chat handoff.

### Install the Codex Inner Edit plugin

The source repository includes a repo-local marketplace. Register and install it with:

```bash
codex plugin marketplace add "/path/to/codex-inner-ide"
codex plugin add codex-inner-edit@codex-inner-ide
```

The plugin connects to the installed app through its `--mcp-stdio` mode. It does not require Node, Python, an HTTP service, or an API key. Start a new Codex task after installing or updating it so the Skill and MCP tools are reloaded.

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
- Codex Desktop `26.721.30844` + `codex-cli 0.146.0-alpha.3`
- Codex Desktop `26.721.41059` + `codex-cli 0.146.0-alpha.3.1`

Unknown versions can still open the IDE from the menu bar, but Sidepanel injection and chat handoff are disabled by default. CDP selectors, Quick Chat UI, and the experimental App Server are not public stable Desktop APIs.

## Distribution Status

- `v0.4.4-preview` is an Apple Silicon preview, not a notarized production release.
- The current build machine has no usable Apple Developer ID, so the Release ZIP retains an ad-hoc signature.
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled third-party components and licenses.
