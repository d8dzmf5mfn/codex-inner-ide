# Companion window bridge

这不是公开 Codex plugin API。菜单栏控制器通过 `WKScriptMessageHandler` 在隔离的 IDE `WKWebView` 中暴露：

```ts
window.codexInnerIdeHost.v1
```

允许的方法固定为：

- `workspace.current`, `workspace.choose`
- `files.list`, `files.read`, `files.write`, `files.create`, `files.rename`, `files.trash`, `files.watch`
- `python.discover`, `python.createVenv`, `python.run`, `python.checkSyntax`, `python.terminate`, `python.subscribe`
- `chatgpt.moreDetails`
- `window.loadState`, `window.saveState`, `window.setDirty`, `window.setPinned`, `window.closeIde`

每个请求必须携带当前 session token。Swift host 拒绝未知方法、绝对路径、路径穿越和 workspace 外符号链接。

`chatgpt.moreDetails` 只预填 Quick Chat composer，不自动发送；定位失败时返回 `mechanism: "clipboard"`。
