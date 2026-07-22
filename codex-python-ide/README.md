# Codex Inner IDE Renderer

React/Monaco renderer，由本地 `NSPanel + WKWebView` host 加载。

- production global：`window.codexInnerIdeHost.v1`
- development fallback：本地 mock host
- production bundle：单个 `ide.js` IIFE 和 `ide.css`
- Monaco worker：inline Blob URL
- 不包含 HTTP server、远程脚本、iframe 或聊天界面

```bash
npm test -- --run
npm run build
```

Bridge 契约见 [companion-window-api.md](docs/companion-window-api.md)。
