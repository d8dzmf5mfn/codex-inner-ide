# Codex Inner IDE

**简体中文** | [English](README_EN.md)

macOS 本地扩展：在 Codex `Files` 下方注入 `IDE` 入口，并优先在 Codex 内置 Browser 中打开真实的多语言 Monaco IDE；握手或兼容性验证失败时自动回退原生 `NSPanel + WKWebView`。它不修改 ChatGPT/Codex App、ASAR、签名或私有 IPC。

> Preview：依赖未公开且可能变化的 Codex Desktop CDP/UI 接口，不是 OpenAI 官方插件，也不隶属于或受 OpenAI 认可。

## 功能

- Browser-first IDE 使用随机 `127.0.0.1` 端口和每进程令牌；RPC、事件流、Origin、16 MiB 请求上限和 CSP 均失败关闭。
- 原生 IDE 窗口继续保留；首次居中，之后按 Workspace 恢复位置，Pin 仅在原生模式显示。
- Monaco、多标签、版本化原子保存、外部修改冲突处理、文件筛选、层级缩进、引导线和可隐藏侧栏。
- Python、Java、JavaScript、TypeScript 提供本地运行；HTML/CSS/Markdown 提供预览；JSON 提供校验；Plain Text 不显示虚假 Run。
- 运行环境只发现本机或 Workspace 已有工具链。缺失时显示可复制命令或官方下载页，并可 `Recheck`；永不自动安装。
- Java 编译产物和 TypeScript 临时产物写入 Workspace 专属应用缓存，不污染项目目录。
- 本地多语言补全合并当前文件符号、Workspace 符号、语言词库和用户片段；Tab 接受，列表显示五项并可滚动。
- 最近 Workspace、快速切换和每 Workspace 独立窗口/文件树状态恢复。
- `More details` 预填 ChatGPT Quick Chat，但不会自动发送。
- Quick Chat 优先使用官方 `⌘⌥N`，失败后使用版本绑定的 UI signal，最后回退到剪贴板。
- `Codex Inner Edit` 插件可为当前 Python 选区或文件生成独立只读修改提案；`Enter` 只应用到 Monaco 缓冲区，`Esc` 拒绝，`⌘S` 才写入磁盘。
- 主题支持 Auto / Light / Dark；Auto 实时跟随 macOS 系统外观。

不包含 Side Chat、Review、交互式 Terminal、Git UI、LSP、Debugger、Notebook、Maven/Gradle 或 AI 补全。

## 下载

- 最新公开预览版为 [`v0.4.1-preview`](https://github.com/d8dzmf5mfn/codex-inner-ide/releases/tag/v0.4.1-preview)。
- 当前提供 Apple Silicon、macOS 14+ 构建。
- 下载 ZIP 和 `.sha256` 文件后，请先核对摘要。

## 构建与运行

要求：

- Apple Silicon Mac，macOS 14 或更高版本。
- 已安装支持版本的 Codex Desktop。
- Xcode Command Line Tools、Swift 6、Node.js 22 和 npm。

```bash
./script/build_and_run.sh
```

输出：

- 安装并启动：`~/Applications/Codex Inner IDE.app`
- 分发包：`dist/Codex.Inner.IDE-v0.4.1-preview-macos-arm64.zip`
- 校验文件：`dist/Codex.Inner.IDE-v0.4.1-preview-macos-arm64.zip.sha256`
- 插件包：`dist/codex-inner-edit-v0.1.0.zip`

只生成分发包、不替换当前安装：

```bash
./script/build_and_run.sh build-only
```

### 安装 Preview 包

1. 下载 ZIP 和对应的 `.sha256` 文件并核对摘要。
2. 解压后将 App 移入 `~/Applications` 或 `/Applications`。
3. 当前 Preview 使用 ad-hoc 签名，尚未使用 Developer ID 签名或 Apple notarization。macOS 可能阻止首次启动；只在你信任下载来源且摘要一致时，通过 Finder 右键选择 **Open**，或自行从源码构建。

首次建立 Codex Sidepanel/聊天集成时，控制器会要求用户确认重启 Codex，并仅监听随机的 `127.0.0.1` CDP 端口。选择 **Open IDE Only** 仍可使用原生 IDE，但不会注入 Sidepanel 或执行聊天交接。

### 安装 Codex Inner Edit 插件

源码仓库包含 repo-local Marketplace。注册并安装：

```bash
codex plugin marketplace add "/path/to/codex-inner-ide"
codex plugin add codex-inner-edit@codex-inner-ide
```

插件通过已安装 App 的 `--mcp-stdio` 模式连接本机 IDE，不需要 Node、Python、HTTP 服务或 API Key。安装或更新后请新建 Codex task 以加载 Skill 和 MCP 工具。

## 测试

```bash
npm --prefix codex-python-ide test -- --run
npm --prefix codex-python-ide run build

CLANG_MODULE_CACHE_PATH=/tmp/codex-inner-ide-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/codex-inner-ide-swift-cache \
swift test --scratch-path /tmp/codex-inner-ide-build
```

Swift 集成测试调用 `/Applications/ChatGPT.app/Contents/Resources/codex app-server`，验证 workspace 内写入、workspace 外拒绝和网络拒绝。

## 兼容性

- Codex Desktop `26.715.70719` + `codex-cli 0.145.0-alpha.27`
- Codex Desktop `26.715.71837` + `codex-cli 0.145.0-alpha.30`
- Codex Desktop `26.715.72028` + `codex-cli 0.145.0-alpha.30`
- Codex Desktop `26.715.72359` + `codex-cli 0.145.0-alpha.30`
- Codex Desktop `26.721.30844` + `codex-cli 0.146.0-alpha.3`

未知版本仍允许从菜单栏打开 IDE，但默认禁用 Sidepanel 和聊天交接。CDP selector、Quick Chat UI 和 experimental App Server 都不是公开稳定的 Desktop API。

## 分发状态

- `v0.4.1-preview` 是 Apple Silicon preview，不是已公证的正式版本。
- 当前机器没有可用的 Apple Developer ID；Release ZIP 会保留 ad-hoc 签名。
- 第三方组件及许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
