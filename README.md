# Codex Inner IDE

macOS 本地扩展：在 Codex `Files` 下方注入 `IDE` 入口，并由现有菜单栏控制器打开原生 `NSPanel + WKWebView` Monaco Python IDE。它不修改 ChatGPT/Codex App、ASAR 或签名。

> Preview：依赖未公开且可能变化的 Codex Desktop CDP/UI 接口，不是 OpenAI 官方插件，也不隶属于或受 OpenAI 认可。

## 功能

- 可调整大小的原生 IDE 窗口；首次居中，之后按 workspace 恢复位置。
- Monaco、文件树、多标签、版本化原子保存和外部修改冲突处理。
- Python 解释器发现、`.venv`、Run/Stop、Output 和 Problems。
- Python 通过 bundled Codex `command/exec` 运行，固定 `workspaceWrite`、唯一 writable root、禁网。
- `Add to chat` 预填绑定的 Codex task；`More details` 预填 ChatGPT Quick Chat；两者都不会自动发送。
- Quick Chat 优先使用官方 `⌘⌥N`，失败后使用版本绑定的 UI signal，最后回退到剪贴板。

不包含 Side Chat、Review、交互式 Terminal、Git、LSP、Debugger、Notebook 或 AI 补全。

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
- 分发包：`dist/Codex Inner IDE-v0.2.1-macos-arm64.zip`
- 校验文件：`dist/Codex Inner IDE-v0.2.1-macos-arm64.zip.sha256`

只生成分发包、不替换当前安装：

```bash
./script/build_and_run.sh build-only
```

### 安装 Preview 包

1. 下载 ZIP 和对应的 `.sha256` 文件并核对摘要。
2. 解压后将 App 移入 `~/Applications` 或 `/Applications`。
3. 当前 Preview 使用 ad-hoc 签名，尚未使用 Developer ID 签名或 Apple notarization。macOS 可能阻止首次启动；只在你信任下载来源且摘要一致时，通过 Finder 右键选择 **Open**，或自行从源码构建。

首次建立 Codex Sidepanel/聊天集成时，控制器会要求用户确认重启 Codex，并仅监听随机的 `127.0.0.1` CDP 端口。选择 **Open IDE Only** 仍可编辑和运行 Python，但不会注入 Sidepanel 或执行聊天交接。

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

未知版本仍允许从菜单栏打开 IDE，但默认禁用 Sidepanel 和聊天交接。CDP selector、Quick Chat UI 和 experimental App Server 都不是公开稳定的 Desktop API。

## 分发状态

- `v0.2.1` 是 Apple Silicon preview，不是已公证的正式版本。
- 当前机器没有可用的 Apple Developer ID；Release ZIP 会保留 ad-hoc 签名。
- 第三方组件及许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
