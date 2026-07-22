# Codex Inner Edit

Codex Inner IDE 的配套插件。它把当前 Python 文件或选区交给独立的只读 Codex turn 生成修改提案，并在 Monaco 中显示内联 Diff。

- `Enter`：接受到编辑器缓冲区，不写磁盘。
- `Esc`：拒绝提案。
- `⌘S`：接受后明确保存。
- 代码不会通过 MCP 工具返回到原 Codex task。

要求先安装并启动 Codex Inner IDE v0.3.0 或更高版本。应用默认从 `~/Applications` 或 `/Applications` 查找，也可以设置 `CODEX_INNER_IDE_APP`。

开发安装：先把仓库 Marketplace 注册到 Codex，再安装 `codex-inner-edit@codex-inner-ide`。插件更新后请新建 task，以重新加载 Skill 和 MCP 工具。
